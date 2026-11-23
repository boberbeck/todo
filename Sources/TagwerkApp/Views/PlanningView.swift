import SwiftUI
import TagwerkCore

/// Geführte Tagesplanung am Morgen: übrig von gestern, Eingang, schätzen, in den Kalender legen.
struct PlanningView: View {
    @Environment(AppModel.self) private var model
    @State private var unplacedCount: Int?

    var body: some View {
        let rolled = model.rolledOverTasks
        let inbox = model.inboxTasks
        let open = model.todayTasks.filter { !$0.isDone }
        let unestimated = open.filter { $0.estimateMinutes == nil }
        let planned = DayPlan.plannedMinutes(open)
        let free = model.freeMinutesToday
        let overplanned = DayPlan.isOverplanned(plannedMinutes: planned, availableMinutes: free)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tag planen")
                        .font(.largeTitle.weight(.bold))
                    Text("\(model.today.startDate().formatted(.dateTime.weekday(.wide).day().month(.wide))) · in vier Schritten zu einem machbaren Tag")
                        .foregroundStyle(.secondary)
                }

                PlanningStep(
                    number: 1,
                    title: "Von gestern übrig",
                    subtitle: rolled.isEmpty ? "Nichts liegen geblieben." : "Behalten, auf später schieben oder erledigt?"
                ) {
                    ForEach(rolled) { task in
                        PlanningRow(task: task) {
                            Button("Behalten") { model.acknowledgeRolledOver(task.id) }
                            Button("Später") {
                                model.plan(task.id, for: nil)
                                model.acknowledgeRolledOver(task.id)
                            }
                            Button("Erledigt") { model.complete(task.id) }
                        }
                    }
                }

                PlanningStep(
                    number: 2,
                    title: "Aus dem Eingang holen",
                    subtitle: inbox.isEmpty ? "Der Eingang ist leer." : "Was kommt heute dran?"
                ) {
                    ForEach(inbox) { task in
                        PlanningRow(task: task) {
                            Button("Heute") { model.plan(task.id, for: model.today) }
                        }
                    }
                }

                PlanningStep(
                    number: 3,
                    title: "Zeit schätzen",
                    subtitle: unestimated.isEmpty ? "Alle Aufgaben für heute haben eine Schätzung." : "Wie lange dauert das ungefähr?"
                ) {
                    ForEach(unestimated) { task in
                        PlanningRow(task: task) {
                            ForEach([15, 30, 60, 90], id: \.self) { minutes in
                                Button(TimeMath.format(minutes: minutes)) {
                                    model.setEstimate(minutes, for: task.id)
                                }
                            }
                        }
                    }
                }

                PlanningStep(
                    number: 4,
                    title: "In den Kalender legen",
                    subtitle: "\(TimeMath.format(minutes: planned)) h geplant, \(TimeMath.format(minutes: free)) h frei neben den Terminen"
                ) {
                    if overplanned {
                        Label("Mehr geplant, als Zeit da ist. Schieb etwas auf morgen.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 12) {
                        Button("In freie Lücken legen") {
                            unplacedCount = model.autoScheduleToday()
                        }
                        if let unplacedCount, unplacedCount > 0 {
                            Text(unplacedCount == 1 ? "1 Aufgabe passt nicht mehr hinein." : "\(unplacedCount) Aufgaben passen nicht mehr hinein.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(open) { task in
                            HStack(spacing: 10) {
                                Text(task.scheduledStart.map { $0.formatted(date: .omitted, time: .shortened) } ?? "–")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .leading)
                                Text(task.title)
                                Spacer()
                                Text("\(TimeMath.format(minutes: task.blockMinutes)) h")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        model.finishPlanning()
                    } label: {
                        Text("Los geht’s")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(GhostButtonStyle(prominent: true))
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Tag planen")
    }
}

struct PlanningStep<Content: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.medium))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PlanningRow<Actions: View>: View {
    let task: TaskItem
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                TaskMetaLine(task: task)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                actions
            }
            .buttonStyle(GhostButtonStyle(small: true))
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
