import SwiftUI
import TagwerkCore

/// Lange Ziele über Wochen, z. B. „AZ-305 bestehen“: Zieldatum, Stundenziel, Fortschritt und die Aufgaben dazu.
struct GoalsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsDone = false

    var body: some View {
        let active = model.activeLongGoals
        let done = model.sortedLongGoals.filter(\.isDone)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Ziele") {
                    EmptyView()
                }

                NewGoalCard()

                if active.isEmpty {
                    Text("Noch kein Ziel. Leg oben eins an, z. B. „AZ-305 bestehen“ bis zum Prüfungstermin mit 40 Stunden Lernzeit.")
                        .foregroundStyle(Theme.tertiary)
                        .padding(.vertical, 8)
                }
                ForEach(active) { goal in
                    GoalCard(goal: goal)
                }

                if !done.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showsDone.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showsDone ? "chevron.down" : "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.tertiary)
                                SectionLabel(text: "Erreicht", detail: "\(done.count)")
                            }
                        }
                        .buttonStyle(.plain)
                        if showsDone {
                            ForEach(done) { goal in
                                GoalCard(goal: goal)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
    }
}

/// Neues Ziel: Titel, bis wann, wie viele Stunden, optional Kunde.
struct NewGoalCard: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date()
    @State private var hours = ""
    @State private var customerID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(Theme.tertiary)
                TextField("Neues Ziel, z. B. „AZ-305 bestehen“", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit(add)
            }
            HStack(spacing: 14) {
                Toggle("Bis", isOn: $hasDueDate)
                    .toggleStyle(.checkbox)
                DatePicker("Zieldatum", selection: $dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!hasDueDate)
                    .fixedSize()
                HStack(spacing: 4) {
                    TextField("Stunden", text: $hours)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("h Ziel (optional)")
                        .foregroundStyle(Theme.secondary)
                }
                Picker("Kunde", selection: $customerID) {
                    Text("Ohne Kunde").tag(UUID?.none)
                    ForEach(model.activeCustomers) { customer in
                        Text(customer.name).tag(UUID?.some(customer.id))
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                Spacer()
                Button("Anlegen", action: add)
                    .buttonStyle(GhostButtonStyle(prominent: true))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.callout)
        }
        .card(padding: 18)
    }

    private func add() {
        let minutes = Double(hours.replacingOccurrences(of: ",", with: ".")).map { Int($0 * 60) }
        guard model.addLongGoal(
            title: title,
            dueDate: hasDueDate ? LocalDate(dueDate) : nil,
            targetMinutes: minutes,
            customerID: customerID
        ) != nil else { return }
        title = ""
        hours = ""
    }
}

/// Ein Ziel mit Fortschritt, Tempo und seinen Aufgaben.
struct GoalCard: View {
    @Environment(AppModel.self) private var model
    let goal: LongGoal

    @State private var newTask = ""
    @State private var showsEditor = false
    @State private var showsAllDone = false

    var body: some View {
        let progress = model.progress(of: goal)
        let tasks = model.goalTasks(goal)
        let open = tasks.filter { !$0.isDone }
        let done = tasks.filter(\.isDone)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    model.toggleLongGoal(goal.id)
                } label: {
                    Image(systemName: goal.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(goal.isDone ? Theme.done : Theme.tertiary)
                }
                .buttonStyle(.plain)
                .help(goal.isDone ? "Wieder öffnen" : "Ziel erreicht")
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.system(size: 20, weight: .medium))
                        .strikethrough(goal.isDone, color: Theme.tertiary)
                    Text(GoalText.summary(goal, progress: progress, customer: model.customer(goal.customerID)?.name))
                        .font(.callout)
                        .foregroundStyle(progress.isBehind ? Theme.warning : Theme.secondary)
                }
                Spacer()
                Button {
                    showsEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondary)
                .help("Ziel bearbeiten")
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressLine(value: progress.fraction ?? 0, height: 6)
                HStack {
                    Text(GoalText.amount(progress))
                        .monospacedDigit()
                    Spacer()
                    if let pace = GoalText.pace(progress) {
                        Text(pace)
                            .foregroundStyle(progress.isBehind ? Theme.warning : Theme.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
            }

            if !goal.isDone {
                VStack(spacing: 8) {
                    ForEach(open) { task in
                        TaskCard(task: task, compact: true, allowsDrop: false)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.tertiary)
                        TextField("Aufgabe für dieses Ziel, z. B. „Modul Identität lernen 1h30“", text: $newTask)
                            .textFieldStyle(.plain)
                            .onSubmit { addTask(today: false) }
                        Button("Heute") { addTask(today: true) }
                            .buttonStyle(GhostButtonStyle())
                            .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                            .help("Anlegen und für heute einplanen; ↩ legt sie in den Eingang")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
            }

            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showsAllDone.toggle() }
                    } label: {
                        Text(showsAllDone ? "Erledigte ausblenden" : "\(done.count) erledigt")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                    if showsAllDone {
                        ForEach(done) { task in
                            DoneRow(task: task)
                        }
                    }
                }
            }
        }
        .card(padding: 20)
        .contextMenu {
            Button(goal.isDone ? "Wieder öffnen" : "Ziel erreicht") { model.toggleLongGoal(goal.id) }
            Button("Bearbeiten …") { showsEditor = true }
            Divider()
            Button("Löschen", role: .destructive) { model.deleteLongGoal(goal.id) }
        }
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap { UUID(uuidString: $0) }
            for id in ids { model.setLongGoal(goal.id, for: id) }
            return !ids.isEmpty
        }
        .sheet(isPresented: $showsEditor) {
            GoalEditor(goal: goal)
                .tagwerkSheet()
        }
    }

    private func addTask(today: Bool) {
        if model.addTask(title: newTask, toGoal: goal.id, plannedDate: today ? model.today : nil) != nil {
            newTask = ""
        }
    }
}

/// Ziel bearbeiten: Titel, Zieldatum, Stundenziel, Kunde, Notizen.
struct GoalEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let goal: LongGoal

    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hours = ""
    @State private var customerID: UUID?
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ziel bearbeiten")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Titel", text: $title)
                Toggle("Zieldatum", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Bis", selection: $dueDate, displayedComponents: .date)
                }
                TextField("Stundenziel", text: $hours, prompt: Text("z. B. 40"))
                Picker("Kunde", selection: $customerID) {
                    Text("Ohne Kunde").tag(UUID?.none)
                    ForEach(model.activeCustomers) { customer in
                        Text(customer.name).tag(UUID?.some(customer.id))
                    }
                }
                TextField("Notizen", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .tagwerkForm()
            HStack {
                Button("Löschen", role: .destructive) {
                    model.deleteLongGoal(goal.id)
                    dismiss()
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    var changed = goal
                    changed.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? goal.title : title.trimmingCharacters(in: .whitespaces)
                    changed.dueDate = hasDueDate ? LocalDate(dueDate) : nil
                    changed.targetMinutes = Double(hours.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? Int($0 * 60) : nil }
                    changed.customerID = customerID
                    changed.notes = notes
                    model.update(changed)
                    dismiss()
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            title = goal.title
            hasDueDate = goal.dueDate != nil
            dueDate = goal.dueDate?.startDate() ?? Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date()
            hours = goal.targetMinutes.map { minutes in
                minutes % 60 == 0 ? "\(minutes / 60)" : String(format: "%.1f", Double(minutes) / 60).replacingOccurrences(of: ".", with: ",")
            } ?? ""
            customerID = goal.customerID
            notes = goal.notes
        }
    }
}

/// Kleine Übersicht der aktiven Ziele (auf Start und im Rückblick).
struct GoalStrip: View {
    @Environment(AppModel.self) private var model
    var limit = 3

    var body: some View {
        let goals = Array(model.activeLongGoals.prefix(limit))
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "Ziele")
                    Spacer()
                    Button("Alle") { model.selection = .goals }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
                ForEach(goals) { goal in
                    let progress = model.progress(of: goal)
                    Button {
                        model.selection = .goals
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(goal.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(GoalText.amount(progress))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.tertiary)
                            }
                            ProgressLine(value: progress.fraction ?? 0)
                            Text(GoalText.summary(goal, progress: progress, customer: nil, compact: true))
                                .font(.caption)
                                .foregroundStyle(progress.isBehind ? Theme.warning : Theme.tertiary)
                                .lineLimit(1)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Texte für Fortschritt und Tempo eines Ziels.
enum GoalText {
    /// „bis 15. Jan. · noch 8 Wochen · Becker & Partner“
    static func summary(_ goal: LongGoal, progress: GoalProgress, customer: String?, compact: Bool = false) -> String {
        var parts: [String] = []
        if goal.isDone {
            parts.append(goal.completedAt.map { "erreicht am \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "erreicht")
        } else if let due = goal.dueDate, let days = progress.daysLeft {
            if !compact { parts.append("bis \(due.startDate().formatted(date: .abbreviated, time: .omitted))") }
            parts.append(remaining(days))
        } else if !compact {
            parts.append("ohne Zieldatum")
        }
        if progress.isBehind { parts.append("hinter dem Plan") }
        if let customer { parts.append(customer) }
        if compact, !goal.isDone, progress.trackedThisWeek > 0 {
            parts.append("\(TimeMath.format(progress.trackedThisWeek)) h diese Woche")
        }
        return parts.joined(separator: " · ")
    }

    /// „12:30 von 40 h“ oder „3 von 5 Aufgaben“
    static func amount(_ progress: GoalProgress) -> String {
        if let target = progress.targetMinutes {
            return "\(TimeMath.format(progress.trackedSeconds)) von \(TimeMath.format(minutes: target)) h"
        }
        let total = progress.openTasks + progress.doneTasks
        if total > 0 {
            return "\(progress.doneTasks) von \(total) Aufgaben · \(TimeMath.format(progress.trackedSeconds)) h"
        }
        return "\(TimeMath.format(progress.trackedSeconds)) h erfasst"
    }

    /// „≈ 3:30 h pro Woche nötig · diese Woche 1:15 h“
    static func pace(_ progress: GoalProgress) -> String? {
        var parts: [String] = []
        if let perWeek = progress.minutesPerWeekNeeded, perWeek > 0 {
            parts.append("≈ \(TimeMath.format(minutes: perWeek)) h pro Woche nötig")
        }
        if progress.trackedThisWeek > 0 {
            parts.append("diese Woche \(TimeMath.format(progress.trackedThisWeek)) h")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func remaining(_ days: Int) -> String {
        switch days {
        case ..<0: return "\(-days) \(-days == 1 ? "Tag" : "Tage") überfällig"
        case 0: return "heute fällig"
        case 1: return "noch 1 Tag"
        case 2..<21: return "noch \(days) Tage"
        default: return "noch \(days / 7) Wochen"
        }
    }
}
