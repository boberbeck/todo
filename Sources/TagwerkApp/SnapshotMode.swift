import AppKit
import SwiftUI
import TagwerkCore

/// Screenshot-Modus für die CI.
///
/// Start mit `-TagwerkSnapshotDir /pfad` (oder Umgebungsvariable `TAGWERK_SNAPSHOT_DIR`).
/// Die App zeigt nacheinander jeden Bildschirm hell und dunkel und legt jeweils eine Datei `.ready`
/// mit Name und Fensternummer ab. Das CI-Skript fotografiert das Fenster mit `screencapture -l`
/// und löscht die Datei. Antwortet niemand, zeichnet die App das Fenster selbst.
enum SnapshotMode {
    static var directory: URL? {
        let environment = ProcessInfo.processInfo.environment["TAGWERK_SNAPSHOT_DIR"]
        let argument = UserDefaults.standard.string(forKey: "TagwerkSnapshotDir")
        guard let path = environment ?? argument, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Beispieldaten statt der echten Datenbank.
    static var usesDemoData: Bool {
        directory != nil
            || ProcessInfo.processInfo.environment["TAGWERK_DEMO"] == "1"
            || UserDefaults.standard.bool(forKey: "TagwerkDemo")
    }

    @MainActor
    static func run(model: AppModel, into directory: URL, openSettings: () -> Void, openWindow: (String) -> Void) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Beispielwerte für die Einstellungen; `register` schreibt nichts dauerhaft.
        UserDefaults.standard.register(defaults: [
            Preferences.meBaseURLKey: "https://helpdesk.example.com",
            Preferences.meTechnicianKey: "301",
            Preferences.serviceKey(for: .wartung): "S-WART",
            Preferences.serviceKey(for: .stoerung): "S-STOER",
            Preferences.serviceKey(for: .projekt): "S-PROJ",
            Preferences.serviceKey(for: .beratung): "S-BERAT",
        ])
        try? await Task.sleep(for: .seconds(2))

        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 600 }) else {
            print("Snapshot: kein Fenster gefunden")
            finish(in: directory)
            return
        }
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let width = min(1280, visible.width)
            let height = min(800, visible.height)
            let frame = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
            window.setFrame(frame, display: true)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        // Musik im Fokus mit Beispielwerten, ohne die Musik-App anzusprechen
        model.music.isDemo = true
        model.music.selectedPlaylist = "Fokus am Morgen"
        // Unteraufgaben der Beispielaufgaben aufgeklappt zeigen
        model.expandedTaskIDs = Set(model.todayTasks.filter { !model.subtasks(of: $0.id).isEmpty && $0.title.hasPrefix("Angebot") }.map(\.id))

        var screens: [(name: String, item: SidebarItem)] = [
            ("start", .today),
            ("plan", .week),
            ("kalender", .calendar),
            ("fokus", .focus),
            ("kunden", .customers),
            ("ziele", .goals),
            ("rueckblick", .review),
            ("tagesplanung", .planning),
            ("tagesabschluss", .close),
        ]
        let richest = model.activeCustomers.max { lhs, rhs in
            model.psps(for: lhs.id, includeInactive: true).count < model.psps(for: rhs.id, includeInactive: true).count
        }
        if let customer = richest {
            screens.insert(("kunde", .customer(customer.id)), at: 5)
        }

        // Pomodoro: zweite Runde läuft, noch gut zwölf Minuten
        UserDefaults.standard.register(defaults: [Preferences.pomodoroEnabledKey: true])
        model.pomodoro = PomodoroState(phase: .work, phaseStart: Date().addingTimeInterval(-12.5 * 60), completedInSet: 1, taskID: model.runningTask?.id)

        for screen in screens {
            model.selection = screen.item
            try? await Task.sleep(for: .seconds(1.5))
            await capture(window, name: screen.name, in: directory)
        }

        // Pomodoro-Pause im Fokus
        model.pomodoro = PomodoroState(phase: .shortBreak, phaseStart: Date().addingTimeInterval(-88), completedInSet: 2, taskID: model.runningTask?.id)
        model.selection = .focus
        try? await Task.sleep(for: .seconds(1.5))
        await capture(window, name: "fokus-pause", in: directory)
        model.pomodoro = nil

        // Aufgabenfenster mit Unteraufgaben
        if let offer = model.todayTasks.first(where: { !model.subtasks(of: $0.id).isEmpty && $0.title.hasPrefix("Angebot") }) {
            model.selection = .today
            model.detailTaskID = offer.id
            try? await Task.sleep(for: .seconds(1.5))
            await capture(window.attachedSheet ?? window, name: "aufgabe", in: directory)
            model.detailTaskID = nil
            try? await Task.sleep(for: .seconds(0.8))
        }

        // Neue Aufgabe direkt im Kalender beschriften
        model.selection = .calendar
        try? await Task.sleep(for: .seconds(1.2))
        model.calendarNewSlot = model.proposedSlot(near: Date().addingTimeInterval(-50 * 60))
        try? await Task.sleep(for: .seconds(1.5))
        log("Neue Aufgabe im Kalender: \(model.calendarNewSlot == nil ? "zu" : "offen")")
        await capture(window, name: "kalender-neu", in: directory)
        model.calendarNewSlot = nil
        try? await Task.sleep(for: .seconds(0.5))

        // Erfasste Zeit im Kalender bearbeiten
        if let entry = model.entriesToday.first(where: { $0.end != nil }) {
            model.selection = .calendar
            try? await Task.sleep(for: .seconds(1))
            model.editingEntry = entry
            try? await Task.sleep(for: .seconds(1.5))
            await capture(window.attachedSheet ?? window, name: "zeit-bearbeiten", in: directory)
            model.editingEntry = nil
            try? await Task.sleep(for: .seconds(0.8))
        }

        // ganzer Bildschirm mit Menüleisten-Uhr
        model.selection = .today
        try? await Task.sleep(for: .seconds(1))
        await capture(nil, name: "bildschirm", in: directory)

        // Schnell erfassen
        if let panel = model.showQuickCapture() {
            try? await Task.sleep(for: .seconds(1))
            await capture(panel, name: "schnellerfassen", in: directory)
            model.hideQuickCapture()
        }

        // Nachfrage nach einer Pause
        model.selection = .today
        if let running = model.runningEntry, let taskID = running.taskID {
            model.idlePrompt = IdlePrompt(start: Date().addingTimeInterval(-25 * 60), end: Date(), taskID: taskID)
            try? await Task.sleep(for: .seconds(1.5))
            await capture(window.attachedSheet ?? window, name: "leerlauf", in: directory)
            model.idlePrompt = nil
            try? await Task.sleep(for: .seconds(0.5))
        }

        // Abgleich mit SAP ByDesign
        model.selection = .customers
        model.sapSyncRows = DemoData.sapRows
        model.showsSAPSync = true
        try? await Task.sleep(for: .seconds(1.5))
        await capture(window.attachedSheet ?? window, name: "sapabgleich", in: directory)
        model.showsSAPSync = false
        try? await Task.sleep(for: .seconds(0.8))

        // Einstellungen, jeder Tab einzeln
        openSettings()
        try? await Task.sleep(for: .seconds(1.5))
        for tab in SettingsView.Tab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsView.tabKey)
            try? await Task.sleep(for: .seconds(1.2))
            if let settings = NSApp.windows.first(where: { candidate in
                candidate.isVisible && candidate !== window && !(candidate is NSPanel) && candidate.frame.width > 300
            }) {
                settings.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .seconds(0.3))
                await capture(settings, name: "einstellungen-\(tab.rawValue.lowercased())", in: directory)
            }
        }
        UserDefaults.standard.set(SettingsView.Tab.general.rawValue, forKey: SettingsView.tabKey)
        NSApp.windows.first { $0.isVisible && $0 !== window && !($0 is NSPanel) && $0.frame.width > 300 }?.close()
        window.makeKeyAndOrderFront(nil)

        // ByDesign-Fenster mit der Beispielseite
        openWindow("bydesign")
        try? await Task.sleep(for: .seconds(6))
        if let browser = NSApp.windows.first(where: { $0.isVisible && $0.title == "SAP ByDesign" }) {
            browser.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(0.5))
            await capture(browser, name: "bydesign", in: directory)
            browser.close()
        } else {
            log("Snapshot: ByDesign-Fenster nicht gefunden")
        }
        finish(in: directory)
    }

    /// Schreibt eine Zeile ins Protokoll des Builds (die App läuft dort ohne sichtbare Konsole).
    static func log(_ message: String) {
        print(message)
        guard let directory else { return }
        let file = directory.appendingPathComponent("protokoll.txt")
        let line = Data((message + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }

    @MainActor
    private static func finish(in directory: URL) {
        try? Data().write(to: directory.appendingPathComponent(".done"))
        NSApp.terminate(nil)
    }

    /// Bittet das CI-Skript um ein Foto. Ohne Antwort zeichnet die App das Fenster selbst.
    @MainActor
    private static func capture(_ window: NSWindow?, name: String, in directory: URL) async {
        let marker = directory.appendingPathComponent(".ready")
        let windowNumber = window?.windowNumber ?? 0
        try? "\(name) \(windowNumber)\n".data(using: .utf8)?.write(to: marker, options: .atomic)

        for _ in 0..<50 {
            if !FileManager.default.fileExists(atPath: marker.path) {
                print("Snapshot: \(name)")
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        try? FileManager.default.removeItem(at: marker)
        if let window, draw(window, to: directory.appendingPathComponent("\(name).png")) {
            print("Snapshot selbst gezeichnet: \(name)")
        } else {
            print("Snapshot fehlgeschlagen: \(name)")
        }
    }

    /// Zeichnet das Fenster ohne Bildschirmfreigabe. Glas-Effekte (Seitenleiste) fehlen dabei.
    @MainActor
    private static func draw(_ window: NSWindow, to url: URL) -> Bool {
        guard let view = window.contentView?.superview ?? window.contentView else { return false }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
}
