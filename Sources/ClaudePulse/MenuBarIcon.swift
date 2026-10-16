import AppKit

/// Two tiny bars for the menu bar: 5-hour usage on top, 7-day below.
/// Drawn as a template image so it follows the menu bar's light/dark tint.
enum MenuBarIcon {
    static func bars(fiveHour: Double?, sevenDay: Double?) -> NSImage {
        let size = NSSize(width: 20, height: 14)
        let image = NSImage(size: size, flipped: true) { _ in
            drawBar(fraction: fiveHour.map { $0 / 100 }, y: 2)
            drawBar(fraction: sevenDay.map { $0 / 100 }, y: 8.5)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawBar(fraction: Double?, y: CGFloat) {
        let track = NSRect(x: 1, y: y, width: 18, height: 4)
        let radius: CGFloat = 2
        NSColor.black.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard let fraction, fraction > 0 else { return }
        var fill = track
        fill.size.width = max(4, track.width * CGFloat(min(1, fraction)))
        NSColor.black.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
