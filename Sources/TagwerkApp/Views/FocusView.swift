import AppKit
import SwiftUI
import TagwerkCore

/// Fokus: eine Aufgabe, sonst nichts. „Zurück“ (oder Esc) und Pomodoro stehen in der Titelleiste.
struct FocusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 8)

            Group {
                if let pomodoro = model.pomodoro, pomodoro.phase.isBreak || pomodoro.phase == .ready {
                    PomodoroBreakPane(state: pomodoro)
                } else if let task = model.focusTask {
                    FocusTaskPane(task: task)
                        .id(task.id)
                } else {
                    VStack(spacing: 16) {
                        Text("Keine Aufgabe für den Fokus")
                            .font(.system(size: 26, weight: .regular))
                        Text("Plane auf Start eine Aufgabe für heute ein, dann geht es hier los.")
                            .foregroundStyle(Theme.secondary)
                        Button("Zur Startseite") { model.selection = .today }
                            .buttonStyle(GhostButtonStyle())
                            .padding(.top, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 16) {
                FocusMusicBar()
                FocusTimeBar()
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .onAppear { model.music.startWatching() }
        .onDisappear { model.music.stopWatching() }
    }
}

struct FocusTaskPane: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var descriptionText = ""
    @State private var showsDetails = false
    @State private var showsSubtaskField = false

    var body: some View {
        let running = model.isRunning(task.id)
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                if let parent = model.parent(of: task) {
                    Button {
                        model.focusedTaskID = parent.id
                    } label: {
                        Label("Teil von „\(parent.title)“", systemImage: "arrow.turn.left.up")
                            .font(.callout)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiary)
                    .help("Zur übergeordneten Aufgabe")
                }
                if let customer = model.customer(task.customerID) {
                    HStack(spacing: 6) {
                        CustomerDot(colorIndex: customer.colorIndex, size: 7)
                        Text(customer.name)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.secondary)
                }
                Text(task.title)
                    .font(.system(size: 32, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 760)
                BookingSummary(task: task)
                    .padding(.top, 2)
                if let goal = model.longGoal(model.resolved(task).longGoalID) {
                    let progress = model.progress(of: goal)
                    Button {
                        model.selection = .goals
                    } label: {
                        Label("\(goal.title) · \(GoalText.amount(progress))", systemImage: "flag.checkered")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiary)
                    .help("Zahlt auf dieses Ziel ein")
                }
            }

            VStack(spacing: 4) {
                let tracked = model.trackedIncludingSubtasks(taskID: task.id, now: model.runningEntry != nil ? model.now : Date())
                if let pomodoro = model.pomodoro, pomodoro.phase == .work {
                    let settings = model.pomodoroSettings
                    Text(PomodoroText.clock(model.pomodoroRemaining))
                        .font(Theme.timerNumber)
                        .monospacedDigit()
                        .foregroundStyle(running ? Theme.text : Theme.secondary)
                    ProgressLine(value: Pomodoro.progress(pomodoro, settings: settings, now: model.now), height: 3, color: running ? Theme.accent : Theme.secondary)
                        .frame(width: 220)
                        .padding(.vertical, 4)
                    Text("Pomodoro \(pomodoro.round(settings: settings)) von \(settings.roundsUntilLongBreak) · \(TimeMath.format(tracked)) h erfasst\(task.estimateMinutes.map { " von \(TimeMath.format(minutes: $0)) h" } ?? "")")
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Text(TimeMath.format(tracked, showSeconds: true))
                        .font(Theme.timerNumber)
                        .monospacedDigit()
                        .foregroundStyle(running ? Theme.text : Theme.secondary)
                    if let estimate = task.estimateMinutes {
                        Text("von \(TimeMath.format(minutes: estimate)) h geplant")
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }

            HStack(spacing: 16) {
                Button {
                    model.complete(task.id)
                } label: {
                    Label("Erledigt", systemImage: "checkmark")
                }
                .buttonStyle(GhostButtonStyle())
                .help("Erledigt (⌘↩), danach kommt die nächste Aufgabe")

                Button {
                    model.toggleTimer(for: task.id)
                } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(IconButtonStyle(size: 72, prominent: true))

                .help(running ? "Pause (⌘T)" : "Start (⌘T)")

                Button {
                    model.focusNextTask()
                } label: {
                    Label("Nächste", systemImage: "forward.end")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(model.todayTasks.filter { !$0.isDone }.count < 2)
                .help("Andere Aufgabe von heute in den Fokus holen")
            }

            BackdatedStartMenu(task: task, asButton: true)

            if !task.isSubtask, !task.isDone, !model.subtasks(of: task.id).isEmpty || showsSubtaskField {
                VStack(alignment: .trailing, spacing: 6) {
                    SubtaskList(parent: task)
                        .frame(maxWidth: 560)
                        .card(padding: 10)
                    Button {
                        model.openDetail(task.id)
                    } label: {
                        Label("Aufgabe öffnen", systemImage: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiary)
                    .help("Alle Angaben, Unteraufgaben und Zeiten in einem Fenster")
                }
                .frame(maxWidth: 580)
            } else if !task.isSubtask, !task.isDone {
                Button {
                    showsSubtaskField = true
                    model.beginSubtaskEntry(for: task.id)
                } label: {
                    Label("Unteraufgaben", systemImage: "checklist")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tertiary)
                .help("In Schritte zerlegen; jeder Schritt kann eigene Zeit und ein eigenes Ticket haben")
            }

            VStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showsDetails.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(detailSummary)
                        Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.callout)
                    .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)

                if showsDetails {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayout(spacing: 8) {
                            WorkTypeMenu(task: task)
                            PSPMenu(task: task)
                            TicketMenu(task: task)
                            if model.resolved(task).hasTicket {
                                WorklogTypeMenu(task: task)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        TextEditor(text: $descriptionText)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 90)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderStrong))
                            .overlay(alignment: .topLeading) {
                                if descriptionText.isEmpty {
                                    Text("Was hast du gemacht? Wird zum Text für den Worklog.")
                                        .foregroundStyle(Theme.tertiary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .frame(maxWidth: 620)
                    .card(padding: 16)
                }
            }
        }
        .padding(.horizontal, 40)
        .onAppear {
            descriptionText = task.workDescription
            model.focusedTaskID = task.id
            showsDetails = model.resolved(task).hasTicket && task.workDescription.isEmpty
        }
        .onChange(of: descriptionText) {
            model.setDescription(descriptionText, for: task.id)
        }
    }

    /// „Wartung · CPSO8643-1 · Bearbeitung“
    private var detailSummary: String {
        var parts: [String] = []
        parts.append(task.workType?.label ?? "Arbeitsart wählen")
        parts.append(model.pspLabel(for: task) ?? "SAP-Aufgabe wählen")
        parts.append(task.workDescription.isEmpty ? "Bearbeitung notieren" : "Bearbeitung")
        return parts.joined(separator: " · ")
    }
}

/// Fokuszeit des Tages gegen das Tagesziel (Input statt Output).
struct FocusTimeBar: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.focusGoalMinutesKey) private var goalMinutes = Preferences.defaultFocusGoalMinutes

    var body: some View {
        let tracked = model.trackedToday(now: model.runningEntry == nil ? Date() : model.now)
        let goal = Double(max(goalMinutes, 1) * 60)
        VStack(spacing: 8) {
            ProgressLine(value: tracked / goal)
            HStack {
                Text("Fokuszeit heute")
                Spacer()
                Text("\(TimeMath.format(tracked)) von \(TimeMath.format(minutes: goalMinutes)) h · \(model.doneToday.count) erledigt")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Musik zum Fokus: Playlist aus der Musik-App, Internetradio oder YouTube. Start, Pause, nächster Titel.
/// Bei YouTube steht der Player sichtbar darüber (so verlangt es YouTube).
struct FocusMusicBar: View {
    @Environment(AppModel.self) private var model
    @State private var showsYouTubeEntry = false
    @State private var youtubeDraft = ""

    var body: some View {
        let music = model.music
        VStack(spacing: 12) {
            if music.source == .youtube, music.youtubeLink != nil, !music.isDemo {
                YouTubePlayerView(player: music.youtube)
                    .frame(width: 356, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.border))
            }
            bar(music)
        }
        .alert("YouTube-Link", isPresented: $showsYouTubeEntry) {
            TextField("https://www.youtube.com/watch?v=…", text: $youtubeDraft)
            Button("Übernehmen") {
                music.chooseYouTube(youtubeDraft)
                if music.youtubeLink != nil { music.startMusic() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Video, Playlist oder Livestream, so wie im Browser kopiert")
        }
    }

    private func bar(_ music: FocusMusic) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(music.source))
                .font(.system(size: 14))
                .foregroundStyle(music.state == .playing ? Theme.secondary : Theme.tertiary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.05)))

            VStack(alignment: .leading, spacing: 2) {
                if let title = music.trackTitle, music.state != .stopped {
                    Text(title)
                        .lineLimit(1)
                    Text([music.trackArtist, music.source == .appleMusic ? music.selectedPlaylist : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                } else if let name = music.selectionName {
                    Text(name)
                        .lineLimit(1)
                    Text(music.source == .youtube ? (music.youtubeLink?.summary ?? "") + " · startet mit dem Timer" : "Startet mit dem Timer")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Text("Musik zum Fokus")
                    Text("Playlist, Radiosender oder YouTube-Link wählen")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
                if let problem = music.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Section("Apple Music") {
                    if music.playlists.isEmpty {
                        Button(music.isLoadingPlaylists ? "Lädt …" : "Playlists laden") { music.loadPlaylists() }
                            .disabled(music.isLoadingPlaylists)
                    } else {
                        ForEach(music.playlists, id: \.self) { name in
                            Button {
                                music.choosePlaylist(name)
                            } label: {
                                if music.source == .appleMusic, name == music.selectedPlaylist {
                                    Label(name, systemImage: "checkmark")
                                } else {
                                    Text(name)
                                }
                            }
                        }
                        Button("Liste neu laden") { music.loadPlaylists() }
                    }
                }
                // Internetradio nach Richtung
                ForEach(RadioStation.genres, id: \.self) { genre in
                    Section("Radio · \(genre)") {
                        ForEach(RadioStation.stations(in: genre)) { station in
                            Button {
                                music.chooseStation(station)
                            } label: {
                                if music.source == .radio, station.id == music.radioStation?.id {
                                    Label("\(station.name) · \(station.detail)", systemImage: "checkmark")
                                } else {
                                    Text("\(station.name) · \(station.detail)")
                                }
                            }
                        }
                    }
                }
                if let custom = music.radioStation, !RadioStation.builtIn.contains(where: { $0.id == custom.id }) {
                    Section("Radio · eigene Adresse") {
                        Button {
                            music.chooseStation(custom)
                        } label: {
                            Label(custom.name, systemImage: music.source == .radio ? "checkmark" : "antenna.radiowaves.left.and.right")
                        }
                    }
                }
                Section("YouTube") {
                    Button(music.youtubeLink == nil ? "YouTube-Link einfügen …" : "Anderen YouTube-Link …") {
                        youtubeDraft = Self.clipboardYouTubeLink() ?? music.youtubeLinkText
                        showsYouTubeEntry = true
                    }
                    // Verlauf: zuletzt gespielte Links, ein Klick spielt sie wieder
                    ForEach(music.youtubeHistory.prefix(8)) { entry in
                        Button {
                            music.playFromHistory(entry)
                        } label: {
                            if music.isCurrent(entry) {
                                Label(entry.displayTitle, systemImage: "checkmark")
                            } else {
                                Text(entry.displayTitle)
                            }
                        }
                    }
                    if !music.youtubeHistory.isEmpty {
                        Button("Verlauf leeren") { music.clearHistory() }
                    }
                }
                if music.hasSelection {
                    Divider()
                    Button("Keine Musik") { music.clearSelection() }
                }
            } label: {
                Image(systemName: "music.note.list")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Theme.secondary)
            .tint(Theme.secondary)
            .help("Musik wählen: Apple Music, Internetradio oder YouTube")
            .onAppear {
                if music.playlists.isEmpty, music.isDemo { music.loadPlaylists() }
            }

            Button {
                music.togglePlayPause()
            } label: {
                Image(systemName: music.state == .playing ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .disabled(!music.hasSelection && music.state == .stopped)
            .help(music.state == .playing ? "Musik anhalten" : "Musik abspielen")

            if music.canSkip {
                Button {
                    music.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .disabled(music.state == .stopped)
                .help("Nächster Titel")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .surface(radius: Theme.Radius.card, elevation: .flat)
    }

    private func icon(_ source: MusicSource) -> String {
        switch source {
        case .appleMusic: return "music.note"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .youtube: return "play.rectangle"
        }
    }

    /// Liegt ein YouTube-Link in der Zwischenablage, gleich vorschlagen.
    static func clipboardYouTubeLink() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string), YouTubeLink.parse(text) != nil else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Pomodoro an oder aus, mit den eingestellten Zeiten.
struct PomodoroToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let enabled = model.isPomodoroEnabled
        let settings = model.pomodoroSettings
        Button {
            model.setPomodoroEnabled(!enabled)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: enabled ? "timer.circle.fill" : "timer")
                Text(enabled ? "Pomodoro \(settings.workMinutes)/\(settings.shortBreakMinutes)" : "Pomodoro")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Theme.text : Theme.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(enabled ? 0.08 : 0.04)))
        }
        .buttonStyle(.plain)
        .help(enabled
              ? "Pomodoro aus. Zeiten in Einstellungen › Fokus."
              : "Pomodoro an: \(settings.workMinutes) Minuten arbeiten, \(settings.shortBreakMinutes) Minuten Pause, nach \(settings.roundsUntilLongBreak) Runden \(settings.longBreakMinutes) Minuten")
    }
}

/// Pause im Pomodoro: zählt herunter, Musik ist aus, danach „Weiter“.
struct PomodoroBreakPane: View {
    @Environment(AppModel.self) private var model
    let state: PomodoroState

    var body: some View {
        let settings = model.pomodoroSettings
        let isReady = state.phase == .ready
        let next = model.task(state.taskID).flatMap { $0.isDone ? nil : $0 } ?? model.focusTask
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text(isReady ? "Pause vorbei" : (state.phase == .longBreak ? "Lange Pause" : "Pause"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isReady ? Theme.accent : Theme.done)
                Text(isReady ? "Weiter geht's" : "Kurz raus, Augen weg vom Bildschirm")
                    .font(.system(size: 30, weight: .regular))
            }
            if !isReady {
                VStack(spacing: 6) {
                    Text(PomodoroText.clock(model.pomodoroRemaining))
                        .font(Theme.timerNumber)
                        .monospacedDigit()
                        .foregroundStyle(Theme.done)
                    ProgressLine(value: Pomodoro.progress(state, settings: settings, now: model.now), height: 3, color: Theme.done)
                        .frame(width: 220)
                }
            }
            Text("\(state.completedInSet == 0 && isReady ? settings.roundsUntilLongBreak : state.completedInSet) von \(settings.roundsUntilLongBreak) Pomodoros\(model.pomodorosToday > 0 ? " · heute \(model.pomodorosToday)" : "")")
                .foregroundStyle(Theme.tertiary)
            if let next {
                Text("Danach: \(next.title)")
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 16) {
                if isReady {
                    Button {
                        model.continuePomodoro()
                    } label: {
                        Label("Weiter", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Theme.accent))
                            .foregroundStyle(Color.black.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(next == nil)
                } else {
                    Button("Pause überspringen") { model.continuePomodoro() }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(next == nil)
                }
                Button("Pomodoro beenden") { model.endPomodoro() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.horizontal, 40)
    }
}

enum PomodoroText {
    /// „24:59“
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
