import SwiftUI
import TagwerkCore

/// Übersicht aller Kunden mit offenen Todos und Stunden im laufenden Monat.
struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TextField("Neuer Kunde", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit(add)
                Button("Anlegen", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)

            if model.activeCustomers.isEmpty {
                ContentUnavailableView(
                    "Noch keine Kunden",
                    systemImage: "person.2",
                    description: Text("Lege oben deinen ersten Kunden an. Seine Todos bleiben nur hier in der App.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.activeCustomers) { customer in
                    Button {
                        model.selection = .customer(customer.id)
                    } label: {
                        HStack(spacing: 10) {
                            CustomerDot(colorIndex: customer.colorIndex, size: 10)
                            Text(customer.name)
                            Spacer()
                            Text("\(model.openTaskCount(for: customer.id)) offen")
                                .foregroundStyle(.secondary)
                            Text("\(TimeMath.format(model.trackedThisMonth(customerID: customer.id))) h im Monat")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Kunden")
        .toolbar {
            ToolbarItem {
                SAPSyncButton()
            }
        }
    }

    private func add() {
        if model.addCustomer(name: newName) != nil {
            newName = ""
        }
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

            Divider()
            NewTaskBar(plannedDate: nil, fixedCustomerID: customer.id)
        }
        .navigationTitle(customer.name)
        .toolbar {
            ToolbarItem {
                SAPSyncButton()
            }
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
        HStack(spacing: 10) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone, color: .secondary)
                Text(planText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 2)
        .contextMenu {
            TaskContextMenu(task: task)
        }
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
