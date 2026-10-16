import Foundation

/// Connects ClaudePulse to Claude Code by editing ~/.claude/settings.json:
/// sets the status line command and adds hook commands. A backup is written
/// first, an existing status line is kept (chained), and only our own entries
/// are removed on disconnect.
enum Installer {
    enum Status: Equatable {
        case notConnected
        case connected
        case partial
        case wrongPath(String)
    }

    static let hookEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "Stop",
                             "PreCompact", "SessionEnd", "PermissionRequest", "SubagentStart", "SubagentStop"]

    /// PermissionRequest waits for an answer from the panel; the others return at once.
    static func hookTimeout(for event: String) -> Int { event == "PermissionRequest" ? 600 : 5 }

    static var executablePath: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }
    static var statusLineCommand: String { "'\(executablePath)' --statusline" }
    static var hookCommand: String { "'\(executablePath)' --hook" }

    private static func isOurs(_ command: String?, flag: String) -> Bool {
        guard let command else { return false }
        return command.contains("ClaudePulse") && command.contains(flag)
    }

    static func status() -> Status {
        guard let settings = loadSettings() else { return .notConnected }
        let statusLine = (settings["statusLine"] as? [String: Any])?["command"] as? String
        let hasStatusLine = isOurs(statusLine, flag: "--statusline")
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hookedEvents = hookEvents.filter { event in
            commands(in: hooks[event]).contains { isOurs($0, flag: "--hook") }
        }

        if !hasStatusLine && hookedEvents.isEmpty { return .notConnected }
        if let statusLine, hasStatusLine, statusLine != statusLineCommand { return .wrongPath(statusLine) }
        if hasStatusLine && hookedEvents.count == hookEvents.count { return .connected }
        return .partial
    }

    static func connect() throws {
        var settings = loadSettings() ?? [:]
        try backup()

        var config = PulseConfig.load()
        if let existing = settings["statusLine"] as? [String: Any],
           let command = existing["command"] as? String,
           !isOurs(command, flag: "--statusline") {
            config.chainedStatusLine = command
        }
        config.save()

        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = statusLineCommand
        if statusLine["padding"] == nil { statusLine["padding"] = 0 }
        settings["statusLine"] = statusLine

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in hookEvents {
            var groups = removingOurs(from: hooks[event])
            groups.append(["hooks": [["type": "command", "command": hookCommand, "timeout": hookTimeout(for: event)]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try save(settings)
    }

    static func disconnect() throws {
        guard var settings = loadSettings() else { return }
        try backup()

        let config = PulseConfig.load()
        if let command = (settings["statusLine"] as? [String: Any])?["command"] as? String,
           isOurs(command, flag: "--statusline") {
            if let chained = config.chainedStatusLine, !chained.isEmpty {
                settings["statusLine"] = ["type": "command", "command": chained]
            } else {
                settings.removeValue(forKey: "statusLine")
            }
        }

        if var hooks = settings["hooks"] as? [String: Any] {
            for event in hookEvents {
                let groups = removingOurs(from: hooks[event])
                hooks[event] = groups.isEmpty ? nil : groups
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }
        try save(settings)

        var cleared = config
        cleared.chainedStatusLine = nil
        cleared.save()
    }

    // MARK: - Helpers

    private static func commands(in eventValue: Any?) -> [String] {
        let groups = eventValue as? [[String: Any]] ?? []
        return groups.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    private static func removingOurs(from eventValue: Any?) -> [[String: Any]] {
        let groups = eventValue as? [[String: Any]] ?? []
        return groups.compactMap { group in
            var group = group
            let kept = (group["hooks"] as? [[String: Any]] ?? []).filter {
                !isOurs($0["command"] as? String, flag: "--hook")
            }
            if kept.isEmpty { return nil }
            group["hooks"] = kept
            return group
        }
    }

    private static func loadSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: Paths.claudeSettings) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func save(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        FileManager.default.writeAtomically(data, to: Paths.claudeSettings)
    }

    private static func backup() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.claudeSettings.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        var target = Paths.claudeDir.appendingPathComponent("settings.json.claudepulse-backup-\(stamp)")
        var n = 1
        while fm.fileExists(atPath: target.path) {
            n += 1
            target = Paths.claudeDir.appendingPathComponent("settings.json.claudepulse-backup-\(stamp)-\(n)")
        }
        try fm.copyItem(at: Paths.claudeSettings, to: target)
    }
}
