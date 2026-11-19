import AppKit
import SwiftUI
import TagwerkCore

/// Wochenrückblick: Wochenziele, Stunden je Tag und je Kunde, Ziele für die nächste Woche.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var newGoal = ""
    @State private var newGoalCustomer: UUID?
    @State private var nextWeekGoal = ""
    @State private var nextWeekCustomer: UUID?
    @State private var exportMessage: String?

    var body: some View {
        let monday = model.currentWeekStart
        let nextMonday = monday.adding(days: 7)
        let days = WeeklyReview.days(ofWeekContaining: monday)
        let byCustomer = model.trackedByCustomer(from: monday, through: monday.adding(days: 6))
        let weekTotal = byCustomer.reduce(0) { $0 + $1.seconds }
        let goals = model.goals(forWeekStarting: monday)
        let nextGoals = model.goals(forWeekStarting: nextMonday)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wochenrückblick")
                            .font(.title2.weight(.semibold))
                        Text("Woche ab \(monday.startDate().formatted(date: .abbreviated, time: .omitted)) · \(TimeMath.format(weekTotal)) h erfasst · \(goals.filter(\.isDone).count) von \(goals.count) Zielen erreicht")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if let file = model.exportAllTimes() {
                            NSWorkspace.shared.activateFileViewerSelecting([file])
                            exportMessage = "Exportiert: \(file.lastPathComponent)"
                        }
                    } label: {
                        Label("Zeiten exportieren", systemImage: "square.and.arrow.up")
                    }
                    .help("Alle erfassten Zeiten als CSV für Excel")
                }
                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Wochenziele") {
                    VStack(alignment: .leading, spacing: 8) {
                        if goals.isEmpty {
                            Text("Noch keine Ziele für diese Woche. Aufgaben verknüpfst du per Rechtsklick › Wochenziel.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(goals) { goal in
                            GoalRow(goal: goal)
                        }
                        GoalEntry(title: $newGoal, customerID: $newGoalCustomer, prompt: "Neues Ziel für diese Woche") {
                            model.addGoal(title: newGoal, customerID: newGoalCustomer, weekStart: monday)
                            newGoal = ""
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox("Nach Tag") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        ForEach(days, id: \.self) { day in
                            GridRow {
                                Text(day.startDate().formatted(.dateTime.weekday(.wide)))
                                    .fontWeight(day == model.today ? .semibold : .regular)
                                Text("\(TimeMath.format(model.tracked(on: day))) h")
                                    .monospacedDigit()
                                Text("\(model.doneCount(on: day)) erledigt")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox("Nach Kunde") {
                    if byCustomer.isEmpty {
                        Text("Diese Woche ist noch keine Zeit erfasst.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            ForEach(byCustomer, id: \.customerID) { row in
                                let customer = model.customer(row.customerID)
                                GridRow {
                                    HStack(spacing: 6) {
                                        CustomerDot(colorIndex: customer?.colorIndex ?? 0)
                                            .opacity(customer == nil ? 0 : 1)
                                        Text(customer?.name ?? "Ohne Kunde")
                                    }
                                    Text("\(TimeMath.format(row.seconds)) h")
                                        .monospacedDigit()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }

                GroupBox("Ziele für nächste Woche") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(nextGoals) { goal in
                            GoalRow(goal: goal)
                        }
                        GoalEntry(title: $nextWeekGoal, customerID: $nextWeekCustomer, prompt: "Was soll nächste Woche klappen?") {
                            model.addGoal(title: nextWeekGoal, customerID: nextWeekCustomer, weekStart: nextMonday)
                            nextWeekGoal = ""
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Rückblick")
    }
}

struct GoalRow: View {
    @Environment(AppModel.self) private var model
    let goal: WeeklyGoal

    var body: some View {
        let customer = model.customer(goal.customerID)
        HStack(spacing: 10) {
            Button {
                model.toggleGoal(goal.id)
            } label: {
                Image(systemName: goal.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(goal.isDone ? Color.green : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .strikethrough(goal.isDone, color: .secondary)
                if let customer {
                    HStack(spacing: 4) {
                        CustomerDot(colorIndex: customer.colorIndex, size: 6)
                        Text(customer.name)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(TimeMath.format(model.trackedSeconds(for: goal))) h")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Ziel löschen", role: .destructive) { model.deleteGoal(goal.id) }
        }
    }
}

struct GoalEntry: View {
    @Environment(AppModel.self) private var model
    @Binding var title: String
    @Binding var customerID: UUID?
    let prompt: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $title)
                .textFieldStyle(.plain)
                .onSubmit(onAdd)
            Picker("Kunde", selection: $customerID) {
                Text("Ohne Kunde").tag(UUID?.none)
                ForEach(model.activeCustomers) { customer in
                    Text(customer.name).tag(UUID?.some(customer.id))
                }
            }
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(.top, 4)
    }
}
