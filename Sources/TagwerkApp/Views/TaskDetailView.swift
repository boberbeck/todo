import AppKit
import SwiftUI
import TagwerkCore

/// Eine Aufgabe mit allem: Titel, Planung, Ticket, Ziel, Unteraufgaben, Notizen und erfasste Zeiten.
/// Öffnet sich per Doppelklick; alles lässt sich hier ändern.
struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    let taskID: UUID
    /// Höhe, die im Hauptfenster zur Verfügung steht
    var height: CGFloat = 720

    @State private var title = ""
    @State private var notes = ""
    @State private var workDescription = ""
    @State private var showsTicketPicker = false
    @State private var timeDraft: TimeEntryDraft?
    @State private var confirmsDelete = false

    private static let estimates = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480]


    var body: some View {
        if let task = model.task(taskID) {
            content(task)
        } else {
            VStack(spacing: 12) {
                Text("Die Aufgabe gibt es nicht mehr.")
                Button("Schließen") { close() }
            }
            .padding(32)
        }
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        let effective = model.resolved(task)
        let running = model.isRunning(task.id)
        VStack(spacing: 0) {
            header(task)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Form {
                if let parent = model.parent(of: task) {
                    Section {
                        LabeledContent("Teil von") {
                            Button(parent.title) { model.openDetail(parent.id) }
                                .buttonStyle(.borderless).foregroundStyle(Theme.accent)
                        }
                    }
                }

                Section("Planung") {
                    Picker("Kunde", selection: Binding(
                        get: { task.customerID },
                        set: { model.setCustomer($0, for: task.id) }
                    )) {
                        Text("Ohne Kunde").tag(UUID?.none)
                        ForEach(model.activeCustomers) { customer in
                            Text(customer.name).tag(UUID?.some(customer.id))
                        }
                    }
                    if !task.isSubtask {
                        Toggle("Für einen Tag geplant", isOn: Binding(
                            get: { task.plannedDate != nil },
                            set: { model.plan(task.id, for: $0 ? model.today : nil) }
                        ))
                        if let planned = task.plannedDate {
                            DatePicker("Tag", selection: Binding(
                                get: { planned.startDate() },
                                set: { model.plan(task.id, for: LocalDate($0)) }
                            ), displayedComponents: .date)
                        }
                    }
                    Picker("Schätzung", selection: Binding(
                        get: { task.estimateMinutes },
                        set: { model.setEstimate($0, for: task.id) }
                    )) {
                        Text("Keine").tag(Int?.none)
                        ForEach(estimateOptions(task), id: \.self) { minutes in
                            Text("\(TimeMath.format(minutes: minutes)) h").tag(Int?.some(minutes))
                        }
                    }
                    if !task.isSubtask {
                        Picker("Ziel", selection: Binding(
                            get: { task.longGoalID },
                            set: { model.setLongGoal($0, for: task.id) }
                        )) {
                            Text("Kein Ziel").tag(UUID?.none)
                            ForEach(model.activeLongGoals) { goal in
                                Text(goal.title).tag(UUID?.some(goal.id))
                            }
                        }
                        Picker("Wochenziel", selection: Binding(
                            get: { task.goalID },
                            set: { model.setGoal($0, for: task.id) }
                        )) {
                            Text("Kein Wochenziel").tag(UUID?.none)
                            ForEach(model.goals(forWeekStarting: model.currentWeekStart)) { goal in
                                Text(goal.title).tag(UUID?.some(goal.id))
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Ticket") {
                        if task.source == .ticket {
                            Text("#\(task.externalID ?? "?") · \(model.ticketTitle(for: task) ?? task.title)")
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Button {
                                showsTicketPicker = true
                            } label: {
                                Text(ticketLabel(task, effective: effective))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                            .buttonStyle(.borderless).foregroundStyle(Theme.accent)
                            .popover(isPresented: $showsTicketPicker, arrowEdge: .bottom) {
                                TicketPicker(taskID: task.id) { showsTicketPicker = false }
                            }
                        }
                    }
                    if effective.hasTicket {
                        Picker("Work Log Type", selection: Binding(
                            get: { task.worklogType },
                            set: { model.setWorklogType($0, for: task.id) }
                        )) {
                            Text("Standard (\(model.defaultWorklogType))").tag(String?.none)
                            ForEach(Preferences.knownWorklogTypes, id: \.self) { type in
                                Text(type).tag(String?.some(type))
                            }
                        }
                    }
                } header: {
                    Text("Ticket")
                } footer: {
                    Text(task.isSubtask ? "Ohne eigenes Ticket gilt das der Aufgabe „\(model.parent(of: task)?.title ?? "")“." : "Mit Ticket geht die Zeit im Tagesabschluss als Worklog dorthin; der Worklog ist freiwillig.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !task.isSubtask {
                    Section("Unteraufgaben") {
                        ForEach(model.subtasks(of: task.id)) { subtask in
                            SubtaskEditRow(task: subtask)
                        }
                        if !task.isDone {
                            AddSubtaskField(parentID: task.id)
                        }
                    }
                }

                Section("Notizen") {
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                }

                Section {
                    TextEditor(text: $workDescription)
                        .font(.body)
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Bearbeitung")
                } footer: {
                    Text("Wird zum Text für den Worklog im Ticket.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    let list = model.entries(forTask: task.id)
                    if list.isEmpty {
                        Text("Noch keine Zeit erfasst.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(list.prefix(30)) { entry in
                        HStack {
                            Text(entry.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .frame(width: 90, alignment: .leading)
                            Text("\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.map { $0.formatted(date: .omitted, time: .shortened) } ?? "läuft")")
                                .monospacedDigit()
                            Spacer()
                            Text(TimeMath.format(entry.duration(now: running ? model.now : Date())))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button {
                                model.deleteEntry(entry.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(entry.isRunning)
                            .help("Diesen Zeiteintrag löschen")
                        }
                    }
                    HStack {
                        Button("Zeit nachtragen …") {
                            let end = Date()
                            timeDraft = TimeEntryDraft(start: end.addingTimeInterval(-30 * 60), minutes: 30, taskID: task.id)
                        }
                        Spacer()
                    }
                } header: {
                    Text("Zeiten · \(TimeMath.format(model.trackedIncludingSubtasks(taskID: task.id, now: running ? model.now : Date()))) h")
                }
            }
            .tagwerkForm()

            Divider()
            footer(task, running: running)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .frame(width: 640, height: height)
        .onAppear {
            title = task.title
            notes = task.notes
            workDescription = task.workDescription
        }
        .onChange(of: notes) { model.setNotes(notes, for: taskID) }
        .onChange(of: workDescription) { model.setDescription(workDescription, for: taskID) }
        .onDisappear { model.setTitle(title, for: taskID) }
        .sheet(item: $timeDraft) { draft in
            AddTimeSheet(draft: draft)
                .tagwerkSheet()
        }
        .confirmationDialog("„\(task.title)“ löschen?", isPresented: $confirmsDelete) {
            Button("Löschen", role: .destructive) {
                model.delete(task.id)
                close()
            }
        } message: {
            Text("Mit Unteraufgaben und allen erfassten Zeiten.")
        }
    }

    private func header(_ task: TaskItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.isDone ? Theme.done : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Wieder öffnen" : "Erledigt")
            VStack(alignment: .leading, spacing: 4) {
                TextField("Titel", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium))
                    .onSubmit { model.setTitle(title, for: taskID) }
                HStack(spacing: 6) {
                    Image(systemName: task.source.systemImage)
                    Text(task.source.label)
                    if let customer = model.customer(task.customerID) {
                        Text("·")
                        CustomerDot(colorIndex: customer.colorIndex, size: 6)
                        Text(customer.name)
                    }
                    Text("· angelegt \(task.createdAt.formatted(date: .abbreviated, time: .omitted))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.setTitle(title, for: taskID)
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Schließen (Esc), auch ein Klick daneben schließt")
        }
    }

    private func close() {
        model.detailTaskID = nil
    }

    private func footer(_ task: TaskItem, running: Bool) -> some View {
        HStack(spacing: 10) {
            Button("Löschen", role: .destructive) { confirmsDelete = true }
            Spacer()
            Button("Im Fokus öffnen") {
                model.setTitle(title, for: taskID)
                model.openFocus(task.id)
                close()
            }
            if !task.isDone {
                Button {
                    model.toggleTimer(for: task.id)
                } label: {
                    Label(running ? "Timer stoppen" : "Timer starten", systemImage: running ? "pause.fill" : "play.fill")
                }
            }
            Button("Fertig") {
                model.setTitle(title, for: taskID)
                close()
            }
            .buttonStyle(GhostButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func estimateOptions(_ task: TaskItem) -> [Int] {
        var options = Self.estimates
        if let current = task.estimateMinutes, !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return options
    }

    private func ticketLabel(_ task: TaskItem, effective: TaskItem) -> String {
        guard let number = effective.linkedTicketNumber else { return "Zuordnen …" }
        let title = model.ticketTitle(for: task).map { " · \($0)" } ?? ""
        let inherited = task.ticketNumber == nil ? " (geerbt)" : ""
        let noLink = effective.linkedTicketKey == nil ? " · ohne Worklog" : ""
        return "#\(number)\(title)\(inherited)\(noLink)"
    }
}

/// Unteraufgabe im Aufgabenfenster: abhaken, umbenennen, Timer, löschen.
struct SubtaskEditRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        let running = model.isRunning(task.id)
        HStack(spacing: 8) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.isDone ? Theme.done : Theme.tertiary)
            }
            .buttonStyle(.plain)
            TextField("Unteraufgabe", text: $title)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .strikethrough(task.isDone, color: Theme.tertiary)
                .focused($focused)
                .onSubmit { model.setTitle(title, for: task.id) }
                .onChange(of: focused) { if !focused { model.setTitle(title, for: task.id) } }
            if let number = task.ticketNumber, number != model.parent(of: task)?.linkedTicketNumber {
                Text("#\(number)")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            let tracked = model.tracked(taskID: task.id, now: running ? model.now : Date())
            if tracked > 0 {
                Text(TimeMath.format(tracked))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !task.isDone {
                Button {
                    model.toggleTimer(for: task.id)
                } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .help(running ? "Timer stoppen" : "Timer starten")
            }
            Button {
                model.openDetail(task.id)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Unteraufgabe öffnen (Ticket, Zeiten)")
            Button {
                model.delete(task.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Unteraufgabe löschen")
        }
        .onAppear { title = task.title }
        .onChange(of: task.title) { title = task.title }
    }
}
