// Draws the Claude Pulse logo: icon (1024) and social preview (1280x640).
// Run: swift assets/make-logo.swift assets
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let coral = color(0xFF7A59), amber = color(0xFFB547)

/// The mark inside a square of `size` at `origin`: heartbeat line plus two usage bars.
func drawMark(in ctx: CGContext, origin: CGPoint, size: CGFloat, background: Bool) {
    let s = size / 1024
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }

    if background {
        // macOS icon grid: 824pt tile with ~185pt corners inside 1024.
        let tile = CGRect(x: origin.x + 100 * s, y: origin.y + 100 * s, width: 824 * s, height: 824 * s)
        let path = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 30 * s, color: color(0x000000, 0.35).cgColor)
        ctx.addPath(path); ctx.setFillColor(color(0x1B1828).cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                            colors: [color(0x2E2945).cgColor, color(0x16131F).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: p(512, 924), end: p(512, 100), options: [])
        // Soft coral glow behind the line.
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [coral.withAlphaComponent(0.28).cgColor, coral.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: p(512, 600), startRadius: 0, endCenter: p(512, 600), endRadius: 420 * s, options: [])
        ctx.restoreGState()
    }

    // Heartbeat line.
    let points: [CGPoint] = [p(210, 590), p(390, 590), p(445, 470), p(520, 760), p(585, 420), p(640, 590), p(814, 590)]
    let line = CGMutablePath()
    line.addLines(between: points)
    ctx.setLineWidth(52 * s); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    // Glow first, as its own stroke, so the clip below can't cut it off.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 34 * s, color: coral.withAlphaComponent(0.75).cgColor)
    ctx.addPath(line); ctx.setStrokeColor(coral.cgColor); ctx.strokePath()
    ctx.restoreGState()
    // Then the gradient, extended past both ends so the round caps are painted too.
    ctx.saveGState()
    ctx.addPath(line); ctx.replacePathWithStrokedPath(); ctx.clip()
    let stroke = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                            colors: [coral.cgColor, amber.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(stroke, start: p(210, 590), end: p(814, 590),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Two usage bars (5-hour, 7-day), like the menu bar icon.
    for (i, fill) in [(0, 0.72), (1, 0.46)] {
        let y = 300 - CGFloat(i) * 78
        let track = CGRect(x: origin.x + 300 * s, y: origin.y + y * s, width: 424 * s, height: 40 * s)
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 20 * s, cornerHeight: 20 * s, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.14).cgColor); ctx.fillPath()
        var bar = track; bar.size.width *= fill
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 20 * s, cornerHeight: 20 * s, transform: nil))
        ctx.setFillColor((i == 0 ? coral : amber).cgColor); ctx.fillPath()
    }
}

func render(width: Int, height: Int, to path: String, draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// App icon.
render(width: 1024, height: 1024, to: "\(out)/icon-1024.png") { ctx in
    drawMark(in: ctx, origin: .zero, size: 1024, background: true)
}

// Social preview: icon on the left, name and tagline on the right.
render(width: 1280, height: 640, to: "\(out)/social-preview.png") { ctx in
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(0x221E33).cgColor, color(0x110F18).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 640), end: CGPoint(x: 1280, y: 0), options: [])
    drawMark(in: ctx, origin: CGPoint(x: 40, y: 80), size: 480, background: true)

    let title = NSAttributedString(string: "Claude Pulse", attributes: [
        .font: NSFont.systemFont(ofSize: 84, weight: .bold), .foregroundColor: NSColor.white])
    title.draw(at: CGPoint(x: 560, y: 350))
    let tagline = NSAttributedString(string: "Your Claude Code sessions and plan limits,\nlive in the macOS menu bar.", attributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.72)])
    tagline.draw(in: CGRect(x: 562, y: 200, width: 680, height: 120))
    let note = NSAttributedString(string: "Limits · sessions · alerts · Allow/Deny from the menu bar", attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: coral])
    note.draw(at: CGPoint(x: 562, y: 150))
}
