import AppKit
import Darwin

/// Brings the terminal running a Claude session to the front. For Terminal.app
/// and iTerm2 it selects the exact tab by tty; for other apps it activates the app.
enum TerminalJumper {
    /// Returns the app it brought forward, for logging.
    @discardableResult
    static func jump(to pid: Int32) -> String? {
        let tty = ttyName(of: pid)
        guard let app = owningApp(of: pid) else { return nil }

        switch app.bundleIdentifier {
        case "com.apple.Terminal":
            if let tty, runAppleScript(terminalScript(tty: tty)) { return app.localizedName }
        case "com.googlecode.iterm2":
            if let tty, runAppleScript(itermScript(tty: tty)) { return app.localizedName }
        default:
            break
        }
        bringForward(app)
        return app.localizedName
    }

    /// A background app's plain activate() is often ignored on macOS 14+.
    /// Opening the app's bundle brings it forward the way a Dock click does.
    private static func bringForward(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) { NSApp?.yieldActivation(to: app) }
        app.unhide()
        app.activate(options: [.activateAllWindows])
        guard let url = app.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// The terminal running this session is the app in front.
    static func isFrontmost(pid: Int32) -> Bool {
        guard let app = owningApp(of: pid) else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private static func owningApp(of pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 {
            if let app = NSRunningApplication(processIdentifier: current), app.bundleIdentifier != nil,
               app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPid(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func kinfo(of pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func parentPid(of pid: Int32) -> Int32? { kinfo(of: pid)?.kp_eproc.e_ppid }

    private static func ttyName(of pid: Int32) -> String? {
        guard let dev = kinfo(of: pid)?.kp_eproc.e_tdev, dev != -1, dev != 0 else { return nil }
        guard let name = devname(dev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func itermScript(tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && result?.booleanValue == true
    }
}
