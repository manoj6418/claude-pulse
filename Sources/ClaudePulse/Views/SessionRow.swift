import SwiftUI
import AppKit

struct SessionRow: View {
    var session: SessionSummary
    var now: Date
    var contextThreshold: Int
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(state: session.activity)
                Text(session.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let branch = session.gitBranch {
                    Chip(text: branch, systemImage: "arrow.triangle.branch")
                }
                Spacer(minLength: 4)
                Text(Format.ago(session.lastActivity, now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 5) {
                Chip(text: session.modelName, systemImage: "cpu", tint: .accentColor)
                if let effort = session.effort {
                    Chip(text: effort, systemImage: "brain", tint: effortTint(effort))
                }
                if let cost = session.costUSD, cost > 0 {
                    Chip(text: Format.cost(cost), systemImage: "dollarsign.circle")
                }
                if let added = session.linesAdded, let removed = session.linesRemoved, added + removed > 0 {
                    Text("+\(added) −\(removed)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                UsageBar(fraction: (session.contextPercentage ?? 0) / 100, color: contextColor, height: 5)
                Text(contextLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            if session.activity.needsAttention || session.activity == .compacting {
                Label(session.attentionMessage ?? session.activity.label, systemImage: attentionIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.activity(session.activity))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(session.activity.needsAttention
                      ? Palette.activity(session.activity).opacity(0.10)
                      : Color.primary.opacity(hovering ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(session.activity.needsAttention ? Palette.activity(session.activity).opacity(0.5) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { TerminalJumper.jump(to: session.pid) }
        .help("\(session.cwd)\nClick to jump to the terminal")
        .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Button("Jump to Terminal") { TerminalJumper.jump(to: session.pid) }
        Button("Open Folder in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd)) }
        Divider()
        Button("Copy Resume Command") {
            copy("cd \(shellQuote(session.cwd)) && claude --resume \(session.sessionId)")
        }
        Button("Copy Session ID") { copy(session.sessionId) }
        if let path = session.transcriptPath {
            Button("Reveal Transcript") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private var contextLabel: String {
        guard let tokens = session.contextTokens else { return "ctx —" }
        let pct = session.contextPercentage.map { " · \(Format.percent($0))" } ?? ""
        return "\(Format.tokens(tokens)) / \(Format.tokens(session.contextWindowSize))\(pct)"
    }

    private var contextColor: Color {
        let pct = session.contextPercentage ?? 0
        if pct >= Double(contextThreshold) { return .red }
        if pct >= Double(contextThreshold) * 0.75 { return .orange }
        return .teal
    }

    private var attentionIcon: String {
        switch session.activity {
        case .needsPermission: return "hand.raised.fill"
        case .waitingInput: return "text.bubble.fill"
        case .compacting: return "rectangle.compress.vertical"
        default: return "info.circle"
        }
    }

    private func effortTint(_ effort: String) -> Color {
        switch effort.lowercased() {
        case "max", "xhigh": return .pink
        case "high": return .purple
        case "medium": return .indigo
        default: return .secondary
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
