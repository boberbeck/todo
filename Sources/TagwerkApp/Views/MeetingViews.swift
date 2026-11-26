import AppKit
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// Was das Meeting-Fenster zeigt: ein Termin (oder ein schon gespeichertes Meeting).
struct MeetingContext: Identifiable {
    var meetingID: UUID?
    var eventID: String?
    var title: String
    var start: Date
    var end: Date
    /// Der Termin selbst, wenn er im Kalender geladen ist (für „Als Zeit erfassen“)
    var event: CalendarEvent?

    var id: String { meetingID?.uuidString ?? eventID ?? "\(title)@\(start.timeIntervalSince1970)" }

    init(meetingID: UUID?, eventID: String?, title: String, start: Date, end: Date, event: CalendarEvent?) {
        self.meetingID = meetingID
        self.eventID = eventID
        self.title = title
        self.start = start
        self.end = end
        self.event = event
    }

    init(event: CalendarEvent) {
        self.init(meetingID: nil, eventID: event.id, title: event.displayTitle, start: event.start, end: event.end, event: event)
    }

    init(meeting: Meeting) {
        self.init(meetingID: meeting.id, eventID: meeting.eventID, title: meeting.title, start: meeting.start, end: meeting.end, event: nil)
    }

    var timeText: String {
        "\(start.formatted(date: .complete, time: .omitted)), \(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

enum MeetingError: LocalizedError {
    case emptyTranscript
    case noCustomer
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript: return "Das Transkript ist leer."
        case .noCustomer: return "Der Kunde wurde nicht gefunden."
        case .unreadable(let name): return "„\(name)“ ließ sich nicht als Text lesen."
        }
    }
}

/// Liest Transkripte aus Dateien: Teams-VTT, Word, RTF, Text oder Markdown.
enum TranscriptReader {
    static func text(from url: URL) throws -> String {
        let documentTypes: [String: NSAttributedString.DocumentType] = [
            "docx": .officeOpenXML, "doc": .docFormat, "rtf": .rtf, "odt": .openDocument, "html": .html, "htm": .html,
        ]
        if let type = documentTypes[url.pathExtension.lowercased()] {
            let attributed = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
            return attributed.string
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw MeetingError.unreadable(url.lastPathComponent)
        }
        return text
    }
}

/// Startet Claude Code in einem Ordner: Tagwerk legt ein kleines Skript ab, das Terminal öffnet und ausführt.
/// So braucht es keine Erlaubnis, das Terminal fernzusteuern.
enum ClaudeCodeLauncher {
    static func prompt(for meeting: Meeting, calendar: Calendar) -> String {
        let day = meeting.start.formatted(date: .numeric, time: .omitted)
        let id = String(meeting.id.uuidString.prefix(8))
        return "Mach aus dem Meeting „\(meeting.title)“ vom \(day) Aufgaben für mich: Lies das Transkript mit meeting_transkript (ID \(id)), "
            + "schlag mir die Aufgaben vor und leg sie nach meinem Okay mit aufgabe_anlegen und meeting \(id) in Tagwerk an."
    }

    static func open(in folder: URL, prompt: String?) throws {
        let script = """
        #!/bin/zsh -l
        rm -f -- "$0"
        export PATH="$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH"
        cd \(quoted(folder.path)) || exit 1
        clear
        if ! command -v claude >/dev/null 2>&1; then
          echo "Claude Code ist auf diesem Mac nicht installiert (Befehl „claude“ fehlt)."
          echo "Installation: https://claude.ai/code"
        else
          claude\(prompt.map { " " + quoted($0) } ?? "")
        fi
        exec "$SHELL" -l

        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tagwerk Claude \(UUID().uuidString.prefix(6)).command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }

    /// In einfache Anführungszeichen für die Shell.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Pfad kürzer: „~/Kunden/ceSA“
func abbreviatedPath(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

/// Meeting-Fenster: Kunde, Transkript (hineinziehen, wählen oder einfügen), Aufgaben daraus, Claude Code.
struct MeetingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let context: MeetingContext

    @State private var customerID: UUID?
    @State private var loaded = false
    @State private var isDropTarget = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        let meeting = model.meeting(for: context)
        let customer = model.customer(customerID)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.title)
                    .font(.title2.weight(.medium))
                    .lineLimit(2)
                Text(context.timeText)
                    .foregroundStyle(Theme.secondary)
            }

            HStack(spacing: 12) {
                Text("Kunde")
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 70, alignment: .leading)
                Picker("Kunde", selection: $customerID) {
                    Text("Ohne Kunde").tag(UUID?.none)
                    ForEach(model.activeCustomers) { option in
                        Text(option.name).tag(UUID?.some(option.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer()
            }

            if let customer {
                folderRow(customer)
            }

            transcriptArea(meeting)

            if let meeting {
                tasksArea(meeting)
            }

            if let message {
                Label(message, systemImage: messageIsError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(messageIsError ? Theme.warning : Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if let event = context.event {
                    if model.isLogged(event) {
                        Label("Als Zeit erfasst", systemImage: "checkmark")
                            .font(.callout)
                            .foregroundStyle(Theme.done)
                    } else if event.end <= Date() {
                        Button("Als Zeit erfassen") {
                            model.logEvent(event, assignment: .init(customerID: customerID))
                            show("Als Zeit erfasst.")
                        }
                        .buttonStyle(GhostButtonStyle(small: true))
                        .help("Den Termin als erledigte Zeit übernehmen, mit diesem Kunden")
                    }
                }
                Spacer()
                Button("Fertig") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    let saved = model.saveMeeting(context, customerID: customerID)
                    model.openClaudeCode(customerID: customerID, meeting: saved.hasTranscript ? saved : nil)
                } label: {
                    Label("Mit Claude Code öffnen", systemImage: "terminal")
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .disabled(meeting?.hasTranscript != true)
                .help(customer == nil
                      ? "Startet Claude Code mit der Bitte, aus dem Meeting Aufgaben zu machen"
                      : "Startet Claude Code im Ordner von \(customer?.name ?? "") mit der Bitte, aus dem Meeting Aufgaben zu machen")
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            customerID = model.suggestedCustomer(for: context)
        }
        .onChange(of: customerID) {
            // Kunde gleich merken, wenn das Meeting schon existiert (beim ersten Transkript sonst ohnehin)
            if loaded, model.meeting(for: context) != nil {
                model.saveMeeting(context, customerID: customerID)
            }
        }
    }

    // MARK: Teile

    private func folderRow(_ customer: Customer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(Theme.secondary)
                .frame(width: 70, alignment: .leading)
            if let path = customer.folderPath, !path.isEmpty {
                Text(abbreviatedPath(path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.secondary)
                    .textSelection(.enabled)
                Button("Im Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .buttonStyle(GhostButtonStyle(small: true))
            } else {
                Text("Noch kein Ordner für \(customer.name)")
                    .foregroundStyle(Theme.tertiary)
                Button("Ordner anlegen") {
                    do {
                        let url = try model.ensureFolder(for: customer.id)
                        show("Ordner angelegt: \(abbreviatedPath(url.path))")
                    } catch {
                        show(error.localizedDescription, isError: true)
                    }
                }
                .buttonStyle(GhostButtonStyle(small: true))
                .help("Legt \(abbreviatedPath(model.customerFoldersBase.appendingPathComponent(MeetingFiles.folderName(for: customer.name)).path)) mit „Meetings“ und einer CLAUDE.md an")
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func transcriptArea(_ meeting: Meeting?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            if let meeting, let path = meeting.transcriptPath, !path.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Theme.accent)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Im Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(GhostButtonStyle(small: true))
                }
                Text("Zum Ersetzen ein anderes Transkript hierher ziehen.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 22))
                        .foregroundStyle(isDropTarget ? Theme.accent : Theme.tertiary)
                    Text("Transkript hierher ziehen")
                        .font(.callout.weight(.medium))
                    Text("Aus Teams als .vtt oder .docx, oder Text")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            HStack(spacing: 8) {
                Button("Datei wählen …") { chooseFile() }
                    .buttonStyle(GhostButtonStyle(small: true))
                Button("Text aus der Zwischenablage") { pasteText() }
                    .buttonStyle(GhostButtonStyle(small: true))
                    .help("Transkript, das du kopiert hast, als Datei ablegen")
                Spacer()
            }
        }
        .padding(14)
        .background(shape.fill(isDropTarget ? Theme.accentSoft : Color.white.opacity(0.03)))
        .overlay(shape.strokeBorder(isDropTarget ? Theme.accent.opacity(0.6) : Theme.border, style: StrokeStyle(lineWidth: 1, dash: meeting?.hasTranscript == true ? [] : [5, 4])))
        .onDrop(of: [.fileURL, .plainText], isTargeted: $isDropTarget) { providers in
            handleDrop(providers)
        }
    }

    private func tasksArea(_ meeting: Meeting) -> some View {
        let fromMeeting = model.tasks(fromMeeting: meeting.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Aufgaben aus dem Meeting")
                    .font(.callout.weight(.medium))
                Spacer()
                if fromMeeting.isEmpty, !meeting.isProcessed, meeting.hasTranscript {
                    Button("Ohne Aufgaben erledigt") { model.markMeetingProcessed(context) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            if fromMeeting.isEmpty {
                Text(meeting.isProcessed
                     ? "Erledigt, ohne Aufgaben für dich."
                     : "Noch keine. „Mit Claude Code öffnen“ lässt Claude welche vorschlagen und hier anlegen.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            } else {
                ForEach(fromMeeting) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isDone ? Theme.done : Theme.tertiary)
                        Text(task.title)
                            .lineLimit(1)
                        Spacer()
                        Button("Öffnen") {
                            dismiss()
                            model.openDetail(task.id)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .font(.callout)
                }
            }
        }
    }

    // MARK: Transkript übernehmen

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in importFile(url) }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text else { return }
                Task { @MainActor in importText(text, source: "Text") }
            }
            return true
        }
        return false
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Transkript wählen (Teams .vtt oder .docx, Text)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(url)
    }

    private func pasteText() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show("In der Zwischenablage ist kein Text.", isError: true)
            return
        }
        importText(text, source: "Text aus der Zwischenablage")
    }

    private func importFile(_ url: URL) {
        do {
            importText(try TranscriptReader.text(from: url), source: url.lastPathComponent)
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func importText(_ text: String, source: String) {
        do {
            let url = try model.storeTranscript(text, for: context, customerID: customerID)
            show("\(source) abgelegt: \(abbreviatedPath(url.path))")
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func show(_ text: String, isError: Bool = false) {
        message = text
        messageIsError = isError
    }
}

/// Ordner des Kunden für Claude Code: anzeigen, anlegen, wählen, CLAUDE.md, Claude Code starten.
struct CustomerFolderRow: View {
    @Environment(AppModel.self) private var model
    let customer: Customer
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                if let path = customer.folderPath, !path.isEmpty {
                    Text(abbreviatedPath(path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.secondary)
                        .textSelection(.enabled)
                    Button("Im Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(GhostButtonStyle(small: true))
                    if !model.hasInstructions(customerID: customer.id) {
                        Button("CLAUDE.md anlegen") {
                            do {
                                try model.writeInstructionsIfMissing(customerName: customer.name, in: URL(fileURLWithPath: path, isDirectory: true))
                                message = "CLAUDE.md angelegt: Ergänze dort, was Claude über \(customer.name) wissen soll."
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                        .buttonStyle(GhostButtonStyle(small: true))
                        .help("Anweisungen für Claude Code: wie es an Meetings und Aufgaben in Tagwerk kommt")
                    }
                    Button {
                        model.openClaudeCode(customerID: customer.id)
                    } label: {
                        Label("Claude Code", systemImage: "terminal")
                    }
                    .buttonStyle(GhostButtonStyle(small: true))
                    .help("Startet Claude Code in diesem Ordner")
                } else {
                    Text("Kein Ordner für Claude Code")
                        .foregroundStyle(Theme.tertiary)
                    Button("Ordner anlegen") {
                        do {
                            let url = try model.ensureFolder(for: customer.id)
                            message = "Angelegt: \(abbreviatedPath(url.path)) mit „Meetings“ und CLAUDE.md"
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    .buttonStyle(GhostButtonStyle(small: true))
                    .help("Legt \(abbreviatedPath(model.customerFoldersBase.appendingPathComponent(MeetingFiles.folderName(for: customer.name)).path)) an")
                }
                Menu {
                    Button("Vorhandenen Ordner wählen …") { chooseFolder() }
                    if customer.folderPath != nil {
                        Button("Verknüpfung lösen") { model.setFolder(nil, for: customer.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer(minLength: 0)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .font(.callout)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Ordner für \(customer.name) wählen (z. B. den, in dem du schon mit Claude Code arbeitest)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setFolder(url, for: customer.id)
        message = "Verknüpft. Fehlt dort eine CLAUDE.md, kannst du sie anlegen."
    }
}

/// Einstellungen › Claude: wo neue Kundenordner entstehen.
struct CustomerFoldersSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Kundenordner in") {
                HStack(spacing: 8) {
                    Text(abbreviatedPath(model.customerFoldersBase.path))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Wählen …") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.message = "Ordner, in dem Tagwerk neue Kundenordner anlegt"
                        if panel.runModal() == .OK, let url = panel.url {
                            model.setCustomerFoldersBase(url)
                        }
                    }
                }
            }
        } header: {
            Text("Meetings und Kundenordner")
        } footer: {
            SettingsFootnote("Jeder Kunde kann einen Ordner für Claude Code haben: mit einer CLAUDE.md (was Claude über den Kunden wissen soll) und den Meeting-Transkripten unter „Meetings“. Doppelklick auf einen Termin öffnet das Meeting: Transkript hineinziehen, dann „Mit Claude Code öffnen“. Claude liest es über die Tagwerk-Werkzeuge und legt die Aufgaben mit Verweis aufs Meeting an.")
        }
    }
}
