import SwiftUI
import TagwerkCore

// MARK: Pausen

/// Schraffur für Pausen: zeigt „hier wurde nicht gearbeitet“, ohne eine Farbe zu belegen.
struct Hatch: View {
    var color: Color = Theme.secondary.opacity(0.28)
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Die Mittagspause im Kalender: schraffierte Fläche, Doppelklick bearbeitet.
struct BreakBlock: View {
    @Environment(AppModel.self) private var model
    let item: WorkBreak
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        HStack(alignment: .top, spacing: 4) {
            if height > 15 {
                Image(systemName: "fork.knife")
                Text(height > 30 ? "Mittagspause · \(range)" : "Mittagspause")
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, height > 15 ? 3 : 0)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(4, height), alignment: .topLeading)
        .background {
            ZStack {
                shape.fill(Theme.surfaceSunken)
                Hatch()
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Theme.border))
        .contentShape(shape)
        .onTapGesture(count: 2) { model.editBreak(item) }
        .contextMenu {
            if item.isRunning {
                Button("Mittagspause beenden") { model.endBreak(resume: true) }
            }
            Button("Mittagspause bearbeiten …") { model.editBreak(item) }
            Divider()
            Button("Mittagspause löschen", role: .destructive) { model.deleteBreak(item.id) }
        }
        .help("Mittagspause \(range)\(item.note.isEmpty ? "" : " · \(item.note)") · Doppelklick bearbeitet")
    }

    private var range: String {
        "\(clock(item.start))–\(item.end.map(clock) ?? "läuft")"
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Mittagspause nachtragen oder bearbeiten. Arbeit, die in diesem Zeitraum erfasst ist, wird herausgenommen.
struct BreakSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: BreakDraft

    @State private var day = Date()
    @State private var from = Date()
    @State private var to = Date()
    @State private var note = ""
    @State private var confirmsDelete = false
    @FocusState private var noteFocused: Bool

    private var isEditing: Bool { draft.breakID != nil }

    var body: some View {
        let now = Date()
        let start = combined(day, from)
        let end = draft.isRunning ? now : combined(day, to)
        let minutes = Int((min(end, now).timeIntervalSince(start) / 60).rounded())
        let work = model.workInside(start: start, end: end)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isEditing ? "Mittagspause bearbeiten" : "Mittagspause nachtragen")
                    .font(Theme.title)
                Text("Zählt nicht als Arbeitszeit und wird nicht gebucht. Kurze Pausen, etwa zwischen Pomodoros, trägst du nicht ein.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
            }

            Form {
                DatePicker("Tag", selection: $day, displayedComponents: .date)
                    .disabled(draft.isRunning)
                DatePicker("Von", selection: $from, displayedComponents: .hourAndMinute)
                if draft.isRunning {
                    LabeledContent("Bis") {
                        Text("läuft")
                            .foregroundStyle(Theme.secondary)
                    }
                } else {
                    DatePicker("Bis", selection: $to, displayedComponents: .hourAndMinute)
                }
                if !isEditing {
                    LabeledContent("Schnell") {
                        HStack(spacing: 6) {
                            Button("12:00–12:30") { set(day: day, fromMinutes: 12 * 60, minutes: 30) }
                            Button("12:00–13:00") { set(day: day, fromMinutes: 12 * 60, minutes: 60) }
                            ForEach([30, 60], id: \.self) { length in
                                Button("letzte \(length) Min") { lastMinutes(length) }
                            }
                        }
                        .buttonStyle(GhostButtonStyle(small: true))
                    }
                }
                TextField("Notiz", text: $note, prompt: Text("optional"))
                    .focused($noteFocused)
                LabeledContent("Dauer") {
                    Text(minutes > 0 ? "\(TimeMath.format(minutes: minutes)) h" : "Ende liegt vor dem Beginn")
                        .monospacedDigit()
                        .foregroundStyle(minutes > 0 ? Theme.text : Theme.warning)
                }
                if work >= 60 {
                    Label("Darin sind \(TimeMath.format(work)) h Arbeit erfasst. Diese Zeit wird dort herausgenommen.", systemImage: "scissors")
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !draft.isRunning, end > now.addingTimeInterval(60) {
                    Label("Endet in der Zukunft und wird auf jetzt gekürzt.", systemImage: "clock")
                        .foregroundStyle(Theme.secondary)
                }
            }
            .tagwerkForm()

            HStack {
                if isEditing {
                    Button("Löschen …", role: .destructive) { confirmsDelete = true }
                        .buttonStyle(GhostButtonStyle(destructive: true))
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Sichern" : "Eintragen") {
                    model.addBreak(start: start, end: end, note: note.trimmingCharacters(in: .whitespacesAndNewlines), replacing: draft.breakID)
                    dismiss()
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(minutes < 5)
                .help(minutes < 5 ? "Mindestens fünf Minuten" : "")
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            day = draft.start
            from = draft.start
            to = draft.end
            note = draft.note
            // Fokus ins Notizfeld statt auf das Datum (dort wäre sonst gleich ein Teil markiert)
            DispatchQueue.main.async { noteFocused = true }
        }
        .confirmationDialog("Mittagspause löschen?", isPresented: $confirmsDelete) {
            Button("Löschen", role: .destructive) {
                if let id = draft.breakID { model.deleteBreak(id) }
                dismiss()
            }
        } message: {
            Text("Herausgenommene Arbeitszeit kommt dadurch nicht zurück.")
        }
    }

    private func set(day date: Date, fromMinutes: Int, minutes: Int) {
        let local = LocalDate(date)
        day = date
        from = FreeTime.date(on: local, minutes: fromMinutes)
        to = FreeTime.date(on: local, minutes: fromMinutes + minutes)
    }

    private func lastMinutes(_ minutes: Int) {
        let now = Date()
        day = now
        to = now
        from = now.addingTimeInterval(TimeInterval(-minutes * 60))
    }

    private func combined(_ day: Date, _ time: Date) -> Date {
        FreeTime.date(on: LocalDate(day), minutes: FreeTime.minutesSinceMidnight(time))
    }
}

/// Fokus während der Mittagspause: wie lange schon, und mit einem Klick weiter.
struct BreakPane: View {
    @Environment(AppModel.self) private var model
    let item: WorkBreak

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.secondary)
            Text("Mittagspause")
                .font(.system(size: 32, weight: .medium))
            VStack(spacing: 6) {
                Text(TimeMath.format(item.duration(now: model.now), showSeconds: true))
                    .font(Theme.timerNumber)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                Text("seit \(item.start.formatted(date: .omitted, time: .shortened)) · zählt nicht als Arbeitszeit")
                    .foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 12) {
                if let task = model.taskAfterBreak {
                    Button {
                        model.endBreak(resume: true)
                    } label: {
                        Label("Weiter mit „\(task.title)“", systemImage: "play.fill")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(GhostButtonStyle(prominent: true))
                    .help("Mittagspause beenden und weiter (⌘T)")
                }
                Button("Beenden") { model.endBreak(resume: false) }
                    .buttonStyle(GhostButtonStyle())
                    .help("Mittagspause beenden, ohne einen Timer zu starten")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }
}

/// „Mittagspause“: hält den Timer an (im Fokus). Pomodoro-Pausen sind etwas anderes und werden nicht eingetragen.
struct StartBreakButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.startBreak()
        } label: {
            Label("Mittagspause", systemImage: "fork.knife")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.tertiary)
        .help("Timer anhalten und die Mittagspause erfassen; danach mit einem Klick weiter (⇧⌘P)")
    }
}

// MARK: Standardaufgaben

/// Standardaufgaben oben auf Start (z. B. „Organisatorisches“): ein Klick startet die Zeit.
struct StandingTaskStrip: View {
    @Environment(AppModel.self) private var model
    @State private var addsNew = false
    @State private var newTitle = ""

    var body: some View {
        let standing = model.standingTasks
        HStack(alignment: .center, spacing: 16) {
            SectionLabel(text: "Standardaufgaben")
                .fixedSize()
                .help("Immer da, nie erledigt: ein Klick startet die Zeit, noch ein Klick stoppt sie")
            FlowLayout(spacing: 8) {
                ForEach(standing) { task in
                    StandingChip(task: task)
                }
                Button {
                    addsNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Color.white.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .help("Neue Standardaufgabe, z. B. „Interne Besprechung“")
                .popover(isPresented: $addsNew, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Neue Standardaufgabe")
                            .font(Theme.cardTitle)
                        TextField("", text: $newTitle, prompt: Text("z. B. Interne Besprechung"))
                            .textFieldStyle(TagwerkFieldStyle())
                            .frame(width: 260)
                            .onSubmit(add)
                        Text("Bleibt immer da und wird nie erledigt. Kunde und SAP-Aufgabe legst du per Rechtsklick › Details fest.")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                            .frame(width: 260, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("Anlegen", action: add)
                                .buttonStyle(GhostButtonStyle(prominent: true, small: true))
                                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(16)
                    .tagwerkPopover()
                }
            }
        }
    }

    private func add() {
        if model.addStandingTask(title: newTitle) != nil {
            newTitle = ""
            addsNew = false
        }
    }
}

/// Eine Standardaufgabe als Knopf: Start und Stopp, darunter die Zeit von heute. Läuft sie, ist sie orange.
struct StandingChip: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    @State private var hovering = false

    var body: some View {
        let running = model.isRunning(task.id)
        let today = model.trackedToday(taskID: task.id)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        Button {
            model.toggleTimer(for: task.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(running ? Theme.accent : (hovering ? Theme.text : Theme.tertiary))
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let customer = model.customer(task.customerID) {
                    CustomerDot(colorIndex: customer.colorIndex, size: 6)
                }
                if today >= 60 || running {
                    Text(TimeMath.format(today))
                        .font(.system(size: 12, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(running ? Theme.accent : Theme.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(shape.fill(running ? Theme.accentSoft : Color.white.opacity(hovering ? 0.08 : 0.04)))
            .overlay(shape.strokeBorder(running ? Theme.accent.opacity(0.5) : Theme.border))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(running ? "Läuft – Klick stoppt" : "Zeit auf „\(task.title)“ starten")
        .contextMenu {
            Button(running ? "Stoppen" : "Starten") { model.toggleTimer(for: task.id) }
            Button("Im Fokus öffnen") { model.openFocus(task.id) }
            Button("Zeit nachtragen …") { model.beginTimeEntry(for: task.id) }
            Divider()
            Button("Details: Kunde, SAP, Ticket …") { model.openDetail(task.id) }
            Divider()
            Button("Entfernen", role: .destructive) { model.removeStandingTask(task.id) }
        }
    }
}
