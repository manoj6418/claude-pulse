import SwiftUI

struct LimitCard: View {
    var title: String
    var window: LimitWindow?
    var windowLength: TimeInterval
    var projection: Projection?
    var now: Date

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
