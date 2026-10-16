import AppKit
import Carbon.HIToolbox

/// ⌃⌥C opens and closes the panel from anywhere. Carbon hotkeys need no
/// Accessibility permission. `ClaudePulse --toggle-panel` does the same.
final class HotKey {
    static let shared = HotKey()
    static let toggleNotification = Notification.Name("dev.local.claudepulse.togglePanel")
    static let label = "⌃⌥C"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var observer: NSObjectProtocol?

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    /// Lets `ClaudePulse --toggle-panel` (another process) open the panel.
    func listenForToggleRequests() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.toggleNotification, object: nil, queue: .main
        ) { _ in HotKey.togglePanel() }
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.togglePanel() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x434C_5053), id: 1) // "CLPS"
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    /// MenuBarExtra has no API to open its panel, so click its status item button.
    static func togglePanel() {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = findButton(in: window.contentView) {
                NSApp.activate(ignoringOtherApps: true)
                button.performClick(nil)
                return
            }
        }
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews {
            if let found = findButton(in: sub) { return found }
        }
        return nil
    }
}
