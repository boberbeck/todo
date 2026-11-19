import AppKit
import SwiftUI
import TagwerkCore

/// Text in der Menüleiste: laufende Zeit und Aufgabe, sonst nur ein Symbol.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let task = model.runningTask {
            Text("▶ \(TimeMath.format(model.tracked(taskID: task.id, now: model.now))) \(String(task.title.prefix(20)))")
        } else {
            Image(systemName: "checklist")
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = model.runningTask {
                Text("Läuft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(TimeMath.format(model.tracked(taskID: task.id, now: model.now), showSeconds: true))
                    .font(.title2.monospacedDigit())
                HStack {
                    Button("Stoppen") { model.stopTimer() }
                    Button("Erledigt") { model.complete(task.id) }
                }
            } else {
                Text("Kein Timer aktiv")
                    .foregroundStyle(.secondary)
            }

            Divider()

            let open = model.todayTasks.filter { !$0.isDone && !model.isRunning($0.id) }
            if !open.isEmpty {
                Text("Heute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(open.prefix(8))) { task in
                    Button {
                        model.startTimer(task.id)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.secondary)
                            Text(task.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }

            Button("Tagwerk öffnen") {
                openWindow(id: "main")
                NSApp.activate()
            }
            Button("Beenden") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

struct SettingsView: View {
    @AppStorage(Preferences.workdayMinutesKey) private var workdayMinutes = Preferences.defaultWorkdayMinutes
    @AppStorage(Preferences.focusGoalMinutesKey) private var focusGoalMinutes = Preferences.defaultFocusGoalMinutes

    var body: some View {
        Form {
            Section("Tag") {
                Stepper(value: $workdayMinutes, in: 60...720, step: 15) {
                    LabeledContent("Freie Zeit pro Tag", value: "\(TimeMath.format(minutes: workdayMinutes)) h")
                }
                Stepper(value: $focusGoalMinutes, in: 30...720, step: 15) {
                    LabeledContent("Tagesziel Fokuszeit", value: "\(TimeMath.format(minutes: focusGoalMinutes)) h")
                }
            }
            Section("Daten") {
                LabeledContent("Speicherort", value: "~/Library/Application Support/Tagwerk")
                Button("Im Finder zeigen") {
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Tagwerk", isDirectory: true)
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
