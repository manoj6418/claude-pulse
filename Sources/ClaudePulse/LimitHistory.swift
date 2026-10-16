import Foundation

/// Samples of plan usage over time, used for burn rate and projections.
struct LimitSample: Codable {
    var at: Date
    var fiveHour: Double?
    var fiveHourResetsAt: Date?
    var sevenDay: Double?
    var sevenDayResetsAt: Date?
}

struct Projection {
    /// Percentage points per hour over the recent past.
    var ratePerHour: Double
    /// When usage reaches 100% at this rate, if before the reset.
    var hitsLimitAt: Date?
    /// Expected usage at reset time at this rate (capped at 100).
    var atReset: Double
}

final class LimitHistory {
    private(set) var samples: [LimitSample] = []
    private let keep: TimeInterval = 8 * 86_400

    init() {
        if let data = try? Data(contentsOf: Paths.historyFile),
           let loaded = try? JSONCoding.decoder.decode([LimitSample].self, from: data) {
            samples = loaded
        }
    }

    func record(_ snapshot: LimitsSnapshot) {
        let sample = LimitSample(
            at: snapshot.capturedAt,
            fiveHour: snapshot.fiveHour?.usedPercentage,
            fiveHourResetsAt: snapshot.fiveHour?.resetsAt,
            sevenDay: snapshot.sevenDay?.usedPercentage,
            sevenDayResetsAt: snapshot.sevenDay?.resetsAt
        )
        if let last = samples.last,
           last.at == sample.at || (last.fiveHour == sample.fiveHour && last.sevenDay == sample.sevenDay
               && sample.at.timeIntervalSince(last.at) < 300) {
            return
        }
        samples.append(sample)
        let cutoff = Date().addingTimeInterval(-keep)
        samples.removeAll { $0.at < cutoff }
        if let data = try? JSONCoding.encoder.encode(samples) {
            FileManager.default.writeAtomically(data, to: Paths.historyFile)
        }
    }

    /// Usage points for the window that resets at `resetsAt`, oldest first.
    func series(resetsAt: Date, value: (LimitSample) -> Double?, resets: (LimitSample) -> Date?) -> [(Date, Double)] {
        samples.compactMap { sample in
            guard let r = resets(sample), abs(r.timeIntervalSince(resetsAt)) < 120, let v = value(sample) else { return nil }
            return (sample.at, v)
        }
    }

    /// Projects one window from samples inside the current window and the lookback.
    /// Usage arrives as whole percents, so one step over a few minutes looks like a
    /// huge rate. No projection until the samples span `minimumSpan`, and the
    /// change is reduced by half a step for rounding.
    func projection(
        current: LimitWindow,
        lookback: TimeInterval,
        minimumSpan: TimeInterval,
        value: (LimitSample) -> Double?,
        resetsAt: (LimitSample) -> Date?,
        now: Date = Date()
    ) -> Projection? {
        let sameWindow = samples.filter { sample in
            guard let r = resetsAt(sample) else { return false }
            return abs(r.timeIntervalSince(current.resetsAt)) < 120 && now.timeIntervalSince(sample.at) <= lookback
        }
        guard let first = sameWindow.first, let firstValue = value(first) else { return nil }
        let span = now.timeIntervalSince(first.at)
        guard span >= minimumSpan else { return nil }
        let hours = span / 3_600

        let rate = max(0, (current.usedPercentage - firstValue - 0.5) / hours)
        let remainingHours = max(0, current.resetsAt.timeIntervalSince(now) / 3_600)
        let atReset = min(100, current.usedPercentage + rate * remainingHours)
        var hitsAt: Date?
        if rate > 0.01 {
            let hoursToFull = (100 - current.usedPercentage) / rate
            if hoursToFull < remainingHours { hitsAt = now.addingTimeInterval(hoursToFull * 3_600) }
        }
        return Projection(ratePerHour: rate, hitsLimitAt: hitsAt, atReset: atReset)
    }
}
