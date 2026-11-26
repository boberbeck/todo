import AppKit
import SwiftUI
import TagwerkCore

/// Text in der Menüleiste: laufende Zeit und Aufgabe, sonst nur ein Symbol.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let task = model.runningTask {
                Text("▶ \(TimeMath.format(model.tracked(taskID: task.id, now: model.now))) \(String(task.title.prefix(20)))")
            } else if let pause = model.runningBreak {
                Text("Mittag \(TimeMath.format(pause.duration(now: model.now)))")
            } else {
                Image(systemName: "checklist")
            }
        }
        // Damit ein Klick aufs Dock-Symbol das Fenster wieder öffnen kann
        .onAppear {
            MainWindow.register { openWindow(id: "main") }
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pause = model.runningBreak {
                Text("Mittagspause")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(TimeMath.format(pause.duration(now: model.now), showSeconds: true))
                    .font(.title2.monospacedDigit())
                HStack {
                    if let task = model.taskAfterBreak {
                        Button("Weiter mit \(task.title)") { model.endBreak(resume: true) }
                            .lineLimit(1)
                    }
                    Button("Beenden") { model.endBreak(resume: false) }
                }
            } else if let task = model.runningTask {
                Text("Läuft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                Text(TimeMath.format(model.tracked(taskID: task.id, now: model.now), showSeconds: true))
                    .font(.title2.monospacedDigit())
                HStack {
                    Button("Stoppen") { model.stopTimer() }
                    Button("Mittagspause") { model.startBreak() }
                    if !task.isStanding {
                        Button("Erledigt") { model.complete(task.id) }
                    }
                }
                Menu("Falsche Aufgabe? Zeit umhängen") {
                    SwitchTaskItems(current: task.id)
                }
                .fixedSize()
                .help("Die Zeit seit dem Start zählt dann für die gewählte Aufgabe, der Timer läuft weiter")
            } else {
                Text("Kein Timer aktiv")
                    .foregroundStyle(.secondary)
            }

            Divider()

            let open = (model.todayTasks.filter { !$0.isDone } + model.standingTasks).filter { !model.isRunning($0.id) }
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

            if model.absence(on: model.today) == nil {
                Button("Heute krank eintragen") {
                    model.markAbsent(.sick, from: model.today, through: model.today)
                }
            }
            Button("Befehlszeile … (⌘K)") {
                openWindow(id: "main")
                NSApp.activate()
                model.openCommandBar()
            }
            Button("Tagwerk öffnen") {
                openWindow(id: "main")
                NSApp.activate()
            }
            Button("Beenden") {
                NSApp.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }
}
