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
            let store = SessionStore(preferences: Preferences())
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
            Snapshot.render(to: args[i + 1], dark: args.contains("--dark"))
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
        _store = StateObject(wrappedValue: SessionStore(preferences: preferences))
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
            Image(systemName: store.attentionCount > 0 ? "exclamationmark.bubble.fill" : "sparkle")
            if let text { Text(text).monospacedDigit() }
        }
    }

    private var text: String? {
        let five = store.limits?.fiveHour.map { Format.percent($0.usedPercentage) }
        let seven = store.limits?.sevenDay.map { Format.percent($0.usedPercentage) }
        var label: String?
        switch preferences.menuBarStyle {
        case .iconOnly: label = nil
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
