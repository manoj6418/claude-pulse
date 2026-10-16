import Foundation

/// One day's spend, from the cost and token totals Claude Code reports per session.
struct DayUsage: Codable {
    var costUSD: Double = 0
    var inputTokens = 0
    var outputTokens = 0
    var costByModel: [String: Double] = [:]
    var costByProject: [String: Double] = [:]
    /// Sessions that spent anything that day.
    var sessions: Set<String>?
}

/// Turns each session's running totals into per-day amounts. Only growth
/// since the last look is added, so restarts never count spend twice.
final class UsageLedger {
    private struct Mark: Codable {
        var cost: Double
        var input: Int
        var output: Int
    }

    private struct Stored: Codable {
        var createdAt: Date
        var days: [String: DayUsage]
        var marks: [String: Mark]
    }

    private var stored: Stored
    /// Spend per session over the last hour, for "share of the last hour".
    private var recentSpend: [String: [(at: Date, cost: Double)]] = [:]
    private let url = Paths.support.appendingPathComponent("usage-ledger.json")

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONCoding.decoder.decode(Stored.self, from: data) {
            stored = loaded
        } else {
            stored = Stored(createdAt: Date(), days: [:], marks: [:])
        }
    }

    func update(with sessions: [SessionSummary], now: Date = Date()) {
        let day = Self.dayFormatter.string(from: now)
        var changed = false

        for session in sessions {
            let cost = session.costUSD ?? 0
            let input = session.totalInputTokens ?? 0
            let output = session.totalOutputTokens ?? 0
            guard cost > 0 || input > 0 else { continue }

            // First sighting: sessions that began after the ledger existed count in full;
            // older ones count only from now on.
            let mark = stored.marks[session.sessionId]
                ?? ((session.startedAt ?? .distantPast) >= stored.createdAt ? Mark(cost: 0, input: 0, output: 0)
                                                                            : Mark(cost: cost, input: input, output: output))
            // A resumed session starts its totals again from zero.
            let restarted = cost < mark.cost - 0.0001 || input < mark.input
            let dCost = restarted ? cost : cost - mark.cost
            let dIn = restarted ? input : input - mark.input
            let dOut = restarted ? output : max(0, output - mark.output)

            stored.marks[session.sessionId] = Mark(cost: cost, input: input, output: output)
            guard dCost > 0.000001 || dIn > 0 || dOut > 0 else {
                if mark.cost != cost || mark.input != input { changed = true }
                continue
            }
            changed = true

            var usage = stored.days[day] ?? DayUsage()
            usage.costUSD += dCost
            usage.inputTokens += dIn
            usage.outputTokens += dOut
            usage.costByModel[session.modelName, default: 0] += dCost
            usage.costByProject[session.projectName, default: 0] += dCost
            usage.sessions = (usage.sessions ?? []).union([session.sessionId])
            stored.days[day] = usage

            if dCost > 0 { recentSpend[session.sessionId, default: []].append((now, dCost)) }
        }

        let hourAgo = now.addingTimeInterval(-3_600)
        recentSpend = recentSpend.mapValues { $0.filter { $0.at > hourAgo } }.filter { !$0.value.isEmpty }

        if changed { save(now: now) }
    }

    func today(now: Date = Date()) -> DayUsage? {
        stored.days[Self.dayFormatter.string(from: now)]
    }

    /// Last 7 days: total cost, distinct sessions, and the project that cost most.
    func week(now: Date = Date()) -> (cost: Double, sessions: Int, topProject: String?) {
        var cost = 0.0
        var sessions = Set<String>()
        var byProject: [String: Double] = [:]
        for offset in 0..<7 {
            let key = Self.dayFormatter.string(from: now.addingTimeInterval(-Double(offset) * 86_400))
            guard let day = stored.days[key] else { continue }
            cost += day.costUSD
            sessions.formUnion(day.sessions ?? [])
            for (project, value) in day.costByProject { byProject[project, default: 0] += value }
        }
        return (cost, sessions.count, byProject.max { $0.value < $1.value }?.key)
    }

    /// All recorded days, oldest first, for CSV export.
    func allDays() -> [(String, DayUsage)] {
        stored.days.sorted { $0.key < $1.key }
    }

    /// Each session's share of spend in the last hour, when there was any.
    func burnShares() -> [String: Double] {
        let totals = recentSpend.mapValues { $0.reduce(0) { $0 + $1.cost } }
        let all = totals.values.reduce(0, +)
        guard all > 0 else { return [:] }
        return totals.mapValues { $0 / all }
    }

    private func save(now: Date) {
        // Keep a month of days and at most 500 session marks.
        let cutoff = Self.dayFormatter.string(from: now.addingTimeInterval(-31 * 86_400))
        stored.days = stored.days.filter { $0.key >= cutoff }
        if stored.marks.count > 500 {
            stored.marks = Dictionary(uniqueKeysWithValues: stored.marks.suffix(500).map { ($0.key, $0.value) })
        }
        if let data = try? JSONCoding.encoder.encode(stored) {
            FileManager.default.writeAtomically(data, to: url)
        }
    }
}
