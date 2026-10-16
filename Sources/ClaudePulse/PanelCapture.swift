import AppKit

/// `ClaudePulse --capture-panel out.png [--menubar]` asks the running app to open
/// its panel and save a screenshot of its own window (no Screen Recording
/// permission is needed for an app's own windows).
enum PanelCapture {
    static let request = Notification.Name("dev.local.claudepulse.capturePanel")
    /// In-app: switch the panel to Settings (true) or the main view (false) before a capture.
    static let showSettings = Notification.Name("dev.local.claudepulse.showSettings")
    private static var observer: NSObjectProtocol?

    static func listen() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: request, object: nil, queue: .main
        ) { note in
            guard let path = note.userInfo?["path"] as? String else { return }
            let menuBar = (note.userInfo?["menubar"] as? String) == "1"
            let settings = (note.userInfo?["settings"] as? String) == "1"
            capture(to: path, menuBarOnly: menuBar, settings: settings)
        }
    }

    private static func capture(to path: String, menuBarOnly: Bool, settings: Bool) {
        if menuBarOnly {
            write(window: statusWindow(), to: path)
            return
        }
        if panelWindow() == nil { HotKey.togglePanel() }
        // The panel's view only listens once it's open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NotificationCenter.default.post(name: showSettings, object: settings)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                write(window: panelWindow(), to: path)
            }
        }
    }

    private static func statusWindow() -> NSWindow? {
        NSApp.windows.first { $0.className.contains("NSStatusBarWindow") && $0.isVisible }
    }

    private static func panelWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && !window.className.contains("NSStatusBarWindow") && window.frame.width >= 300
        }
    }

    private static func write(window: NSWindow?, to path: String) {
        guard let window else {
            Notifier.log("capture: window not found")
            return
        }
        let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                            [.boundsIgnoreFraming, .bestResolution])
        guard let image,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            Notifier.log("capture: could not capture window")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
