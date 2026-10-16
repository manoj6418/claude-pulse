import SwiftUI

struct RecentRow: View {
    var event: RecentEvent
    var now: Date
    /// The session is still running, so clicking can jump to it.
    var canJump: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(event.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Format.ago(event.at, now: now))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering && canJump ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if canJump, let pid = event.pid { TerminalJumper.jump(to: pid) }
        }
        .help(canJump ? "\(event.detail)\nClick to jump to the terminal" : event.detail)
    }

    private var icon: String {
        switch event.kind {
        case .finished: return "checkmark.circle.fill"
        case .needsPermission: return "hand.raised.fill"
        case .limit: return "gauge.with.dots.needle.67percent"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .finished: return .green
        case .needsPermission: return .orange
        case .limit: return .red
        }
    }
}
