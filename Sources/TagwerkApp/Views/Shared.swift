import AppKit
import SwiftUI
import TagwerkCore

/// Feste Farbpalette für Kunden. In der Datenbank steht nur der Index.
enum CustomerPalette {
    /// Gedämpft, damit sie in die Fläche passen; bewusst ohne Orange (das heißt in Tagwerk „jetzt“).
    static let colors: [Color] = [
        Color(red: 0.478, green: 0.584, blue: 0.784),  // Taubenblau
        Color(red: 0.788, green: 0.647, blue: 0.353),  // Ocker
        Color(red: 0.498, green: 0.686, blue: 0.541),  // Salbei
        Color(red: 0.604, green: 0.549, blue: 0.769),  // Lavendel
        Color(red: 0.773, green: 0.541, blue: 0.608),  // Rosé
        Color(red: 0.416, green: 0.686, blue: 0.690),  // Petrol
        Color(red: 0.725, green: 0.514, blue: 0.420),  // Ton
        Color(red: 0.616, green: 0.651, blue: 0.416),  // Oliv
    ]
    static var count: Int { colors.count }

    static func color(_ index: Int) -> Color {
        colors[((index % count) + count) % count]
    }
}

struct CustomerDot: View {
    let colorIndex: Int
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(CustomerPalette.color(colorIndex))
            .frame(width: size, height: size)
    }
}

/// "Ticket #1234 · Kunde A · Wochenziel"
struct TaskMetaLine: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    /// Wochenziel mit anzeigen.
    var showsBooking = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: task.source.systemImage)
            Text(sourceText)
            if let customer = model.customer(task.customerID) {
                Text("·")
                CustomerDot(colorIndex: customer.colorIndex, size: 6)
                Text(customer.name)
            }
            if showsBooking, let goal = model.goal(task.goalID) {
                Text("·")
                Image(systemName: "target")
                Text(goal.title)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var sourceText: String {
        if let number = model.ticketNumber(for: task) {
            return task.source == .ticket ? "Ticket #\(number)" : "\(task.source.label) · Ticket #\(number)"
        }
        return task.source.label
    }
}

/// Rechtsklick-Menü für eine Aufgabe, überall gleich.
struct TaskContextMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button("Öffnen …") { model.openDetail(task.id) }
        Button("Im Fokus öffnen") { model.openFocus(task.id) }
        if task.meetingID != nil || task.source == .calendar {
            Button("Meeting & Transkript …") { model.openMeeting(for: task) }
        }
        if !task.isDone {
            Button(task.isSubtask ? "Weitere Unteraufgabe" : "Unteraufgabe hinzufügen") { model.beginSubtaskEntry(for: task.id) }
        }
        Button("Zeit nachtragen …") { model.beginTimeEntry(for: task.id) }
        if !task.isDone {
            BackdatedStartMenu(task: task)
        }
        if task.isSubtask {
            Button("Wieder eigene Aufgabe") { model.promoteSubtask(task.id) }
        }
        let day = model.effectiveDay(of: task)
        let tomorrow = model.today.adding(days: 1)
        if day != model.today, !task.isStanding {
            Button(task.isSubtask ? "Einzeln für heute einplanen" : "Für heute einplanen") { model.plan(task.id, for: model.today) }
        }
        if !task.isDone {
            if task.scheduledStart == nil {
                Button("In die nächste freie Lücke legen") { model.scheduleInNextGap(task.id) }
            } else {
                Button("Zeitblock entfernen") { model.schedule(task.id, at: nil) }
            }
        }
        if !task.isStanding {
            if day != tomorrow {
                Button(task.isSubtask ? "Einzeln für morgen einplanen" : "Auf morgen verschieben") { model.plan(task.id, for: tomorrow) }
            }
            Menu(task.isSubtask ? "Einzeln einplanen am" : "Einplanen am") {
                ForEach(DayText.upcomingWorkdays(from: model.today), id: \.self) { option in
                    Button(DayText.long(option, today: model.today)) { model.plan(task.id, for: option) }
                        .disabled(option == day)
                }
            }
        }
        if task.isSubtask, task.plannedDate != nil {
            Button("Wieder mit der Aufgabe planen") { model.plan(task.id, for: nil) }
        }
        if task.plannedDate != nil, !task.isSubtask {
            Button("Zurück in den Eingang") { model.plan(task.id, for: nil) }
        }
        Divider()
        Menu("Kunde") {
            Button("Ohne Kunde") { model.setCustomer(nil, for: task.id) }
            ForEach(model.activeCustomers) { customer in
                Button(customer.name) { model.setCustomer(customer.id, for: task.id) }
            }
        }
        if task.source != .ticket {
            Menu(model.ticketNumber(for: task).map { "Ticket #\($0)" } ?? "Ticket zuordnen") {
                ForEach(model.ticketTasks.filter { !$0.isDone }.prefix(15)) { ticket in
                    Button("#\(ticket.linkedTicketNumber ?? "?") \(ticket.title)") { model.linkTicket(ticket, to: task.id) }
                }
                Divider()
                Button("Suchen oder Nummer eingeben …") { model.ticketPickerTaskID = task.id }
                if task.ticketNumber != nil || task.ticketKey != nil {
                    Button("Kein Ticket") { model.unlinkTicket(from: task.id) }
                }
            }
        }
        if model.resolved(task).hasTicket {
            Menu("Work Log Type: \(model.worklogType(for: task))") {
                ForEach(Preferences.knownWorklogTypes, id: \.self) { type in
                    Button(type) { model.setWorklogType(type, for: task.id) }
                }
                Divider()
                Button("Standard (\(model.defaultWorklogType))") { model.setWorklogType(nil, for: task.id) }
            }
        }
        if !task.isSubtask {
            Menu(model.longGoal(task.longGoalID).map { "Ziel: \($0.title)" } ?? "Ziel") {
                ForEach(model.activeLongGoals) { goal in
                    Button {
                        model.setLongGoal(goal.id, for: task.id)
                    } label: {
                        if goal.id == task.longGoalID {
                            Label(goal.title, systemImage: "checkmark")
                        } else {
                            Text(goal.title)
                        }
                    }
                }
                if model.activeLongGoals.isEmpty {
                    Button("Neues Ziel anlegen …") { model.selection = .goals }
                }
                if task.longGoalID != nil {
                    Divider()
                    Button("Kein Ziel") { model.setLongGoal(nil, for: task.id) }
                }
            }
            Menu("Wochenziel") {
                ForEach(model.goals(forWeekStarting: model.currentWeekStart)) { goal in
                    Button(goal.title) { model.setGoal(goal.id, for: task.id) }
                }
                Divider()
                Button("Kein Wochenziel") { model.setGoal(nil, for: task.id) }
            }
        }
        Menu("Schätzung") {
            ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                Button("\(TimeMath.format(minutes: minutes)) h") { model.setEstimate(minutes, for: task.id) }
            }
            Divider()
            Button("Keine") { model.setEstimate(nil, for: task.id) }
        }
        Divider()
        Button("Löschen", role: .destructive) { model.delete(task.id) }
    }
}

/// Eingabezeile für neue Aufgaben. Eine Zeitangabe am Ende wird zur Schätzung ("… 1h30").
struct NewTaskBar: View {
    @Environment(AppModel.self) private var model
    let plannedDate: LocalDate?
    var fixedCustomerID: UUID? = nil

    @State private var title = ""
    @State private var customerID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
            TextField("Neue Aufgabe, z. B. „Angebot schreiben 1h30“", text: $title)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(add)
            if fixedCustomerID == nil {
                Picker("Kunde", selection: $customerID) {
                    Text("Ohne Kunde").tag(UUID?.none)
                    ForEach(model.activeCustomers) { customer in
                        Text(customer.name).tag(UUID?.some(customer.id))
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onChange(of: model.newTaskRequest) {
            focused = true
        }
    }

    private func add() {
        if model.addTask(title: title, customerID: fixedCustomerID ?? customerID, plannedDate: plannedDate) != nil {
            title = ""
        }
    }
}

struct ColorChooser: View {
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<CustomerPalette.count, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(CustomerPalette.color(index))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: index == selected ? 2 : 0)
                                .padding(-2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Senkrechte Trennlinie, die man mit der Maus ziehen kann. Sie verändert die Breite der Spalte rechts von ihr
/// (oder links, mit `resizesLeftColumn`). Doppelklick setzt die Breite zurück.
struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    /// Sichtbare Linie; ohne Linie bleibt nur der Bereich zum Ziehen.
    var showsLine = true
    /// Die Spalte links wird breiter, wenn man nach rechts zieht (z. B. der Eingang im Wochenplan).
    var resizesLeftColumn = false
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(showsLine ? Color(nsColor: .separatorColor) : Color.clear)
            .frame(width: showsLine ? 1 : 12)
            .overlay {
                Capsule()
                    .fill(Theme.accent.opacity(startWidth != nil ? 0.7 : (hovering ? 0.35 : 0)))
                    .frame(width: 3)
                    .padding(.vertical, showsLine ? 0 : 40)
            }
            .overlay {
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != hovering else { return }
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? min(width, range.upperBound)
                                startWidth = start
                                let delta = Double(value.translation.width)
                                width = min(range.upperBound, max(range.lowerBound, resizesLeftColumn ? start + delta : start - delta))
                            }
                            .onEnded { _ in startWidth = nil }
                    )
                    .onTapGesture(count: 2) { width = defaultValue }
            }
            .help("Ziehen ändert die Breite, Doppelklick setzt sie zurück")
            .onDisappear {
                if hovering { NSCursor.pop() }
            }
    }
}

/// Work Log Type eines Tickets, mit den Namen aus ServiceDesk Plus.
struct WorklogTypeMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Menu {
            ForEach(Preferences.knownWorklogTypes, id: \.self) { type in
                Button {
                    model.setWorklogType(type, for: task.id)
                } label: {
                    if type == model.worklogType(for: task) {
                        Label(type, systemImage: "checkmark")
                    } else {
                        Text(type)
                    }
                }
            }
            if task.worklogType != nil {
                Divider()
                Button("Standard (\(model.defaultWorklogType))") { model.setWorklogType(nil, for: task.id) }
            }
        } label: {
            Text(model.worklogType(for: task))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help("Work Log Type in ManageEngine (Pflichtfeld beim Worklog)")
    }
}
