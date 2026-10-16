import Foundation
import UserNotifications

/// Sends macOS notifications for limit thresholds, full context, sessions that
/// need you and sessions that finished. Clicking a session notification jumps
/// to its terminal.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var firedLimitKeys: Set<String> = []
    private var lastAttention: [String: ActivityState] = [:]
    private var firedContext: Set<String> = []
    /// Last Stop notified per session. Only finishes after launch count, so
    /// starting the app never replays old ones but never drops a new one either.
    private var lastFinished: [String: Date] = [:]
    private let launchedAt = Date()
    private var notifiedFinishedAt: [String: Date] = [:]

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    override init() {
        super.init()
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkLimits(_ snapshot: LimitsSnapshot?, thresholds: [Int]) {
        guard let snapshot else { return }
        check(window: snapshot.fiveHour, name: "5-hour", thresholds: thresholds)
        check(window: snapshot.sevenDay, name: "7-day", thresholds: thresholds)
    }

    private func check(window: LimitWindow?, name: String, thresholds: [Int]) {
        guard let window, window.resetsAt > Date() else { return }
        guard let crossed = thresholds.sorted().last(where: { window.usedPercentage >= Double($0) }) else { return }
        let key = "\(name)-\(Int(window.resetsAt.timeIntervalSince1970))-\(crossed)"
        guard !firedLimitKeys.contains(key) else { return }
        firedLimitKeys.insert(key)
        post(
            title: "Claude \(name) limit at \(Format.percent(window.usedPercentage))",
            body: "Resets \(Format.resetTime(window.resetsAt)) (in \(Format.countdown(to: window.resetsAt)))."
        )
    }

    func checkSessions(
        _ sessions: [SessionSummary],
        contextThreshold: Int,
        notifyAttention: Bool,
        notifyFinished: Bool,
        finishedMinSeconds: Int
    ) {
        let now = Date()
        for session in sessions {
            checkFinished(session, enabled: notifyFinished, minSeconds: finishedMinSeconds, now: now)

            let previous = lastAttention[session.sessionId]
            lastAttention[session.sessionId] = session.activity
            if notifyAttention, session.activity.needsAttention, previous != nil, previous != session.activity {
                // Claude's "waiting for your input" follows a finish by about a minute; one ping is enough.
                let justFinished = notifiedFinishedAt[session.sessionId].map { now.timeIntervalSince($0) < 600 } ?? false
                if !(session.activity == .waitingInput && justFinished) {
                    post(
                        title: "\(session.name): \(session.activity.label.lowercased())",
                        body: session.attentionMessage ?? session.cwd,
                        pid: session.pid
                    )
                }
            }

            if let pct = session.contextPercentage, pct >= Double(contextThreshold) {
                if !firedContext.contains(session.sessionId) {
                    firedContext.insert(session.sessionId)
                    post(
                        title: "\(session.name): context \(Format.percent(pct)) full",
                        body: "Consider /compact or a fresh session before auto-compact kicks in.",
                        pid: session.pid
                    )
                }
            } else {
                firedContext.remove(session.sessionId)
            }
        }
        let live = Set(sessions.map(\.sessionId))
        lastAttention = lastAttention.filter { live.contains($0.key) }
        lastFinished = lastFinished.filter { live.contains($0.key) }
        notifiedFinishedAt = notifiedFinishedAt.filter { live.contains($0.key) }
    }

    private func checkFinished(_ session: SessionSummary, enabled: Bool, minSeconds: Int, now: Date) {
        guard let finishedAt = session.finishedAt, finishedAt > launchedAt.addingTimeInterval(-10) else { return }
        if let previous = lastFinished[session.sessionId], finishedAt <= previous { return }
        lastFinished[session.sessionId] = finishedAt
        guard enabled, now.timeIntervalSince(finishedAt) < 120 else { return }

        var worked: TimeInterval?
        if let started = session.turnStartedAt, started < finishedAt {
            worked = finishedAt.timeIntervalSince(started)
        }
        if let worked, worked < Double(minSeconds) { return }

        notifiedFinishedAt[session.sessionId] = now
        postFinished(session, worked: worked)
    }

    /// "✓ name finished" / "Worked 4m · first line of the reply"
    private func postFinished(_ session: SessionSummary, worked: TimeInterval?, test: Bool = false) {
        var body = worked.map { "Worked \(Format.duration($0))" } ?? "Done"
        if let reply = Self.preview(session.finalReply) { body += " · \(reply)" }
        post(title: "\(test ? "Test: " : "")✓ \(session.name) finished", body: body, pid: session.pid)
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
        postFinished(session, worked: worked, test: true)
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

    private func post(title: String, subtitle: String? = nil, body: String, pid: Int32? = nil) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle, !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        if let pid { content.userInfo = ["pid": Int(pid)] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            Self.log("\(title) | \(subtitle ?? "") | \(body.replacingOccurrences(of: "\n", with: " / "))\(error.map { " | error: \($0.localizedDescription)" } ?? "")")
        }
    }

    /// Keeps the last 200 notifications in notifications.log, for checking what fired.
    private static func log(_ line: String) {
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
        if let pid = response.notification.request.content.userInfo["pid"] as? Int {
            DispatchQueue.main.async { TerminalJumper.jump(to: Int32(pid)) }
        }
        completionHandler()
    }
}
