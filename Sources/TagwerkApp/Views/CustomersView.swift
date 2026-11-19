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
    @State private var showDone = false

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
            .padding(20)

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

            Divider()
            NewTaskBar(plannedDate: nil, fixedCustomerID: customer.id)
        }
        .navigationTitle(customer.name)
        .onAppear {
            name = customer.name
        }
        .onDisappear(perform: saveName)
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
