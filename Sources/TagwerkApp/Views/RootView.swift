import SwiftUI
import TagwerkCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section {
                    Label("Heute", systemImage: "sun.max").tag(SidebarItem.today)
                    Label("Fokus", systemImage: "scope").tag(SidebarItem.focus)
                    Label("Kunden", systemImage: "person.2").tag(SidebarItem.customers)
                    Label("Rückblick", systemImage: "chart.bar").tag(SidebarItem.review)
                }
                if !model.activeCustomers.isEmpty {
                    Section("Meine Kunden") {
                        ForEach(model.activeCustomers) { customer in
                            Label {
                                Text(customer.name)
                            } icon: {
                                CustomerDot(colorIndex: customer.colorIndex)
                            }
                            .tag(SidebarItem.customer(customer.id))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            switch model.selection ?? .today {
            case .today:
                TodayView()
            case .focus:
                FocusView()
            case .customers:
                CustomersView()
            case .review:
                ReviewView()
            case .planning:
                PlanningView()
            case .close:
                DayCloseView()
            case .customer(let id):
                CustomerDetailView(customerID: id)
            }
        }
        .task {
            model.installQuickCapture()
            if let directory = SnapshotMode.directory {
                await SnapshotMode.run(model: model, into: directory)
            }
        }
        .sheet(item: $model.idlePrompt) { prompt in
            IdlePromptView(prompt: prompt)
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

/// Nachfrage nach einer erkannten Pause während eines laufenden Timers.
struct IdlePromptView: View {
    @Environment(AppModel.self) private var model
    let prompt: IdlePrompt

    var body: some View {
        let task = model.task(prompt.taskID)
        let others = model.todayTasks.filter { $0.id != prompt.taskID && !$0.isDone }
        VStack(alignment: .leading, spacing: 14) {
            Label("Du warst \(prompt.minutes) Minuten weg", systemImage: "cup.and.saucer")
                .font(.title2.weight(.semibold))
            Text("Von \(prompt.start.formatted(date: .omitted, time: .shortened)) bis \(prompt.end.formatted(date: .omitted, time: .shortened)) gab es keine Eingabe, der Timer für „\(task?.title ?? "die Aufgabe")“ lief weiter.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Zeit behalten") { model.resolveIdle(.keep) }
                Menu("Anderer Aufgabe geben") {
                    ForEach(others) { other in
                        Button(other.title) { model.resolveIdle(.assign(to: other.id)) }
                    }
                }
                .fixedSize()
                .disabled(others.isEmpty)
                Spacer()
                Button("Pause abziehen") { model.resolveIdle(.discard) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
