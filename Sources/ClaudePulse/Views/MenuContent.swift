import SwiftUI
import ServiceManagement

struct MenuContent: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var preferences: Preferences
    /// Snapshots can't render a ScrollView, so they lay the list out flat.
    var staticLayout = false
    @State private var showingSettings = false
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showingSettings {
                SettingsPanel(store: store, preferences: preferences)
            } else {
                if store.installStatus != .connected { connectBanner }
                limits
                sessions
            }
            footer
        }
        .padding(14)
        .frame(width: 400)
        .onReceive(clock) { now = $0 }
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
                          projection: store.fiveHourProjection, now: now)
                LimitCard(title: "7-day", window: store.limits?.sevenDay, windowLength: 7 * 86_400,
                          projection: store.sevenDayProjection, now: now)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
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
                ScrollView { sessionList }
                    .frame(maxHeight: 440)
                    .scrollIndicators(.never)
            }
        }
    }

    private var sessionList: some View {
        VStack(spacing: 8) {
            ForEach(store.sessions) { session in
                SessionRow(session: session, now: now, contextThreshold: preferences.contextThreshold)
            }
        }
    }

    private var totalCost: String? {
        let total = store.sessions.compactMap(\.costUSD).reduce(0, +)
        return total > 0 ? "\(Format.cost(total)) API-equivalent" : nil
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
            }

            group("Alerts") {
                Toggle("Notify when a session finishes", isOn: $preferences.notifyFinished)
                if preferences.notifyFinished {
                    Stepper(finishedThresholdLabel, value: $preferences.finishedMinSeconds, in: 0...600, step: 15)
                        .padding(.leading, 18)
                        .foregroundStyle(.secondary)
                }
                Toggle("Notify when a session needs permission or input", isOn: $preferences.notifyAttention)
                HStack {
                    Text("Limit alerts at")
                    Spacer()
                    TextField("75, 90, 95", text: thresholdsBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
                Stepper("Context alert at \(preferences.contextThreshold)%",
                        value: $preferences.contextThreshold, in: 50...95, step: 5)
                Button("Send test notification") { store.sendTestNotification() }
                    .controlSize(.small)
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
            : "Only if it worked \(Format.duration(Double(preferences.finishedMinSeconds)))+"
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
