import AppKit
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

    static func signal(title: String, body: String, sound: String) {
        if UserDefaults.standard.bool(forKey: Preferences.pomodoroSoundKey) {
            NSSound(named: NSSound.Name(sound))?.play()
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
