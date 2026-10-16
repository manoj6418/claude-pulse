import SwiftUI
import AppKit

/// Renders the menu panel with live data to a PNG: ClaudePulse --snapshot out.png [--dark]
enum Snapshot {
    @MainActor
    static func render(to path: String, dark: Bool) {
        let preferences = Preferences()
        let store = SessionStore(preferences: preferences)
        // Let the first background refresh land.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        let view = MenuContent(store: store, preferences: preferences, staticLayout: true)
            .background(dark ? Color(white: 0.13) : Color(white: 0.96))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
