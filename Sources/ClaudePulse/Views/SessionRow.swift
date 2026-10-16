import SwiftUI
import AppKit

struct SessionRow: View {
    var session: SessionSummary
    var now: Date
    var contextThreshold: Int
    var onAnswer: (PermissionRequestRecord, PermissionDecision) -> Void = { _, _ in }
    var primaryRequestId: String?
    var label = SessionLabel()
    /// Model + effort most sessions use; the row only shows its own when different.
    var commonModel: String?
    var onLabelChange: (SessionLabel) -> Void = { _ in }
    @State private var hovering = false
    @State private var showSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(state: session.activity)
                if label.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Text(label.name ?? session.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(label.name ?? session.name)
                Spacer(minLength: 4)
                Text(Format.ago(session.lastActivity, now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if !session.steps.isEmpty {
                    Button {
                        withAnimation(.snappy) { showSteps.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showSteps ? 180 : 0))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(showSteps ? "Hide recent steps" : "Show recent steps")
                }
            }

            HStack(spacing: 5) {
                if modelText != commonModel {
                    Chip(text: session.modelName, systemImage: "cpu", tint: .accentColor)
                    if let effort = session.effort {
                        Chip(text: effort, systemImage: "brain", tint: effortTint(effort))
                    }
                }
                if let cost = session.costUSD, cost > 0 {
                    Chip(text: Format.cost(cost), systemImage: "dollarsign.circle")
                }
                if let share = session.burnShare, share >= 0.05 {
                    Chip(text: "\(Int((share * 100).rounded()))% of last hr", systemImage: "flame", tint: share >= 0.5 ? .orange : .secondary)
                        .help("This session's share of all Claude spend in the last hour")
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
            if !infoItems.isEmpty {
                HStack(spacing: 10) {
                    ForEach(infoItems, id: \.text) { item in
                        Label(item.text, systemImage: item.icon)
                            .foregroundStyle(item.color)
                            .help(item.help)
                    }
                }
                .font(.system(size: 10))
                .lineLimit(1)
            }
            if let failed = session.lastStepFailed {
                Label("Failed: \(failed.text)\(failed.error.map { " · \($0)" } ?? "")", systemImage: "xmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(failed.error ?? failed.text)
            }
            if showSteps {
                StepList(steps: session.steps, now: now)
            }
            if let compactionNote {
                Text(compactionNote)
                    .font(.system(size: 10))
                    .foregroundStyle(compactsSoon ? .orange : .secondary)
            }

            if session.permissionRequests.isEmpty, let line = activityLine {
                Label(line.text, systemImage: line.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(line.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(line.text)
            }

            if let request = session.permissionRequests.first {
                PermissionCard(
                    request: request,
                    moreCount: session.permissionRequests.count - 1,
                    isPrimary: request.id == primaryRequestId,
                    onAnswer: { onAnswer(request, $0) }
                )
            } else if session.activity == .waitingInput {
                Label("Your turn", systemImage: "arrow.turn.down.left")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help(session.attentionMessage ?? "Claude finished and is waiting for your next message")
            } else if session.activity.isBlocking || session.activity == .compacting {
                Label(session.attentionMessage ?? session.activity.label, systemImage: attentionIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.activity(session.activity))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .overlay(alignment: .leading) {
            if let color = label.color.map(Palette.label) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(color)
                    .frame(width: 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(session.activity.isBlocking
                      ? Palette.activity(session.activity).opacity(0.10)
                      : Color.primary.opacity(hovering ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(session.activity.isBlocking ? Palette.activity(session.activity).opacity(0.5) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { TerminalJumper.jump(to: session.pid) }
        .help("\(session.cwd)\nClick to jump to the terminal")
        .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Button("Jump to Terminal") { TerminalJumper.jump(to: session.pid) }
        Divider()
        Button(label.pinned ? "Unpin" : "Pin to Top") {
            var l = label; l.pinned.toggle(); onLabelChange(l)
        }
        Button("Rename…") { rename() }
        Menu("Colour") {
            ForEach(SessionLabel.colors, id: \.self) { name in
                Button(name.capitalized) { var l = label; l.color = name; onLabelChange(l) }
            }
            if label.color != nil {
                Divider()
                Button("None") { var l = label; l.color = nil; onLabelChange(l) }
            }
        }
        Divider()
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

    /// Git, cache and background agents, as small icon + text items.
    private var infoItems: [(text: String, icon: String, color: Color, help: String)] {
        var items: [(String, String, Color, String)] = []
        if let branch = session.gitBranch {
            items.append((branch, "arrow.triangle.branch", .secondary, "Git branch"))
        }
        if let git = session.git {
            if git.changedFiles > 0 {
                items.append(("\(git.changedFiles) uncommitted", "pencil.line", .orange, "\(git.changedFiles) changed files not committed"))
            }
            if git.ahead > 0 {
                items.append(("\(git.ahead) unpushed", "arrow.up.circle", .orange, "\(git.ahead) commits not pushed"))
            }
            if git.isClean { items.append(("clean", "checkmark.circle", .secondary, "No uncommitted or unpushed changes")) }
        }
        if let cache = session.cache {
            let pct = "cache \(Int((cache.hitRate * 100).rounded()))%"
            if let until = cache.warmUntil {
                let left = until.timeIntervalSince(now)
                items.append(left > 0
                    ? ("\(pct) · warm \(Format.duration(left))", "bolt.horizontal.circle", .secondary,
                       "Last request read \(pct) of its input from the prompt cache. The cache stays warm until \(Format.resetTime(until)); after that the next message re-reads the whole context.")
                    : ("\(pct) · cold", "snowflake", .blue,
                       "The prompt cache expired at \(Format.resetTime(until)). The next message re-reads the whole context, which costs more."))
            } else {
                items.append((pct, "bolt.horizontal.circle", .secondary, "Share of the last request's input read from the prompt cache"))
            }
        }
        if session.runningAgents > 0 {
            items.append(("\(session.runningAgents) agent\(session.runningAgents == 1 ? "" : "s")", "person.2", .purple, "Background agents running in this session"))
        }
        return items
    }

    private func rename() {
        let alert = NSAlert()
        alert.messageText = "Rename session"
        alert.informativeText = "Shown only in Claude Pulse. Leave empty to use the session's own name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = label.name ?? session.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var l = label
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        l.name = name.isEmpty || name == session.name ? nil : name
        onLabelChange(l)
    }

    /// "Running go test ./... · 4m", "Thinking · 2m", or a stuck warning.
    private var activityLine: (text: String, icon: String, color: Color)? {
        guard session.activity == .working else { return nil }
        if let step = session.currentStep {
            let since = session.currentStepStartedAt.map { " · \(Format.elapsed(now.timeIntervalSince($0)))" } ?? ""
            return (step + since, "gearshape.2", .secondary)
        }
        if session.looksStuck(now: now) {
            let quiet = session.lastActivity.map { Format.duration(now.timeIntervalSince($0)) } ?? "a while"
            return ("Possibly stuck · nothing new for \(quiet)", "exclamationmark.triangle.fill", .orange)
        }
        let since = session.turnStartedAt.map { " · \(Format.elapsed(now.timeIntervalSince($0)))" } ?? ""
        if session.runningAgents > 0 {
            return ("Agents working" + since, "person.2", .secondary)
        }
        return ("Working" + since, "ellipsis.bubble", .secondary)
    }

    /// Auto-compact happens near the end of the window (about 97% on 1M models).
    private var compactsSoon: Bool { (session.contextPercentage ?? 0) >= 90 }

    private var compactionNote: String? {
        var parts: [String] = []
        if compactsSoon { parts.append("Auto-compact soon") }
        if session.compactCount > 0 { parts.append("Compacted \(session.compactCount)×") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var modelText: String {
        [session.modelName, session.effort].compactMap { $0 }.joined(separator: " ")
    }

    private var contextLabel: String {
        // Right after /compact Claude Code reports nothing until the next reply.
        guard let tokens = session.contextTokens, tokens > 0 else {
            return session.compactCount > 0 ? "— until next reply" : "ctx —"
        }
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
