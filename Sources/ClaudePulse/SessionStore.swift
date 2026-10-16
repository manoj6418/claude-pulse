import Foundation
import Combine
import Darwin

final class Preferences: ObservableObject {
    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case fiveHour = "5h %"
        case both = "5h + 7d %"
        case iconOnly = "Icon only"
        var id: String { rawValue }
    }

    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    @Published var limitThresholds: [Int] {
        didSet { defaults.set(limitThresholds, forKey: "limitThresholds") }
    }
    @Published var contextThreshold: Int {
        didSet { defaults.set(contextThreshold, forKey: "contextThreshold") }
    }
    @Published var notifyAttention: Bool {
        didSet { defaults.set(notifyAttention, forKey: "notifyAttention") }
    }
    @Published var notifyFinished: Bool {
        didSet { defaults.set(notifyFinished, forKey: "notifyFinished") }
    }
    /// Turns shorter than this finish without a notification (you were likely watching).
    @Published var finishedMinSeconds: Int {
        didSet { defaults.set(finishedMinSeconds, forKey: "finishedMinSeconds") }
    }

    private let defaults = UserDefaults.standard

    init() {
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .fiveHour
        limitThresholds = defaults.array(forKey: "limitThresholds") as? [Int] ?? [75, 90, 95]
        contextThreshold = defaults.object(forKey: "contextThreshold") as? Int ?? 80
        notifyAttention = defaults.object(forKey: "notifyAttention") as? Bool ?? true
        notifyFinished = defaults.object(forKey: "notifyFinished") as? Bool ?? true
        finishedMinSeconds = defaults.object(forKey: "finishedMinSeconds") as? Int ?? 30
    }
}

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var limits: LimitsSnapshot?
    @Published private(set) var fiveHourProjection: Projection?
    @Published private(set) var sevenDayProjection: Projection?
    @Published private(set) var installStatus: Installer.Status = .notConnected
    @Published private(set) var lastRefresh = Date()

    let preferences: Preferences
    private let reader = TranscriptReader()
    private let history = LimitHistory()
    private let notifier = Notifier()
    private let queue = DispatchQueue(label: "claudepulse.refresh", qos: .utility)
    private var timer: Timer?
    private var tick = 0

    init(preferences: Preferences) {
        self.preferences = preferences
        Paths.ensureSupportDirs()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    var attentionCount: Int { sessions.filter { $0.activity.needsAttention }.count }

    func refresh() {
        tick += 1
        let checkInstall = tick % 5 == 1
        let cleanUp = tick % 150 == 1
        queue.async { [weak self] in
            guard let self else { return }
            let sessions = self.loadSessions()
            let limits = Self.currentLimits()
            if let limits { self.history.record(limits) }
            let fiveProjection = limits?.fiveHour.flatMap { w in
                self.history.projection(current: w, lookback: 3_600, minimumSpan: 20 * 60,
                                        value: { $0.fiveHour }, resetsAt: { $0.fiveHourResetsAt })
            }
            let sevenProjection = limits?.sevenDay.flatMap { w in
                self.history.projection(current: w, lookback: 24 * 3_600, minimumSpan: 2 * 3_600,
                                        value: { $0.sevenDay }, resetsAt: { $0.sevenDayResetsAt })
            }
            let install = checkInstall ? Installer.status() : nil
            if cleanUp { Self.cleanUpStaleFiles(live: Set(sessions.map(\.sessionId))) }

            DispatchQueue.main.async {
                self.sessions = sessions
                self.limits = limits
                self.fiveHourProjection = fiveProjection
                self.sevenDayProjection = sevenProjection
                if let install { self.installStatus = install }
                self.lastRefresh = Date()
                self.notifier.checkLimits(limits, thresholds: self.preferences.limitThresholds)
                self.notifier.checkSessions(
                    sessions,
                    contextThreshold: self.preferences.contextThreshold,
                    notifyAttention: self.preferences.notifyAttention,
                    notifyFinished: self.preferences.notifyFinished,
                    finishedMinSeconds: self.preferences.finishedMinSeconds
                )
            }
        }
    }

    func sendTestNotification(preferring preferred: SessionSummary? = nil) {
        let session = preferred ?? sessions.first { $0.finalReply != nil } ?? sessions.first
        notifier.sendTest(using: session)
    }

    func connect() throws {
        try Installer.connect()
        installStatus = Installer.status()
    }

    func disconnect() throws {
        try Installer.disconnect()
        installStatus = Installer.status()
    }

    // MARK: - Loading

    /// Drops windows whose reset time has passed: their usage is back to 0.
    private static func currentLimits() -> LimitsSnapshot? {
        guard var snapshot = LimitsStore.load() else { return nil }
        let now = Date()
        if let w = snapshot.fiveHour, w.resetsAt <= now { snapshot.fiveHour = nil }
        if let w = snapshot.sevenDay, w.resetsAt <= now { snapshot.sevenDay = nil }
        return snapshot
    }

    private func loadSessions() -> [SessionSummary] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Paths.claudeSessions, includingPropertiesForKeys: nil)) ?? []
        var result: [SessionSummary] = []
        var seen = Set<String>()

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(RegistryEntry.self, from: data),
                  Self.isAlive(entry.pid),
                  !seen.contains(entry.sessionId)
            else { continue }
            seen.insert(entry.sessionId)
            result.append(summary(for: entry))
        }

        return result.sorted { a, b in
            if a.activity.needsAttention != b.activity.needsAttention { return a.activity.needsAttention }
            if (a.activity == .working) != (b.activity == .working) { return a.activity == .working }
            return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
        }
    }

    private func summary(for entry: RegistryEntry) -> SessionSummary {
        let bridge = Self.load(BridgeSession.self, from: Paths.bridgeSessions.appendingPathComponent("\(entry.sessionId).json"))
        let hook = Self.load(HookStateRecord.self, from: Paths.hookStates.appendingPathComponent("\(entry.sessionId).json"))
        let path = reader.transcriptPath(sessionId: entry.sessionId, cwd: entry.cwd, hint: bridge?.transcriptPath)
        let transcript = path.flatMap { reader.read(path: $0) }

        let registryUpdated = entry.updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        let lastActivity = [transcript?.lastAssistantAt, bridge?.updatedAt, hook?.updatedAt, registryUpdated]
            .compactMap { $0 }.max()

        // The bridge reflects /model and /effort changes before the next reply lands in the transcript.
        let bridgeIsNewer = bridge != nil && (transcript?.lastAssistantAt == nil
            || bridge!.updatedAt >= transcript!.lastAssistantAt!.addingTimeInterval(-5))
        let modelId = bridgeIsNewer ? (bridge?.modelId ?? transcript?.modelId) : (transcript?.modelId ?? bridge?.modelId)
        let effort = bridgeIsNewer ? (bridge?.effort ?? transcript?.effort) : (transcript?.effort ?? bridge?.effort)
        let modelName = (bridgeIsNewer ? bridge?.modelName : nil) ?? ModelCatalog.displayName(for: modelId)

        let windowSize = bridge?.contextWindowSize
            ?? ModelCatalog.contextWindow(for: modelId, requested: transcript?.requestedModel)
        let tokens = bridgeIsNewer ? (bridge?.contextTokens ?? transcript?.contextTokens) : transcript?.contextTokens
        var percentage: Double?
        if bridgeIsNewer, let pct = bridge?.contextUsedPercentage {
            percentage = pct
        } else if let tokens {
            percentage = Double(tokens) / Double(windowSize) * 100
        }

        let (activity, message) = Self.activity(
            registryStatus: entry.status,
            registryStatusAt: registryUpdated,
            hook: hook,
            lastReplyAt: transcript?.lastAssistantAt
        )

        let fallbackName = ((entry.cwd ?? "") as NSString).lastPathComponent
        return SessionSummary(
            pid: entry.pid,
            sessionId: entry.sessionId,
            name: bridge?.sessionName ?? entry.name ?? fallbackName,
            cwd: entry.cwd ?? bridge?.cwd ?? "",
            startedAt: entry.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            activity: activity,
            attentionMessage: message,
            modelId: modelId,
            modelName: modelName,
            effort: effort,
            contextTokens: tokens,
            contextWindowSize: windowSize,
            contextPercentage: percentage,
            gitBranch: transcript?.gitBranch,
            costUSD: bridge?.costUSD,
            linesAdded: bridge?.linesAdded,
            linesRemoved: bridge?.linesRemoved,
            lastActivity: lastActivity,
            transcriptPath: path,
            entrypoint: entry.entrypoint,
            turnStartedAt: hook?.turnStartedAt,
            finishedAt: hook?.finishedAt,
            finalReply: hook?.finalReply
        )
    }

    private static func activity(
        registryStatus: String?,
        registryStatusAt: Date?,
        hook: HookStateRecord?,
        lastReplyAt: Date?
    ) -> (ActivityState, String?) {
        let registry: ActivityState = {
            let s = registryStatus?.lowercased() ?? ""
            if s.contains("permission") { return .needsPermission }
            if s.contains("wait") || s.contains("input") { return .waitingInput }
            if s == "busy" || s.contains("work") || s.contains("run") { return .working }
            return .idle
        }()
        guard let hook else { return (registry, nil) }

        let hookState: ActivityState
        switch hook.state {
        case .needsPermission: hookState = .needsPermission
        case .waitingInput: hookState = .waitingInput
        case .working: hookState = .working
        case .compacting: hookState = .compacting
        case .idle: hookState = .idle
        }

        // A reply written after the prompt means the session moved on.
        if hookState.needsAttention, let reply = lastReplyAt, reply > hook.updatedAt.addingTimeInterval(1) {
            return (.working, nil)
        }
        if let at = registryStatusAt, at > hook.updatedAt.addingTimeInterval(1), !hookState.needsAttention {
            return (registry, nil)
        }
        return (hookState, hookState.needsAttention ? hook.message : nil)
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(type, from: data)
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func cleanUpStaleFiles(live: Set<String>) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-86_400)
        for dir in [Paths.bridgeSessions, Paths.hookStates] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let id = file.deletingPathExtension().lastPathComponent
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if !live.contains(id), let modified, modified < cutoff { try? fm.removeItem(at: file) }
            }
        }
    }
}
