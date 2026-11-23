import AppKit
import Foundation
import Observation
import TagwerkCore

/// Automatische Updates aus dem Release „aktuell“ auf GitHub: prüft beim Start und alle sechs Stunden,
/// fragt nach und ersetzt nach Bestätigung die App, danach startet Tagwerk neu.
/// Das Repository ist privat; dafür braucht es einen GitHub-Schlüssel, der nur lesen darf (im Schlüsselbund).
@MainActor
@Observable
final class Updater {
    static let repository = "boberbeck/todo"
    static let tag = "aktuell"
    static let tokenAccount = "github-update-token"
    static let tokenPage = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    struct Available: Equatable {
        var release: ReleaseInfo
        var changes: [String]
    }

    private(set) var available: Available?
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var status: String?
    private(set) var lastCheck: Date?
    /// Zeigt die Nachfrage „Jetzt aktualisieren?“
    var showsPrompt = false

    @ObservationIgnored private var cachedHasToken: Bool?
    @ObservationIgnored private var dismissedCommit: String?

    var currentBuild: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }

    var hasToken: Bool {
        if let cachedHasToken { return cachedHasToken }
        let exists = Keychain.exists(account: Self.tokenAccount)
        cachedHasToken = exists
        return exists
    }

    func setToken(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            Keychain.delete(account: Self.tokenAccount)
        } else {
            Keychain.set(clean, account: Self.tokenAccount)
        }
        cachedHasToken = !clean.isEmpty
        status = nil
    }

    var isAutomatic: Bool {
        UserDefaults.standard.object(forKey: Preferences.updateAutoCheckKey) as? Bool ?? true
    }

    // MARK: Prüfen

    /// Beim Start und danach alle sechs Stunden, wenn ein Schlüssel hinterlegt ist.
    func checkIfDue() {
        guard isAutomatic, hasToken, !isChecking, !isInstalling, SnapshotMode.directory == nil else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 6 * 3600 { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard let token = Keychain.get(account: Self.tokenAccount), !token.isEmpty else {
            status = "Für Updates fehlt der GitHub-Schlüssel (Einstellungen › Allgemein › Updates)."
            return
        }
        isChecking = true
        defer { isChecking = false }
        lastCheck = Date()
        do {
            let data: Data
            do {
                data = try await Self.send(ReleaseCheck.releaseRequest(repository: Self.repository, tag: Self.tag, token: token))
            } catch let error as UpdateError where error.status == 404 {
                throw await diagnoseNotFound(token: token)
            }
            let release = try ReleaseCheck.parseRelease(data)
            guard release.isNewer(thanBuild: currentBuild) else {
                available = nil
                status = currentBuild == "lokal"
                    ? "Selbst gebaute Fassung: Updates aus GitHub sind aus."
                    : "Tagwerk ist aktuell (Stand \(currentBuild ?? "?"))."
                return
            }
            var changes: [String] = []
            if let build = currentBuild,
               let compare = try? await Self.send(ReleaseCheck.compareRequest(repository: Self.repository, base: build, head: release.commit, token: token)) {
                changes = ReleaseCheck.parseChanges(compare)
            }
            available = Available(release: release, changes: changes)
            status = "Neue Fassung verfügbar (Stand \(release.shortCommit))."
            AppLog.info("Update", "Neue Fassung \(release.shortCommit) verfügbar (laufend: \(currentBuild ?? "?"))")
            if userInitiated || dismissedCommit != release.commit {
                showsPrompt = true
            }
        } catch {
            status = "Update-Prüfung fehlgeschlagen: \(error)"
            AppLog.warning("Update", "Prüfung fehlgeschlagen: \(error)")
        }
    }

    /// „Später“: für diese Fassung nicht mehr von selbst fragen (der Hinweis oben bleibt).
    func postpone() {
        dismissedCommit = available?.release.commit
        showsPrompt = false
    }

    // MARK: Installieren

    /// Lädt die DMG, prüft die App darin, ersetzt die laufende App und startet neu.
    func install() async {
        guard let available, let url = available.release.dmgURL,
              let token = Keychain.get(account: Self.tokenAccount) else { return }
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app", !target.path.contains("/AppTranslocation/") else {
            status = "Tagwerk läuft nicht aus „Programme“. Erst die App dorthin ziehen, dann aktualisieren."
            return
        }
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            status = "Keine Schreibrechte in \(target.deletingLastPathComponent().path)."
            return
        }
        isInstalling = true
        showsPrompt = false
        status = "Lädt die neue Fassung …"
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("tagwerk-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (downloaded, response) = try await URLSession.shared.download(for: ReleaseCheck.assetRequest(url, token: token))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("Download fehlgeschlagen (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            let dmg = work.appendingPathComponent("Tagwerk.dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)

            status = "Prüft und entpackt …"
            let mount = work.appendingPathComponent("mount")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            try Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
            let staged = work.appendingPathComponent("Tagwerk.app")
            defer { try? Self.run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mount.path]) }
            try Self.run("/usr/bin/ditto", [mount.appendingPathComponent("Tagwerk.app").path, staged.path])
            try? Self.run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path])

            // Nur eine echte, unversehrte Tagwerk-App einsetzen
            guard Bundle(url: staged)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError("Die geladene App ist nicht Tagwerk.")
            }
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])

            status = "Installiert, Tagwerk startet neu …"
            AppLog.info("Update", "Fassung \(available.release.shortCommit) wird eingesetzt, Neustart")
            try launchReplacement(staged: staged, target: target, work: work)
            NSApp.terminate(nil)
        } catch {
            isInstalling = false
            status = "Update fehlgeschlagen: \(error)"
            AppLog.error("Update", "Installation fehlgeschlagen: \(error)")
        }
    }

    /// Kleines Skript, das wartet, bis Tagwerk beendet ist, dann die App austauscht und neu startet.
    private func launchReplacement(staged: URL, target: URL, work: URL) throws {
        let script = work.appendingPathComponent("austauschen.sh")
        try """
        #!/bin/bash
        PID="$1"; NEW="$2"; TARGET="$3"; WORK="$4"
        for i in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        rm -rf "$TARGET.alt"
        if mv "$TARGET" "$TARGET.alt" && /usr/bin/ditto "$NEW" "$TARGET"; then
          rm -rf "$TARGET.alt"
        else
          rm -rf "$TARGET"; mv "$TARGET.alt" "$TARGET"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        /usr/bin/open "$TARGET"
        rm -rf "$WORK"
        """.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), staged.path, target.path, work.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    // MARK: Hilfen

    struct UpdateError: Error, CustomStringConvertible {
        let description: String
        var status: Int = 0
        init(_ description: String, status: Int = 0) {
            self.description = description
            self.status = status
        }
    }

    /// GitHub meldet bei fehlenden Rechten „nicht gefunden“. Welches Recht fehlt, zeigt die Abfrage des Repositorys.
    private func diagnoseNotFound(token: String) async -> UpdateError {
        do {
            _ = try await Self.send(ReleaseCheck.repositoryRequest(repository: Self.repository, token: token))
            return UpdateError("Der Schlüssel sieht das Repository, darf aber keine Releases lesen. Bei GitHub den Schlüssel öffnen › Permissions › Repository permissions › „Contents“ auf „Read-only“ stellen und speichern. (Selten: das Release wird gerade neu gebaut, dann in ein paar Minuten noch einmal prüfen.)")
        } catch {
            return UpdateError("Der Schlüssel sieht das Repository \(Self.repository) nicht. Bei GitHub den Schlüssel öffnen › Repository access › „Only select repositories“ › \(Self.repository) auswählen und speichern; außerdem „Contents: Read-only“.")
        }
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw UpdateError("Der GitHub-Schlüssel gilt nicht (mehr). Neu anlegen und hier eintragen.", status: 401) }
            if status == 404 { throw UpdateError("Release nicht gefunden oder der Schlüssel darf das Repository nicht lesen.", status: 404) }
            throw UpdateError("GitHub antwortet mit HTTP \(status).", status: status)
        }
        return data
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return text
    }
}
