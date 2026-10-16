import Foundation

struct GitState: Equatable {
    var changedFiles: Int
    var ahead: Int
    var behind: Int
    var hasUpstream: Bool

    var isClean: Bool { changedFiles == 0 && ahead == 0 }
}

/// Reads `git status` for each session folder at most every 30 seconds.
/// Only used from the store's background queue.
final class GitWatcher {
    private struct Entry {
        var state: GitState?
        var checkedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private let interval: TimeInterval = 30

    func state(for cwd: String, now: Date = Date()) -> GitState? {
        guard !cwd.isEmpty else { return nil }
        if let entry = cache[cwd], now.timeIntervalSince(entry.checkedAt) < interval { return entry.state }
        let state = Self.read(cwd)
        cache[cwd] = Entry(state: state, checkedAt: now)
        return state
    }

    private static func read(_ cwd: String) -> GitState? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd, "status", "--porcelain=v1", "--branch", "--untracked-files=normal"]
        var variables = ProcessInfo.processInfo.environment
        variables["GIT_OPTIONAL_LOCKS"] = "0" // never take the index lock the session's own git may need
        process.environment = variables
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil } // not a repository
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parse(text)
    }

    /// "## main...origin/main [ahead 2, behind 1]" then one line per changed file.
    static func parse(_ text: String) -> GitState {
        var state = GitState(changedFiles: 0, ahead: 0, behind: 0, hasUpstream: false)
        for line in text.split(separator: "\n") {
            if line.hasPrefix("## ") {
                state.hasUpstream = line.contains("...")
                if let ahead = number(after: "ahead ", in: line) { state.ahead = ahead }
                if let behind = number(after: "behind ", in: line) { state.behind = behind }
            } else if !line.isEmpty {
                state.changedFiles += 1
            }
        }
        return state
    }

    private static func number(after marker: String, in line: Substring) -> Int? {
        guard let range = line.range(of: marker) else { return nil }
        return Int(line[range.upperBound...].prefix { $0.isNumber })
    }
}
