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
            if let directory = SnapshotMode.directory {
                await SnapshotMode.run(model: model, into: directory)
            }
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
