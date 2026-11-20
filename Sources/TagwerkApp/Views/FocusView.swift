import SwiftUI
import TagwerkCore

/// Fokus: eine Aufgabe, sonst nichts. Ohne Leiste oben; zurück mit dem Pfeil oder Esc.
struct FocusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let running = model.runningEntry != nil
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.leaveFocus()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .keyboardShortcut(.cancelAction)
                .help("Zurück (Esc)")
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(running ? Theme.accent : Theme.tertiary)
                        .frame(width: 7, height: 7)
                    Text("FOKUS")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Group {
                if let task = model.focusTask {
                    FocusTaskPane(task: task)
                        .id(task.id)
                } else {
                    VStack(spacing: 14) {
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

            VStack(spacing: 14) {
                FocusMusicBar()
                FocusTimeBar()
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
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
        VStack(spacing: 22) {
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
                        Text(customer.name.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.6)
                    }
                    .foregroundStyle(Theme.secondary)
                }
                Text(task.title)
                    .font(.system(size: 36, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 760)
                if let number = model.ticketNumber(for: task) {
                    Text("Ticket #\(number)")
                        .font(.callout)
                        .foregroundStyle(Theme.tertiary)
                }
            }

            VStack(spacing: 4) {
                Text(TimeMath.format(model.trackedIncludingSubtasks(taskID: task.id, now: model.runningEntry != nil ? model.now : Date()), showSeconds: true))
                    .font(.system(size: 76, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(running ? Theme.text : Theme.secondary)
                if let estimate = task.estimateMinutes {
                    Text("von \(TimeMath.format(minutes: estimate)) h geplant")
                        .foregroundStyle(Theme.tertiary)
                }
            }

            HStack(spacing: 18) {
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
                        .font(.system(size: 24))
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(Theme.accent))
                        .foregroundStyle(Color.black.opacity(0.85))
                }
                .buttonStyle(.plain)
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
                SubtaskList(parent: task)
                    .frame(maxWidth: 520)
                    .card(padding: 10)
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
                        HStack(spacing: 10) {
                            WorkTypeMenu(task: task)
                            PSPMenu(task: task)
                            TicketMenu(task: task)
                            if model.resolved(task).hasTicket {
                                WorklogTypeMenu(task: task)
                            }
                            Spacer(minLength: 0)
                        }
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
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .frame(maxWidth: 620)
                    .card(padding: 14)
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

/// Musik zum Fokus: Playlist aus der Musik-App, Start, Pause, nächster Titel.
struct FocusMusicBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let music = model.music
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 14))
                .foregroundStyle(music.state == .playing ? Theme.accent : Theme.tertiary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.05)))

            VStack(alignment: .leading, spacing: 2) {
                if let title = music.trackTitle, music.state != .stopped {
                    Text(title)
                        .lineLimit(1)
                    Text([music.trackArtist, music.selectedPlaylist].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                } else if let playlist = music.selectedPlaylist {
                    Text(playlist)
                        .lineLimit(1)
                    Text("Startet mit dem Timer")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Text("Musik zum Fokus")
                    Text("Wähle eine Playlist aus der Musik-App")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
                if let problem = music.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Menu {
                if music.playlists.isEmpty {
                    Button(music.isLoadingPlaylists ? "Lädt …" : "Playlists laden") { music.loadPlaylists() }
                        .disabled(music.isLoadingPlaylists)
                } else {
                    ForEach(music.playlists, id: \.self) { name in
                        Button {
                            music.selectedPlaylist = name
                        } label: {
                            if name == music.selectedPlaylist {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                    Divider()
                    Button("Liste neu laden") { music.loadPlaylists() }
                }
                if music.selectedPlaylist != nil {
                    Divider()
                    Button("Keine Musik") { music.selectedPlaylist = nil }
                }
            } label: {
                Image(systemName: "music.note.list")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Theme.secondary)
            .help("Playlist wählen")
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
            .disabled(music.selectedPlaylist == nil && music.state == .stopped)
            .help(music.state == .playing ? "Musik anhalten" : "Musik abspielen")

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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
    }
}
