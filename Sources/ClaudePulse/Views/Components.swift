import SwiftUI

enum Palette {
    static func usage(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        if pct >= 50 { return .yellow }
        return .green
    }

    static func activity(_ state: ActivityState) -> Color {
        switch state {
        case .needsPermission: return .orange
        case .waitingInput: return .blue
        case .working: return .green
        case .compacting: return .purple
        case .idle: return .secondary
        }
    }
}

/// Horizontal usage bar with an optional pace marker (how much of the window has elapsed).
struct UsageBar: View {
    var fraction: Double
    var color: Color
    var marker: Double? = nil
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
                if let marker {
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2, height: height + 6)
                        .offset(x: geo.size.width * min(1, max(0, marker)) - 1)
                }
            }
        }
        .frame(height: height)
    }
}

struct Chip: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct StatusDot: View {
    var state: ActivityState
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Palette.activity(state))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Palette.activity(state), lineWidth: 2)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.6)
                    .opacity(state == .idle ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
            .help(state.label)
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
