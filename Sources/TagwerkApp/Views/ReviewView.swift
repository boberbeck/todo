import AppKit
import Charts
import SwiftUI
import TagwerkCore

/// Wochenrückblick: Stunden, Tagesdurchschnitt, Anteil Kundenarbeit, Verlauf, Wochenziele.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var weekStart: LocalDate?
    @State private var newGoal = ""
    @State private var newGoalCustomer: UUID?
    @State private var nextWeekGoal = ""
    @State private var nextWeekCustomer: UUID?
    @State private var exportMessage: String?

    var body: some View {
        let monday = weekStart ?? model.currentWeekStart
        let nextMonday = monday.adding(days: 7)
        let days = WeeklyReview.days(ofWeekContaining: monday)
        let byCustomer = model.trackedByCustomer(from: monday, through: monday.adding(days: 6))
        let total = byCustomer.reduce(0) { $0 + $1.seconds }
        let customerTime = byCustomer.filter { $0.customerID != nil }.reduce(0) { $0 + $1.seconds }
        let workedDays = days.filter { model.tracked(on: $0) > 0 }.count
        let goal = Double(max(model.weeklyGoalMinutes, 1) * 60)
        let goals = model.goals(forWeekStarting: monday)
        let nextGoals = model.goals(forWeekStarting: nextMonday)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Wochenrückblick", subtitle: "Wie viel Zeit deine Woche wohin gegangen ist.") {
                    HStack(spacing: 12) {
                        WeekSwitcher(weekStart: Binding(get: { monday }, set: { weekStart = $0 }), currentWeek: model.currentWeekStart)
                        Button {
                            if let file = model.exportAllTimes() {
                                NSWorkspace.shared.activateFileViewerSelecting([file])
                                exportMessage = "Exportiert: \(file.lastPathComponent)"
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(GhostButtonStyle())
                        .help("Alle erfassten Zeiten als CSV für Excel exportieren")
                    }
                }
                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }

                HStack(alignment: .top, spacing: 16) {
                    StatCard(
                        title: "Stunden",
                        value: "\(TimeMath.format(total)) / \(TimeMath.format(minutes: model.weeklyGoalMinutes)) h",
                        detail: "\(Int((total / goal * 100).rounded())) % des Wochenziels",
                        accent: true
                    )
                    StatCard(
                        title: "Tagesdurchschnitt",
                        value: "\(TimeMath.format(workedDays > 0 ? total / Double(workedDays) : 0)) h",
                        detail: workedDays == 1 ? "an 1 Arbeitstag" : "an \(workedDays) Arbeitstagen"
                    )
                    StatCard(
                        title: "Kundenarbeit",
                        value: total > 0 ? "\(Int((customerTime / total * 100).rounded())) %" : "–",
                        detail: "\(TimeMath.format(customerTime)) h für Kunden, \(TimeMath.format(total - customerTime)) h Sonstiges"
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(text: "Stunden pro Tag")
                        if total == 0 {
                            emptyText("In dieser Woche ist noch keine Zeit erfasst.")
                        } else {
                            Chart(days, id: \.self) { day in
                                BarMark(
                                    x: .value("Tag", day.startDate().formatted(.dateTime.weekday(.abbreviated))),
                                    y: .value("Stunden", model.tracked(on: day) / 3600)
                                )
                                .foregroundStyle(day == model.today ? Theme.accent : Theme.accent.opacity(0.55))
                                .cornerRadius(4)
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine().foregroundStyle(Theme.border)
                                    AxisValueLabel {
                                        if let hours = value.as(Double.self) {
                                            Text("\(Int(hours)) h")
                                        }
                                    }
                                }
                            }
                            .frame(height: 220)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 22)

                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(text: "Stunden nach Kunde")
                        if byCustomer.isEmpty {
                            emptyText("Noch keine Zeit erfasst.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(byCustomer, id: \.customerID) { row in
                                    CustomerShareRow(customer: model.customer(row.customerID), seconds: row.seconds, total: total)
                                }
                            }
                        }
                        Rectangle().fill(Theme.border).frame(height: 1)
                        SectionLabel(text: "Kundenarbeit und Sonstiges")
                        GeometryReader { geometry in
                            HStack(spacing: 2) {
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(width: total > 0 ? geometry.size.width * customerTime / total : 0)
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .frame(height: 12)
                        HStack(spacing: 16) {
                            legend(color: Theme.accent, text: "Kunden · \(TimeMath.format(customerTime)) h")
                            legend(color: Color.white.opacity(0.25), text: "Sonstiges · \(TimeMath.format(total - customerTime)) h")
                        }
                    }
                    .frame(width: 360, alignment: .leading)
                    .card(padding: 22)
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: "Stunden · letzte Wochen")
                    let weeks = (0..<8).reversed().map { monday.adding(days: -7 * $0) }
                    Chart(weeks, id: \.self) { week in
                        BarMark(
                            x: .value("Woche", WeekSwitcher.label(for: week)),
                            y: .value("Stunden", model.trackedInWeek(starting: week) / 3600)
                        )
                        .foregroundStyle(week == monday ? Theme.accent : Color.white.opacity(0.22))
                        .cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Theme.border)
                            AxisValueLabel {
                                if let hours = value.as(Double.self) {
                                    Text("\(Int(hours)) h")
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .card(padding: 22)

                if !model.activeLongGoals.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Lange Ziele", detail: "Stand heute")
                        ForEach(model.activeLongGoals) { goal in
                            let progress = model.progress(of: goal)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(goal.title)
                                    Spacer()
                                    Text(GoalText.amount(progress))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(Theme.secondary)
                                }
                                ProgressLine(value: progress.fraction ?? 0, height: 6)
                                Text([GoalText.summary(goal, progress: progress, customer: model.customer(goal.customerID)?.name), GoalText.pace(progress)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(progress.isBehind ? Theme.accent : Theme.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 22)
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Wochenziele", detail: "\(goals.filter(\.isDone).count) von \(goals.count) erreicht")
                        if goals.isEmpty {
                            emptyText("Noch keine Ziele für diese Woche. Aufgaben verknüpfst du per Rechtsklick › Wochenziel.")
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
                    .card(padding: 22)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Ziele für nächste Woche")
                        ForEach(nextGoals) { goal in
                            GoalRow(goal: goal)
                        }
                        GoalEntry(title: $nextWeekGoal, customerID: $nextWeekCustomer, prompt: "Was soll nächste Woche klappen?") {
                            model.addGoal(title: nextWeekGoal, customerID: nextWeekCustomer, weekStart: nextMonday)
                            nextWeekGoal = ""
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 22)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.tertiary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondary)
        }
    }
}

/// Anteil eines Kunden an der Woche als Balken.
struct CustomerShareRow: View {
    let customer: Customer?
    let seconds: TimeInterval
    let total: TimeInterval

    var body: some View {
        let color = customer.map { CustomerPalette.color($0.colorIndex) } ?? Color.white.opacity(0.3)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(customer?.name ?? "Ohne Kunde")
                    .lineLimit(1)
                Spacer()
                Text("\(TimeMath.format(seconds)) h")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            .font(.callout)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(color)
                        .frame(width: total > 0 ? geometry.size.width * seconds / total : 0)
                }
            }
            .frame(height: 5)
        }
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
