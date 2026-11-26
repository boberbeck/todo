import AppKit
import SwiftUI
import TagwerkCore

@main
struct TagwerkApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.live()

    var body: some Scene {
        Window("Tagwerk", id: "main") {
            RootView()
                .environment(model)
                // Kein blauer Systemrahmen um Eingabefelder; Felder zeigen den Fokus selbst
                .focusEffectDisabled()
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 760)
        // Eine Leiste statt zwei: Reiter in der Titelleiste, ohne den Fenstertitel
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            TagwerkCommands(model: model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .focusEffectDisabled()
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .focusEffectDisabled()
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Beim Start über `swift run` oder Xcode (Swift-Paket) hätte die App sonst kein Dock-Symbol.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Der Timer läuft in der Menüleiste weiter, auch wenn das Fenster zu ist.
        false
    }

    /// Klick auf das Dock-Symbol: das Hauptfenster wieder öffnen (auch wenn es geschlossen war).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            MainWindow.show()
        }
        return true
    }
}

/// Öffnet das Hauptfenster von außerhalb einer Ansicht (Dock-Symbol). Die Menüleiste meldet dafür beim Start,
/// wie SwiftUI das Fenster öffnet; sie ist immer da, auch wenn das Fenster zu ist.
@MainActor
enum MainWindow {
    private static var opener: (() -> Void)?

    static func register(_ open: @escaping () -> Void) {
        opener = open
    }

    static func show() {
        if let opener {
            opener()
        } else if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true })
            ?? NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}

struct TagwerkCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neue Aufgabe") { model.requestNewTask() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Aufgabe") {
            Button("Schnell erfassen (⌃⌥ Leertaste)") { model.showQuickCapture() }
            Button("Timer starten oder stoppen") { model.toggleTimerForFocus() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Erledigt") { model.completeFocused() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Fehler melden …") { model.showsBugReport = true }
            Button("Zeit nachtragen …") { model.beginTimeEntry(for: model.focusTask?.id) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button(model.runningBreak == nil ? "Mittagspause starten" : "Mittagspause beenden") {
                if model.runningBreak == nil {
                    model.startBreak()
                } else {
                    model.endBreak(resume: true)
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Mittagspause nachtragen …") { model.beginBreakEntry() }
        }
        CommandMenu("Gehe zu") {
            Button("Befehlszeile …") { model.openCommandBar() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Start") { model.selection = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("Woche planen") { model.selection = .week }
                .keyboardShortcut("2", modifiers: .command)
            Button("Kalender") { model.selection = .calendar }
                .keyboardShortcut("3", modifiers: .command)
            Button("Fokus") { model.selection = .focus }
                .keyboardShortcut("4", modifiers: .command)
            Button("Kunden") { model.selection = .customers }
                .keyboardShortcut("5", modifiers: .command)
            Button("Ziele") { model.selection = .goals }
                .keyboardShortcut("6", modifiers: .command)
            Button("Rückblick") { model.selection = .review }
                .keyboardShortcut("7", modifiers: .command)
            Divider()
            Button("Tag planen") { model.selection = .planning }
                .keyboardShortcut("0", modifiers: .command)
            Button("Tag abschließen") { model.selection = .close }
                .keyboardShortcut("9", modifiers: .command)
        }
    }
}

enum Preferences {
    static let workdayStartKey = "workdayStartMinutes"
    static let workdayEndKey = "workdayEndMinutes"
    static let focusGoalMinutesKey = "focusGoalMinutes"
    static let calendarModesKey = "calendarModes"
    static let writeBlocksKey = "writeTimeBlocksToCalendar"
    static let planningOnLaunchKey = "showPlanningOnLaunch"
    static let lastPlannedDayKey = "lastPlannedDay"
    static let showInboxKey = "showInbox"
    /// Standardaufgaben einmal angelegt (danach nicht wieder, auch wenn man sie löscht)
    static let standingSeededKey = "standingTasksSeeded"
    static let roundingStepKey = "roundingStepMinutes"
    static let roundingModeKey = "roundingMode"
    static let meBaseURLKey = "manageEngineBaseURL"
    static let meAuthKindKey = "manageEngineAuthKind"
    static let meTechnicianKey = "manageEngineTechnicianID"
    static let meAutoFetchKey = "manageEngineAutoFetch"
    static let idleMinutesKey = "idleMinutes"
    static let calendarWidthKey = "calendarColumnWidth"
    /// Updates aus GitHub
    static let updateAutoCheckKey = "updateAutoCheck"
    /// Zuletzt angebotener Absturzbericht (Dateiname)
    static let lastSeenCrashKey = "lastSeenCrashReport"
    /// Pomodoro im Fokus
    static let pomodoroEnabledKey = "pomodoroEnabled"
    static let pomodoroWorkKey = "pomodoroWorkMinutes"
    static let pomodoroShortBreakKey = "pomodoroShortBreakMinutes"
    static let pomodoroLongBreakKey = "pomodoroLongBreakMinutes"
    static let pomodoroRoundsKey = "pomodoroRounds"
    static let pomodoroAutoContinueKey = "pomodoroAutoContinue"
    static let pomodoroSoundKey = "pomodoroSound"
    /// Töne je Anlass (Kennung aus `SoundLibrary`) und Lautstärke 0…1
    static let pomodoroShortBreakSoundKey = "pomodoroSoundShortBreak"
    static let pomodoroLongBreakSoundKey = "pomodoroSoundLongBreak"
    static let pomodoroResumeSoundKey = "pomodoroSoundResume"
    static let pomodoroVolumeKey = "pomodoroSoundVolume"
    /// Fernzugriff für Claude im Browser und auf dem Handy
    static let remoteEnabledKey = "remoteMCPEnabled"
    static let remotePortKey = "remoteMCPPort"
    static let remotePublicURLKey = "remoteMCPPublicURL"
    static let remoteTunnelCommandKey = "remoteMCPTunnelCommand"
    /// Standard-Work-Log-Type für Tickets, bei denen keiner gewählt ist.
    static let defaultWorklogTypeKey = "worklogTypeDefault"
    /// Work Log Types in ServiceDesk Plus, genau wie dort benannt (Pflichtfeld beim Worklog).
    static let knownWorklogTypes = [
        "Change Bearbeitung",
        "Fehlalarm",
        "Fehleranalyse, Incident & Problem Bearbeitung",
        "Incident zur Kenntnis genommen",
        "ServiceCenter",
        "Ticketbearbeitung",
        "Wartung",
    ]
    static let calendarHourHeightKey = "calendarHourHeight"

    static let defaultCalendarWidth: Double = 260
    static let minCalendarWidth: Double = 200
    static let maxCalendarWidth: Double = 900
    static let defaultHourHeight: Double = 48
    static let hourHeightRange: ClosedRange<Double> = 32...160

    static func reflectionKey(for day: LocalDate) -> String { "reflection.\(day.string)" }

    static let defaultWorkdayStart = 8 * 60
    static let defaultWorkdayEnd = 17 * 60
    static let defaultFocusGoalMinutes = 360

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            workdayStartKey: defaultWorkdayStart,
            workdayEndKey: defaultWorkdayEnd,
            focusGoalMinutesKey: defaultFocusGoalMinutes,
            writeBlocksKey: false,
            planningOnLaunchKey: true,
            showInboxKey: true,
            roundingStepKey: 15,
            roundingModeKey: RoundingMode.nearest.rawValue,
            meAutoFetchKey: true,
            idleMinutesKey: 10,
            pomodoroWorkKey: 25,
            pomodoroShortBreakKey: 5,
            pomodoroLongBreakKey: 15,
            pomodoroRoundsKey: 4,
            pomodoroSoundKey: true,
            pomodoroShortBreakSoundKey: "Glass",
            pomodoroLongBreakSoundKey: "tagwerk:gong",
            pomodoroResumeSoundKey: "Hero",
            pomodoroVolumeKey: 0.8,
        ])
    }
}
