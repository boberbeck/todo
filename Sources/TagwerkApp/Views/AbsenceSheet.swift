import SwiftUI
import TagwerkCore

/// Entwurf für „Abwesenheit eintragen“.
struct AbsenceDraft: Identifiable {
    let id = UUID()
    var kind: AbsenceKind
    var from: LocalDate
    var through: LocalDate
}

/// Krank oder Urlaub eintragen, für einen Tag (auch halb) oder mehrere.
struct AbsenceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: AbsenceDraft

    @State private var kind: AbsenceKind = .sick
    @State private var from = Date()
    @State private var through = Date()
    @State private var halfDay = false
    @State private var note = ""
    @State private var moveTasks = true

    var body: some View {
        let start = LocalDate(from)
        let end = LocalDate(through)
        let days = Absences.workdays(from: start, through: max(start, end))
        let single = days.count == 1
        let openTasks = model.tasks.filter { task in
            !task.isDone && task.parentID == nil && (task.plannedDate.map { days.contains($0) } ?? false)
        }

        VStack(alignment: .leading, spacing: 16) {
            Text("Abwesenheit eintragen")
                .font(Theme.title)

            Form {
                Picker("Art", selection: $kind) {
                    ForEach(AbsenceKind.allCases) { kind in
                        Label(kind.label, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                DatePicker("Von", selection: $from, displayedComponents: .date)
                DatePicker("Bis", selection: $through, in: from..., displayedComponents: .date)
                if single {
                    Toggle("Nur ein halber Tag", isOn: $halfDay)
                }
                TextField("Notiz", text: $note, prompt: Text("optional, z. B. Arzttermin"))
                LabeledContent("Arbeitstage") {
                    Text(days.isEmpty ? "keine (Wochenende)" : (single && halfDay ? "½" : "\(days.count)"))
                        .monospacedDigit()
                        .foregroundStyle(days.isEmpty ? Theme.warning : Theme.text)
                }
                if !openTasks.isEmpty, !(single && halfDay) {
                    Toggle("\(openTasks.count) offene Aufgabe\(openTasks.count == 1 ? "" : "n") auf den nächsten Arbeitstag verschieben", isOn: $moveTasks)
                }
            }
            .tagwerkForm()

            Text("Wochenenden zählen nicht mit. Das Wochenziel wird um diese Tage kleiner. In SAP ByDesign trägst du die Abwesenheit wie gewohnt selbst ein.")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Eintragen") {
                    model.markAbsent(kind, from: start, through: end, halfDay: single && halfDay, note: note, moveTasks: moveTasks)
                    dismiss()
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(days.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            kind = draft.kind
            from = draft.from.startDate()
            through = draft.through.startDate()
        }
        .onChange(of: from) {
            if through < from { through = from }
        }
    }
}
