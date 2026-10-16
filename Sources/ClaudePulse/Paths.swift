import Foundation

enum Paths {
    /// CLAUDE_PULSE_HOME points everything at another folder, for testing.
    static let home = ProcessInfo.processInfo.environment["CLAUDE_PULSE_HOME"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser

    static let claudeDir = home.appendingPathComponent(".claude")
    static let claudeSessions = claudeDir.appendingPathComponent("sessions")
    static let claudeProjects = claudeDir.appendingPathComponent("projects")
    static let claudeSettings = claudeDir.appendingPathComponent("settings.json")

    static let support = home
        .appendingPathComponent("Library/Application Support/ClaudePulse")
    static let bridgeSessions = support.appendingPathComponent("sessions")
    static let hookStates = support.appendingPathComponent("states")
    static let limitsFile = support.appendingPathComponent("limits.json")
    static let historyFile = support.appendingPathComponent("limit-history.json")
    static let configFile = support.appendingPathComponent("config.json")

    static func ensureSupportDirs() {
        for dir in [support, bridgeSessions, hookStates] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Claude Code stores transcripts under a folder named after the cwd,
    /// with every character that is not a letter, digit or hyphen turned into "-".
    static func projectSlug(for cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") ? $0 : "-" })
    }
}

extension FileManager {
    func writeAtomically(_ data: Data, to url: URL) {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).tmp")
        do {
            try data.write(to: tmp)
            _ = try replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? removeItem(at: tmp)
            try? data.write(to: url, options: .atomic)
        }
    }
}
