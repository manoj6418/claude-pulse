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
        var currentStep = previous?.currentStep
        var currentStepStartedAt = previous?.currentStepStartedAt
        var compactCount = previous?.compactCount ?? 0
        var steps = previous?.steps ?? []
        var agents = (previous?.agents ?? [:]).filter { now.timeIntervalSince($0.value) < 2 * 3_600 } // drop orphans
        // Tool calls from inside a background agent carry agent_id; they don't change the main step.
        let fromAgent = (json["agent_id"] as? String).map { !$0.isEmpty } ?? false
        let toolUseId = json["tool_use_id"] as? String

        switch event {
        case "UserPromptSubmit":
            state = .working
            // Background task results arrive as prompts mid-turn; they don't start a new turn.
            if previous?.state != .working || turnStartedAt == nil {
                turnStartedAt = now
                currentStep = nil
                currentStepStartedAt = nil
            }
        case "PreToolUse":
            state = .working
            if !fromAgent {
                let text = describeStep(tool: json["tool_name"] as? String ?? "Tool",
                                        input: json["tool_input"] as? [String: Any] ?? [:])
                currentStep = text
                currentStepStartedAt = now
                steps.append(StepRecord(id: toolUseId ?? UUID().uuidString, text: text, startedAt: now))
                if steps.count > 10 { steps.removeFirst(steps.count - 10) }
            }
        case "PostToolUse", "PostToolUseFailure":
            state = .working
            if !fromAgent {
                currentStep = nil
                currentStepStartedAt = nil
                let failed = event == "PostToolUseFailure"
                let error = (json["error"] as? String).flatMap { $0.split(whereSeparator: \.isNewline).first.map(String.init) }
                let interrupted = json["is_interrupt"] as? Bool
                if let index = steps.lastIndex(where: { $0.id == toolUseId || (toolUseId == nil && $0.endedAt == nil) }) {
                    steps[index].endedAt = now
                    steps[index].failed = failed
                    steps[index].error = failed ? error.map { String($0.prefix(160)) } : nil
                    steps[index].interrupted = interrupted
                }
            }
        case "SubagentStart":
            state = previous?.state ?? .working
            if let id = json["agent_id"] as? String { agents[id] = now }
        case "SubagentStop":
            state = previous?.state ?? .working
            if let id = json["agent_id"] as? String { agents[id] = nil }
        case "SessionStart":
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
            currentStep = nil
            currentStepStartedAt = nil
            finishedAt = now
            finalReply = (json["last_assistant_message"] as? String).map { String($0.prefix(300)) }
        case "PreCompact":
            state = .compacting
            compactCount += 1
        case "PermissionRequest":
            let tool = json["tool_name"] as? String ?? "Tool"
            // Plan approval and Claude's own questions need the terminal's richer UI.
            guard !["AskUserQuestion", "ExitPlanMode"].contains(tool) else { return }
            state = .needsPermission
            message = "\(tool) wants permission"
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
            turnStartedAt: turnStartedAt, finishedAt: finishedAt, finalReply: finalReply,
            currentStep: currentStep, currentStepStartedAt: currentStepStartedAt, compactCount: compactCount,
            steps: steps, agents: agents
        )
        if let data = try? JSONCoding.encoder.encode(record) {
            FileManager.default.writeAtomically(data, to: stateURL)
        }

        if event == "PermissionRequest" {
            waitForPermissionAnswer(json, sessionId: sessionId, stateURL: stateURL)
        }
    }

    // MARK: - Permission requests

    /// The terminal shows its own prompt while this waits, and whichever is
    /// answered first wins. Prints a decision only when the answer came from
    /// Claude Pulse; quits quietly once the session moves on without one.
    private static func waitForPermissionAnswer(_ json: [String: Any], sessionId: String, stateURL: URL) {
        let fm = FileManager.default
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let suggestions = json["permission_suggestions"] as? [[String: Any]] ?? []
        let toolName = json["tool_name"] as? String ?? "Tool"
        let request = PermissionRequestRecord(
            id: UUID().uuidString,
            sessionId: sessionId,
            cwd: json["cwd"] as? String,
            toolName: toolName,
            summary: summarize(tool: toolName, input: input),
            detail: input["description"] as? String,
            canAlwaysAllow: !suggestions.isEmpty,
            createdAt: Date(),
            hookPid: getpid()
        )
        let requestURL = Paths.permissionRequests.appendingPathComponent("\(request.id).json")
        let responseURL = Paths.permissionResponses.appendingPathComponent("\(request.id).json")
        guard let data = try? JSONCoding.encoder.encode(request) else { return }
        fm.writeAtomically(data, to: requestURL)
        defer {
            try? fm.removeItem(at: requestURL)
            try? fm.removeItem(at: responseURL)
        }

        let registryPid = registryPid(for: sessionId)
        let deadline = Date().addingTimeInterval(590)
        while Date() < deadline {
            if let data = try? Data(contentsOf: responseURL),
               let response = try? JSONDecoder().decode(PermissionResponse.self, from: data),
               response.id == request.id {
                printDecision(response.decision, suggestions: suggestions)
                return
            }
            if answeredElsewhere(since: request.createdAt, stateURL: stateURL, registryPid: registryPid) { return }
            if getppid() == 1 { return } // Claude Code went away
            usleep(250_000)
        }
    }

    /// The session moved on: a later hook event that isn't "needs permission",
    /// or Claude Code marked the session idle (e.g. the prompt was cancelled).
    private static func answeredElsewhere(since created: Date, stateURL: URL, registryPid: Int32?) -> Bool {
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONCoding.decoder.decode(HookStateRecord.self, from: data),
           state.updatedAt > created.addingTimeInterval(0.5), state.state != .needsPermission {
            return true
        }
        if let pid = registryPid,
           let data = try? Data(contentsOf: Paths.claudeSessions.appendingPathComponent("\(pid).json")),
           let entry = try? JSONDecoder().decode(RegistryEntry.self, from: data),
           entry.status == "idle",
           let at = entry.updatedAt, Date(timeIntervalSince1970: at / 1000) > created {
            return true
        }
        return false
    }

    private static func registryPid(for sessionId: String) -> Int32? {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.claudeSessions, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let entry = try? JSONDecoder().decode(RegistryEntry.self, from: data),
               entry.sessionId == sessionId {
                return entry.pid
            }
        }
        return nil
    }

    private static func printDecision(_ decision: PermissionDecision, suggestions: [[String: Any]]) {
        var body: [String: Any]
        switch decision {
        case .allow:
            body = ["behavior": "allow"]
        case .alwaysAllow:
            body = ["behavior": "allow"]
            if !suggestions.isEmpty { body["updatedPermissions"] = suggestions }
        case .deny:
            body = ["behavior": "deny", "message": "Denied from Claude Pulse.", "interrupt": false]
        }
        let output: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output) {
            FileHandle.standardOutput.write(data)
        }
    }

    /// Short present-tense line for the session row: "Running go test ./...", "Editing edd.go".
    static func describeStep(tool: String, input: [String: Any]) -> String {
        func file(_ key: String) -> String? {
            (input[key] as? String).map { ($0 as NSString).lastPathComponent }
        }
        func short(_ text: String) -> String {
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return line.count > 80 ? String(line.prefix(80)) + "…" : line
        }
        switch tool {
        case "Bash":
            return "Running " + short(dropLeadingCd(input["command"] as? String ?? "a command"))
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return "Editing " + (file("file_path") ?? file("notebook_path") ?? "a file")
        case "Read":
            return "Reading " + (file("file_path") ?? "a file")
        case "Grep", "Glob":
            return "Searching " + short(input["pattern"] as? String ?? "files")
        case "WebFetch":
            let host = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? "the web"
            return "Fetching " + host
        case "WebSearch":
            return "Searching the web: " + short(input["query"] as? String ?? "")
        case "Task", "Agent":
            return "Agent: " + short(input["description"] as? String ?? "working")
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                return "Using " + parts.dropFirst().joined(separator: " ")
            }
            return "Using " + tool
        }
    }

    /// "cd /some/long/path && go test ./..." → "go test ./...": the folder is already on the row.
    /// Also drops leading variable settings: "SP=/tmp/x; B=y go test" → "go test".
    static func dropLeadingCd(_ command: String) -> String {
        var rest = command.trimmingCharacters(in: .whitespaces)
        let assignment = try! NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'[^']*'|\S*)\s*(;|&&)?\s*"#)
        while true {
            let before = rest
            if rest.hasPrefix("cd "), let range = rest.range(of: "&&") {
                rest = rest[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
            let ns = rest as NSString
            if let match = assignment.firstMatch(in: rest, range: NSRange(location: 0, length: ns.length)) {
                rest = ns.substring(from: match.range.length).trimmingCharacters(in: .whitespaces)
            }
            if rest == before { break }
        }
        return rest.isEmpty ? command : rest
    }

    /// One line saying what the tool will do.
    private static func summarize(tool: String, input: [String: Any]) -> String {
        for key in ["command", "file_path", "notebook_path", "url", "path", "pattern", "query", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return String(value.prefix(600)) }
        }
        guard !input.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return tool }
        return String(text.prefix(600))
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
            totalInputTokens: (ctx?["total_input_tokens"] as? NSNumber)?.intValue,
            totalOutputTokens: (ctx?["total_output_tokens"] as? NSNumber)?.intValue,
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
