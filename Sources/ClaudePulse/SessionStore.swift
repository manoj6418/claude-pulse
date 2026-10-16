import Foundation
import Combine
import Darwin

final class Preferences: ObservableObject {
    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case bars = "Bars"
        case fiveHour = "5h %"
        case both = "5h + 7d %"
        case iconOnly = "Icon only"
        var id: String { rawValue }
    }

    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    @Published var notifyFinished: Bool {
        didSet { defaults.set(notifyFinished, forKey: "notifyFinished") }
    }
    /// Turns shorter than this finish without a notification (you were likely watching).
    @Published var finishedMinSeconds: Int {
        didSet { defaults.set(finishedMinSeconds, forKey: "finishedMinSeconds") }
    }
    @Published var notifyPermission: Bool {
        didSet { defaults.set(notifyPermission, forKey: "notifyPermission") }
    }
    @Published var notifyWaitingInput: Bool {
        didSet { defaults.set(notifyWaitingInput, forKey: "notifyWaitingInput") }
    }
    @Published var notifyContext: Bool {
        didSet { defaults.set(notifyContext, forKey: "notifyContext") }
    }
    @Published var contextThreshold: Int {
        didSet { defaults.set(contextThreshold, forKey: "contextThreshold") }
    }
    @Published var limitThresholds: [Int] {
        didSet { defaults.set(limitThresholds, forKey: "limitAlertThresholds") }
    }
    @Published var notifyReset: Bool {
        didSet { defaults.set(notifyReset, forKey: "notifyReset") }
    }
    @Published var hotkeyEnabled: Bool {
        didSet {
            defaults.set(hotkeyEnabled, forKey: "hotkeyEnabled")
            HotKey.shared.setEnabled(hotkeyEnabled)
        }
    }
    @Published var groupByProject: Bool {
        didSet { defaults.set(groupByProject, forKey: "groupByProject") }
    }
    @Published var hideIdle: Bool {
        didSet { defaults.set(hideIdle, forKey: "hideIdle") }
    }

    @Published var notifyLongRunning: Bool {
        didSet { defaults.set(notifyLongRunning, forKey: "notifyLongRunning") }
    }
    @Published var longRunningMinutes: Int {
        didSet { defaults.set(longRunningMinutes, forKey: "longRunningMinutes") }
    }
    @Published var notifyUncommittedOnClose: Bool {
        didSet { defaults.set(notifyUncommittedOnClose, forKey: "notifyUncommittedOnClose") }
    }
    /// Daily spend cap in USD; 0 turns the budget alerts off.
    @Published var dailyBudget: Double {
        didSet { defaults.set(dailyBudget, forKey: "dailyBudget") }
    }
    @Published var dailySummary: Bool {
        didSet { defaults.set(dailySummary, forKey: "dailySummary") }
    }
    @Published var weeklySummary: Bool {
        didSet { defaults.set(weeklySummary, forKey: "weeklySummary") }
    }
    /// Skip a session's banners while its terminal app is in front (you're likely looking at it).
    @Published var quietWhenTerminalInFront: Bool {
        didSet { defaults.set(quietWhenTerminalInFront, forKey: "quietWhenTerminalInFront") }
    }
    @Published var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") }
    }
    @Published var showClaudeStatus: Bool {
        didSet { defaults.set(showClaudeStatus, forKey: "showClaudeStatus") }
    }
    @Published var newSessionTerminal: String {
        didSet { defaults.set(newSessionTerminal, forKey: "newSessionTerminal") }
    }

    // Phone alerts through ntfy.
    @Published var phoneEnabled: Bool {
        didSet { defaults.set(phoneEnabled, forKey: "phoneEnabled") }
    }
    @Published var phoneServer: String {
        didSet { defaults.set(phoneServer, forKey: "phoneServer") }
    }
    @Published var phoneTopic: String {
        didSet { defaults.set(phoneTopic, forKey: "phoneTopic") }
    }
    @Published var phoneFinished: Bool {
        didSet { defaults.set(phoneFinished, forKey: "phoneFinished") }
    }
    @Published var phonePermission: Bool {
        didSet { defaults.set(phonePermission, forKey: "phonePermission") }
    }
    /// Off: phone alerts say which session and what happened, never the command or reply text.
    @Published var phoneIncludeDetails: Bool {
        didSet { defaults.set(phoneIncludeDetails, forKey: "phoneIncludeDetails") }
    }

    private let defaults = UserDefaults.standard

    init() {
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .bars
        notifyFinished = defaults.object(forKey: "notifyFinished") as? Bool ?? true
        finishedMinSeconds = defaults.object(forKey: "finishedMinSeconds") as? Int ?? 30
        notifyPermission = defaults.object(forKey: "notifyPermission") as? Bool ?? true
        notifyWaitingInput = defaults.object(forKey: "notifyWaitingInput") as? Bool ?? false
        notifyContext = defaults.object(forKey: "notifyContext") as? Bool ?? false
        contextThreshold = defaults.object(forKey: "contextThreshold") as? Int ?? 80
        limitThresholds = defaults.array(forKey: "limitAlertThresholds") as? [Int] ?? [90]
        notifyReset = defaults.object(forKey: "notifyReset") as? Bool ?? true
        hotkeyEnabled = defaults.object(forKey: "hotkeyEnabled") as? Bool ?? true
        groupByProject = defaults.object(forKey: "groupByProject") as? Bool ?? false
        hideIdle = defaults.object(forKey: "hideIdle") as? Bool ?? false
        notifyLongRunning = defaults.object(forKey: "notifyLongRunning") as? Bool ?? true
        longRunningMinutes = defaults.object(forKey: "longRunningMinutes") as? Int ?? 15
        notifyUncommittedOnClose = defaults.object(forKey: "notifyUncommittedOnClose") as? Bool ?? true
        dailyBudget = defaults.object(forKey: "dailyBudget") as? Double ?? 0
        dailySummary = defaults.object(forKey: "dailySummary") as? Bool ?? false
        weeklySummary = defaults.object(forKey: "weeklySummary") as? Bool ?? true
        quietWhenTerminalInFront = defaults.object(forKey: "quietWhenTerminalInFront") as? Bool ?? true
        checkForUpdates = defaults.object(forKey: "checkForUpdates") as? Bool ?? true
        showClaudeStatus = defaults.object(forKey: "showClaudeStatus") as? Bool ?? true
        newSessionTerminal = defaults.string(forKey: "newSessionTerminal") ?? "Terminal"
        phoneEnabled = defaults.object(forKey: "phoneEnabled") as? Bool ?? false
        phoneServer = defaults.string(forKey: "phoneServer") ?? "https://ntfy.sh"
        phoneFinished = defaults.object(forKey: "phoneFinished") as? Bool ?? true
        phonePermission = defaults.object(forKey: "phonePermission") as? Bool ?? true
        phoneIncludeDetails = defaults.object(forKey: "phoneIncludeDetails") as? Bool ?? false
        if let topic = defaults.string(forKey: "phoneTopic"), !topic.isEmpty {
            phoneTopic = topic
        } else {
            phoneTopic = PhoneNotifier.randomTopic()
            defaults.set(phoneTopic, forKey: "phoneTopic")
        }
    }

    var alertSettings: AlertSettings {
        AlertSettings(
            finished: notifyFinished,
            finishedMinSeconds: finishedMinSeconds,
            permission: notifyPermission,
            waitingInput: notifyWaitingInput,
            context: notifyContext,
            contextThreshold: contextThreshold,
            limitThresholds: limitThresholds,
            reset: notifyReset,
            longRunningMinutes: notifyLongRunning ? longRunningMinutes : nil,
            uncommittedOnClose: notifyUncommittedOnClose,
            dailyBudget: dailyBudget,
            dailySummary: dailySummary,
            weeklySummary: weeklySummary,
            quietWhenTerminalInFront: quietWhenTerminalInFront
        )
    }
}

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var limits: LimitsSnapshot?
    @Published private(set) var fiveHourProjection: Projection?
    @Published private(set) var sevenDayProjection: Projection?
    @Published private(set) var installStatus: Installer.Status = .notConnected
    @Published private(set) var lastRefresh = Date()
    @Published private(set) var recent: [RecentEvent] = []
    /// Prompts from sessions Claude Code doesn't list (e.g. sessions started inside another one).
    @Published private(set) var unlistedRequests: [PermissionRequestRecord] = []
    @Published private(set) var today: DayUsage?
    @Published private(set) var fiveHourSeries: [(Date, Double)] = []
    @Published private(set) var sevenDaySeries: [(Date, Double)] = []
    @Published private(set) var labels: [String: SessionLabel] = [:]
    /// Set when status.claude.com reports a problem.
    @Published private(set) var claudeStatus: (text: String, severity: String)?
    /// Set when GitHub has a newer release.
    @Published private(set) var update: (version: String, url: URL)?
    /// Folders of recent sessions, newest first, for "New session".
    @Published private(set) var recentProjects: [String] = []

    let preferences: Preferences
    private let reader = TranscriptReader()
    private let history = LimitHistory()
    private let ledger = UsageLedger()
    private let gitWatcher = GitWatcher()
    private let notifier = Notifier()
    private let queue = DispatchQueue(label: "claudepulse.refresh", qos: .utility)
    private var timer: Timer?
    private var tick = 0
    private let recentLimit = 20

    /// Off for one-shot command-line runs (snapshots, tests), so they never
    /// repeat the running app's notifications.
    private let detectsEvents: Bool

    init(preferences: Preferences, detectsEvents: Bool = true) {
        self.preferences = preferences
        self.detectsEvents = detectsEvents
        Paths.ensureSupportDirs()
        recent = Self.loadRecent()
        if let data = UserDefaults.standard.data(forKey: "sessionLabels"),
           let saved = try? JSONDecoder().decode([String: SessionLabel].self, from: data) {
            labels = saved
        }
        recentProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
        notifier.onEvent = { [weak self] event in self?.addRecent(event) }
        notifier.onAnswer = { [weak self] id, decision in self?.answer(requestId: id, with: decision) }
        notifier.onPhone = { [weak self] kind, title, short, detailed in
            guard let self, self.detectsEvents else { return }
            let p = self.preferences
            guard p.phoneEnabled, (kind == .finished && p.phoneFinished) || (kind == .permission && p.phonePermission)
            else { return }
            PhoneNotifier.send(server: p.phoneServer, topic: p.phoneTopic, title: title,
                               message: p.phoneIncludeDetails ? detailed : short, kind: kind)
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Sessions blocked on a permission prompt: the "need you" badge and menu bar count.
    var attentionCount: Int { sessions.filter { $0.activity.isBlocking }.count + unlistedRequests.count }

    func refresh() {
        tick += 1
        let checkInstall = tick % 5 == 1
        if detectsEvents, tick % 150 == 1 { checkClaudeStatus() }       // every 5 minutes
        if detectsEvents, tick % 21_600 == 1 { checkForUpdate() }       // every 12 hours
        let cleanUp = tick % 150 == 1
        let answered = answeredRequests
        queue.async { [weak self] in
            guard let self else { return }
            let requests = Self.loadPermissionRequests().filter { !answered.contains($0.id) }
            var sessions = self.loadSessions(requests: requests)
            self.ledger.update(with: sessions)
            let shares = self.ledger.burnShares()
            for i in sessions.indices { sessions[i].burnShare = shares[sessions[i].sessionId] }
            let today = self.ledger.today()
            let week = self.ledger.week()
            let fiveSeries = Self.currentLimits()?.fiveHour.map { w in
                self.history.series(resetsAt: w.resetsAt, value: { $0.fiveHour }, resets: { $0.fiveHourResetsAt })
            } ?? []
            let sevenSeries = Self.currentLimits()?.sevenDay.map { w in
                self.history.series(resetsAt: w.resetsAt, value: { $0.sevenDay }, resets: { $0.sevenDayResetsAt })
            } ?? []
            let listed = Set(sessions.map(\.sessionId))
            let unlisted = requests.filter { !listed.contains($0.sessionId) }.sorted { $0.createdAt < $1.createdAt }
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
                self.rememberProjects(sessions.map(\.cwd))
                self.unlistedRequests = unlisted
                self.today = today
                self.fiveHourSeries = fiveSeries
                self.sevenDaySeries = sevenSeries
                self.limits = limits
                self.fiveHourProjection = fiveProjection
                self.sevenDayProjection = sevenProjection
                if let install { self.installStatus = install }
                self.lastRefresh = Date()
                guard self.detectsEvents else { return }
                let settings = self.preferences.alertSettings
                self.notifier.checkLimits(limits, settings: settings)
                self.notifier.checkSessions(sessions, settings: settings)
                self.notifier.checkUnlistedRequests(unlisted, settings: settings)
                self.notifier.prunePermissionRequests(keeping: Set(requests.map(\.id)))
                self.notifier.checkSpend(today: today, week: week, settings: settings)
            }
        }
    }

    // MARK: - Labels

    func setLabel(_ label: SessionLabel, for sessionId: String) {
        labels[sessionId] = label == SessionLabel() ? nil : label
        if let data = try? JSONEncoder().encode(labels) {
            UserDefaults.standard.set(data, forKey: "sessionLabels")
        }
    }

    // MARK: - Recent projects and new sessions

    private func rememberProjects(_ folders: [String]) {
        var list = recentProjects
        for folder in folders where !folder.isEmpty {
            list.removeAll { $0 == folder }
            list.insert(folder, at: 0)
        }
        list = Array(list.prefix(12))
        guard list != recentProjects else { return }
        recentProjects = list
        UserDefaults.standard.set(list, forKey: "recentProjects")
    }

    /// Opens Terminal or iTerm in `folder` and starts `claude` there.
    func startSession(in folder: String) {
        let command = "cd \(Self.shellQuote(folder)) && claude"
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source: String
        if preferences.newSessionTerminal == "iTerm" {
            source = """
            tell application id "com.googlecode.iterm2"
                activate
                set w to (create window with default profile)
                tell current session of w to write text "\(escaped)"
            end tell
            """
        } else {
            source = """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { Notifier.log("new session failed: \(error)") }
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: - Export

    /// One total row per day, then one row per model and per project.
    func exportCSV(to url: URL) throws {
        var lines = ["date,kind,name,cost_usd,input_tokens,output_tokens,sessions"]
        func field(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        for (day, usage) in ledger.allDays() {
            lines.append("\(day),total,,\(String(format: "%.4f", usage.costUSD)),\(usage.inputTokens),\(usage.outputTokens),\(usage.sessions?.count ?? 0)")
            for (model, cost) in usage.costByModel.sorted(by: { $0.value > $1.value }) {
                lines.append("\(day),model,\(field(model)),\(String(format: "%.4f", cost)),,,")
            }
            for (project, cost) in usage.costByProject.sorted(by: { $0.value > $1.value }) {
                lines.append("\(day),project,\(field(project)),\(String(format: "%.4f", cost)),,,")
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Claude status and updates (network; each can be turned off)

    private static let web: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func checkClaudeStatus() {
        guard preferences.showClaudeStatus,
              let url = URL(string: "https://status.claude.com/api/v2/status.json") else {
            claudeStatus = nil
            return
        }
        Self.web.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let status = json["status"] as? [String: Any],
                  let indicator = status["indicator"] as? String
            else { return }
            let text = status["description"] as? String ?? indicator
            DispatchQueue.main.async {
                self?.claudeStatus = indicator == "none" ? nil : (text, indicator)
            }
        }.resume()
    }

    func checkForUpdate() {
        guard preferences.checkForUpdates,
              let url = URL(string: "https://api.github.com/repos/manoj6418/claude-pulse/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        Self.web.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let newer = latest.compare(current, options: .numeric) == .orderedDescending
            DispatchQueue.main.async { self?.update = newer ? (latest, page) : nil }
        }.resume()
    }


    func sendPhoneTest(completion: @escaping (String?) -> Void) {
        let p = preferences
        PhoneNotifier.send(server: p.phoneServer, topic: p.phoneTopic, title: "✓ Claude Pulse test",
                           message: "Phone alerts are working.", kind: .test, completion: completion)
    }

    func sendTestNotification(preferring preferred: SessionSummary? = nil) {
        let session = preferred ?? sessions.first { $0.finalReply != nil } ?? sessions.first
        notifier.sendTest(using: session)
    }

    // MARK: - Recent

    // MARK: - Permission answers

    /// Requests answered from here; hidden until their hook removes the file.
    private var answeredRequests: Set<String> = []

    func answer(_ request: PermissionRequestRecord, with decision: PermissionDecision) {
        answer(requestId: request.id, with: decision)
    }

    func answer(requestId: String, with decision: PermissionDecision) {
        let requestURL = Paths.permissionRequests.appendingPathComponent("\(requestId).json")
        guard FileManager.default.fileExists(atPath: requestURL.path),
              let data = try? JSONEncoder().encode(PermissionResponse(id: requestId, decision: decision))
        else { return }
        FileManager.default.writeAtomically(
            data, to: Paths.permissionResponses.appendingPathComponent("\(requestId).json"))
        answeredRequests.insert(requestId)
        Notifier.log("answered \(decision.rawValue) for request \(requestId)")
        refresh()
    }

    /// Requests whose hook is still waiting; a dead hook's leftovers are removed.
    private static func loadPermissionRequests() -> [PermissionRequestRecord] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Paths.permissionRequests, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let request = try? JSONCoding.decoder.decode(PermissionRequestRecord.self, from: data)
            else { return nil }
            guard isAlive(request.hookPid) else {
                try? fm.removeItem(at: file)
                return nil
            }
            return request
        }
    }

    func clearRecent() {
        recent = []
        saveRecent()
    }

    private func addRecent(_ event: RecentEvent) {
        recent.insert(event, at: 0)
        if recent.count > recentLimit { recent.removeLast(recent.count - recentLimit) }
        saveRecent()
    }

    private func saveRecent() {
        if let data = try? JSONCoding.encoder.encode(recent) {
            FileManager.default.writeAtomically(data, to: Paths.recentFile)
        }
    }

    private static func loadRecent() -> [RecentEvent] {
        guard let data = try? Data(contentsOf: Paths.recentFile),
              let events = try? JSONCoding.decoder.decode([RecentEvent].self, from: data)
        else { return [] }
        return events
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

    private func loadSessions(requests: [PermissionRequestRecord]) -> [SessionSummary] {
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
            var session = summary(for: entry)
            session.git = gitWatcher.state(for: session.cwd)
            let hookState = Self.load(HookStateRecord.self, from: Paths.hookStates.appendingPathComponent("\(entry.sessionId).json"))
            session.steps = hookState?.steps ?? []
            session.runningAgents = (hookState?.agents ?? [:]).filter { Date().timeIntervalSince($0.value) < 2 * 3_600 }.count
            session.permissionRequests = requests
                .filter { $0.sessionId == entry.sessionId }
                .sorted { $0.createdAt < $1.createdAt }
            if let first = session.permissionRequests.first {
                session.activity = .needsPermission
                session.attentionMessage = "\(first.toolName) wants permission"
            }
            result.append(session)
        }

        return result.sorted { a, b in
            if a.activity.isBlocking != b.activity.isBlocking { return a.activity.isBlocking }
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
            totalInputTokens: bridge?.totalInputTokens,
            totalOutputTokens: bridge?.totalOutputTokens,
            linesAdded: bridge?.linesAdded,
            linesRemoved: bridge?.linesRemoved,
            lastActivity: lastActivity,
            transcriptPath: path,
            entrypoint: entry.entrypoint,
            // A session can start working again without a prompt (e.g. a background task
            // reporting back); then the turn began when Claude Code marked it busy.
            turnStartedAt: Self.turnStart(hook: hook, busySince: registryUpdated),
            finishedAt: hook?.finishedAt,
            finalReply: hook?.finalReply,
            currentStep: activity == .working ? hook?.currentStep : nil,
            currentStepStartedAt: activity == .working ? hook?.currentStepStartedAt : nil,
            compactCount: hook?.compactCount ?? 0,
            cache: Self.cacheInfo(transcript)
        )
    }

    private static func cacheInfo(_ transcript: TranscriptInfo?) -> CacheInfo? {
        guard let t = transcript, let read = t.cacheReadTokens else { return nil }
        let total = read + (t.cacheWriteTokens ?? 0) + (t.uncachedTokens ?? 0)
        guard total > 0 else { return nil }
        let warmUntil = zip2(t.lastAssistantAt, t.cacheTTL).map { $0.addingTimeInterval($1) }
        return CacheInfo(hitRate: Double(read) / Double(total), warmUntil: warmUntil)
    }

    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    private static func turnStart(hook: HookStateRecord?, busySince: Date?) -> Date? {
        guard let started = hook?.turnStartedAt else { return busySince }
        if let finished = hook?.finishedAt, finished >= started { return busySince ?? started }
        return started
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
