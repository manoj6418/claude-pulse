import SwiftUI
import UserNotifications

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--statusline") {
            Bridge.runStatusLine()
            return
        }
        if args.contains("--hook") {
            Bridge.runHook()
            return
        }
        if args.contains("--connect") || args.contains("--disconnect") || args.contains("--status") {
            do {
                if args.contains("--connect") { try Installer.connect() }
                if args.contains("--disconnect") { try Installer.disconnect() }
                print("Claude Code connection: \(Installer.status())")
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        if let i = args.firstIndex(of: "--jump"), i + 1 < args.count, let pid = Int32(args[i + 1]) {
            print(TerminalJumper.jump(to: pid) ?? "no app found")
            return
        }
        if args.contains("--phone-test") {
            let p = Preferences()
            PhoneNotifier.send(server: p.phoneServer, topic: p.phoneTopic, title: "✓ Claude Pulse test",
                               message: "Phone alerts are working.", kind: .test) { error in
                print(error ?? "sent to \(p.phoneServer)/\(p.phoneTopic.prefix(16))…")
                exit(error == nil ? 0 : 1)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(20))
            return
        }
        if let i = args.firstIndex(of: "--capture-panel"), i + 1 < args.count {
            let path = URL(fileURLWithPath: args[i + 1]).standardizedFileURL.path
            DistributedNotificationCenter.default().postNotificationName(
                PanelCapture.request, object: nil,
                userInfo: ["path": path, "menubar": args.contains("--menubar") ? "1" : "0",
                           "settings": args.contains("--settings") ? "1" : "0"],
                deliverImmediately: true)
            return
        }
        if args.contains("--toggle-panel") {
            DistributedNotificationCenter.default().postNotificationName(
                HotKey.toggleNotification, object: nil, userInfo: nil, deliverImmediately: true)
            return
        }
        if args.contains("--notification-settings") {
            UNUserNotificationCenter.current().getNotificationSettings { s in
                print("authorization:", s.authorizationStatus.rawValue, "(0 notDetermined, 1 denied, 2 authorized, 3 provisional)")
                print("alertSetting:", s.alertSetting.rawValue, "(0 notSupported, 1 disabled, 2 enabled)")
                print("alertStyle:", s.alertStyle.rawValue, "(0 none, 1 banner, 2 alert)")
                print("notificationCenter:", s.notificationCenterSetting.rawValue, "sound:", s.soundSetting.rawValue)
                exit(0)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(3))
            return
        }
        if args.contains("--test-notification") {
            let store = SessionStore(preferences: Preferences(), detectsEvents: false)
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            if let i = args.firstIndex(of: "--session"), i + 1 < args.count {
                let wanted = args[i + 1]
                let session = store.sessions.first { $0.sessionId.hasPrefix(wanted) || $0.name.localizedCaseInsensitiveContains(wanted) }
                store.sendTestNotification(preferring: session)
            } else {
                store.sendTestNotification()
            }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            return
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.render(to: args[i + 1], dark: args.contains("--dark"), settings: args.contains("--settings"))
            return
        }
        ClaudePulseApp.main()
    }
}

struct ClaudePulseApp: App {
    @StateObject private var preferences: Preferences
    @StateObject private var store: SessionStore

    init() {
        let preferences = Preferences()
        _preferences = StateObject(wrappedValue: preferences)
        // A copy pointed at another home (CLAUDE_PULSE_HOME, used for demo screenshots)
        // shows that data but never sends notifications or takes the hotkey.
        let variables = ProcessInfo.processInfo.environment
        let isDemo = variables["CLAUDE_PULSE_HOME"] != nil
        _store = StateObject(wrappedValue: SessionStore(preferences: preferences, detectsEvents: !isDemo))
        switch variables["CLAUDE_PULSE_APPEARANCE"] {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if isDemo {
            PanelCapture.listen()
            return
        }
        HotKey.shared.setEnabled(preferences.hotkeyEnabled)
        HotKey.shared.listenForToggleRequests()
        PanelCapture.listen()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store, preferences: preferences)
        } label: {
            MenuBarLabel(store: store, preferences: preferences)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var preferences: Preferences

    var body: some View {
        HStack(spacing: 3) {
            if preferences.menuBarStyle == .bars {
                Image(nsImage: MenuBarIcon.bars(
                    fiveHour: store.limits?.fiveHour?.usedPercentage,
                    sevenDay: store.limits?.sevenDay?.usedPercentage
                ))
                if store.attentionCount > 0 {
                    Image(systemName: "exclamationmark.bubble.fill")
                    Text("\(store.attentionCount)").monospacedDigit()
                }
            } else {
                Image(systemName: store.attentionCount > 0 ? "exclamationmark.bubble.fill" : "sparkle")
                if let text { Text(text).monospacedDigit() }
            }
        }
    }

    private var text: String? {
        let five = store.limits?.fiveHour.map { Format.percent($0.usedPercentage) }
        let seven = store.limits?.sevenDay.map { Format.percent($0.usedPercentage) }
        var label: String?
        switch preferences.menuBarStyle {
        case .iconOnly, .bars: label = nil
        case .fiveHour: label = five
        case .both:
            if five != nil || seven != nil { label = "\(five ?? "–") · \(seven ?? "–")" }
        }
        if store.attentionCount > 0 {
            label = [label, "\(store.attentionCount)"].compactMap { $0 }.joined(separator: " ")
        }
        return label
    }
}
