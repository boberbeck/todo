import SwiftUI
import TagwerkCore

/// Woche planen: links der Eingang, daneben eine Spalte je Tag. Aufgaben zieht man zwischen den Spalten hin und her.
struct WeekPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var weekStart: LocalDate?
    /// Breite des Eingangs, mit der Maus an seinem rechten Rand verstellbar
    @AppStorage(Preferences.planInboxWidthKey) private var inboxWidth = Preferences.defaultPlanInboxWidth

    var body: some View {
        let monday = weekStart ?? model.currentWeekStart
        let days = (0..<7).map { monday.adding(days: $0) }
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Woche planen", subtitle: weekSummary(days)) {
                HStack(spacing: 16) {
                    Text(monday.startDate().formatted(.dateTime.month(.wide).year()))
                        .foregroundStyle(Theme.secondary)
                    WeekSwitcher(weekStart: Binding(get: { monday }, set: { weekStart = $0 }), currentWeek: model.currentWeekStart)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 24)

            HStack(alignment: .top, spacing: 4) {
                InboxColumn()
                    .frame(width: CGFloat(inboxWidth))

                ResizeHandle(
                    width: $inboxWidth,
                    range: Preferences.planInboxWidthRange,
                    defaultValue: Preferences.defaultPlanInboxWidth,
                    showsLine: false,
                    resizesLeftColumn: true
                )

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(days, id: \.self) { day in
                                DayPlanColumn(day: day)
                                    .frame(width: 260)
                                    .id(day)
                            }
                        }
                        .padding(.trailing, 32)
                    }
                    .onAppear {
                        if days.contains(model.today) {
                            proxy.scrollTo(model.today.adding(days: -1) < monday ? model.today : model.today.adding(days: -1), anchor: .leading)
                        }
                    }
                }
            }
            .padding(.leading, 32)
            .padding(.bottom, 24)
        }
    }

    private func weekSummary(_ days: [LocalDate]) -> String {
        let open = days.reduce(0) { $0 + model.dayTasks($1).filter { !$0.isDone }.count }
        let planned = days.reduce(0) { $0 + DayPlan.plannedMinutes(model.dayTasks($1).filter { !$0.isDone }) }
        return "\(open) offene Aufgaben · \(TimeMath.format(minutes: planned)) h geschätzt · Eingang: \(model.inboxTasks.count)"
    }
}

/// Spalte eines Tages in der Wochenplanung.
struct DayPlanColumn: View {
    @Environment(AppModel.self) private var model
    let day: LocalDate
    @State private var isDropTarget = false

    var body: some View {
        let isToday = day == model.today
        let isPast = day < model.today
        let tasks = model.dayTasks(day)
        let open = tasks.filter { !$0.isDone }
        let done = tasks.filter(\.isDone)
        let planned = DayPlan.plannedMinutes(open)

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day.startDate().formatted(.dateTime.weekday(.abbreviated)))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isPast ? Theme.secondary : Theme.text)
                    Text("\(day.day)")
                        .font(.title3)
                        .foregroundStyle(isToday ? Theme.accent : Theme.secondary)
                    Spacer()
                    Text(capacity(planned: planned))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isOverplanned(planned) ? Theme.warning : Theme.tertiary)
                }
                Rectangle()
                    .fill(isToday ? Theme.accent : Theme.borderStrong)
                    .frame(height: isToday ? 2 : 1)
            }

            if !isPast {
                AddTaskField(day: day, compact: true)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(open) { task in
                        TaskCard(task: task, compact: true, dropDay: day)
                    }
                    ForEach(done) { task in
                        TaskCard(task: task, compact: true, dropDay: day)
                    }
                    if tasks.isEmpty, !isPast {
                        Text("Aufgaben hierher ziehen")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isDropTarget ? Theme.accentSoft : (isToday ? Theme.todayTint.opacity(0.5) : Color.white.opacity(0.015)))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isDropTarget ? Theme.accent.opacity(0.6) : Theme.border))
        .opacity(isPast ? 0.7 : 1)
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap { UUID(uuidString: $0) }
            for id in ids { model.move(id, to: day, before: nil) }
            return !ids.isEmpty
        } isTargeted: { isDropTarget = $0 }
    }

    private var isWorkday: Bool {
        !Calendar.current.isDateInWeekend(day.startDate())
    }

    private func capacity(planned: Int) -> String {
        guard isWorkday, day >= model.today else {
            return planned > 0 ? "\(TimeMath.format(minutes: planned)) h" : ""
        }
        return "\(TimeMath.format(minutes: planned)) / \(TimeMath.format(minutes: model.freeMinutes(on: day))) h"
    }

    private func isOverplanned(_ planned: Int) -> Bool {
        isWorkday && day >= model.today && planned > model.freeMinutes(on: day)
    }
}

/// Eingang als erste Spalte der Wochenplanung.
struct InboxColumn: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Eingang")
                        .font(.title3.weight(.medium))
                    Text("\(model.inboxTasks.count)")
                        .font(.title3)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    if model.canUseManageEngine {
                        Button {
                            Task { await model.importTickets() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.secondary)
                        .disabled(model.isSyncingTickets)
                        .help("Tickets aus ManageEngine abrufen")
                    }
                }
                Rectangle()
                    .fill(Theme.borderStrong)
                    .frame(height: 1)
            }

            AddTaskField(day: nil, compact: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.inboxTasks) { task in
                        TaskCard(task: task, compact: true, allowsDrop: false)
                    }
                    if model.inboxTasks.isEmpty {
                        Text("Leer. Mails aus Outlook hierher ziehen.")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(isDropTarget ? Theme.accentSoft : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isDropTarget ? Theme.accent.opacity(0.6) : Theme.border))
        // Aufgaben (zurück in den Eingang) und Mails, Links oder Text aus anderen Apps
        .onDrop(of: DropImporter.acceptedTypes, isTargeted: $isDropTarget) { providers in
            DropImporter.handle(providers, model: model)
        }
    }
}
