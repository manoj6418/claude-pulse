import Foundation

/// Command-line modes Claude Code calls into:
///   ClaudePulse --statusline   (statusLine.command)  stdin = status line JSON
///   ClaudePulse --hook         (hook command)        stdin = hook event JSON
/// Both save a small snapshot for the menu bar app and return fast.
enum Bridge {
    static func runStatusLine() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        Paths.ensureSupportDirs()
        guard let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else {
            runChained(input)
            return
        }

        let limits = saveLimits(json)
        let session = saveSession(json)

        if !runChained(input) {
            print(statusText(session: session, limits: limits))
        }
    }

    static func runHook() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        Paths.ensureSupportDirs()
        guard let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
              let sessionId = json["session_id"] as? String,
              let event = json["hook_event_name"] as? String
        else { return }

        let stateURL = Paths.hookStates.appendingPathComponent("\(sessionId).json")
        let previous = (try? Data(contentsOf: stateURL))
            .flatMap { try? JSONCoding.decoder.decode(HookStateRecord.self, from: $0) }
        let now = Date()
        let state: HookState
        var message: String?
        var turnStartedAt = previous?.turnStartedAt
        var finishedAt = previous?.finishedAt
        var finalReply = previous?.finalReply

        switch event {
        case "UserPromptSubmit":
            state = .working
            // Background task results arrive as prompts mid-turn; they don't start a new turn.
            if previous?.state != .working || turnStartedAt == nil {
                turnStartedAt = now
            }
        case "PostToolUse", "SessionStart":
            state = .working
        case "Notification":
            message = json["message"] as? String
            switch json["notification_type"] as? String {
            case "permission_prompt": state = .needsPermission
            case "idle_prompt": state = .waitingInput
            default:
                if message?.localizedCaseInsensitiveContains("permission") == true {
                    state = .needsPermission
                } else if message?.localizedCaseInsensitiveContains("waiting") == true {
                    state = .waitingInput
                } else {
                    return
                }
            }
        case "Stop":
            state = .idle
            finishedAt = now
            finalReply = (json["last_assistant_message"] as? String).map { String($0.prefix(300)) }
        case "PreCompact":
            state = .compacting
        case "SessionEnd":
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(
                at: Paths.bridgeSessions.appendingPathComponent("\(sessionId).json"))
            return
        default:
            return
        }

        let record = HookStateRecord(
            sessionId: sessionId, state: state, message: message, updatedAt: now,
            turnStartedAt: turnStartedAt, finishedAt: finishedAt, finalReply: finalReply
        )
        if let data = try? JSONCoding.encoder.encode(record) {
            FileManager.default.writeAtomically(data, to: stateURL)
        }
    }

    // MARK: - Status line snapshot

    private static func saveLimits(_ json: [String: Any]) -> LimitsSnapshot? {
        guard let rate = json["rate_limits"] as? [String: Any] else { return LimitsStore.load() }
        let fresh = LimitsSnapshot(
            fiveHour: window(rate["five_hour"]),
            sevenDay: window(rate["seven_day"]),
            capturedAt: Date()
        )
        guard fresh.fiveHour != nil || fresh.sevenDay != nil else { return LimitsStore.load() }

        // A window can be missing on its own; keep the last known one until it resets.
        var merged = fresh
        if let previous = LimitsStore.load() {
            if merged.fiveHour == nil, let old = previous.fiveHour, old.resetsAt > Date() { merged.fiveHour = old }
            if merged.sevenDay == nil, let old = previous.sevenDay, old.resetsAt > Date() { merged.sevenDay = old }
        }
        if let data = try? JSONCoding.encoder.encode(merged) {
            FileManager.default.writeAtomically(data, to: Paths.limitsFile)
        }
        return merged
    }

    private static func window(_ any: Any?) -> LimitWindow? {
        guard let w = any as? [String: Any],
              let used = (w["used_percentage"] as? NSNumber)?.doubleValue,
              let resets = (w["resets_at"] as? NSNumber)?.doubleValue
        else { return nil }
        return LimitWindow(usedPercentage: used, resetsAt: Date(timeIntervalSince1970: resets))
    }

    private static func saveSession(_ json: [String: Any]) -> BridgeSession? {
        guard let sessionId = json["session_id"] as? String else { return nil }
        let model = json["model"] as? [String: Any]
        let ctx = json["context_window"] as? [String: Any]
        let usage = ctx?["current_usage"] as? [String: Any]
        let cost = json["cost"] as? [String: Any]
        let workspace = json["workspace"] as? [String: Any]

        var contextTokens: Int?
        if let usage {
            contextTokens = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
        }

        let session = BridgeSession(
            sessionId: sessionId,
            sessionName: json["session_name"] as? String,
            cwd: json["cwd"] as? String ?? workspace?["current_dir"] as? String,
            projectDir: workspace?["project_dir"] as? String,
            transcriptPath: json["transcript_path"] as? String,
            modelId: model?["id"] as? String,
            modelName: model?["display_name"] as? String,
            effort: (json["effort"] as? [String: Any])?["level"] as? String,
            contextUsedPercentage: (ctx?["used_percentage"] as? NSNumber)?.doubleValue,
            contextWindowSize: (ctx?["context_window_size"] as? NSNumber)?.intValue,
            contextTokens: contextTokens,
            costUSD: (cost?["total_cost_usd"] as? NSNumber)?.doubleValue,
            linesAdded: (cost?["total_lines_added"] as? NSNumber)?.intValue,
            linesRemoved: (cost?["total_lines_removed"] as? NSNumber)?.intValue,
            durationMs: (cost?["total_duration_ms"] as? NSNumber)?.doubleValue,
            version: json["version"] as? String,
            updatedAt: Date()
        )
        if let data = try? JSONCoding.encoder.encode(session) {
            FileManager.default.writeAtomically(
                data, to: Paths.bridgeSessions.appendingPathComponent("\(sessionId).json"))
        }
        return session
    }

    // MARK: - Status line text

    static func statusText(session: BridgeSession?, limits: LimitsSnapshot?) -> String {
        let dim = "\u{1B}[2m", reset = "\u{1B}[0m"
        var parts: [String] = []

        if let session {
            var model = session.modelName ?? ModelCatalog.displayName(for: session.modelId)
            if let effort = session.effort { model += " \(dim)\(effort)\(reset)" }
            parts.append(model)
            if let pct = session.contextUsedPercentage {
                parts.append("ctx \(colored(pct))")
            }
        }
        if let w = limits?.fiveHour, w.resetsAt > Date() {
            parts.append("5h \(colored(w.usedPercentage)) \(dim)↻\(Format.countdown(to: w.resetsAt))\(reset)")
        }
        if let w = limits?.sevenDay, w.resetsAt > Date() {
            parts.append("7d \(colored(w.usedPercentage))")
        }
        return parts.joined(separator: " \(dim)·\(reset) ")
    }

    private static func colored(_ pct: Double) -> String {
        let code = pct >= 90 ? "31" : pct >= 75 ? "33" : "32"
        return "\u{1B}[\(code)m\(Int(pct.rounded()))%\u{1B}[0m"
    }

    // MARK: - Chained status line

    /// If the user already had a status line, keep showing theirs: pass the same
    /// stdin through and print its output. Returns true when one ran.
    @discardableResult
    private static func runChained(_ input: Data) -> Bool {
        guard let command = PulseConfig.load().chainedStatusLine, !command.isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        FileHandle.standardOutput.write(output)
        return true
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

enum LimitsStore {
    static func load() -> LimitsSnapshot? {
        guard let data = try? Data(contentsOf: Paths.limitsFile) else { return nil }
        return try? JSONCoding.decoder.decode(LimitsSnapshot.self, from: data)
    }
}

struct PulseConfig: Codable {
    var chainedStatusLine: String?

    static func load() -> PulseConfig {
        guard let data = try? Data(contentsOf: Paths.configFile),
              let config = try? JSONDecoder().decode(PulseConfig.self, from: data)
        else { return PulseConfig() }
        return config
    }

    func save() {
        Paths.ensureSupportDirs()
        if let data = try? JSONEncoder().encode(self) {
            FileManager.default.writeAtomically(data, to: Paths.configFile)
        }
    }
}
