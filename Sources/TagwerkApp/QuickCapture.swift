import AppKit
import Carbon
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// Systemweites Tastenkürzel über die Carbon-API. Braucht keine Bedienungshilfen-Freigabe.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Standard: ⌃⌥ Leertaste
    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey), action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(noErr) }
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                return OSStatus(noErr)
            },
            1,
            &eventType,
            context,
            &handlerRef
        )
        let identifier = EventHotKeyID(signature: OSType(0x5457_4B31), id: 1) // "TWK1"
        RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Kleines schwebendes Fenster zum schnellen Erfassen, von überall per Tastenkürzel.
@MainActor
final class QuickCaptureController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var hotKey: GlobalHotKey?

    init(model: AppModel) {
        self.model = model
    }

    func installHotKey() {
        guard hotKey == nil else { return }
        hotKey = GlobalHotKey { [weak self] in
            MainActor.assumeIsolated {
                self?.toggle()
            }
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    @discardableResult
    func show() -> NSWindow? {
        guard let model else { return nil }
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 96),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Schnell erfassen"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = QuickCaptureView { [weak self] in
            self?.hide()
        }
        .environment(model)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}

struct QuickCaptureView: View {
    @Environment(AppModel.self) private var model
    let onDone: () -> Void

    @State private var text = ""
    @State private var forToday = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                TextField("Was steht an? z. B. „Kunde zurückrufen 15m“", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(add)
            }
            HStack {
                Toggle("Gleich für heute einplanen", isOn: $forToday)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Text("↩ übernehmen · esc schließen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .frame(width: 560)
        .onAppear { focused = true }
        .onExitCommand(perform: onDone)
    }

    private func add() {
        guard model.addTask(title: text, customerID: nil, plannedDate: forToday ? model.today : nil) != nil else { return }
        text = ""
        onDone()
    }
}

/// Nimmt Mails (z. B. aus Outlook), Dateien, Links und Text per Drag-and-drop als Aufgaben an.
/// Ohne `plannedDate` landen sie im Eingang, sonst gleich an dem Tag (z. B. auf „Heute“ gezogen).
enum DropImporter {
    /// `.item` zuletzt: so kommt jedes Ziehen hier an und steht im Protokoll, auch wenn das Format unbekannt ist
    /// (das neue Outlook bietet je nach Version andere Formate an).
    static let acceptedTypes: [UTType] = [.emailMessage, .fileURL, .url, .plainText, .item]

    @MainActor
    static func handle(_ providers: [NSItemProvider], model: AppModel, plannedDate: LocalDate? = nil) -> Bool {
        // Für die Fehlersuche: jedes Ziehen mit den angebotenen Formaten protokollieren (ohne Inhalt)
        let place = plannedDate == nil ? "Eingang" : "Tag"
        for (index, provider) in providers.enumerated() {
            AppLog.info("Drop", "\(place), Teil \(index + 1) von \(providers.count): \(provider.registeredTypeIdentifiers.joined(separator: ", ")) · Name: \(provider.suggestedName == nil ? "keiner" : "vorhanden")")
        }
        var handled = false
        for provider in providers {
            let suggested = provider.suggestedName
            let types = provider.registeredTypeIdentifiers.joined(separator: ", ")
            if let mailType = provider.registeredTypeIdentifiers.first(where: { identifier in
                UTType(identifier)?.conforms(to: .emailMessage) ?? false
            }) {
                handled = true
                // Das neue Outlook liefert beim Ziehen nicht immer eine lesbare Mail-Datei. Dann helfen der vorgeschlagene
                // Name oder mitgelieferter Text. Was ankam, steht (ohne Inhalt) im Protokoll.
                let hasText = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                AppLog.info("Mail-Drop", "Lade \(mailType) …")
                _ = provider.loadFileRepresentation(forTypeIdentifier: mailType) { url, error in
                    let data = url.flatMap { try? Data(contentsOf: $0) }
                    let header = data.map(EmailHeaderParser.parse)
                    let fileName = url?.lastPathComponent
                    let note = "Typen: \(types) · Name: \(suggested == nil ? "keiner" : "vorhanden") · Datei: .\(url?.pathExtension ?? "–"), \(data?.count ?? 0) Bytes, beginnt mit \(signature(data)) · Betreff \(header?.subject == nil ? "nicht gefunden" : "gefunden") · Fehler: \(describe(error))"
                    let title = MailDropTitle.best(subject: header?.subject, suggestedName: suggested, fileName: fileName, text: nil)
                    Task { @MainActor in
                        AppLog.info("Mail-Drop", note)
                        if title == nil, hasText {
                            _ = provider.loadObject(ofClass: String.self) { text, _ in
                                let fromText = MailDropTitle.best(subject: nil, suggestedName: nil, fileName: nil, text: text)
                                Task { @MainActor in
                                    model.addMailTask(subject: fromText, from: header?.from, link: nil, plannedDate: plannedDate)
                                }
                            }
                        } else {
                            model.addMailTask(subject: title, from: header?.from, link: nil, plannedDate: plannedDate)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url else {
                        let failure = describe(error)
                        Task { @MainActor in AppLog.warning("Mail-Drop", "Datei-Link nicht lesbar: \(failure)") }
                        return
                    }
                    // Das neue Outlook legt statt eines Links den Quelltext der Mail ab („Received: …“)
                    guard url.isFileURL else {
                        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            let header = data.flatMap(MailDropPayload.mailHeader(fromFileURLData:))
                            let title = MailDropTitle.best(subject: header?.subject, suggestedName: suggested, fileName: nil, text: nil)
                            let note = "Mail als Quelltext statt Datei-Link: \(data?.count ?? 0) Bytes · Betreff \(header?.subject == nil ? "nicht gefunden" : "gefunden") · Absender \(header?.from == nil ? "nicht gefunden" : "gefunden")"
                            Task { @MainActor in
                                AppLog.info("Mail-Drop", note)
                                if header != nil || title != nil {
                                    model.addMailTask(subject: title, from: header?.from, link: nil, plannedDate: plannedDate)
                                } else {
                                    model.reportUnreadableDrop()
                                }
                            }
                        }
                        return
                    }
                    let isMail = ["eml", "msg", "emlx"].contains(url.pathExtension.lowercased())
                    let data = isMail ? try? Data(contentsOf: url) : nil
                    let header = data.map(EmailHeaderParser.parse)
                    let note = "Datei: .\(url.pathExtension), \(data?.count ?? 0) Bytes, beginnt mit \(signature(data)) · Betreff \(header?.subject == nil ? "nicht gefunden" : "gefunden")"
                    let plainNote = "Datei ohne Mail-Endung: .\(url.pathExtension.isEmpty ? "–" : url.pathExtension), Name \(url.deletingPathExtension().lastPathComponent.count) Zeichen, Schema \(url.scheme ?? "–")"
                    Task { @MainActor in
                        if isMail {
                            AppLog.info("Mail-Drop", note)
                            let title = MailDropTitle.best(subject: header?.subject, suggestedName: nil, fileName: url.lastPathComponent, text: nil)
                            model.addMailTask(subject: title, from: header?.from, link: nil, plannedDate: plannedDate)
                        } else {
                            AppLog.info("Mail-Drop", plainNote)
                            model.addMailTask(subject: url.deletingPathExtension().lastPathComponent, from: nil, link: url.absoluteString, plannedDate: plannedDate)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        AppLog.info("Drop", "Link mit Schema \(url.scheme ?? "–")")
                        model.addLinkTask(url, plannedDate: plannedDate)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in
                        // Eine aus Tagwerk gezogene Aufgabe kommt als ID: an den Tag (oder zurück in den Eingang) legen.
                        if let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)), model.task(id) != nil {
                            model.move(id, to: plannedDate, before: nil)
                        } else {
                            AppLog.info("Drop", "Text mit \(text.count) Zeichen")
                            model.addTextTask(text, plannedDate: plannedDate)
                        }
                    }
                }
            } else if let otherType = provider.registeredTypeIdentifiers.first {
                // Unbekanntes Format (z. B. eine versprochene Datei): trotzdem versuchen, eine Mail daraus zu lesen.
                handled = true
                _ = provider.loadFileRepresentation(forTypeIdentifier: otherType) { url, error in
                    let data = url.flatMap { try? Data(contentsOf: $0) }
                    let header = data.map(EmailHeaderParser.parse)
                    let note = "Unbekanntes Format \(otherType) · Typen: \(types) · Datei: .\(url?.pathExtension ?? "–"), \(data?.count ?? 0) Bytes, beginnt mit \(signature(data)) · Betreff \(header?.subject == nil ? "nicht gefunden" : "gefunden") · Fehler: \(describe(error))"
                    let title = MailDropTitle.best(subject: header?.subject, suggestedName: suggested, fileName: url?.lastPathComponent, text: nil)
                    let looksLikeMail = header?.subject != nil || header?.from != nil
                    Task { @MainActor in
                        AppLog.info("Mail-Drop", note)
                        if looksLikeMail || title != nil {
                            model.addMailTask(subject: title, from: header?.from, link: nil, plannedDate: plannedDate)
                        } else {
                            model.reportUnreadableDrop()
                        }
                    }
                }
            }
        }
        if !handled { AppLog.warning("Drop", "Kein passendes Format, nichts angelegt") }
        return handled
    }

    /// Fehler kurz und ohne Inhalt fürs Protokoll.
    static func describe(_ error: Error?) -> String {
        guard let error else { return "keiner" }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

    /// Die ersten Bytes als Hex, um das Format zu erkennen (z. B. D0CF11E0 = Outlook-.msg), ohne Inhalt zu protokollieren.
    static func signature(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "–" }
        return data.prefix(4).map { String(format: "%02X", $0) }.joined()
    }
}
