import AppKit
import SwiftUI
import TagwerkCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.selection != .focus {
                TopBar()
            }
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: model.sapAutoFetchRequest) {
            openWindow(id: "bydesign")
            // Im Hintergrund lassen, damit es nicht stört
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.windows.first { $0.title == "SAP ByDesign" }?.orderBack(nil)
            }
        }
        .onChange(of: model.selection) { old, new in
            if new == .focus, old != .focus { model.focusReturn = old }
        }
        .task {
            model.installQuickCapture()
            if let directory = SnapshotMode.directory {
                await SnapshotMode.run(model: model, into: directory, openSettings: { openSettings() }, openWindow: { openWindow(id: $0) })
            }
        }
        .sheet(item: $model.idlePrompt) { prompt in
            IdlePromptView(prompt: prompt)
        }
        .sheet(isPresented: $model.showsSAPSync, onDismiss: { model.sapSyncRows = nil }) {
            SAPSyncSheet(initialRows: model.sapSyncRows)
        }
        .sheet(item: $model.timeEntryDraft) { draft in
            AddTimeSheet(draft: draft)
        }
        .sheet(isPresented: Binding(
            get: { model.ticketPickerTaskID != nil },
            set: { if !$0 { model.ticketPickerTaskID = nil } }
        )) {
            if let id = model.ticketPickerTaskID {
                TicketPicker(taskID: id) { model.ticketPickerTaskID = nil }
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

    @ViewBuilder
    private var page: some View {
        switch model.selection ?? .today {
        case .today:
            StartView()
        case .week:
            WeekPlanView()
        case .calendar:
            WeekCalendarView()
        case .focus:
            FocusView()
        case .customers:
            CustomersView()
        case .customer(let id):
            CustomerDetailView(customerID: id)
        case .goals:
            GoalsView()
        case .review:
            ReviewView()
        case .planning:
            RitualPage(title: "Tag planen") { PlanningView() }
        case .close:
            RitualPage(title: "Tag abschließen") { DayCloseView() }
        }
    }
}

/// Leiste oben: Logo, Reiter, laufender Timer und Einstellungen.
struct TopBar: View {
    @Environment(AppModel.self) private var model

    struct Tab: Identifiable {
        let title: String
        let item: SidebarItem
        let shortcut: String
        var id: String { title }
    }

    private let tabs: [Tab] = [
        Tab(title: "Start", item: .today, shortcut: "1"),
        Tab(title: "Plan", item: .week, shortcut: "2"),
        Tab(title: "Kalender", item: .calendar, shortcut: "3"),
        Tab(title: "Fokus", item: .focus, shortcut: "4"),
        Tab(title: "Kunden", item: .customers, shortcut: "5"),
        Tab(title: "Ziele", item: .goals, shortcut: "6"),
        Tab(title: "Rückblick", item: .review, shortcut: "7"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            LogoMark()
                .frame(width: 26, height: 26)
                .padding(.trailing, 14)
                .help("Tagwerk")
            ForEach(tabs) { tab in
                let selected = isSelected(tab.item)
                Button {
                    model.selection = tab.item
                } label: {
                    Text(tab.title)
                        .font(.system(size: 14, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.white.opacity(0.08) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(tab.title) (⌘\(tab.shortcut))")
            }
            Spacer(minLength: 16)
            RunningTimerPill()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().strokeBorder(Theme.borderStrong))
            }
            .buttonStyle(.plain)
            .help("Einstellungen (⌘,)")
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Theme.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func isSelected(_ item: SidebarItem) -> Bool {
        switch (model.selection ?? .today, item) {
        case (.customer, .customers): return true
        case (.planning, .today), (.close, .today): return true
        default: return model.selection == item
        }
    }
}

/// Läuft ein Timer, steht er oben rechts; ein Klick öffnet den Fokus.
struct RunningTimerPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let task = model.runningTask {
            Button {
                model.openFocus(task.id)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                    Text(TimeMath.format(model.tracked(taskID: task.id, now: model.now), showSeconds: true))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(task.title)
                        .lineLimit(1)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: 200, alignment: .leading)
                    if let pomodoro = model.pomodoro, pomodoro.phase == .work {
                        Label(PomodoroText.clock(model.pomodoroRemaining), systemImage: "timer")
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .help("Pomodoro: so lange bis zur Pause")
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.accentSoft))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Läuft – im Fokus öffnen")
        } else if let pomodoro = model.pomodoro, pomodoro.phase.isBreak || pomodoro.phase == .ready {
            Button {
                model.selection = .focus
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: pomodoro.phase == .ready ? "play.circle.fill" : "cup.and.saucer.fill")
                    Text(pomodoro.phase == .ready ? "Pause vorbei – weiter" : "Pause \(PomodoroText.clock(model.pomodoroRemaining))")
                        .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(pomodoro.phase == .ready ? Theme.accent : Theme.done)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill((pomodoro.phase == .ready ? Theme.accent : Theme.done).opacity(0.14)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Pomodoro – im Fokus öffnen")
        }
    }
}

/// Rahmen für die Rituale „Tag planen“ und „Tag abschließen“: Zurück zum Start oben links.
struct RitualPage<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.selection = .today
                } label: {
                    Label("Start", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            content()
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
