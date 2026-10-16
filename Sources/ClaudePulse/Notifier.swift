import Foundation
import UserNotifications

/// What the user wants to be notified about.
struct AlertSettings {
    var finished: Bool
    var finishedMinSeconds: Int
    var permission: Bool
    var waitingInput: Bool
    var context: Bool
    var contextThreshold: Int
    var limitThresholds: [Int]
    var reset: Bool
    /// nil = off.
    var longRunningMinutes: Int?
    var uncommittedOnClose: Bool
    var dailyBudget: Double
    var dailySummary: Bool
    var weeklySummary: Bool
    var quietWhenTerminalInFront: Bool
}

/// Detects session and limit events, records the important ones for the
/// Recent list, and sends macOS notifications for the ones switched on.
/// Clicking a session notification jumps to its terminal.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main thread for every finished / needs-permission / limit event.
    var onEvent: ((RecentEvent) -> Void)?
    /// Called on the main thread when a notification's Allow / Always allow / Deny is chosen.
    var onAnswer: ((String, PermissionDecision) -> Void)?
    /// Called for finished / permission events, for phone alerts: kind, title, short body, detailed body.
    var onPhone: ((PhoneNotifier.Kind, String, String, String) -> Void)?

    /// Last state of each limit window, to spot a reset.
    private var lastWindows: [String: LimitWindow] = [:]
    /// Long-running steps already reported: "sessionId|startedAt".
    private var longRunningFired: Set<String> = []
    /// Last session seen per id, to report what a closed session left behind.
    private var lastSeenSessions: [String: SessionSummary] = [:]
    private var budgetFired: Set<String> = []
    private var quiet = false

    private static let permissionCategory = "CLAUDE_PERMISSION"
    private static let permissionAlwaysCategory = "CLAUDE_PERMISSION_ALWAYS"
    private var notifiedRequests: Set<String> = []

    private var firedLimitKeys: Set<String> = []
    private var lastActivity: [String: ActivityState] = [:]
    private var firedContext: Set<String> = []
    /// Last Stop handled per session. Only finishes after launch count, so
    /// starting the app never replays old ones but never drops a new one either.
    private var lastFinished: [String: Date] = [:]
    private let launchedAt = Date()
    private var finishedSeenAt: [String: Date] = [:]

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    override init() {
        super.init()
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Approving needs an unlocked Mac; denying is always safe.
        let allow = UNNotificationAction(identifier: PermissionDecision.allow.rawValue, title: "Allow",
                                         options: [.authenticationRequired])
        let always = UNNotificationAction(identifier: PermissionDecision.alwaysAllow.rawValue, title: "Always allow",
                                          options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: PermissionDecision.deny.rawValue, title: "Deny", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.permissionCategory, actions: [allow, deny],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.permissionAlwaysCategory, actions: [allow, always, deny],
                                   intentIdentifiers: []),
        ])
    }

    // MARK: - Limits

    func checkLimits(_ snapshot: LimitsSnapshot?, settings: AlertSettings) {
        checkReset(snapshot?.fiveHour, name: "5-hour", enabled: settings.reset)
        checkReset(snapshot?.sevenDay, name: "7-day", enabled: settings.reset)
        guard let snapshot else { return }
        check(window: snapshot.fiveHour, name: "5-hour", thresholds: settings.limitThresholds)
        check(window: snapshot.sevenDay, name: "7-day", thresholds: settings.limitThresholds)
    }

    /// "Your 5-hour limit reset" once a window you'd used at least half of rolls over.
    private func checkReset(_ window: LimitWindow?, name: String, enabled: Bool) {
        let previous = lastWindows[name]
        if let window, window.resetsAt > Date() { lastWindows[name] = window }
        guard let previous, previous.resetsAt <= Date() else { return }
        // Seen once per window: forget it after reporting.
        if lastWindows[name]?.resetsAt == previous.resetsAt { lastWindows[name] = nil }
        guard previous.usedPercentage >= 50 else { return }
        let title = "Claude \(name) limit reset"
        let body = "Back to full. You had used \(Format.percent(previous.usedPercentage))."
        record(.limit, title: title, detail: body, session: nil)
        if enabled { post(title: title, body: body) }
    }

    private func check(window: LimitWindow?, name: String, thresholds: [Int]) {
        guard let window, window.resetsAt > Date() else { return }
        guard let crossed = thresholds.sorted().last(where: { window.usedPercentage >= Double($0) }) else { return }
        let key = "\(name)-\(Int(window.resetsAt.timeIntervalSince1970))-\(crossed)"
        guard !firedLimitKeys.contains(key) else { return }
        firedLimitKeys.insert(key)

        let title = "Claude \(name) limit at \(Format.percent(window.usedPercentage))"
        let body = "Resets \(Format.resetTime(window.resetsAt)) (in \(Format.countdown(to: window.resetsAt)))."
        record(.limit, title: title, detail: body, session: nil)
        post(title: title, body: body)
    }

    // MARK: - Sessions

    func checkSessions(_ sessions: [SessionSummary], settings: AlertSettings) {
        let now = Date()
        quiet = settings.quietWhenTerminalInFront
        checkClosed(sessions, settings: settings)
        for session in sessions {
            checkLongRunning(session, settings: settings, now: now)
            checkPermissionRequests(session, settings: settings)
            checkFinished(session, settings: settings, now: now)
            checkActivity(session, settings: settings, now: now)
            checkContext(session, settings: settings)
        }
        let live = Set(sessions.map(\.sessionId))
        lastActivity = lastActivity.filter { live.contains($0.key) }
        lastFinished = lastFinished.filter { live.contains($0.key) }
        finishedSeenAt = finishedSeenAt.filter { live.contains($0.key) }
    }

    /// Prompts from sessions Claude Code doesn't list; they have no row to jump to.
    func checkUnlistedRequests(_ requests: [PermissionRequestRecord], settings: AlertSettings) {
        for request in requests where !notifiedRequests.contains(request.id) {
            notifiedRequests.insert(request.id)
            let name = request.cwd.map { ($0 as NSString).lastPathComponent } ?? "Claude Code"
            let body = request.summary.count > 160 ? String(request.summary.prefix(160)) + "…" : request.summary
            onEvent?(RecentEvent(kind: .needsPermission, title: "\(name) needs permission",
                                 detail: "\(request.toolName): \(body)", sessionId: request.sessionId, pid: nil, at: Date()))
            onPhone?(.permission, "\(name) needs permission", "\(request.toolName) is waiting for your answer.",
                     "\(request.toolName): \(body)")
            guard settings.permission else { continue }
            post(title: "\(name): allow \(request.toolName)?", body: body,
                 category: request.canAlwaysAllow ? Self.permissionAlwaysCategory : Self.permissionCategory,
                 extra: ["requestId": request.id])
        }
    }

    /// Forget prompts that are no longer waiting.
    func prunePermissionRequests(keeping pending: Set<String>) {
        notifiedRequests = notifiedRequests.filter { pending.contains($0) }
    }

    /// "go test has been running 15m in promise-engine": a tool that's still going.
    private func checkLongRunning(_ session: SessionSummary, settings: AlertSettings, now: Date) {
        guard let minutes = settings.longRunningMinutes, let step = session.currentStep,
              let started = session.currentStepStartedAt,
              now.timeIntervalSince(started) >= Double(minutes) * 60 else { return }
        let key = "\(session.sessionId)|\(started.timeIntervalSince1970)"
        guard !longRunningFired.contains(key) else { return }
        longRunningFired.insert(key)
        post(title: "\(session.name): still running after \(Format.duration(now.timeIntervalSince(started)))",
             body: step, pid: session.pid)
    }

    /// A session that closed with uncommitted or unpushed work.
    private func checkClosed(_ sessions: [SessionSummary], settings: AlertSettings) {
        let live = Set(sessions.map(\.sessionId))
        for (id, last) in lastSeenSessions where !live.contains(id) {
            // Only sessions that edited code themselves; another session's leftovers in the same repo don't count.
            let edited = (last.linesAdded ?? 0) + (last.linesRemoved ?? 0) > 0
            guard settings.uncommittedOnClose, edited, let git = last.git, !git.isClean else { continue }
            var parts: [String] = []
            if git.changedFiles > 0 { parts.append("\(git.changedFiles) uncommitted file\(git.changedFiles == 1 ? "" : "s")") }
            if git.ahead > 0 { parts.append("\(git.ahead) unpushed commit\(git.ahead == 1 ? "" : "s")") }
            let title = "\(last.name) closed with \(parts.joined(separator: " and "))"
            record(.finished, title: title, detail: last.cwd, session: nil)
            post(title: title, body: last.cwd)
        }
        lastSeenSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0) })
        longRunningFired = longRunningFired.filter { live.contains(String($0.split(separator: "|").first ?? "")) }
    }

    // MARK: - Spend

    func checkSpend(today: DayUsage?, week: (cost: Double, sessions: Int, topProject: String?),
                    settings: AlertSettings, now: Date = Date()) {
        let day = Self.dayKey(now)
        if settings.dailyBudget > 0, let spent = today?.costUSD {
            for (fraction, label) in [(1.0, "reached"), (0.8, "at 80% of")] where spent >= settings.dailyBudget * fraction {
                let key = "\(day)-\(fraction)"
                if !budgetFired.contains(key) {
                    budgetFired.insert(key)
                    if fraction == 1.0 { budgetFired.insert("\(day)-0.8") }
                    post(title: "Claude spend \(label) today's budget",
                         body: "\(Format.cost(spent)) of \(Format.cost(settings.dailyBudget)) (API-equivalent).")
                }
                break
            }
        }

        // Summaries go out once, after 6 PM.
        guard Calendar.current.component(.hour, from: now) >= 18 else { return }
        let defaults = UserDefaults.standard
        if settings.dailySummary, defaults.string(forKey: "lastDailySummary") != day, let today, today.costUSD > 0 {
            defaults.set(day, forKey: "lastDailySummary")
            let top = today.costByProject.max { $0.value < $1.value }?.key
            post(title: "Claude today: \(Format.cost(today.costUSD))",
                 body: "\(today.sessions?.count ?? 0) sessions" + (top.map { " · top project \($0)" } ?? ""))
        }
        let isFriday = Calendar.current.component(.weekday, from: now) == 6
        if settings.weeklySummary, isFriday, defaults.string(forKey: "lastWeeklySummary") != day, week.cost > 0 {
            defaults.set(day, forKey: "lastWeeklySummary")
            post(title: "Claude this week: \(Format.cost(week.cost))",
                 body: "\(week.sessions) sessions" + (week.topProject.map { " · top project \($0)" } ?? ""))
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// One notification per waiting prompt, with Allow / Deny buttons.
    private func checkPermissionRequests(_ session: SessionSummary, settings: AlertSettings) {
        for request in session.permissionRequests where !notifiedRequests.contains(request.id) {
            notifiedRequests.insert(request.id)
            let title = "\(session.name): allow \(request.toolName)?"
            let body = request.summary.count > 160 ? String(request.summary.prefix(160)) + "…" : request.summary
            record(.needsPermission, title: "\(session.name) needs permission", detail: "\(request.toolName): \(body)", session: session)
            onPhone?(.permission, "\(session.name) needs permission", "\(request.toolName) is waiting for your answer.",
                     "\(request.toolName): \(body)")
            guard settings.permission else { continue }
            post(
                title: title,
                body: body,
                pid: session.pid,
                category: request.canAlwaysAllow ? Self.permissionAlwaysCategory : Self.permissionCategory,
                extra: ["requestId": request.id]
            )
        }
    }

    private func checkFinished(_ session: SessionSummary, settings: AlertSettings, now: Date) {
        guard let finishedAt = session.finishedAt, finishedAt > launchedAt.addingTimeInterval(-10) else { return }
        if let previous = lastFinished[session.sessionId], finishedAt <= previous { return }
        lastFinished[session.sessionId] = finishedAt
        guard now.timeIntervalSince(finishedAt) < 120 else { return }

        var worked: TimeInterval?
        if let started = session.turnStartedAt, started < finishedAt {
            worked = finishedAt.timeIntervalSince(started)
        }
        if let worked, worked < Double(settings.finishedMinSeconds) { return }

        finishedSeenAt[session.sessionId] = now
        let (title, body) = finishedText(session, worked: worked)
        record(.finished, title: title, detail: body, session: session)
        if settings.finished { post(title: title, body: body, pid: session.pid) }
        onPhone?(.finished, title, worked.map { "Worked \(Format.duration($0))" } ?? "Done", body)
    }

    private func checkActivity(_ session: SessionSummary, settings: AlertSettings, now: Date) {
        let previous = lastActivity[session.sessionId]
        lastActivity[session.sessionId] = session.activity
        guard previous != nil, previous != session.activity else { return }

        switch session.activity {
        case .needsPermission:
            guard session.permissionRequests.isEmpty else { return } // has its own notification with buttons
            let title = "\(session.name) needs permission"
            let body = session.attentionMessage ?? session.cwd
            record(.needsPermission, title: title, detail: body, session: session)
            if settings.permission { post(title: title, body: body, pid: session.pid) }
        case .waitingInput:
            // Claude's "waiting for your input" follows a finish by about a minute; one ping is enough.
            let justFinished = finishedSeenAt[session.sessionId].map { now.timeIntervalSince($0) < 600 } ?? false
            if settings.waitingInput, !justFinished {
                post(title: "\(session.name) is waiting for you", body: session.attentionMessage ?? session.cwd, pid: session.pid)
            }
        default:
            break
        }
    }

    private func checkContext(_ session: SessionSummary, settings: AlertSettings) {
        guard let pct = session.contextPercentage, pct >= Double(settings.contextThreshold) else {
            firedContext.remove(session.sessionId)
            return
        }
        guard settings.context, !firedContext.contains(session.sessionId) else { return }
        firedContext.insert(session.sessionId)
        post(
            title: "\(session.name): context \(Format.percent(pct)) full",
            body: "Consider /compact or a fresh session before auto-compact kicks in.",
            pid: session.pid
        )
    }

    // MARK: - Text

    /// "✓ name finished" / "Worked 4m · first line of the reply"
    private func finishedText(_ session: SessionSummary, worked: TimeInterval?) -> (String, String) {
        var body = worked.map { "Worked \(Format.duration($0))" } ?? "Done"
        if let reply = Self.preview(session.finalReply) { body += " · \(reply)" }
        return ("✓ \(session.name) finished", body)
    }

    /// A realistic "finished" notification built from a live session.
    func sendTest(using session: SessionSummary?) {
        guard let session else {
            post(title: "✓ Claude Pulse test", body: "Notifications are working. No session is running to preview.")
            return
        }
        let worked = session.turnStartedAt.map { started -> TimeInterval in
            let end = session.finishedAt.flatMap { $0 > started ? $0 : nil } ?? Date()
            return end.timeIntervalSince(started)
        }
        let (title, body) = finishedText(session, worked: worked)
        post(title: "Test: \(title)", body: body, pid: session.pid)
    }

    /// First line of the reply as plain text, kept short.
    private static func preview(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline)
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "`", with: "")
                if l.hasPrefix("#") || l.hasPrefix("- ") || l.hasPrefix("* ") {
                    l = String(l.drop(while: { $0 == "#" || $0 == "-" || $0 == "*" || $0 == " " }))
                }
                return l
            }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > 140 ? String(line.prefix(140)) + "…" : line
    }

    // MARK: - Delivery

    private func record(_ kind: RecentEvent.Kind, title: String, detail: String, session: SessionSummary?) {
        onEvent?(RecentEvent(kind: kind, title: title, detail: detail,
                             sessionId: session?.sessionId, pid: session?.pid, at: Date()))
    }

    private func post(title: String, body: String, pid: Int32? = nil,
                      category: String? = nil, extra: [String: String] = [:]) {
        guard available else { return }
        if quiet, let pid, TerminalJumper.isFrontmost(pid: pid) {
            Self.log("quiet (terminal in front): \(title)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var info: [String: Any] = extra
        if let pid { info["pid"] = Int(pid) }
        content.userInfo = info
        if let category { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            Self.log("\(title) | \(body)\(error.map { " | error: \($0.localizedDescription)" } ?? "")")
        }
    }

    /// Keeps the last 200 notifications in notifications.log, for checking what fired.
    static func log(_ line: String) {
        let url = Paths.support.appendingPathComponent("notifications.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        lines.append("\(stamp) \(line)")
        let text = lines.suffix(200).joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while the panel is open (the app counts as active then).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let requestId = info["requestId"] as? String,
           let decision = PermissionDecision(rawValue: response.actionIdentifier) {
            DispatchQueue.main.async {
                self.onAnswer?(requestId, decision)
                Self.log("notification action: \(decision.rawValue) for request \(requestId)")
            }
            completionHandler()
            return
        }
        let pid = info["pid"] as? Int
        DispatchQueue.main.async {
            let target = pid.flatMap { TerminalJumper.jump(to: Int32($0)) }
            Self.log("clicked: \(response.notification.request.content.title) → \(target ?? "no app found for pid \(pid.map(String.init) ?? "none")")")
        }
        completionHandler()
    }
}
