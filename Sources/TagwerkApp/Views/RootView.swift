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
        .background(AppBackground())
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
                .tagwerkSheet()
        }
        .sheet(isPresented: $model.showsSAPSync, onDismiss: { model.sapSyncRows = nil }) {
            SAPSyncSheet(initialRows: model.sapSyncRows)
                .tagwerkSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.updater.showsPrompt },
            set: { if !$0 { model.updater.postpone() } }
        )) {
            UpdatePromptView()
                .tagwerkSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.showsBugReport },
            set: { if !$0 { model.showsBugReport = false; model.pendingCrash = nil } }
        )) {
            BugReportView()
                .tagwerkSheet()
        }
        .overlay {
            // Aufgabenfenster über dem Hauptfenster; ein Klick daneben schließt es.
            if let id = model.detailTaskID {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.55)
                            .contentShape(Rectangle())
                            .onTapGesture { model.detailTaskID = nil }
                        TaskDetailView(taskID: id, height: max(420, min(780, geometry.size.height - 40)))
                            .id(id)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(Theme.surfaceFloating))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                            .surface(radius: Theme.Radius.panel, elevation: .floating, fill: Theme.surfaceFloating)
                            .tint(Theme.accent)
                            .buttonStyle(GhostButtonStyle())
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.detailTaskID)
        .sheet(item: $model.timeEntryDraft) { draft in
            AddTimeSheet(draft: draft)
                .tagwerkSheet()
        }
        .sheet(item: $model.editingEntry) { entry in
            EditEntrySheet(entry: entry)
                .tagwerkSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.ticketPickerTaskID != nil },
            set: { if !$0 { model.ticketPickerTaskID = nil } }
        )) {
            if let id = model.ticketPickerTaskID {
                TicketPicker(taskID: id) { model.ticketPickerTaskID = nil }
                    .tagwerkSheet()
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
        .tint(Theme.accent)
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
                    TopBarTabLabel(title: tab.title, selected: selected)
                }
                .buttonStyle(.plain)
                .help("\(tab.title) (⌘\(tab.shortcut))")
            }
            Spacer(minLength: 16)
            UpdatePill()
            RunningTimerPill()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle(size: 32))
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

/// Reiter oben: gewählt als helle Fläche, sonst nur Text.
struct TopBarTabLabel: View {
    let title: String
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Theme.text : (hovering ? Theme.text.opacity(0.85) : Theme.secondary))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.08 : 0.04))
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
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
                        .font(.system(.callout, design: .rounded).weight(.semibold))
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
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35)))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Du warst \(prompt.minutes) Minuten weg")
                        .font(Theme.title)
                    Text("\(prompt.start.formatted(date: .omitted, time: .shortened))–\(prompt.end.formatted(date: .omitted, time: .shortened)) ohne Eingabe")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                }
            }
            Text("Der Timer für „\(task?.title ?? "die Aufgabe")“ lief weiter. Soll die Zeit zählen?")
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Zeit behalten") { model.resolveIdle(.keep) }
                Menu("Einer anderen Aufgabe geben") {
                    ForEach(others) { other in
                        Button(other.title) { model.resolveIdle(.assign(to: other.id)) }
                    }
                }
                .fixedSize()
                .disabled(others.isEmpty)
                Spacer()
                Button("Pause abziehen") { model.resolveIdle(.discard) }
                    .buttonStyle(GhostButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 540)
    }
}

/// Hinweis oben, wenn eine neue Fassung bereitliegt.
struct UpdatePill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updater = model.updater
        if updater.available != nil || updater.isInstalling {
            Button {
                updater.showsPrompt = true
            } label: {
                HStack(spacing: 6) {
                    if updater.isInstalling {
                        ProgressView().controlSize(.small)
                        Text("Aktualisiert …")
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Update")
                    }
                }
                .font(.callout)
                .foregroundStyle(Theme.done)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.done.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(updater.isInstalling)
            .padding(.trailing, 8)
            .help(updater.status ?? "Neue Fassung verfügbar")
        }
    }
}

/// Nachfrage: neue Fassung, was neu ist, jetzt aktualisieren.
struct UpdatePromptView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updater = model.updater
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.done)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Neue Fassung von Tagwerk")
                        .font(.title2.weight(.semibold))
                    if let release = updater.available?.release {
                        Text("Stand \(release.shortCommit)\(release.publishedAt.map { " vom \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "") · jetzt \(updater.currentBuild ?? "?")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let changes = updater.available?.changes, !changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Was ist neu")
                        .font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(changes.prefix(15).enumerated()), id: \.offset) { _, change in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•")
                                    Text(change)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
            Text("Tagwerk lädt die neue Fassung, ersetzt sich in „Programme“ und startet neu. Deine Daten bleiben, ein laufender Timer läuft weiter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let status = updater.status, updater.isInstalling || status.contains("fehlgeschlagen") || status.contains("nicht") {
                HStack(spacing: 8) {
                    if updater.isInstalling { ProgressView().controlSize(.small) }
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(status.contains("fehlgeschlagen") ? Theme.danger : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Später") { updater.postpone() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(updater.isInstalling)
                Button("Jetzt aktualisieren") {
                    Task { await updater.install() }
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(updater.isInstalling || updater.available == nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
