import AppKit
import SwiftUI
import TagwerkCore

/// Screenshot-Modus für die CI: `TAGWERK_SNAPSHOT_DIR=/pfad swift run Tagwerk`
/// startet mit Beispieldaten, fotografiert jeden Bildschirm hell und dunkel und beendet sich.
enum SnapshotMode {
    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["TAGWERK_SNAPSHOT_DIR"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Beispieldaten statt der echten Datenbank.
    static var usesDemoData: Bool {
        directory != nil || ProcessInfo.processInfo.environment["TAGWERK_DEMO"] == "1"
    }

    @MainActor
    static func run(model: AppModel, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))

        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 600 }) else {
            print("Snapshot: kein Fenster gefunden")
            NSApp.terminate(nil)
            return
        }
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.center()
        window.makeKeyAndOrderFront(nil)

        var screens: [(name: String, item: SidebarItem)] = [
            ("heute", .today),
            ("fokus", .focus),
            ("kunden", .customers),
            ("rueckblick", .review),
        ]
        if let customer = model.activeCustomers.first {
            screens.insert(("kunde", .customer(customer.id)), at: 3)
        }

        let appearances: [(name: NSAppearance.Name, suffix: String)] = [(.aqua, "hell"), (.darkAqua, "dunkel")]
        for appearance in appearances {
            NSApp.appearance = NSAppearance(named: appearance.name)
            for screen in screens {
                model.selection = screen.item
                try? await Task.sleep(for: .seconds(1.5))
                let url = directory.appendingPathComponent("\(screen.name)-\(appearance.suffix).png")
                if capture(window, to: url) {
                    print("Snapshot: \(url.lastPathComponent)")
                } else {
                    print("Snapshot fehlgeschlagen: \(url.lastPathComponent)")
                }
            }
        }
        NSApp.terminate(nil)
    }

    /// Zeichnet das ganze Fenster samt Titelleiste in eine PNG-Datei. Braucht keine Bildschirmfreigabe.
    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) -> Bool {
        guard let view = window.contentView?.superview ?? window.contentView else { return false }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
