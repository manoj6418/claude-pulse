import Foundation

enum ModelCatalog {
    /// Friendly name for a model id such as "claude-opus-5-5" or "claude-sonnet-4-6[1m]".
    static func displayName(for id: String?) -> String {
        guard var id = id?.lowercased(), !id.isEmpty else { return "Unknown" }
        let oneM = id.contains("[1m]")
        id = id.replacingOccurrences(of: "[1m]", with: "")
        if id.hasPrefix("claude-") { id.removeFirst("claude-".count) }

        let families = ["fable", "opus", "sonnet", "haiku"]
        guard let family = families.first(where: { id.hasPrefix($0) }) else {
            return oneM ? "\(id) 1M" : id
        }
        let rest = id.dropFirst(family.count).split(separator: "-")
        let version = rest.prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        var name = family.capitalized
        if !version.isEmpty { name += " \(version)" }
        if oneM { name += " 1M" }
        return name
    }

    /// Context window when the status line did not report one. The 5.x families
    /// and any "[1m]" id run with 1M tokens; everything else is assumed 200K.
    static func contextWindow(for id: String?, requested: String?) -> Int {
        let ids = [id, requested].compactMap { $0?.lowercased() }
        if ids.contains(where: { $0.contains("[1m]") }) { return 1_000_000 }
        let oneMillionDefaults = ["fable-5", "opus-5", "sonnet-5", "haiku-5"]
        if ids.contains(where: { candidate in oneMillionDefaults.contains { candidate.contains($0) } }) {
            return 1_000_000
        }
        return 200_000
    }
}
