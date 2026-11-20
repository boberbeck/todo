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
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            TagwerkCommands(model: model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("SAP ByDesign", id: "bydesign") {
            ByDesignBrowserView()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 780)

        Settings {
            SettingsView()
                .environment(model)
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
            Button("Zeit nachtragen …") { model.beginTimeEntry(for: model.focusTask?.id) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("SAP-Aufgaben abgleichen …") { model.showsSAPSync = true }
        }
        CommandMenu("Gehe zu") {
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
    static let roundingStepKey = "roundingStepMinutes"
    static let roundingModeKey = "roundingMode"
    static let meBaseURLKey = "manageEngineBaseURL"
    static let meAuthKindKey = "manageEngineAuthKind"
    static let meTechnicianKey = "manageEngineTechnicianID"
    static let meAutoFetchKey = "manageEngineAutoFetch"
    static let idleMinutesKey = "idleMinutes"
    static let calendarWidthKey = "calendarColumnWidth"
    static let bydesignURLKey = "bydesignURL"
    static let bydesignUserKey = "bydesignUser"
    static let bydesignTaskListURLKey = "bydesignTaskListURL"
    static let bydesignAutoFetchKey = "bydesignAutoFetch"
    /// Fernzugriff für Claude im Browser und auf dem Handy
    static let remoteEnabledKey = "remoteMCPEnabled"
    static let remotePortKey = "remoteMCPPort"
    static let remotePublicURLKey = "remoteMCPPublicURL"
    static let remoteTunnelCommandKey = "remoteMCPTunnelCommand"
    static let bydesignLastAutoFetchKey = "bydesignLastAutoFetch"
    static let bydesignPasswordAccount = "bydesign"
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

    static func serviceKey(for workType: WorkType) -> String { "serviceProduct.\(workType.rawValue)" }

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
        ])
    }
}
