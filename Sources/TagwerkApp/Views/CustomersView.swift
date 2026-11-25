import SwiftUI
import TagwerkCore

/// Kunden: Kennzahlen oben, darunter eine Karte je Kunde mit Stunden dieser Woche.
struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var showsArchived = false
    @State private var showsNewCustomer = false
    @State private var newName = ""

    var body: some View {
        let active = model.activeCustomers
        let archived = model.customers.filter(\.isArchived)
        let shown = showsArchived ? archived : active
        let monthTotal = active.reduce(0) { $0 + model.trackedThisMonth(customerID: $1.id) }
        let openCount = active.reduce(0) { $0 + model.openTaskCount(for: $1.id) }

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: "Kunden",
                    subtitle: "\(TimeMath.format(monthTotal)) h diesen Monat · \(openCount) offene Aufgaben"
                ) {
                    HStack(spacing: 10) {
                        Button {
                            showsNewCustomer = true
                        } label: {
                            Label("Neuer Kunde", systemImage: "plus")
                        }
                        .buttonStyle(GhostButtonStyle(prominent: true))
                        .popover(isPresented: $showsNewCustomer, arrowEdge: .bottom) {
                            newCustomerForm
                        }
                    }
                }

                HStack {
                    Picker("Anzeigen", selection: $showsArchived) {
                        Text("Aktiv · \(active.count)").tag(false)
                        Text("Archiviert · \(archived.count)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    // Auswahl ist keine Hauptaktion: nicht in Orange
                    .tint(Theme.surfaceRaised)
                    Spacer()
                }

                if shown.isEmpty {
                    Text(showsArchived ? "Keine archivierten Kunden" : "Noch keine Kunden")
                        .foregroundStyle(Theme.tertiary)
                } else {
                    VStack(spacing: 0) {
                        CustomerListHeader()
                        ForEach(shown) { customer in
                            Rectangle().fill(Theme.border).frame(height: 1)
                            CustomerRow(customer: customer)
                        }
                    }
                    .surface()
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
    }

    private var newCustomerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Neuer Kunde")
                .font(.system(size: 14, weight: .medium))
            TextField("Name", text: $newName)
                .textFieldStyle(TagwerkFieldStyle())
                .frame(width: 260)
                .onSubmit(add)
            HStack {
                Spacer()
                Button("Anlegen", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    private func add() {
        if let customer = model.addCustomer(name: newName) {
            newName = ""
            showsNewCustomer = false
            model.selection = .customer(customer.id)
        }
    }
}

/// Kennzahl in einer Karte.
struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title)
            Text(value)
                .font(Theme.statNumber)
                .foregroundStyle(accent ? Theme.accent : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 24)
    }
}

/// Spaltenköpfe der Kundenliste.
struct CustomerListHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Kunde")
            Spacer(minLength: 16)
            CustomerColumn.header("Diese Woche", width: CustomerColumn.hours)
            CustomerColumn.header("Monat", width: CustomerColumn.hours)
            CustomerColumn.header("Offen", width: CustomerColumn.count)
            Color.clear.frame(width: 12)
        }
        .font(.caption)
        .foregroundStyle(Theme.tertiary)
        .padding(.horizontal, 16)
        .frame(height: 32)
    }
}

/// Spaltenbreiten der Kundenliste, damit Köpfe und Zahlen untereinander stehen.
enum CustomerColumn {
    static let hours: CGFloat = 88
    static let count: CGFloat = 56

    static func header(_ title: String, width: CGFloat) -> some View {
        Text(title).frame(width: width, alignment: .trailing)
    }
}

/// Ein Kunde als Zeile: Stunden dieser Woche und im Monat, offene Aufgaben.
struct CustomerRow: View {
    @Environment(AppModel.self) private var model
    let customer: Customer
    @State private var hovering = false

    var body: some View {
        let monday = model.currentWeekStart
        let week = model.trackedByCustomer(from: monday, through: monday.adding(days: 6))
            .first { $0.customerID == customer.id }?.seconds ?? 0
        Button {
            model.selection = .customer(customer.id)
        } label: {
            HStack(spacing: 12) {
                CustomerDot(colorIndex: customer.colorIndex, size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let account = customer.manageEngineAccount, !account.isEmpty, account != customer.name {
                        Text(account)
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 16)
                number("\(TimeMath.format(week)) h", width: CustomerColumn.hours, primary: true)
                number("\(TimeMath.format(model.trackedThisMonth(customerID: customer.id))) h", width: CustomerColumn.hours)
                number("\(model.openTaskCount(for: customer.id))", width: CustomerColumn.count)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .frame(width: 12)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Color.white.opacity(hovering ? 0.04 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func number(_ text: String, width: CGFloat, primary: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 14, design: .rounded).monospacedDigit())
            .foregroundStyle(primary ? Theme.text : Theme.secondary)
            .frame(width: width, alignment: .trailing)
    }
}

struct CustomerDetailView: View {
    @Environment(AppModel.self) private var model
    let customerID: UUID

    var body: some View {
        if let customer = model.customer(customerID) {
            CustomerDetailContent(customer: customer)
                .id(customer.id)
        } else {
            ContentUnavailableView("Kunde nicht gefunden", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

/// Ein Kunde mit seinen lokalen Todos. Diese Todos verlassen die App nie.
struct CustomerDetailContent: View {
    @Environment(AppModel.self) private var model
    let customer: Customer

    @State private var name = ""
    @State private var account = ""
    @State private var showDone = false

    var body: some View {
        let open = model.customerTasks(customer.id, done: false)
        let done = model.customerTasks(customer.id, done: true)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    model.selection = .customers
                } label: {
                    Label("Kunden", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            HStack(spacing: 12) {
                CustomerDot(colorIndex: customer.colorIndex, size: 14)
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.medium))
                    .onSubmit(saveName)
                Spacer()
                ColorChooser(selected: customer.colorIndex) { index in
                    var changed = customer
                    changed.colorIndex = index
                    model.update(changed)
                }
                Text("\(TimeMath.format(model.trackedThisMonth(customerID: customer.id))) h im Monat")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Kunden archivieren") {
                        var changed = customer
                        changed.isArchived = true
                        model.update(changed)
                        model.selection = .customers
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            HStack(spacing: 8) {
                Image(systemName: "ticket")
                    .foregroundStyle(.secondary)
                TextField("Konto in ManageEngine (ordnet Tickets diesem Kunden zu)", text: $account)
                    .textFieldStyle(TagwerkFieldStyle())
                    .frame(maxWidth: 420)
                    .onSubmit(saveAccount)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            List {
                Section("Offen (\(open.count))") {
                    if open.isEmpty {
                        Text("Keine offenen Todos.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(open) { task in
                        CustomerTaskRow(task: task)
                    }
                }
                Section {
                    DisclosureGroup("Erledigt (\(done.count))", isExpanded: $showDone) {
                        ForEach(Array(done.prefix(50))) { task in
                            CustomerTaskRow(task: task)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()
            NewTaskBar(plannedDate: nil, fixedCustomerID: customer.id)
        }
        .onAppear {
            name = customer.name
            account = customer.manageEngineAccount ?? ""
        }
        .onDisappear {
            saveName()
            saveAccount()
        }
    }

    private func saveAccount() {
        let trimmed = account.trimmingCharacters(in: .whitespaces)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        guard value != customer.manageEngineAccount else { return }
        var changed = customer
        changed.manageEngineAccount = value
        model.update(changed)
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != customer.name else { return }
        var changed = customer
        changed.name = trimmed
        model.update(changed)
    }
}

struct CustomerTaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Button {
                    model.toggleDone(task.id)
                } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isDone ? Theme.done : Color.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .strikethrough(task.isDone, color: .secondary)
                    HStack(spacing: 8) {
                        Text(planText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SubtaskToggle(task: task)
                    }
                }

                Spacer()

                if !task.isDone && task.plannedDate != model.today {
                    Button("Heute") {
                        model.plan(task.id, for: model.today)
                    }
                    .buttonStyle(GhostButtonStyle(small: true))
                    .controlSize(.small)
                }

                Text(model.timeLabel(for: task, now: Date()))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contextMenu {
                TaskContextMenu(task: task)
            }
            ExpandedSubtasks(task: task)
        }
        .padding(.vertical, 2)
    }

    private var planText: String {
        if task.isDone, let completed = task.completedAt {
            return "erledigt am \(completed.formatted(date: .abbreviated, time: .omitted))"
        }
        guard let date = task.plannedDate else { return "nicht eingeplant" }
        if date == model.today { return "heute" }
        return "geplant für \(date.startDate().formatted(date: .abbreviated, time: .omitted))"
    }
}
