import AppKit
import SwiftUI
import TagwerkCore

/// Feste Farbpalette für Kunden. In der Datenbank steht nur der Index.
enum CustomerPalette {
    static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
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

/// "Ticket #1234 · Kunde A · Störung"
struct TaskMetaLine: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    /// Arbeitsart und PSP-Element mit anzeigen (im Fokus stehen sie als eigene Felder daneben).
    var showsBooking = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: task.source.systemImage)
            Text(sourceText)
            if let customer = model.customer(task.customerID) {
                Text("·")
                CustomerDot(colorIndex: customer.colorIndex, size: 6)
                Text(customer.name)
            }
            if showsBooking, let workType = task.workType {
                Text("·")
                Text(workType.label)
            }
            if showsBooking, let psp = model.pspLabel(for: task) {
                Text("·")
                Text("SAP \(psp)")
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

struct WorkTypeMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Menu {
            ForEach(WorkType.allCases) { workType in
                Button(workType.label) { model.setWorkType(workType, for: task.id) }
            }
            Divider()
            Button("Keine Arbeitsart") { model.setWorkType(nil, for: task.id) }
        } label: {
            Text(task.workType?.label ?? "Arbeitsart wählen")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }
}

/// Rechtsklick-Menü für eine Aufgabe, überall gleich.
struct TaskContextMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button("Im Fokus öffnen") { model.openFocus(task.id) }
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
        if task.plannedDate != model.today, !task.isSubtask {
            Button("Für heute einplanen") { model.plan(task.id, for: model.today) }
        }
        if !task.isDone {
            if task.scheduledStart == nil {
                Button("In die nächste freie Lücke legen") { model.scheduleInNextGap(task.id) }
            } else {
                Button("Zeitblock entfernen") { model.schedule(task.id, at: nil) }
            }
        }
        if !task.isSubtask {
            Button("Auf morgen verschieben") { model.plan(task.id, for: model.today.adding(days: 1)) }
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
        Menu("Arbeitsart") {
            ForEach(WorkType.allCases) { workType in
                Button(workType.label) { model.setWorkType(workType, for: task.id) }
            }
            Divider()
            Button("Keine") { model.setWorkType(nil, for: task.id) }
        }
        Menu("SAP-Aufgabe") {
            ForEach(model.activeCustomers) { customer in
                let psps = model.psps(for: customer.id)
                if !psps.isEmpty {
                    Menu(customer.name) {
                        ForEach(psps) { psp in
                            Button(psp.label) { model.setSAPTask(psp, for: task.id) }
                        }
                    }
                }
            }
            if task.pspElement != nil {
                Divider()
                Button("Keine SAP-Aufgabe") { model.setPSPElement("", for: task.id) }
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
        HStack(spacing: 5) {
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

/// PSP-Element wählen: zuletzt genutzte Elemente des Kunden zuerst, sonst frei eingeben.
struct PSPMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var showsPicker = false

    var body: some View {
        Button {
            showsPicker = true
        } label: {
            Text(label)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            SAPTaskPicker(selectedCode: task.pspElement, selectedActivity: task.sapActivity) { psp, customCode in
                if let psp {
                    model.setSAPTask(psp, for: task.id)
                } else {
                    model.setPSPElement(customCode ?? "", for: task.id)
                }
                showsPicker = false
            }
        }
        .help("SAP-Aufgabe (PSP-Element), gilt für alle Zeiten dieser Aufgabe")
    }

    private var label: String {
        guard let label = model.pspLabel(for: task) else { return "SAP-Aufgabe wählen" }
        return task.pspElement == nil ? "\(label) (geerbt)" : label
    }
}

/// Suche über alle SAP-Aufgaben (PSP-Elemente) aller Kunden, nach Nummer, Name, Tätigkeit oder Kunde.
/// Wählt man eine, übernimmt die Aufgabe auch deren Kunden; für Internes reicht so „Team Sitzung“.
struct SAPTaskPicker: View {
    @Environment(AppModel.self) private var model
    let selectedCode: String?
    var selectedActivity: String? = nil
    /// (gewähltes PSP-Element, sonst eine von Hand eingetippte Nummer; beides nil = keine SAP-Aufgabe)
    let onSelect: (PSPElement?, String?) -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let found = results
        VStack(alignment: .leading, spacing: 8) {
            TextField("Suchen: Nummer, Name, Tätigkeit oder Kunde", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    if let first = found.first {
                        onSelect(first, nil)
                    } else if SAPImport.looksLikeTaskID(query.trimmingCharacters(in: .whitespaces)) {
                        onSelect(nil, query.trimmingCharacters(in: .whitespaces))
                    }
                }
            if model.pspElements.isEmpty {
                Text("Noch keine SAP-Aufgaben. Hol sie unter Kunden › SAP-Abgleich.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(found) { psp in
                        Button {
                            onSelect(psp, nil)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(psp.title.isEmpty ? psp.code : psp.title)
                                            .lineLimit(1)
                                        if let activity = psp.activity, !activity.isEmpty, activity != psp.title {
                                            Text(activity)
                                                .font(.caption.weight(.medium))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Theme.accent.opacity(0.18)))
                                                .lineLimit(1)
                                        }
                                    }
                                    Text(detail(for: psp))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if psp.matches(code: selectedCode, activity: selectedActivity) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    let typed = query.trimmingCharacters(in: .whitespaces)
                    if found.isEmpty, SAPImport.looksLikeTaskID(typed) {
                        Button("„\(typed)“ übernehmen") { onSelect(nil, typed) }
                            .padding(8)
                    }
                }
            }
            .frame(height: 280)
            if selectedCode != nil {
                Divider()
                Button("Keine SAP-Aufgabe") { onSelect(nil, nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 440)
        .onAppear { focused = true }
    }

    private func detail(for psp: PSPElement) -> String {
        var parts = [psp.code]
        if let activity = psp.activity, !activity.isEmpty, activity != psp.title { parts.append(activity) }
        if let customer = model.customer(psp.customerID) { parts.append(customer.name) }
        return parts.joined(separator: " · ")
    }

    private var results: [PSPElement] {
        let words = query.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split(separator: " ")
            .map(String.init)
        return model.pspElements
            .filter(\.isActive)
            .filter { psp in
                guard !words.isEmpty else { return true }
                let haystack = [psp.code, psp.title, psp.activity ?? "", model.customer(psp.customerID)?.name ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: nil)
                return words.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                let left = lhs.lastUsedAt ?? .distantPast
                let right = rhs.lastUsedAt ?? .distantPast
                if left != right { return left > right }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }
}

/// Senkrechte Trennlinie, die man mit der Maus ziehen kann. Sie verändert die Breite der Spalte rechts von ihr.
/// Doppelklick setzt die Breite zurück.
struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    /// Sichtbare Linie; ohne Linie bleibt nur der Bereich zum Ziehen.
    var showsLine = true
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
                                width = min(range.upperBound, max(range.lowerBound, start - Double(value.translation.width)))
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
