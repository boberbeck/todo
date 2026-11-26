import AppKit
import TagwerkCore
import UserNotifications

/// Signale für Pomodoro: ein Ton und eine Mitteilung (auch wenn Tagwerk im Hintergrund ist).
@MainActor
enum PomodoroNotifier {
    private static let delegate = Delegate()

    /// Mitteilungen gehen nur aus einer echten App heraus (nicht bei `swift run`).
    private static var canNotify: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && SnapshotMode.directory == nil
    }

    static func requestPermission() {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func signal(title: String, body: String, event: PomodoroSoundEvent) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Preferences.pomodoroSoundKey) {
            SoundLibrary.play(defaults.string(forKey: event.key) ?? event.defaultSound, volume: Float(defaults.double(forKey: Preferences.pomodoroVolumeKey)))
        }
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "pomodoro-\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request) { _ in }
    }

    /// Zeigt die Mitteilung auch, wenn Tagwerk vorne ist.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .list])
        }
    }
}

/// Wann ein Pomodoro-Ton kommt; jeder Anlass hat seinen eigenen Ton.
enum PomodoroSoundEvent: CaseIterable, Identifiable {
    case shortBreak
    case longBreak
    case resume

    var id: Self { self }

    var label: String {
        switch self {
        case .shortBreak: return "Kurze Pause"
        case .longBreak: return "Lange Pause"
        case .resume: return "Pause vorbei"
        }
    }

    var key: String {
        switch self {
        case .shortBreak: return Preferences.pomodoroShortBreakSoundKey
        case .longBreak: return Preferences.pomodoroLongBreakSoundKey
        case .resume: return Preferences.pomodoroResumeSoundKey
        }
    }

    var defaultSound: String {
        switch self {
        case .shortBreak: return "Glass"
        case .longBreak: return "tagwerk:gong"
        case .resume: return "Hero"
        }
    }
}

/// Alle Töne zur Auswahl: eigene Tagwerk-Klänge, die von macOS und selbst hinzugefügte Dateien.
/// Gespeichert wird eine Kennung: "" = kein Ton, "tagwerk:gong", "datei:Name.mp3" oder der Name eines macOS-Tons.
enum SoundLibrary {
    static let silent = ""
    private static let chimePrefix = "tagwerk:"
    private static let filePrefix = "datei:"
    private static let audioExtensions: Set<String> = ["aiff", "aif", "caf", "wav", "mp3", "m4a"]
    /// Hält den gerade spielenden Ton fest, sonst bricht er sofort ab.
    @MainActor private static var playing: NSSound?

    static func chimeID(_ chime: Chime) -> String { chimePrefix + chime.rawValue }

    /// Selbst hinzugefügte Töne
    static var ownFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tagwerk", isDirectory: true)
            .appendingPathComponent("Klänge", isDirectory: true)
    }

    /// Erzeugte Tagwerk-Klänge (lassen sich jederzeit neu erzeugen)
    private static var generatedFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tagwerk", isDirectory: true)
            .appendingPathComponent("Klänge", isDirectory: true)
    }

    static var chimes: [String] { Chime.allCases.map(chimeID) }

    /// Töne von macOS (und aus ~/Library/Sounds), nach Namen sortiert.
    static func systemSounds() -> [String] {
        let folders = [
            URL(fileURLWithPath: "/System/Library/Sounds"),
            URL(fileURLWithPath: "/Library/Sounds"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds"),
        ]
        let names = folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                .map { $0.deletingPathExtension().lastPathComponent }
        }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func ownSounds() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(at: ownFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .map { filePrefix + $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func label(_ id: String) -> String {
        if id == silent { return "Kein Ton" }
        if id.hasPrefix(chimePrefix) {
            return Chime(rawValue: String(id.dropFirst(chimePrefix.count)))?.label ?? id
        }
        if id.hasPrefix(filePrefix) {
            return (String(id.dropFirst(filePrefix.count)) as NSString).deletingPathExtension
        }
        return id
    }

    /// Spielt einen Ton; ein noch laufender hört auf.
    @MainActor
    static func play(_ id: String, volume: Float) {
        playing?.stop()
        playing = nil
        guard id != silent, let sound = makeSound(id) else { return }
        sound.volume = max(0.05, min(1, volume))
        playing = sound
        sound.play()
    }

    /// Für den Selbsttest: Länge des Tons in Sekunden, `nil` = lässt sich nicht laden.
    static func duration(of id: String) -> TimeInterval? {
        makeSound(id)?.duration
    }

    private static func makeSound(_ id: String) -> NSSound? {
        if id.hasPrefix(chimePrefix) {
            guard let chime = Chime(rawValue: String(id.dropFirst(chimePrefix.count))),
                  let url = chimeFile(chime) else { return nil }
            return NSSound(contentsOf: url, byReference: true)
        }
        if id.hasPrefix(filePrefix) {
            let url = ownFolder.appendingPathComponent(String(id.dropFirst(filePrefix.count)))
            return NSSound(contentsOf: url, byReference: true)
        }
        return NSSound(named: NSSound.Name(id))
    }

    /// Tagwerk-Klang als Datei, beim ersten Mal erzeugt.
    private static func chimeFile(_ chime: Chime) -> URL? {
        let url = generatedFolder.appendingPathComponent("\(chime.rawValue)-1.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do {
            try FileManager.default.createDirectory(at: generatedFolder, withIntermediateDirectories: true)
            try ChimeSynth.wav(chime).write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.error("Ton", "Klang \(chime.rawValue) nicht erzeugt: \(error.localizedDescription)")
            return nil
        }
    }

    /// Eigenen Ton übernehmen (wird in den Tagwerk-Ordner kopiert); gibt seine Kennung zurück.
    static func importSound(from source: URL) throws -> String {
        try FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)
        var target = ownFolder.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
            let base = source.deletingPathExtension().lastPathComponent
            target = ownFolder.appendingPathComponent("\(base) \(Int(Date().timeIntervalSince1970)).\(source.pathExtension)")
        }
        try FileManager.default.copyItem(at: source, to: target)
        return filePrefix + target.lastPathComponent
    }
}
