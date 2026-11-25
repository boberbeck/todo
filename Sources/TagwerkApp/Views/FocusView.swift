import AppKit
import SwiftUI
import TagwerkCore

/// Fokus: eine Aufgabe, sonst nichts. „Zurück“ (oder Esc) und Pomodoro stehen in der Titelleiste.
struct FocusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 8)

            // Passt der Inhalt nicht ins Fenster (kleines Fenster, Titelleiste), lässt er sich scrollen statt abgeschnitten zu werden
            GeometryReader { geometry in
                ScrollView {
                    focusContent
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }

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

    @ViewBuilder
    private var focusContent: some View {
        if let pause = model.runningBreak {
            BreakPane(item: pause)
        } else if let pomodoro = model.pomodoro, pomodoro.phase.isBreak || pomodoro.phase == .ready {
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
                if model.resolved(task).hasTicket {
                    BookingSummary(task: task)
                        .padding(.top, 2)
                }
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
                .disabled(task.isStanding)
                .help(task.isStanding ? "Standardaufgaben werden nie erledigt" : "Erledigt (⌘↩), danach kommt die nächste Aufgabe")

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

            HStack(spacing: 24) {
                BackdatedStartMenu(task: task, asButton: true)
                if running {
                    StartBreakButton()
                }
            }

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

    /// „Ticket #1234 · Bearbeitung“
    private var detailSummary: String {
        var parts: [String] = []
        parts.append(model.resolved(task).linkedTicketNumber.map { "Ticket #\($0)" } ?? "Ticket zuordnen")
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

/// Musik zum Fokus: Klangwelt, Internetradio, Apple Music oder YouTube. Start, Pause, nächster Titel.
/// Gewählt wird in einem eigenen Fenster mit einem Reiter je Quelle. Bei YouTube steht der Player sichtbar darüber.
struct FocusMusicBar: View {
    @Environment(AppModel.self) private var model

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
    }

    private func bar(_ music: FocusMusic) -> some View {
        HStack(spacing: 12) {
            Image(systemName: MusicPicker.icon(music.source))
                .font(.system(size: 14))
                .foregroundStyle(music.state == .playing ? Theme.secondary : Theme.tertiary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.05)))

            // Ein Klick auf den Titel öffnet die Auswahl
            Button {
                openPicker(music)
            } label: {
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
                        Text("Startet mit dem Timer · ändern")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                    } else {
                        Text("Musik zum Fokus")
                        Text("Musik wählen")
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Musik wählen")

            Button {
                openPicker(music)
            } label: {
                Image(systemName: "music.note.list")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Musik wählen: Klangwelt, Internetradio, Apple Music oder YouTube")
            .popover(isPresented: Binding(get: { music.showsPicker }, set: { music.showsPicker = $0 }), arrowEdge: .top) {
                MusicPicker { music.showsPicker = false }
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

    /// Öffnet die Auswahl beim Reiter der gerade gewählten Quelle.
    private func openPicker(_ music: FocusMusic) {
        music.pickerTab = music.source
        music.showsPicker = true
    }
}

/// Auswahl der Fokus-Musik: oben die Quelle, darunter nur deren Einträge.
struct MusicPicker: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    @State private var youtubeDraft = ""

    /// Reihenfolge der Reiter: was ohne Einrichtung geht, zuerst
    private let tabs: [MusicSource] = [.soundscape, .radio, .appleMusic, .youtube]

    var body: some View {
        let music = model.music
        VStack(alignment: .leading, spacing: 16) {
            // Reiter im Stil der Titelleiste: runde Flächen, gewählt eine Stufe heller, kein Orange
            HStack(spacing: 4) {
                ForEach(tabs) { source in
                    SourceTab(source: source, selected: music.pickerTab == source) {
                        music.pickerTab = source
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surfaceSunken))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    switch music.pickerTab {
                    case .soundscape: soundscapeList(music)
                    case .radio: radioList(music)
                    case .appleMusic: appleMusicList(music)
                    case .youtube: youtubeList(music)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(height: 300)

            Rectangle().fill(Theme.border).frame(height: 1)

            HStack {
                if music.hasSelection {
                    Button("Keine Musik") {
                        music.clearSelection()
                        close()
                    }
                    .buttonStyle(GhostButtonStyle(small: true))
                }
                Spacer()
                Text(Self.footnote(music.pickerTab))
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        // Breite am Inhalt, Abstand außen: so bleibt auch bei runden Fensterecken genug Luft
        .frame(width: 360)
        .padding(20)
        .background(Theme.surfaceFloating)
        .focusEffectDisabled()
        .presentationBackground(Theme.surfaceFloating)
        .onAppear {
            if music.playlists.isEmpty, music.isDemo { music.loadPlaylists() }
        }
    }

    // MARK: Listen

    @ViewBuilder
    private func soundscapeList(_ music: FocusMusic) -> some View {
        ForEach(SoundscapeMode.allCases) { mode in
            MusicRow(
                title: mode.label,
                subtitle: mode.detail,
                selected: music.source == .soundscape && music.soundscapeSettings.mode == mode
            ) {
                music.chooseSoundscape(mode)
                close()
            }
        }
        Text("Passt sich an: gerade \(music.currentMood().description)")
            .font(.caption)
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    @ViewBuilder
    private func radioList(_ music: FocusMusic) -> some View {
        ForEach(RadioStation.genres, id: \.self) { genre in
            GroupHeader(title: genre)
            ForEach(RadioStation.stations(in: genre)) { station in
                MusicRow(
                    title: station.name,
                    subtitle: station.detail,
                    selected: music.source == .radio && station.id == music.radioStation?.id
                ) {
                    music.chooseStation(station)
                    close()
                }
            }
        }
        if let custom = music.radioStation, !RadioStation.builtIn.contains(where: { $0.id == custom.id }) {
            GroupHeader(title: "Eigene Adresse")
            MusicRow(title: custom.name, subtitle: custom.url.absoluteString, selected: music.source == .radio) {
                music.chooseStation(custom)
                close()
            }
        }
    }

    @ViewBuilder
    private func appleMusicList(_ music: FocusMusic) -> some View {
        if music.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Deine eigenen Playlists aus der Musik-App")
                    .foregroundStyle(Theme.secondary)
                Button(music.isLoadingPlaylists ? "Lädt …" : "Playlists laden") { music.loadPlaylists() }
                    .buttonStyle(GhostButtonStyle(small: true))
                    .disabled(music.isLoadingPlaylists)
            }
            .padding(12)
        } else {
            ForEach(music.playlists, id: \.self) { name in
                MusicRow(title: name, subtitle: nil, selected: music.source == .appleMusic && name == music.selectedPlaylist) {
                    music.choosePlaylist(name)
                    if music.state == .playing { music.startMusic() }
                    close()
                }
            }
            Button("Liste neu laden") { music.loadPlaylists() }
                .buttonStyle(GhostButtonStyle(small: true))
                .padding(.top, 8)
                .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func youtubeList(_ music: FocusMusic) -> some View {
        HStack(spacing: 8) {
            TextField("YouTube-Link einfügen", text: $youtubeDraft)
                .textFieldStyle(TagwerkFieldStyle())
                .onSubmit { playDraft(music) }
            Button("Abspielen") { playDraft(music) }
                .buttonStyle(GhostButtonStyle(small: true))
                .disabled(YouTubeLink.parse(youtubeDraft) == nil)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onAppear {
            if youtubeDraft.isEmpty { youtubeDraft = FocusMusicBar.clipboardYouTubeLink() ?? "" }
        }
        if !music.youtubeHistory.isEmpty {
            GroupHeader(title: "Zuletzt gespielt")
            ForEach(music.youtubeHistory) { entry in
                MusicRow(
                    title: entry.displayTitle,
                    subtitle: entry.lastPlayed.formatted(.relative(presentation: .named)),
                    selected: music.isCurrent(entry),
                    onRemove: { music.removeFromHistory(entry) }
                ) {
                    music.playFromHistory(entry)
                    close()
                }
            }
        }
    }

    private func playDraft(_ music: FocusMusic) {
        guard YouTubeLink.parse(youtubeDraft) != nil else { return }
        music.chooseYouTube(youtubeDraft)
        music.startMusic()
        close()
    }

    static func footnote(_ source: MusicSource) -> String {
        switch source {
        case .soundscape: return "Erzeugt von Tagwerk, offline"
        case .radio: return "Werbefrei, überwiegend ohne Gesang"
        case .appleMusic: return "Über die Musik-App"
        case .youtube: return "Player bleibt im Fokus sichtbar"
        }
    }

    static func icon(_ source: MusicSource) -> String {
        switch source {
        case .appleMusic: return "music.note"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .youtube: return "play.rectangle"
        case .soundscape: return "waveform"
        }
    }
}

/// Eine Zeile in der Musikauswahl: Titel, Zusatz, Haken wenn gewählt, optional Entfernen.
private struct MusicRow: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    var onRemove: (() -> Void)?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onRemove, hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .help("Aus dem Verlauf entfernen")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Color.white.opacity(selected ? 0.07 : (hovering ? 0.04 : 0))))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Reiter der Musikauswahl: Symbol und Name, gewählt als hellere runde Fläche.
private struct SourceTab: View {
    let source: MusicSource
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: MusicPicker.icon(source))
                    .font(.system(size: 11))
                Text(source == .radio ? "Radio" : source.label)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Theme.text : (hovering ? Theme.text.opacity(0.85) : Theme.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.09 : 0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Kleine Zwischenüberschrift in der Musikauswahl.
private struct GroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

extension FocusMusicBar {
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
