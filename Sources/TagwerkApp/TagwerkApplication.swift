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

        Settings {
            SettingsView()
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
            Button("Timer starten oder stoppen") { model.toggleTimerForFocus() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Erledigt") { model.completeFocused() }
                .keyboardShortcut(.return, modifiers: .command)
        }
        CommandMenu("Gehe zu") {
            Button("Heute") { model.selection = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("Fokus") { model.selection = .focus }
                .keyboardShortcut("2", modifiers: .command)
            Button("Kunden") { model.selection = .customers }
                .keyboardShortcut("3", modifiers: .command)
            Button("Rückblick") { model.selection = .review }
                .keyboardShortcut("4", modifiers: .command)
        }
    }
}

enum Preferences {
    static let workdayMinutesKey = "workdayMinutes"
    static let focusGoalMinutesKey = "focusGoalMinutes"
    static let defaultWorkdayMinutes = 480
    static let defaultFocusGoalMinutes = 360
}
