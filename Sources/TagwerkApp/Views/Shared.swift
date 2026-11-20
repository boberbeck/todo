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
            if showsBooking, let psp = task.pspElement {
                Text("·")
                Text("PSP \(psp)")
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
        if task.source == .ticket, let number = task.externalID {
            return "Ticket #\(number)"
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
        if task.plannedDate != model.today {
            Button("Für heute einplanen") { model.plan(task.id, for: model.today) }
        }
        if !task.isDone {
            if task.scheduledStart == nil {
                Button("In die nächste freie Lücke legen") { model.scheduleInNextGap(task.id) }
            } else {
                Button("Zeitblock entfernen") { model.schedule(task.id, at: nil) }
            }
        }
        Button("Auf morgen verschieben") { model.plan(task.id, for: model.today.adding(days: 1)) }
        if task.plannedDate != nil {
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
        if task.source == .ticket {
            Menu("Work Log Type: \(model.worklogType(for: task))") {
                ForEach(Preferences.knownWorklogTypes, id: \.self) { type in
                    Button(type) { model.setWorklogType(type, for: task.id) }
                }
                Divider()
                Button("Standard (\(model.defaultWorklogType))") { model.setWorklogType(nil, for: task.id) }
            }
        }
        Menu("Wochenziel") {
            ForEach(model.goals(forWeekStarting: model.currentWeekStart)) { goal in
                Button(goal.title) { model.setGoal(goal.id, for: task.id) }
            }
            Divider()
            Button("Kein Wochenziel") { model.setGoal(nil, for: task.id) }
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

    @State private var showsCustomEntry = false
    @State private var customCode = ""

    var body: some View {
        let options = model.psps(for: task.customerID)
        Menu {
            ForEach(options) { psp in
                Button(psp.label) { model.setPSPElement(psp.code, for: task.id) }
            }
            if task.customerID == nil {
                // Ohne Kunde (z. B. ein erfasster Termin): PSP-Elemente aller Kunden, setzt den Kunden mit
                ForEach(model.activeCustomers) { customer in
                    let psps = model.psps(for: customer.id)
                    if !psps.isEmpty {
                        Menu(customer.name) {
                            ForEach(psps) { psp in
                                Button(psp.label) {
                                    model.setCustomer(customer.id, for: task.id)
                                    model.setPSPElement(psp.code, for: task.id)
                                }
                            }
                        }
                    }
                }
            }
            if !options.isEmpty || task.customerID == nil {
                Divider()
            }
            Button("Anderes PSP-Element …") {
                customCode = task.pspElement ?? ""
                showsCustomEntry = true
            }
            if task.pspElement != nil {
                Button("Kein PSP-Element") { model.setPSPElement("", for: task.id) }
            }
        } label: {
            Text(task.pspElement.map { "PSP \($0)" } ?? "PSP wählen")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .popover(isPresented: $showsCustomEntry) {
            HStack(spacing: 8) {
                TextField("PSP-Element", text: $customCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(saveCustom)
                Button("Übernehmen", action: saveCustom)
            }
            .padding(12)
        }
        .help("PSP-Element in SAP ByDesign, gilt für alle Zeiten dieser Aufgabe")
    }

    private func saveCustom() {
        model.setPSPElement(customCode, for: task.id)
        showsCustomEntry = false
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
