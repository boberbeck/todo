import SwiftUI
import TagwerkCore

/// Erfasste Zeit genau bearbeiten: Aufgabe, Tag, Beginn und Ende ändern oder den Eintrag löschen.
/// Öffnet per Doppelklick auf einen Eintrag im Kalender.
struct EditEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: TimeEntry

    @State private var taskID: UUID?
    @State private var day = Date()
    @State private var from = Date()
    @State private var to = Date()
    @State private var confirmsDelete = false

    private var isRunning: Bool { entry.end == nil }

    var body: some View {
        let start = EntryEditing.keepingSeconds(combined(day, from), of: entry.start)
        let end: Date? = isRunning ? nil : EntryEditing.keepingSeconds(combined(day, to), of: entry.end)
        let now = Date()
        let problem = EntryEditing.problem(start: start, end: end, excluding: entry.id, in: model.entries, now: now)
        let minutes = Int(((end ?? now).timeIntervalSince(start) / 60).rounded())

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Zeit bearbeiten")
                    .font(.title2.weight(.semibold))
                Text(isRunning
                     ? "Der Timer läuft noch. Ändern lässt sich der Beginn, z. B. wenn du zu spät gestartet hast."
                     : "Beginn, Ende oder Aufgabe korrigieren. Im Kalender geht das auch direkt mit der Maus.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Aufgabe", selection: $taskID) {
                    if taskID == nil {
                        Text("Ohne Aufgabe").tag(UUID?.none)
                    }
                    ForEach(candidates) { task in
                        Text(label(for: task)).tag(UUID?.some(task.id))
                    }
                }
                DatePicker("Tag", selection: $day, displayedComponents: .date)
                    .disabled(isRunning)
                DatePicker("Von", selection: $from, displayedComponents: .hourAndMinute)
                if isRunning {
                    LabeledContent("Bis") {
                        Text("läuft")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    DatePicker("Bis", selection: $to, displayedComponents: .hourAndMinute)
                }
                LabeledContent("Dauer") {
                    Text(minutes > 0 ? "\(TimeMath.format(minutes: minutes)) h" : "–")
                        .monospacedDigit()
                }
                if let problem {
                    Label(message(for: problem), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tagwerkForm()

            if wasBooked {
                Text("Für diesen Tag ist schon gebucht. Nach der Änderung im Tagesabschluss prüfen und neu senden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Löschen …", role: .destructive) { confirmsDelete = true }
                    .disabled(isRunning)
                    .help(isRunning ? "Erst den Timer stoppen" : "Diesen Eintrag löschen")
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    model.updateEntry(entry.id, start: start, end: end, taskID: taskID)
                    dismiss()
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            taskID = entry.taskID
            day = entry.start
            from = entry.start
            to = entry.end ?? now
        }
        .confirmationDialog("Eintrag löschen?", isPresented: $confirmsDelete) {
            Button("Löschen", role: .destructive) {
                model.deleteEntry(entry.id)
                dismiss()
            }
        } message: {
            Text("Die erfasste Zeit \(clock(entry.start))–\(entry.end.map { clock($0) } ?? "") verschwindet aus Kalender und Tagesabschluss.")
        }
    }

    /// Schon gebucht (Worklog gesendet oder in SAP abgehakt)? Dann muss nach der Änderung neu gebucht werden.
    private var wasBooked: Bool {
        let entryDay = LocalDate(entry.start)
        return model.bookings.contains { $0.taskID == entry.taskID && $0.day == entryDay && $0.status.isDone }
    }

    private func message(for problem: EntryEditing.Problem) -> String {
        switch problem {
        case .endBeforeStart:
            return "Das Ende liegt vor dem Beginn."
        case .inFuture:
            return "Die Zeit liegt in der Zukunft."
        case .overlaps(let other):
            let title = model.task(other.taskID)?.title ?? "Ohne Aufgabe"
            let range = "\(clock(other.start))–\(other.end.map { clock($0) } ?? "läuft")"
            return "Überschneidet sich mit „\(title)“ (\(range)). Die Zeit würde doppelt zählen; erst den anderen Eintrag kürzen."
        }
    }

    /// Bisherige Aufgabe zuerst, dann die des Tages, von heute und offene, ohne Doppelte.
    private var candidates: [TaskItem] {
        let current = model.task(entry.taskID).map { [$0] } ?? []
        let sameDay = model.dayTasks(LocalDate(day))
        let open = model.tasks.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<UUID>()
        return (current + sameDay + model.todayTasks + open).filter { seen.insert($0.id).inserted }.prefix(60).map { $0 }
    }

    private func label(for task: TaskItem) -> String {
        let title = model.parent(of: task).map { "\($0.title) › \(task.title)" } ?? task.title
        if let customer = model.customer(task.customerID) {
            return "\(title) · \(customer.name)"
        }
        return title
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func combined(_ day: Date, _ time: Date) -> Date {
        FreeTime.date(on: LocalDate(day), minutes: FreeTime.minutesSinceMidnight(time))
    }
}
