import AppKit
import SwiftUI
import TagwerkCore

/// Fehler melden: beschreiben, ansehen, was mitgeht, dann als GitHub-Issue, Datei oder Text für den Chat.
struct BugReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var expected = ""
    @State private var includeLog = true
    @State private var includeCrash = true
    @State private var showsPreview = false
    @State private var message: String?
    @State private var crash: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fehler melden")
                        .font(.title2.weight(.medium))
                    Text(crash != nil ? "Tagwerk ist zuletzt abgestürzt. Der Bericht von macOS kann mit." : "Was ist schiefgegangen? Das Protokoll hilft beim Finden.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Form {
                TextField("Kurztitel (optional)", text: $title)
                TextField("Was ist passiert?", text: $description, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Was hätte passieren sollen? (optional)", text: $expected, axis: .vertical)
                    .lineLimit(2...4)
                Toggle("Protokoll mitschicken", isOn: $includeLog)
                if let crash {
                    Toggle("Absturzbericht mitschicken (\(crash.lastPathComponent))", isOn: $includeCrash)
                }
                DisclosureGroup("Ansehen, was mitgeht", isExpanded: $showsPreview) {
                    ScrollView {
                        Text(previewText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }
            }
            .tagwerkForm()
            Text("Das Protokoll enthält keine Passwörter oder Schlüssel, aber Ticketnummern und Meldungen aus ManageEngine. Bitte kurz ansehen, bevor du es weitergibst.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Abbrechen") {
                    BugReport.markCrashSeen(crash)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Für den Chat kopieren") { copyForChat() }
                    .disabled(!canSend)
                Button("Als Datei sichern") { saveFile(reveal: true) }
                    .disabled(!canSend)
                Button("Bei GitHub melden") { openIssue() }
                    .buttonStyle(GhostButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSend)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            crash = model.pendingCrash ?? BugReport.crashReports().first.flatMap { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return Date().timeIntervalSince(date) < 2 * 86400 ? url : nil
            }
            if model.pendingCrash != nil, description.isEmpty {
                description = "Tagwerk ist abgestürzt."
            }
        }
    }

    private var canSend: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var attachedCrash: URL? { includeCrash ? crash : nil }

    private var previewText: String {
        BugReport.text(description: description.isEmpty ? "…" : description, expected: expected, model: model,
                       logLines: includeLog ? 40 : 0, crash: attachedCrash)
    }

    private func copyForChat() {
        let text = BugReport.text(description: description, expected: expected, model: model, logLines: includeLog ? 150 : 0, crash: attachedCrash)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        AppLog.info("Fehlerbericht", "für den Chat kopiert")
        message = "In der Zwischenablage. Einfach im Chat mit Claude einfügen (⌘V)."
        BugReport.markCrashSeen(crash)
    }

    @discardableResult
    private func saveFile(reveal: Bool) -> URL? {
        do {
            let url = try BugReport.save(description: description, expected: expected, model: model, includeLog: includeLog, crash: attachedCrash)
            if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            message = "Gesichert: \(url.lastPathComponent) in „Downloads“."
            BugReport.markCrashSeen(crash)
            return url
        } catch {
            message = "Sichern fehlgeschlagen: \(error.localizedDescription)"
            return nil
        }
    }

    private func openIssue() {
        let file = saveFile(reveal: true)
        guard let url = BugReport.issueURL(title: title, description: description, expected: expected, model: model,
                                           includeLog: includeLog, crash: attachedCrash) else { return }
        NSWorkspace.shared.open(url)
        AppLog.info("Fehlerbericht", "GitHub-Seite geöffnet")
        message = "Die GitHub-Seite ist offen und vorausgefüllt. \(file.map { "Zieh noch „\($0.lastPathComponent)“ aus dem geöffneten Finder-Fenster in das Textfeld, dann „Submit new issue“." } ?? "")"
    }
}
