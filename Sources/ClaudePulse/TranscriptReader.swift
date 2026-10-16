import Foundation

/// Reads the newest main-thread assistant turn from a session transcript.
/// Only the tail of the file is read, and results are cached by size + mtime.
final class TranscriptReader {
    private struct CacheEntry {
        var size: UInt64
        var modified: Date
        var info: TranscriptInfo
    }

    private var cache: [String: CacheEntry] = [:]
    private var pathBySession: [String: String] = [:]
    private let tailBytes: UInt64 = 768 * 1024

    func transcriptPath(sessionId: String, cwd: String?, hint: String?) -> String? {
        let fm = FileManager.default
        if let hint, fm.fileExists(atPath: hint) { return hint }
        if let cached = pathBySession[sessionId], fm.fileExists(atPath: cached) { return cached }

        if let cwd {
            let guess = Paths.claudeProjects
                .appendingPathComponent(Paths.projectSlug(for: cwd))
                .appendingPathComponent("\(sessionId).jsonl").path
            if fm.fileExists(atPath: guess) {
                pathBySession[sessionId] = guess
                return guess
            }
        }
        let dirs = (try? fm.contentsOfDirectory(atPath: Paths.claudeProjects.path)) ?? []
        for dir in dirs {
            let candidate = Paths.claudeProjects.appendingPathComponent(dir)
                .appendingPathComponent("\(sessionId).jsonl").path
            if fm.fileExists(atPath: candidate) {
                pathBySession[sessionId] = candidate
                return candidate
            }
        }
        return nil
    }

    func read(path: String) -> TranscriptInfo? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let modified = attrs[.modificationDate] as? Date
        else { return nil }

        if let hit = cache[path], hit.size == size, hit.modified == modified {
            return hit.info
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let start = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }

        let info = parseTail(data, droppedHead: start > 0)
        cache[path] = CacheEntry(size: size, modified: modified, info: info)
        return info
    }

    private func parseTail(_ data: Data, droppedHead: Bool) -> TranscriptInfo {
        var info = TranscriptInfo()
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if droppedHead, !lines.isEmpty { lines.removeFirst() } // first line is likely cut

        let assistantMarker = Array(#""type":"assistant""#.utf8)
        for line in lines.reversed() {
            if info.gitBranch == nil, let branch = Self.extractBranch(line) {
                info.gitBranch = branch
            }
            guard line.firstRange(of: assistantMarker) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  (obj["isSidechain"] as? Bool) != true,
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let input = Self.int(usage["input_tokens"])
            let creation = Self.int(usage["cache_creation_input_tokens"])
            let read = Self.int(usage["cache_read_input_tokens"])
            info.modelId = message["model"] as? String
            info.requestedModel = obj["requestedModel"] as? String
            info.effort = obj["effort"] as? String
            info.contextTokens = input + creation + read
            info.outputTokens = Self.int(usage["output_tokens"])
            if let branch = obj["gitBranch"] as? String, !branch.isEmpty { info.gitBranch = branch }
            if let ts = obj["timestamp"] as? String { info.lastAssistantAt = Self.parseDate(ts) }
            break
        }
        return info
    }

    private static func extractBranch(_ line: Data.SubSequence) -> String? {
        let marker = Array(#""gitBranch":""#.utf8)
        guard let range = line.firstRange(of: marker) else { return nil }
        let rest = line[range.upperBound...]
        guard let end = rest.firstIndex(of: UInt8(ascii: "\"")) else { return nil }
        let branch = String(decoding: rest[rest.startIndex..<end], as: UTF8.self)
        return branch.isEmpty ? nil : branch
    }

    private static func int(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? 0 }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    static func parseDate(_ s: String) -> Date? { isoFractional.date(from: s) ?? iso.date(from: s) }
}
