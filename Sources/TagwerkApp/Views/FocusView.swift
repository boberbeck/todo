import SwiftUI
import TagwerkCore

/// Fokus-Modus: nur eine Aufgabe groß, rechts die Done-Liste von heute.
struct FocusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let task = model.focusTask {
                    FocusTaskPane(task: task)
                        .id(task.id)
                } else {
                    ContentUnavailableView(
                        "Keine offene Aufgabe",
                        systemImage: "scope",
                        description: Text("Plane im Tagesplan eine Aufgabe für heute ein.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            DoneListPane()
                .frame(width: 300)
        }
        .navigationTitle("Fokus")
    }
}

struct FocusTaskPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.focusGoalMinutesKey) private var focusGoalMinutes = Preferences.defaultFocusGoalMinutes
    let task: TaskItem

    @State private var descriptionText = ""
    @State private var pspText = ""

    var body: some View {
        let running = model.isRunning(task.id)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Jetzt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(3)
                HStack(spacing: 10) {
                    TaskMetaLine(task: task, showsBooking: false)
                    WorkTypeMenu(task: task)
                    TextField("PSP-Element", text: $pspText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onSubmit { model.setPSPElement(pspText, for: task.id) }
                        .help("PSP-Element in SAP ByDesign, gilt für alle Zeiten dieser Aufgabe")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(TimeMath.format(model.tracked(taskID: task.id, now: running ? model.now : Date()), showSeconds: true))
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let estimate = task.estimateMinutes {
                    Text("von \(TimeMath.format(minutes: estimate)) h geplant")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.toggleTimer(for: task.id)
                } label: {
                    Label(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)

                Button {
                    model.complete(task.id)
                } label: {
                    Label("Erledigt", systemImage: "checkmark")
                        .frame(minWidth: 110)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .help("Erledigt (⌘↩), danach kommt die nächste Aufgabe")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bearbeitung")
                        .font(.headline)
                    Spacer()
                    Text("für Worklog und SAP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $descriptionText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 80, maxHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.15))
                    )
            }

            Spacer(minLength: 0)

            FocusTimeBar(goalMinutes: focusGoalMinutes)
        }
        .padding(32)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            descriptionText = task.workDescription
            pspText = task.pspElement ?? ""
            model.focusedTaskID = task.id
        }
        .onChange(of: descriptionText) {
            model.setDescription(descriptionText, for: task.id)
        }
        .onDisappear {
            model.setPSPElement(pspText, for: task.id)
        }
    }
}

/// Fokuszeit des Tages gegen das Tagesziel (Input statt Output).
struct FocusTimeBar: View {
    @Environment(AppModel.self) private var model
    let goalMinutes: Int

    var body: some View {
        let tracked = model.trackedToday(now: model.runningEntry == nil ? Date() : model.now)
        let goal = Double(max(goalMinutes, 1) * 60)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fokuszeit heute")
                    .font(.headline)
                Spacer()
                Text("\(TimeMath.format(tracked)) von \(TimeMath.format(minutes: goalMinutes)) h")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(tracked / goal, 1))
        }
    }
}

/// Done-Liste: was heute erledigt ist, mit Zeit und Buchungsziel.
struct DoneListPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Heute erledigt")
                    .font(.title3.weight(.semibold))
                Text("Done-Liste mit Buchungsziel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.doneToday.isEmpty {
                Text("Noch nichts erledigt.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.doneToday) { task in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                    Text("bucht: \(task.bookingTargets)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(TimeMath.format(model.tracked(taskID: task.id, now: Date())))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                            }
                            Divider()
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Text("Gebucht wird beim Tagesabschluss.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
