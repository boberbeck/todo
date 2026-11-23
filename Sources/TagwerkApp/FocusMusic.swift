import Foundation
import Observation
import TagwerkCore

/// Musik im Fokus aus drei Quellen: Playlist der Musik-App (Apple Music, per AppleScript),
/// Internetradio (direkt in Tagwerk) oder ein YouTube-Link (offizieller Player, sichtbar im Fokus).
/// Für Apple Music fragt macOS beim ersten Mal, ob Tagwerk die Musik-App steuern darf.
@MainActor
@Observable
final class FocusMusic {
    enum State: Equatable {
        case stopped
        case playing
        case paused
    }

    static let playlistKey = "focusMusicPlaylist"
    static let autoPlayKey = "focusMusicAutoPlay"
    static let pauseWithTimerKey = "focusMusicPauseWithTimer"
    static let shuffleKey = "focusMusicShuffle"
    static let sourceKey = "focusMusicSource"
    static let radioStationKey = "focusMusicRadioStation"
    static let youtubeLinkKey = "focusMusicYouTubeLink"
    static let youtubeHistoryKey = "focusMusicYouTubeHistory"

    let radio = RadioPlayer()
    let youtube = YouTubePlayer()

    private(set) var playlists: [String] = []
    private(set) var state: State = .stopped
    private(set) var trackTitle: String?
    private(set) var trackArtist: String?
    private(set) var problem: String?
    private(set) var isLoadingPlaylists = false

    /// Hat Tagwerk die Musik gestartet? Nur dann hält es sie beim Stoppen des Timers auch an.
    @ObservationIgnored private var startedByTagwerk = false
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    /// Für Bildschirmfotos: feste Beispielwerte, keine Skripte.
    @ObservationIgnored var isDemo = false

    /// Die Playlist für den Fokus, in den Einstellungen gewählt.
    var selectedPlaylist: String? = FocusMusic.storedPlaylist() {
        didSet { UserDefaults.standard.set(selectedPlaylist ?? "", forKey: Self.playlistKey) }
    }

    private static func storedPlaylist() -> String? {
        let value = UserDefaults.standard.string(forKey: playlistKey)
        return value?.isEmpty == false ? value : nil
    }

    /// Woher die Musik kommt. Beim Wechsel verstummt die bisherige Quelle.
    var source: MusicSource = MusicSource(rawValue: UserDefaults.standard.string(forKey: FocusMusic.sourceKey) ?? "") ?? .appleMusic {
        didSet {
            guard source != oldValue else { return }
            UserDefaults.standard.set(source.rawValue, forKey: Self.sourceKey)
            silence(oldValue)
            state = .stopped
            trackTitle = nil
            trackArtist = nil
            problem = nil
        }
    }

    /// Gewählter Radiosender (eingebaut oder eigene Adresse).
    var radioStation: RadioStation? = FocusMusic.storedStation() {
        didSet {
            let data = radioStation.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: Self.radioStationKey)
        }
    }

    private static func storedStation() -> RadioStation? {
        guard let data = UserDefaults.standard.data(forKey: radioStationKey) else { return nil }
        return try? JSONDecoder().decode(RadioStation.self, from: data)
    }

    /// YouTube-Link, wie eingefügt.
    var youtubeLinkText: String = UserDefaults.standard.string(forKey: FocusMusic.youtubeLinkKey) ?? "" {
        didSet { UserDefaults.standard.set(youtubeLinkText, forKey: Self.youtubeLinkKey) }
    }

    var youtubeLink: YouTubeLink? { YouTubeLink.parse(youtubeLinkText) }

    /// Zuletzt gespielte YouTube-Links, neueste zuerst.
    var youtubeHistory: [YouTubeHistoryEntry] = FocusMusic.storedHistory() {
        didSet {
            let data = try? JSONEncoder().encode(youtubeHistory)
            UserDefaults.standard.set(data, forKey: Self.youtubeHistoryKey)
        }
    }

    private static func storedHistory() -> [YouTubeHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: youtubeHistoryKey) else { return [] }
        return (try? JSONDecoder().decode([YouTubeHistoryEntry].self, from: data)) ?? []
    }

    /// Ist dieser Verlaufseintrag der gerade gewählte Link?
    func isCurrent(_ entry: YouTubeHistoryEntry) -> Bool {
        source == .youtube && YouTubeHistoryEntry(link: youtubeLinkText, lastPlayed: Date()).id == entry.id
    }

    func playFromHistory(_ entry: YouTubeHistoryEntry) {
        chooseYouTube(entry.link)
        startMusic()
    }

    func removeFromHistory(_ entry: YouTubeHistoryEntry) {
        youtubeHistory.removeAll { $0.id == entry.id }
    }

    func clearHistory() {
        youtubeHistory = []
    }

    /// Ist für die gewählte Quelle etwas ausgesucht?
    var hasSelection: Bool {
        switch source {
        case .appleMusic: return selectedPlaylist != nil
        case .radio: return radioStation != nil
        case .youtube: return youtubeLink != nil
        }
    }

    /// Was gewählt ist, für die Anzeige.
    var selectionName: String? {
        switch source {
        case .appleMusic: return selectedPlaylist
        case .radio: return radioStation?.name
        case .youtube: return youtubeLink == nil ? nil : "YouTube"
        }
    }

    init() {
        radio.onChange = { [weak self] playing, title, problem in
            guard let self, self.source == .radio else { return }
            self.update(playing: playing, title: title ?? self.radioStation?.name, subtitle: title == nil ? "Internetradio" : self.radioStation?.name, problem: problem)
        }
        youtube.onChange = { [weak self] playing, title, problem in
            guard let self, self.source == .youtube else { return }
            self.update(playing: playing, title: title, subtitle: "YouTube", problem: problem)
            if let title {
                self.youtubeHistory = YouTubeHistory.settingTitle(title, for: self.youtubeLinkText, in: self.youtubeHistory)
            }
        }
    }

    private func update(playing: Bool, title: String?, subtitle: String?, problem: String?) {
        if playing {
            state = .playing
        } else if state != .stopped || problem != nil {
            state = problem == nil ? .paused : .stopped
        }
        trackTitle = title
        trackArtist = subtitle
        if let problem {
            self.problem = problem
        } else if playing {
            self.problem = nil
        }
    }

    // MARK: Auswahl

    func choosePlaylist(_ name: String) {
        selectedPlaylist = name
        source = .appleMusic
    }

    func chooseStation(_ station: RadioStation) {
        let wasPlaying = state == .playing
        radioStation = station
        source = .radio
        if wasPlaying || state == .playing { startMusic() }
    }

    func chooseYouTube(_ text: String) {
        youtubeLinkText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        source = .youtube
    }

    /// „Keine Musik“: die Auswahl der aktuellen Quelle löschen.
    func clearSelection() {
        silence(source)
        switch source {
        case .appleMusic: selectedPlaylist = nil
        case .radio: radioStation = nil
        case .youtube: youtubeLinkText = ""
        }
        state = .stopped
        trackTitle = nil
        trackArtist = nil
    }

    private func silence(_ old: MusicSource) {
        guard !isDemo else { return }
        switch old {
        case .appleMusic:
            if state == .playing, startedByTagwerk {
                Task { _ = try? await AppleMusicScript.run(AppleMusicScript.pause) }
            }
        case .radio:
            radio.stop()
        case .youtube:
            youtube.pause()
        }
    }

    private var autoPlay: Bool { UserDefaults.standard.object(forKey: Self.autoPlayKey) as? Bool ?? true }
    private var pauseWithTimer: Bool { UserDefaults.standard.object(forKey: Self.pauseWithTimerKey) as? Bool ?? true }
    private var shuffle: Bool { UserDefaults.standard.bool(forKey: Self.shuffleKey) }

    // MARK: Steuerung

    func loadPlaylists() {
        guard !isDemo else {
            playlists = ["Fokus am Morgen", "Lo-Fi Arbeit", "Klavier leise"]
            return
        }
        isLoadingPlaylists = true
        Task {
            defer { isLoadingPlaylists = false }
            do {
                let output = try await AppleMusicScript.run(AppleMusicScript.playlists)
                playlists = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                problem = playlists.isEmpty ? "In der Musik-App gibt es noch keine eigenen Playlists." : nil
            } catch {
                problem = String(describing: error)
            }
        }
    }

    /// Startet die gewählte Musik (Playlist von vorne, Sender live, YouTube-Link).
    func startMusic() {
        if isDemo {
            state = .playing
            return
        }
        switch source {
        case .appleMusic:
            playPlaylist()
        case .radio:
            guard let station = radioStation else { return }
            startedByTagwerk = true
            radio.play(station)
        case .youtube:
            guard let link = youtubeLink else { return }
            startedByTagwerk = true
            youtubeHistory = YouTubeHistory.adding(youtubeLinkText, at: Date(), to: youtubeHistory)
            youtube.play(link)
        }
    }

    /// Startet die gewählte Playlist der Musik-App (von vorne).
    private func playPlaylist() {
        guard let playlist = selectedPlaylist else { return }
        startedByTagwerk = true
        Task {
            do {
                _ = try await AppleMusicScript.run(AppleMusicScript.play(playlist: playlist, shuffle: shuffle))
                problem = nil
            } catch {
                problem = String(describing: error)
            }
            await refresh()
        }
    }

    func togglePlayPause() {
        if isDemo {
            state = state == .playing ? .paused : .playing
            return
        }
        guard source == .appleMusic else {
            if state == .playing {
                pause()
            } else {
                startMusic()
            }
            return
        }
        switch state {
        case .stopped:
            playPlaylist()
        case .playing, .paused:
            startedByTagwerk = true
            Task {
                _ = try? await AppleMusicScript.run(AppleMusicScript.playPause)
                await refresh()
            }
        }
    }

    /// Nächster Titel; beim Radio nicht möglich, bei YouTube das nächste Video der Playlist.
    var canSkip: Bool { source != .radio }

    func nextTrack() {
        guard !isDemo else { return }
        if source == .youtube {
            youtube.next()
            return
        }
        guard source == .appleMusic else { return }
        Task {
            _ = try? await AppleMusicScript.run(AppleMusicScript.next)
            await refresh()
        }
    }

    func pause() {
        guard !isDemo else {
            state = .paused
            return
        }
        switch source {
        case .radio:
            radio.pause()
            return
        case .youtube:
            youtube.pause()
            return
        case .appleMusic:
            break
        }
        Task {
            _ = try? await AppleMusicScript.run(AppleMusicScript.pause)
            await refresh()
        }
    }

    // MARK: Timer

    func timerStarted(inFocus: Bool) {
        guard inFocus, autoPlay, hasSelection else { return }
        if state == .paused, startedByTagwerk {
            togglePlayPause()
        } else if state != .playing {
            startMusic()
        }
    }

    /// Pomodoro-Pause: Musik anhalten; mit dem nächsten Start des Timers spielt sie weiter.
    func pauseForBreak() {
        guard state == .playing else { return }
        startedByTagwerk = true
        pause()
    }

    func timerStopped() {
        guard pauseWithTimer, startedByTagwerk, state == .playing else { return }
        pause()
    }

    // MARK: Anzeige

    /// Fragt den Stand der Musik-App ab, solange der Fokus offen ist.
    func startWatching() {
        guard statusTask == nil else { return }
        if isDemo {
            state = .playing
            trackTitle = "Regen am Fenster"
            trackArtist = "Studio Nord"
            return
        }
        // Nur wer eine Playlist gewählt hat, nutzt die Musik; sonst fragt Tagwerk die Musik-App gar nicht erst.
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.source == .appleMusic, self?.selectedPlaylist != nil {
                    await self?.refresh()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopWatching() {
        statusTask?.cancel()
        statusTask = nil
        // YouTube nur mit sichtbarem Player: verlässt man den Fokus, hält das Video an
        if source == .youtube, !isDemo {
            youtube.pause()
        }
    }

    private func refresh() async {
        guard let output = try? await AppleMusicScript.run(AppleMusicScript.status) else { return }
        let lines = output.components(separatedBy: "\n")
        switch lines.first {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }
        trackTitle = lines.count > 1 && !lines[1].isEmpty ? lines[1] : nil
        trackArtist = lines.count > 2 && !lines[2].isEmpty ? lines[2] : nil
    }
}

/// AppleScript für die Musik-App, ausgeführt mit /usr/bin/osascript außerhalb des Hauptthreads.
enum AppleMusicScript {
    struct ScriptError: Error, CustomStringConvertible {
        let message: String

        var description: String {
            if message.contains("-1743") || message.lowercased().contains("not authorized") {
                return "Tagwerk darf die Musik-App noch nicht steuern. Erlaube es unter Systemeinstellungen › Datenschutz & Sicherheit › Automation."
            }
            if message.contains("-1728") {
                return "Die Playlist wurde in der Musik-App nicht gefunden."
            }
            return "Die Musik-App meldet: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    static let playlists = """
    tell application "Music"
        set playlistNames to name of every user playlist whose special kind is none
    end tell
    set AppleScript's text item delimiters to linefeed
    return playlistNames as text
    """

    static let playPause = #"tell application "Music" to playpause"#

    static let next = #"if application "Music" is running then tell application "Music" to next track"#

    static let pause = #"if application "Music" is running then tell application "Music" to pause"#

    static let status = """
    if application "Music" is not running then return "stopped"
    tell application "Music"
        set playerState to player state
        if playerState is playing then
            set stateText to "playing"
        else if playerState is paused then
            set stateText to "paused"
        else
            return "stopped"
        end if
        try
            return stateText & linefeed & (name of current track) & linefeed & (artist of current track)
        on error
            return stateText
        end try
    end tell
    """

    static func play(playlist: String, shuffle: Bool) -> String {
        """
        tell application "Music"
            set shuffle enabled to \(shuffle ? "true" : "false")
            play (first user playlist whose name is "\(escape(playlist))")
        end tell
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func run(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ScriptError(message: error.localizedDescription))
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: ScriptError(message: String(decoding: errorData, as: UTF8.self)))
                }
            }
        }
    }
}
