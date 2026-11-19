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
enum DropImporter {
    static let acceptedTypes: [UTType] = [.emailMessage, .fileURL, .url, .plainText]

    @MainActor
    static func handle(_ providers: [NSItemProvider], model: AppModel) -> Bool {
        var handled = false
        for provider in providers {
            if let mailType = provider.registeredTypeIdentifiers.first(where: { identifier in
                UTType(identifier)?.conforms(to: .emailMessage) ?? false
            }) {
                handled = true
                _ = provider.loadFileRepresentation(forTypeIdentifier: mailType) { url, _ in
                    guard let url, let data = try? Data(contentsOf: url) else { return }
                    let header = EmailHeaderParser.parse(data)
                    Task { @MainActor in
                        model.addMailTask(subject: header.subject, from: header.from, link: nil)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let isMail = url.pathExtension.lowercased() == "eml"
                    let header = isMail ? (try? Data(contentsOf: url)).map(EmailHeaderParser.parse) : nil
                    Task { @MainActor in
                        if let header {
                            model.addMailTask(subject: header.subject, from: header.from, link: nil)
                        } else {
                            model.addMailTask(subject: url.deletingPathExtension().lastPathComponent, from: nil, link: url.absoluteString)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        model.addLinkTask(url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in
                        model.addTextTask(text)
                    }
                }
            }
        }
        return handled
    }
}
