import SwiftUI
import Charts

struct LimitCard: View {
    var title: String
    var window: LimitWindow?
    var windowLength: TimeInterval
    var projection: Projection?
    var now: Date
    /// Usage samples in this window, for the small history chart.
    var series: [(Date, Double)] = []
    /// Chart only the recorded part, not the whole window (for 7 days that's mostly empty).
    var chartRecordedOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let window {
                    Text(Format.percent(window.usedPercentage))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.usage(window.usedPercentage))
                        .monospacedDigit()
                } else {
                    Text("—").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
            }

            UsageBar(
                fraction: (window?.usedPercentage ?? 0) / 100,
                color: Palette.usage(window?.usedPercentage ?? 0),
                marker: elapsedFraction
            )

            if let window, series.count >= 2 {
                history(window)
            }

            if let window {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text(Format.resetTime(window.resetsAt)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("in \(Format.countdown(to: window.resetsAt, from: now))")
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("Resets \(window.resetsAt.formatted(date: .complete, time: .shortened))")

                if let paceText {
                    Label(paceText.text, systemImage: paceText.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(paceText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No data yet. It appears after the next reply in any session (Pro/Max plans).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    /// How usage climbed since the window opened; the x axis spans the whole window.
    private func history(_ window: LimitWindow) -> some View {
        let windowStart = window.resetsAt.addingTimeInterval(-windowLength)
        let points = series.filter { $0.0 >= windowStart }
        let start = chartRecordedOnly ? (points.first?.0 ?? windowStart) : windowStart
        let end = chartRecordedOnly ? max(now, start.addingTimeInterval(60)) : window.resetsAt
        let color = Palette.usage(window.usedPercentage)
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("Time", point.0), y: .value("Used", point.1))
                    .foregroundStyle(color.opacity(0.18))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("Time", point.0), y: .value("Used", point.1))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.stepEnd)
            }
            RuleMark(x: .value("Now", now))
                .foregroundStyle(Color.primary.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 26)
        .help(chartRecordedOnly ? "Usage since Claude Pulse started recording" : "Usage since this window opened")
    }

    /// Share of the window that has already passed; the bar's marker shows "on pace" usage.
    private var elapsedFraction: Double? {
        guard let window else { return nil }
        let remaining = window.resetsAt.timeIntervalSince(now)
        return min(1, max(0, 1 - remaining / windowLength))
    }

    private var paceText: (text: String, icon: String, color: Color)? {
        guard let window else { return nil }
        if let projection, let hits = projection.hitsLimitAt {
            return ("At this pace you hit 100% at \(Format.resetTime(hits)) (in \(Format.countdown(to: hits, from: now)))",
                    "exclamationmark.triangle.fill", .orange)
        }
        if let projection, projection.ratePerHour > 0.05 {
            return ("~\(Format.percent(projection.atReset)) by reset at \(String(format: "%.1f", projection.ratePerHour))%/h",
                    "speedometer", .secondary)
        }
        guard let elapsed = elapsedFraction, elapsed > 0.05 else { return nil }
        let pace = window.usedPercentage / 100 - elapsed
        if pace > 0.1 { return ("Ahead of an even pace", "hare", .orange) }
        if pace < -0.1 { return ("Plenty of room left", "checkmark.circle", .green) }
        return ("On an even pace", "equal.circle", .secondary)
    }
}
