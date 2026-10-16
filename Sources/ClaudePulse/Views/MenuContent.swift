import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct MenuContent: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var preferences: Preferences
    /// Snapshots can't render a ScrollView, so they lay the list out flat.
    var staticLayout = false
    @State var showingSettings = false
    @State private var now = Date()
    @State private var sessionListHeight: CGFloat = 0
    @AppStorage("recentExpanded") private var recentExpanded = false
    @AppStorage("todayExpanded") private var todayExpanded = false
    @State private var showIdle = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showingSettings {
                if staticLayout {
                    SettingsPanel(store: store, preferences: preferences)
                } else {
                    FitScrollView(maxHeight: max(300, (NSScreen.main?.visibleFrame.height ?? 900) - 140)) {
                        SettingsPanel(store: store, preferences: preferences)
                    }
                }
            } else {
                if let status = store.claudeStatus { statusBanner(status) }
                if let update = store.update { updateBanner(update) }
                if store.installStatus != .connected { connectBanner }
                if !store.unlistedRequests.isEmpty { unlistedRequestCards }
                limits
                if let today = store.today, today.costUSD > 0 { todayLine(today) }
                sessions
                if !recentEvents.isEmpty { recentList }
            }
            footer
        }
        .padding(14)
        .frame(width: 400)
        .onReceive(clock) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: PanelCapture.showSettings)) { note in
            showingSettings = (note.object as? Bool) ?? false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.orange.gradient)
            Text(showingSettings ? "Settings" : "Claude Pulse").font(.system(size: 14, weight: .bold))
            if !showingSettings, store.attentionCount > 0 {
                Chip(text: "\(store.attentionCount) need you", systemImage: "bell.fill", tint: .orange)
            }
            Spacer()
            if !showingSettings, !store.recentProjects.isEmpty {
                Menu {
                    Section("Start Claude in…") {
                        ForEach(store.recentProjects, id: \.self) { folder in
                            Button((folder as NSString).lastPathComponent) { store.startSession(in: folder) }
                                .help(folder)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("New Claude session in \(preferences.newSessionTerminal)")
            }
            Button {
                withAnimation(.snappy) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "xmark.circle.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help(showingSettings ? "Back" : "Settings")
        }
    }

    private var connectBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(bannerTitle, systemImage: "link.badge.plus")
                .font(.system(size: 12, weight: .semibold))
            Text("Adds a status line and a few hooks to ~/.claude/settings.json (a backup is saved first). This is how the 5h/7d limits and \"needs you\" alerts reach the menu bar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(store.installStatus == .notConnected ? "Connect" : "Repair") { try? store.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Text("New sessions pick it up; restart running ones.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Prompts from sessions that have no row (Claude Code doesn't list them).
    private var unlistedRequestCards: some View {
        VStack(spacing: 8) {
            ForEach(store.unlistedRequests) { request in
                VStack(alignment: .leading, spacing: 6) {
                    Text(request.cwd.map { ($0 as NSString).lastPathComponent } ?? "Claude Code")
                        .font(.system(size: 12, weight: .semibold))
                    PermissionCard(request: request, moreCount: 0, isPrimary: request.id == primaryRequestId) {
                        store.answer(request, with: $0)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.5)))
            }
        }
    }

    /// The prompt that ⌘↩ / ⌘⌫ answer: the first one shown.
    private var primaryRequestId: String? {
        store.unlistedRequests.first?.id
            ?? store.sessions.first { !$0.permissionRequests.isEmpty }?.permissionRequests.first?.id
    }

    private var bannerTitle: String {
        switch store.installStatus {
        case .connected: return "Connected"
        case .notConnected: return "Connect to Claude Code"
        case .partial: return "Connection incomplete"
        case .wrongPath: return "Connected to an old app location"
        }
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Plan usage", trailing: limitsFreshness)
            HStack(alignment: .top, spacing: 8) {
                LimitCard(title: "5-hour", window: store.limits?.fiveHour, windowLength: 5 * 3_600,
                          projection: store.fiveHourProjection, now: now, series: store.fiveHourSeries)
                LimitCard(title: "7-day", window: store.limits?.sevenDay, windowLength: 7 * 86_400,
                          projection: store.sevenDayProjection, now: now, series: store.sevenDaySeries,
                          chartRecordedOnly: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Today $12.40 · 3.1M in · 210k out", opening to the top models and projects.
    private func todayLine(_ today: DayUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { todayExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(todayExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    SectionHeader(title: "Today").fixedSize()
                    Text(Format.cost(today.costUSD)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Text("· \(Format.tokens(today.inputTokens)) in · \(Format.tokens(today.outputTokens)) out")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("API-equivalent spend reported by Claude Code for connected sessions, counted while Claude Pulse runs")

            if todayExpanded {
                HStack(alignment: .top, spacing: 16) {
                    breakdown("By model", today.costByModel)
                    breakdown("By project", today.costByProject)
                }
                .padding(.leading, 15)
                Button("Export all days as CSV…") { exportCSV() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .padding(.leading, 15)
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "claude-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.exportCSV(to: url)
    }

    private func statusBanner(_ status: (text: String, severity: String)) -> some View {
        Link(destination: URL(string: "https://status.claude.com")!) {
            Label("Claude: \(status.text)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .foregroundStyle(status.severity == "minor" ? .orange : .red)
                .background((status.severity == "minor" ? Color.orange : Color.red).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Open status.claude.com")
    }

    private func updateBanner(_ update: (version: String, url: URL)) -> some View {
        Link(destination: update.url) {
            Label("Claude Pulse \(update.version) is available — download", systemImage: "arrow.down.circle")
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func breakdown(_ title: String, _ values: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(values.sorted { $0.value > $1.value }.prefix(4), id: \.key) { item in
                HStack(spacing: 6) {
                    Text(item.key).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(Format.cost(item.value)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var limitsFreshness: String? {
        guard let captured = store.limits?.capturedAt else { return nil }
        return "updated \(Format.ago(captured, now: now))"
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sessions · \(store.sessions.count)", trailing: totalCost)
            if store.sessions.isEmpty {
                Text("No Claude Code sessions running.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else if staticLayout {
                sessionList
            } else {
                // A ScrollView has no natural height, so size it to the measured
                // list and only scroll once the list outgrows the screen.
                ScrollView {
                    sessionList.background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                        }
                    )
                }
                .frame(height: min(max(sessionListHeight, 60), maxSessionListHeight))
                .scrollIndicators(sessionListHeight > maxSessionListHeight ? .automatic : .never)
                .onPreferenceChange(ListHeightKey.self) { sessionListHeight = $0 }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if preferences.groupByProject {
                ForEach(projectGroups, id: \.name) { group in
                    HStack(spacing: 5) {
                        Image(systemName: "folder").font(.system(size: 10))
                        Text(group.name).font(.system(size: 11, weight: .semibold))
                        Text("\(group.sessions.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    ForEach(group.sessions) { sessionRow($0) }
                }
            } else {
                ForEach(visibleSessions) { sessionRow($0) }
            }
            if !hiddenIdle.isEmpty {
                Button(showIdle ? "Hide idle sessions" : "Show \(hiddenIdle.count) idle session\(hiddenIdle.count == 1 ? "" : "s")") {
                    withAnimation(.snappy) { showIdle.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        SessionRow(session: session, now: now, contextThreshold: preferences.contextThreshold,
                   onAnswer: { store.answer($0, with: $1) }, primaryRequestId: primaryRequestId,
                   label: store.labels[session.sessionId] ?? SessionLabel(),
                   onLabelChange: { store.setLabel($0, for: session.sessionId) })
    }

    /// Idle for 30+ minutes with nothing waiting; hidden when "Hide idle sessions" is on.
    private var hiddenIdle: [SessionSummary] {
        guard preferences.hideIdle else { return [] }
        return store.sessions.filter { session in
            session.activity == .idle && session.permissionRequests.isEmpty
                && store.labels[session.sessionId]?.pinned != true
                && now.timeIntervalSince(session.lastActivity ?? .distantPast) > 1_800
        }
    }

    /// Who needs you first, then pinned sessions, then the rest in the store's order.
    private var visibleSessions: [SessionSummary] {
        let hidden = showIdle ? [] : Set(hiddenIdle.map(\.sessionId))
        let shown = store.sessions.filter { !hidden.contains($0.sessionId) }
        func rank(_ s: SessionSummary) -> Int {
            if s.activity.needsAttention { return 0 }
            return store.labels[s.sessionId]?.pinned == true ? 1 : 2
        }
        return shown.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Sessions by project folder, keeping the list's order (who needs you first).
    private var projectGroups: [(name: String, sessions: [SessionSummary])] {
        var order: [String] = []
        var groups: [String: [SessionSummary]] = [:]
        for session in visibleSessions {
            if groups[session.projectName] == nil { order.append(session.projectName) }
            groups[session.projectName, default: []].append(session)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Room for the session list: the screen height minus the rest of the panel.
    private var maxSessionListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        var rest: CGFloat = 330
        rest += recentEvents.isEmpty ? 0 : (recentExpanded ? 190 : 30)
        rest += (store.today?.costUSD ?? 0) > 0 ? (todayExpanded ? 130 : 30) : 0
        rest += CGFloat(store.unlistedRequests.count) * 190
        return max(240, screen - rest)
    }

    private var totalCost: String? {
        let total = store.sessions.compactMap(\.costUSD).reduce(0, +)
        return total > 0 ? "\(Format.cost(total)) API-equivalent" : nil
    }

    /// Last 3 events from the past day.
    private var recentEvents: [RecentEvent] {
        Array(store.recent.filter { now.timeIntervalSince($0.at) < 86_400 }.prefix(3))
    }

    /// Folded to one line by default so the session list keeps the room.
    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.snappy) { recentExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(recentExpanded ? 90 : 0))
                        SectionHeader(title: "Recent · \(recentEvents.count)")
                            .fixedSize()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !recentExpanded, let latest = recentEvents.first {
                    Text(latest.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if recentExpanded {
                    Button("Clear") { store.clearRecent() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                }
            }
            if recentExpanded {
                VStack(spacing: 2) {
                    ForEach(recentEvents) { event in
                        RecentRow(event: event, now: now, canJump: canJump(event))
                    }
                }
            }
        }
    }

    private func canJump(_ event: RecentEvent) -> Bool {
        guard let id = event.sessionId else { return false }
        return store.sessions.contains { $0.sessionId == id }
    }

    private var footer: some View {
        HStack {
            Text("Refreshed \(Format.ago(store.lastRefresh, now: now))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .keyboardShortcut("q")
        }
    }
}

struct SettingsPanel: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var preferences: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var message: String?
    @State private var phoneStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("Menu bar") {
                Picker("Show", selection: $preferences.menuBarStyle) {
                    ForEach(Preferences.MenuBarStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle("\(HotKey.label) opens this panel from anywhere", isOn: $preferences.hotkeyEnabled)
            }

            group("Sessions") {
                Toggle("Group by project", isOn: $preferences.groupByProject)
                Toggle("Hide sessions idle for 30+ minutes", isOn: $preferences.hideIdle)
            }

            group("Notify me when") {
                Toggle("A session finishes", isOn: $preferences.notifyFinished)
                if preferences.notifyFinished {
                    Stepper(finishedThresholdLabel, value: $preferences.finishedMinSeconds, in: 0...600, step: 15)
                        .padding(.leading, 18)
                        .foregroundStyle(.secondary)
                }
                Toggle("A session needs permission", isOn: $preferences.notifyPermission)
                Toggle("A session is waiting for my input", isOn: $preferences.notifyWaitingInput)
                Toggle("A session's context is almost full", isOn: $preferences.notifyContext)
                if preferences.notifyContext {
                    Stepper("At \(preferences.contextThreshold)%",
                            value: $preferences.contextThreshold, in: 50...95, step: 5)
                        .padding(.leading, 18)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Plan usage reaches")
                    Spacer()
                    TextField("90", text: thresholdsBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("%").foregroundStyle(.secondary)
                }
                Toggle("A limit resets (after you'd used half of it)", isOn: $preferences.notifyReset)
                Toggle("A command runs long", isOn: $preferences.notifyLongRunning)
                if preferences.notifyLongRunning {
                    Stepper("After \(preferences.longRunningMinutes) min", value: $preferences.longRunningMinutes, in: 5...120, step: 5)
                        .padding(.leading, 18)
                        .foregroundStyle(.secondary)
                }
                Toggle("A session closes with uncommitted or unpushed work", isOn: $preferences.notifyUncommittedOnClose)
                Toggle("Stay quiet while that session's terminal is in front", isOn: $preferences.quietWhenTerminalInFront)
                Button("Send test notification") { store.sendTestNotification() }
                    .controlSize(.small)
            }

            group("Spend") {
                HStack {
                    Text("Daily budget")
                    Spacer()
                    Text("$").foregroundStyle(.secondary)
                    TextField("off", value: $preferences.dailyBudget, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                Text("Alerts at 80% and 100% of the day's API-equivalent spend. 0 turns it off.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Toggle("Daily summary at 6 PM", isOn: $preferences.dailySummary)
                Toggle("Weekly summary on Friday at 6 PM", isOn: $preferences.weeklySummary)
            }

            group("New sessions") {
                Picker("Open in", selection: $preferences.newSessionTerminal) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm").tag("iTerm")
                }
                .pickerStyle(.segmented)
                Text("The + button starts claude in a recent project folder.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            group("Online") {
                Toggle("Show Claude service problems (status.claude.com)", isOn: $preferences.showClaudeStatus)
                    .onChange(of: preferences.showClaudeStatus) { _, _ in store.checkClaudeStatus() }
                Toggle("Check GitHub for Claude Pulse updates", isOn: $preferences.checkForUpdates)
                    .onChange(of: preferences.checkForUpdates) { _, on in if on { store.checkForUpdate() } }
            }

            group("Phone alerts") {
                Toggle("Also send to my phone (ntfy)", isOn: $preferences.phoneEnabled)
                if preferences.phoneEnabled {
                    Text("Install the free **ntfy** app on your phone and subscribe to this topic. Keep it private: anyone who knows it can read the alerts.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("Topic", text: $preferences.phoneTopic)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(preferences.phoneTopic, forType: .string)
                        }
                        Button("New") { preferences.phoneTopic = PhoneNotifier.randomTopic() }
                            .help("Make a new random topic")
                    }
                    .controlSize(.small)
                    HStack {
                        Text("Server").foregroundStyle(.secondary)
                        TextField("https://ntfy.sh", text: $preferences.phoneServer)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)
                    Toggle("When a session finishes", isOn: $preferences.phoneFinished)
                    Toggle("When a session needs permission", isOn: $preferences.phonePermission)
                    Toggle("Include the command or reply text", isOn: $preferences.phoneIncludeDetails)
                        .help("Off: the phone gets only the session name and what happened")
                    HStack {
                        Button("Send test to phone") {
                            phoneStatus = "Sending…"
                            store.sendPhoneTest { phoneStatus = $0 ?? "Sent. Check your phone." }
                        }
                        .controlSize(.small)
                        if let phoneStatus {
                            Text(phoneStatus).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }

            group("Claude Code connection") {
                HStack {
                    Text(statusText).foregroundStyle(store.installStatus == .connected ? .green : .orange)
                    Spacer()
                    if store.installStatus == .connected {
                        Button("Disconnect") { run { try store.disconnect() } }
                    } else {
                        Button("Connect") { run { try store.connect() } }
                    }
                }
                if let message {
                    Text(message).font(.system(size: 11)).foregroundStyle(.red)
                }
            }
        }
        .font(.system(size: 12))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            content()
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var finishedThresholdLabel: String {
        preferences.finishedMinSeconds == 0
            ? "Every finished turn"
            : "Only if it worked \(preferences.finishedMinSeconds < 60 ? "\(preferences.finishedMinSeconds)s" : Format.duration(Double(preferences.finishedMinSeconds)))+"
    }

    private var statusText: String {
        switch store.installStatus {
        case .connected: return "Connected"
        case .notConnected: return "Not connected"
        case .partial: return "Partly connected"
        case .wrongPath: return "Points at an old app location"
        }
    }

    private var thresholdsBinding: Binding<String> {
        Binding(
            get: { preferences.limitThresholds.map(String.init).joined(separator: ", ") },
            set: { text in
                let values = text.split(whereSeparator: { $0 == "," || $0 == " " })
                    .compactMap { Int($0) }
                    .filter { (1...100).contains($0) }
                if !values.isEmpty { preferences.limitThresholds = Array(Set(values)).sorted() }
            }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        run {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
