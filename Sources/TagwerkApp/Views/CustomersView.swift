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
        let pspCount = model.pspElements.filter(\.isActive).count

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: "Kunden",
                    subtitle: "\(TimeMath.format(monthTotal)) h diesen Monat · \(openCount) offene Aufgaben · \(pspCount) PSP-Elemente"
                ) {
                    HStack(spacing: 10) {
                        Button {
                            model.showsSAPSync = true
                        } label: {
                            Label("SAP-Abgleich", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(GhostButtonStyle())
                        .help("Projektaufgaben aus SAP ByDesign als PSP-Elemente übernehmen")
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
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(shown) { customer in
                        CustomerCard(customer: customer)
                    }
                    if !showsArchived {
                        Button {
                            showsNewCustomer = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                Text("Neuer Kunde")
                            }
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 190)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
    }

    private var newCustomerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Neuer Kunde")
                .font(.headline)
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
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
        .card(padding: 22)
    }
}

/// Ein Kunde als Karte: Stunden dieser Woche, Monat, offene Todos, PSP-Elemente.
struct CustomerCard: View {
    @Environment(AppModel.self) private var model
    let customer: Customer
    @State private var hovering = false

    var body: some View {
        let monday = model.currentWeekStart
        let week = model.trackedByCustomer(from: monday, through: monday.adding(days: 6))
            .first { $0.customerID == customer.id }?.seconds ?? 0
        let color = CustomerPalette.color(customer.colorIndex)
        Button {
            model.selection = .customer(customer.id)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(String(customer.name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(color)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.name)
                            .font(.title3)
                            .lineLimit(1)
                        if let account = customer.manageEngineAccount, !account.isEmpty {
                            Text(account)
                                .font(.caption)
                                .foregroundStyle(Theme.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TimeMath.format(week))
                            .font(Theme.statNumber)
                        SectionLabel(text: "Diese Woche")
                    }
                    Spacer()
                    Text("\(TimeMath.format(model.trackedThisMonth(customerID: customer.id))) h im Monat")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(spacing: 14) {
                    Label("\(model.openTaskCount(for: customer.id)) offen", systemImage: "circle")
                    Label("\(model.psps(for: customer.id).count) PSP", systemImage: "number")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(hovering ? Theme.surfaceRaised : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(color.opacity(0.7))
                    .frame(height: 2)
                    .padding(.horizontal, 22)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
    @State private var newPSPCode = ""
    @State private var newPSPTitle = ""

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
                SAPSyncButton()
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            HStack(spacing: 12) {
                CustomerDot(colorIndex: customer.colorIndex, size: 14)
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
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
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                    .onSubmit(saveAccount)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            List {
                Section("PSP-Elemente") {
                    let psps = model.psps(for: customer.id, includeInactive: true)
                    if psps.isEmpty {
                        Text("Noch keine PSP-Elemente. Leg die an, auf die du für diesen Kunden buchst.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(psps) { psp in
                        PSPRow(psp: psp)
                    }
                    HStack(spacing: 8) {
                        TextField("PSP-Element, z. B. Projektaufgabe-ID", text: $newPSPCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit(addPSP)
                        TextField("Bezeichnung (optional)", text: $newPSPTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addPSP)
                        Button("Hinzufügen", action: addPSP)
                            .disabled(newPSPCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
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

    private func addPSP() {
        if model.addPSP(customerID: customer.id, code: newPSPCode, title: newPSPTitle) != nil {
            newPSPCode = ""
            newPSPTitle = ""
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
                    .buttonStyle(.bordered)
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

struct PSPRow: View {
    @Environment(AppModel.self) private var model
    let psp: PSPElement

    var body: some View {
        HStack(spacing: 10) {
            Text(psp.code)
                .font(.body.monospaced())
                .foregroundStyle(psp.isActive ? Color.primary : Color.secondary)
            Text(psp.title)
                .foregroundStyle(.secondary)
            Spacer()
            if let used = psp.lastUsedAt {
                Text("zuletzt \(used.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !psp.isActive {
                Text("inaktiv")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("aktiv", isOn: Binding(
                get: { psp.isActive },
                set: { active in
                    var changed = psp
                    changed.isActive = active
                    model.update(changed)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Inaktive Elemente erscheinen nicht mehr in der Auswahl")
        }
        .contextMenu {
            Button("Löschen", role: .destructive) { model.deletePSP(psp.id) }
        }
    }
}

/// Öffnet den Abgleich mit SAP ByDesign.
struct SAPSyncButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showsSAPSync = true
        } label: {
            Label("SAP-Abgleich", systemImage: "arrow.triangle.2.circlepath")
        }
        .help("Projektaufgaben aus SAP ByDesign als PSP-Elemente übernehmen")
    }
}
