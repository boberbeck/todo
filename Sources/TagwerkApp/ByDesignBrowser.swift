import AppKit
import Observation
import SwiftUI
import TagwerkCore
import Vision
import WebKit

/// ByDesign in einem eigenen Fenster: anmelden wie im Browser, Aufgabenliste öffnen,
/// „Aufgaben holen“ liest die Tabelle von der Seite. Tagwerk speichert kein Passwort;
/// die Anmeldung bleibt wie in Safari als Cookie auf diesem Mac.
@MainActor
@Observable
final class ByDesignBrowserModel {
    private(set) var collected: [SAPTaskRow] = []
    private(set) var status = "Melde dich an und öffne die Liste deiner Aufgaben."
    private(set) var isReading = false
    private(set) var currentURL: String = ""
    private(set) var canGoBack = false
    @ObservationIgnored weak var webView: WKWebView?
    /// Liefert Benutzer und Passwort aus dem Schlüsselbund, falls hinterlegt.
    @ObservationIgnored var credentials: () -> (user: String, password: String)? = { nil }
    /// Nur auf diesem Rechner (Host der gespeicherten ByDesign-Adresse) wird das Passwort eingesetzt.
    @ObservationIgnored var allowedHost: String?
    @ObservationIgnored private var lastLoginAttempt: Date?
    @ObservationIgnored private(set) var didSubmitLogin = false

    func load(_ address: String) {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text) else { return }
        webView?.load(URLRequest(url: url))
    }

    func loadDemoPage() {
        webView?.loadHTMLString(ByDesignDemoPage.html, baseURL: nil)
    }

    func updateNavigation() {
        currentURL = webView?.url?.absoluteString ?? ""
        canGoBack = webView?.canGoBack ?? false
    }

    private(set) var isLoginPage = false
    var hasPage: Bool { !currentURL.isEmpty && !currentURL.hasPrefix("about:") }

    /// Schaut alle zwei Sekunden auf die Seite: Anmeldeseite? Aufgabennummern zu sehen? Sammelt still mit.
    func watchPage() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard let webView, !isReading else { continue }
            _ = webView
            isLoginPage = await pageHasPasswordField()
            if !isLoginPage { await readFromPage() }
        }
    }

    /// Scrollt die Liste Stück für Stück durch und sammelt dabei, bis drei Schritte lang nichts Neues kommt.
    /// ByDesign lädt nur die sichtbaren Zeilen; so kommen auch die weiter unten dazu.
    @discardableResult
    func collectAll() async -> Int {
        guard let webView, !isReading else { return collected.count }
        isReading = true
        defer { isReading = false }
        status = "Scrollt durch die Liste und sammelt …"
        var quietSteps = 0
        for _ in 0..<80 {
            let before = collected.count
            await readFromPage()
            let moved = (await webView.tagwerkEvaluate(ByDesignDemoPage.scrollScript) as? Bool) ?? false
            try? await Task.sleep(for: .milliseconds(800))
            await readFromPage()
            quietSteps = collected.count > before ? 0 : quietSteps + 1
            if !moved && quietSteps >= 1 { break }
            if quietSteps >= 3 { break }
        }
        _ = await webView.tagwerkEvaluate(ByDesignDemoPage.scrollToTopScript)
        status = "\(collected.count) Aufgaben eingesammelt."
        return collected.count
    }

    /// Liest die Seite ohne Texterkennung und sammelt die Treffer.
    private func readFromPage() async {
        guard let page = await pageContent() else { return }
        merge(Self.rows(from: page))
    }

    private func pageContent() async -> PageContent? {
        guard let webView,
              let json = await webView.tagwerkEvaluate(ByDesignDemoPage.extractionScript) as? String,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PageContent.self, from: data)
    }

    /// Drei Lesarten der Seite, die ergiebigste zählt: nach Lage auf dem Bildschirm (wie ein Mensch liest),
    /// nach Tabellenzeilen im Seitenaufbau und als reiner Text.
    static func rows(from page: PageContent) -> [SAPTaskRow] {
        let layout = SAPImport.rows(fromLayout: page.boxes ?? [])
        let cells = SAPImport.rows(fromCells: page.rows)
        let best = SAPImport.best(of: [layout, cells])
        return best.isEmpty ? SAPImport.rows(fromText: page.text) : best
    }

    /// Seite fertig geladen: bei einer Anmeldeseite Benutzer und Passwort einsetzen.
    func pageLoaded() {
        updateNavigation()
        Task { await tryAutoLogin() }
    }

    private func tryAutoLogin() async {
        guard let webView, let host = webView.url?.host?.lowercased(), isTrusted(host),
              let login = credentials() else { return }
        if let lastLoginAttempt, Date().timeIntervalSince(lastLoginAttempt) < 30 { return }
        let result = try? await webView.callAsyncJavaScript(
            ByDesignDemoPage.loginScript,
            arguments: ["user": login.user, "password": login.password],
            in: nil,
            contentWorld: .defaultClient
        ) as? String
        if let result, result != "kein-formular" {
            lastLoginAttempt = Date()
            didSubmitLogin = true
            status = "Angemeldet mit gespeichertem Benutzer …"
        }
    }

    /// Die ByDesign-Adresse selbst oder die Anmeldeseiten von SAP.
    private func isTrusted(_ host: String) -> Bool {
        if let allowedHost, host == allowedHost.lowercased() { return true }
        return host.hasSuffix(".sapbydesign.com") || host.hasSuffix(".businessbydesign.cloud.sap")
            || host.hasSuffix(".accounts.ondemand.com") || host.hasSuffix(".accounts.cloud.sap")
    }

    /// Automatischer Abruf: gemerkte Liste öffnen, warten, bis Aufgabennummern zu sehen sind.
    func fetchAutomatically(from address: String) async -> [SAPTaskRow] {
        collected = []
        load(address)
        var reloadedAfterLogin = false
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(3))
            if didSubmitLogin, !reloadedAfterLogin, let host = webView?.url?.host, isTrusted(host.lowercased()),
               !(await pageHasPasswordField()) {
                // Nach der Anmeldung landet ByDesign oft auf der Startseite: Liste noch einmal öffnen
                reloadedAfterLogin = true
                load(address)
                continue
            }
            if await readTasks(allowsTextRecognition: false) > 0 {
                await collectAll()
                return collected
            }
        }
        return collected
    }

    private func pageHasPasswordField() async -> Bool {
        let result = await webView?.tagwerkEvaluate("document.querySelector('input[type=\"password\"]') !== null") as? Bool
        return result ?? false
    }

    func reset() {
        collected = []
        status = "Liste geleert."
    }

    /// Liest die sichtbare Tabelle: erst aus dem Seiteninhalt, sonst per Texterkennung aus einem Bild der Seite.
    @discardableResult
    func readTasks(allowsTextRecognition: Bool = true) async -> Int {
        guard let webView, !isReading else { return 0 }
        isReading = true
        defer { isReading = false }

        var found: [SAPTaskRow] = []
        var source = "Seite"
        if let page = await pageContent() {
            found = Self.rows(from: page)
        }
        if found.isEmpty, allowsTextRecognition, let image = await snapshot(of: webView) {
            source = "Texterkennung"
            found = (try? await ScreenTextReader.taskRows(from: image)) ?? []
        }

        let before = collected.count
        merge(found)
        let added = collected.count - before
        if found.isEmpty {
            status = "Auf dieser Seite keine Aufgabennummern gefunden. Ist die Liste mit den Aufgaben (Task ID) offen?"
        } else {
            let activities = found.filter { !($0.activity ?? "").isEmpty }.count
            let detail = activities > 0 ? ", \(activities) mit Tätigkeit" : ", ohne Tätigkeit (Spalte „Activity“ nicht gefunden)"
            status = "\(found.count) Einträge gelesen (\(source)\(detail)), \(max(0, added)) davon neu. Lange Liste? „Alle einsammeln“ scrollt durch."
        }
        return found.count
    }

    /// Eine Zeile je Aufgabe und Tätigkeit. Bekannte werden ergänzt (z. B. ein Name, der beim ersten Lesen fehlte).
    private func merge(_ rows: [SAPTaskRow]) {
        guard !rows.isEmpty else { return }
        collected = SAPImport.merged(collected + rows)
    }

    /// Speichert, was Tagwerk auf der Seite liest (Tabellenzeilen und Text), in „Downloads“.
    /// Hilft, das Erkennen auf die echte ByDesign-Tabelle abzustimmen.
    func savePageForDiagnosis() async -> URL? {
        guard let webView,
              let json = await webView.tagwerkEvaluate(ByDesignDemoPage.extractionScript) as? String else { return nil }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent("Tagwerk-ByDesign-Seite.json")
        do {
            try Data(json.utf8).write(to: url)
            status = "Gesichert: \(url.lastPathComponent) in Downloads. Bitte vor dem Weitergeben ansehen; sie enthält deine Aufgabenliste."
            return url
        } catch {
            status = "Sichern fehlgeschlagen: \(error.localizedDescription)"
            return nil
        }
    }

    /// Bild der sichtbaren Seite (für die Texterkennung).
    func pageImage() async -> CGImage? {
        guard let webView else { return nil }
        return await snapshot(of: webView)
    }

    private func snapshot(of webView: WKWebView) async -> CGImage? {
        await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, _ in
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    struct PageContent: Decodable {
        let rows: [[String]]
        let text: String
        /// Text-Schnipsel mit ihrer Lage auf dem Bildschirm
        let boxes: [TextBox]?
    }
}

/// Fenster mit ByDesign.
struct ByDesignBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.bydesignURLKey) private var savedAddress = ""
    @AppStorage(Preferences.bydesignTaskListURLKey) private var taskListAddress = ""
    @State private var browser = ByDesignBrowserModel()
    @State private var address = ""
    @State private var isAutomaticRun = false

    var body: some View {
        let count = browser.collected.count
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                step(1, "Anmelden", done: browser.hasPage && !browser.isLoginPage)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                step(2, count == 0 ? "Aufgabenliste öffnen" : "\(count) Aufgaben erkannt", done: count > 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                step(3, "Übernehmen", done: false)
                Spacer()
                Button {
                    Task { await browser.collectAll() }
                } label: {
                    Label(browser.isReading ? "Sammelt …" : "Alle einsammeln", systemImage: "arrow.down.to.line")
                }
                .controlSize(.large)
                .disabled(!browser.hasPage || browser.isLoginPage || browser.isReading)
                .help("Scrollt selbst durch die Liste, bis alle Aufgaben erkannt sind")
                Button {
                    take()
                } label: {
                    Text(count == 0 ? "Aufgaben übernehmen" : "\(count) Aufgaben übernehmen")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(count == 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                Button {
                    browser.webView?.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browser.canGoBack)
                .help("Zurück")
                Button {
                    browser.webView?.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Neu laden")
                TextField("Adresse von ByDesign, z. B. https://my123456.sapbydesign.com", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit(open)
                Button("Öffnen", action: open)
                    .controlSize(.small)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                if count > 0 {
                    Button("Neu anfangen") { browser.reset() }
                        .controlSize(.small)
                        .help("Erkannte Aufgaben verwerfen")
                }
                Button {
                    Task {
                        if let url = await browser.savePageForDiagnosis() {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("Seite sichern (Fehlersuche): speichert, was Tagwerk auf der Seite liest, in Downloads")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))

            Divider()

            ByDesignWebView(browser: browser)
        }
        .frame(minWidth: 900, minHeight: 620)
        .onAppear {
            address = savedAddress
            browser.credentials = { model.byDesignCredentials() }
            browser.allowedHost = URL(string: savedAddress)?.host
            if SnapshotMode.usesDemoData {
                browser.loadDemoPage()
            } else if model.sapAutoFetchActive {
                runAutomatically()
            } else if !taskListAddress.isEmpty {
                browser.load(taskListAddress)
            } else if !savedAddress.isEmpty {
                browser.load(savedAddress)
            }
        }
        .onChange(of: model.sapAutoFetchActive) {
            if model.sapAutoFetchActive { runAutomatically() }
        }
        .task {
            await browser.watchPage()
        }
        .task {
            // Im Build: Beispielseite lesen, einmal über den Seiteninhalt und einmal per Texterkennung
            guard SnapshotMode.directory != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            let count = await browser.readTasks()
            SnapshotMode.log("ByDesign-Beispiel aus dem Seiteninhalt: \(count) Einträge")
            for row in browser.collected {
                SnapshotMode.log("  \(row.code) | \(row.title) | \(row.activity ?? "-") | \(row.project)")
            }
            if let image = await browser.pageImage(), let rows = try? await ScreenTextReader.taskRows(from: image) {
                SnapshotMode.log("ByDesign-Beispiel per Texterkennung: \(rows.count) Einträge")
                for row in rows {
                    SnapshotMode.log("  \(row.code) | \(row.title) | \(row.activity ?? "-")")
                }
            } else {
                SnapshotMode.log("Texterkennung ohne Ergebnis")
            }
        }
        .onChange(of: browser.currentURL) {
            if address.isEmpty || !browser.currentURL.hasPrefix("about:") {
                address = browser.currentURL.isEmpty ? address : browser.currentURL
            }
        }
    }

    private func step(_ number: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(title)
                .foregroundStyle(done ? Color.primary : Color.secondary)
        }
        .font(.callout.weight(.medium))
    }

    private var hint: String {
        if isAutomaticRun {
            return "Automatischer Abruf läuft: Tagwerk meldet sich an, sammelt die Aufgaben ein und schließt dieses Fenster danach selbst. Neue Projekte zeigt es dir anschließend im SAP-Abgleich."
        }
        if !browser.hasPage {
            return "Trag oben die Adresse von ByDesign ein (wie im Browser) und klick „Öffnen“."
        }
        if browser.isLoginPage {
            return model.hasByDesignPassword
                ? "Tagwerk meldet dich mit Benutzer und Passwort aus den Einstellungen an …"
                : "Melde dich an wie im Browser. Mit Benutzer und Passwort unter Einstellungen › Buchung geht das künftig von selbst."
        }
        if browser.collected.isEmpty {
            return "Öffne die Liste mit deinen Aufgaben (die mit der Spalte „Aufgabennummer“). Tagwerk erkennt sie von selbst."
        }
        return "ByDesign zeigt nur die sichtbaren Zeilen. „Alle einsammeln“ scrollt selbst durch die Liste (oder scroll von Hand, Tagwerk sammelt mit). Dann „übernehmen“; die Liste wird für den automatischen Abruf gemerkt."
    }

    /// Erkannte Aufgaben in den Abgleich geben und die Seite für den automatischen Abruf merken.
    private func take() {
        if !browser.currentURL.isEmpty, !browser.currentURL.hasPrefix("about:") {
            taskListAddress = browser.currentURL
        }
        model.sapSyncRows = browser.collected
        model.showsSAPSync = true
        model.selection = .customers
        dismissWindow(id: "bydesign")
    }

    /// Automatischer Abruf: anmelden, gemerkte Liste lesen, bekannte Projekte übernehmen, Fenster schließen.
    private func runAutomatically() {
        guard !isAutomaticRun else { return }
        let target = taskListAddress.isEmpty ? savedAddress : taskListAddress
        guard !target.isEmpty else {
            model.reportSAPAutoFetch("Keine Aufgabenliste gemerkt. Öffne sie einmal im ByDesign-Fenster und klicke „Diese Liste merken“.")
            model.sapAutoFetchActive = false
            return
        }
        isAutomaticRun = true
        Task {
            let rows = await browser.fetchAutomatically(from: target)
            if rows.isEmpty {
                model.reportSAPAutoFetch("Keine Aufgaben gefunden. Anmeldung fehlgeschlagen oder die Liste hat sich geändert; einmal von Hand im ByDesign-Fenster prüfen.")
                model.sapAutoFetchActive = false
                isAutomaticRun = false
                return
            }
            model.applySAPAutomatically(rows)
            model.sapAutoFetchActive = false
            isAutomaticRun = false
            dismissWindow(id: "bydesign")
            if model.showsSAPSync {
                // Neue Projekte zuordnen: Hauptfenster mit dem Abgleich nach vorn
                openWindow(id: "main")
                NSApp.activate()
            }
        }
    }

    private func open() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Nur der Anfang der Adresse wird gemerkt, damit beim nächsten Mal die Anmeldeseite kommt.
        if let url = URL(string: text.lowercased().hasPrefix("http") ? text : "https://" + text), let host = url.host {
            savedAddress = "\(url.scheme ?? "https")://\(host)"
        }
        browser.load(text)
    }
}

/// WKWebView für SwiftUI. Nutzt den normalen Datenspeicher, damit die Anmeldung erhalten bleibt.
struct ByDesignWebView: NSViewRepresentable {
    let browser: ByDesignBrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Manche Anmeldeseiten mögen eingebettete Browser nicht; als Safari auftreten.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        browser.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let browser: ByDesignBrowserModel

        init(browser: ByDesignBrowserModel) {
            self.browser = browser
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            browser.pageLoaded()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            browser.updateNavigation()
        }

        /// Fenster, die ByDesign neu öffnen will, im selben Fenster laden.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

/// Texterkennung mit dem Vision-Framework von macOS, z. B. für ein Bildschirmfoto der Aufgabenliste.
enum ScreenTextReader {
    static func taskRows(from image: CGImage) async throws -> [SAPTaskRow] {
        let items = try await recognize(image)
        let boxes = items.map { item in
            TextBox(
                text: SAPImport.repairOCRCell(item.text),
                x: item.box.minX * Double(image.width),
                y: (1 - item.box.maxY) * Double(image.height),
                width: item.box.width * Double(image.width),
                height: item.box.height * Double(image.height)
            )
        }
        let repaired = group(items).map { $0.map(SAPImport.repairOCRCell) }
        var rows = SAPImport.best(of: [SAPImport.rows(fromLayout: boxes), SAPImport.rows(fromCells: repaired)])
        if rows.isEmpty {
            rows = SAPImport.rows(fromLines: repaired.map { $0.joined(separator: " ") })
        }
        return SAPImport.repairOCRCodes(rows)
    }

    static func taskRows(fromImageAt url: URL) async throws -> [SAPTaskRow] {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return try await taskRows(from: image)
    }

    /// Erkannter Text, nach Zeilen und von links nach rechts geordnet.
    static func cells(from image: CGImage) async throws -> [[String]] {
        group(try await recognize(image))
    }

    /// Erkannter Text mit Lage (Vision zählt von unten links, Werte zwischen 0 und 1).
    private static func recognize(_ image: CGImage) async throws -> [(box: CGRect, text: String)] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["de-DE", "en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let items = (request.results ?? []).compactMap { observation -> (box: CGRect, text: String)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return (observation.boundingBox, text)
            }
            return items
        }.value
    }

    /// Fasst Textstücke mit ähnlicher Höhe zu Zeilen zusammen (Vision zählt von unten).
    private static func group(_ items: [(box: CGRect, text: String)]) -> [[String]] {
        let sorted = items.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(box: CGRect, text: String)]] = []
        for item in sorted {
            if let last = rows.last?.first, abs(last.box.midY - item.box.midY) < max(last.box.height, item.box.height) * 0.6 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text) }
    }
}

/// Beispielseite für Bildschirmfotos und den Test im Build, aufgebaut wie eine ByDesign-Tabelle.
enum ByDesignDemoPage {
    /// Sammelt Tabellenzeilen (auch ARIA-Raster aus Div-Elementen), den Text der Seite samt Rahmen
    /// und jedes Text-Schnipsel mit seiner Lage auf dem Bildschirm (für das Lesen wie ein Mensch).
    static let extractionScript = """
    (() => {
      const rows = [];
      const texts = [];
      const boxes = [];
      const cellSelector = '[role="gridcell"], [role="cell"], [role="columnheader"], [role="rowheader"], td, th';
      const skipTags = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|OPTION|TITLE|HEAD)$/;
      const layout = (doc, offsetX, offsetY) => {
        const win = doc.defaultView;
        const styles = new Map();
        const styleOf = (el) => {
          if (!styles.has(el)) { styles.set(el, win.getComputedStyle(el)); }
          return styles.get(el);
        };
        const clips = new Map();
        const clipOf = (el) => {
          if (!el || el === doc.body || el === doc.documentElement) { return null; }
          if (clips.has(el)) { return clips.get(el); }
          let result = clipOf(el.parentElement);
          const style = styleOf(el);
          if (/(auto|scroll|hidden|clip)/.test(style.overflowX + ' ' + style.overflowY)) {
            const r = el.getBoundingClientRect();
            result = result
              ? { left: Math.max(result.left, r.left), top: Math.max(result.top, r.top), right: Math.min(result.right, r.right), bottom: Math.min(result.bottom, r.bottom) }
              : { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
          }
          clips.set(el, result);
          return result;
        };
        const hidden = (el) => {
          const style = styleOf(el);
          return style.visibility === 'hidden' || style.display === 'none' || parseFloat(style.opacity) === 0;
        };
        const push = (raw, left, top, right, height, el) => {
          const text = (raw || '').replace(/\\s+/g, ' ').trim();
          if (!text || right - left <= 0 || height <= 0) { return; }
          const clip = clipOf(el);
          if (clip) {
            const mid = top + height / 2;
            if (mid < clip.top || mid > clip.bottom || left >= clip.right || right <= clip.left) { return; }
            left = Math.max(left, clip.left);
            right = Math.min(right, clip.right);
          }
          if (right - left <= 0) { return; }
          boxes.push({ text: text.slice(0, 300), x: left + offsetX, y: top + offsetY, width: right - left, height: height });
        };
        if (doc.body) {
          const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, null);
          const range = doc.createRange();
          let node;
          let count = 0;
          while ((node = walker.nextNode()) && count < 20000) {
            const parent = node.parentElement;
            if (!parent || skipTags.test(parent.tagName) || !node.nodeValue || !node.nodeValue.trim()) { continue; }
            range.selectNodeContents(node);
            const rects = range.getClientRects();
            if (!rects.length || hidden(parent)) { continue; }
            count += 1;
            const first = rects[0];
            let left = first.left;
            let right = first.right;
            for (const r of rects) { left = Math.min(left, r.left); right = Math.max(right, r.right); }
            push(node.nodeValue, left, first.top, right, first.height, parent);
          }
          doc.querySelectorAll('input, textarea').forEach((el) => {
            const type = (el.type || '').toLowerCase();
            if (['hidden', 'password', 'checkbox', 'radio', 'button', 'submit', 'image', 'file', 'reset'].includes(type) || !el.value) { return; }
            if (hidden(el)) { return; }
            const r = el.getBoundingClientRect();
            const height = Math.min(r.height, 24);
            push(el.value, r.left, r.top + (r.height - height) / 2, r.right, height, el);
          });
        }
      };
      const visit = (doc, offsetX, offsetY, depth) => {
        try {
          if (doc.body) { texts.push(doc.body.innerText || ''); }
          doc.querySelectorAll('[role="row"], tr').forEach((row) => {
            const cells = Array.from(row.querySelectorAll(cellSelector))
              .filter((cell) => cell.closest('[role="row"], tr') === row)
              .map((cell) => (cell.innerText || cell.textContent || '').trim());
            if (cells.length > 0) { rows.push(cells); }
          });
          try { layout(doc, offsetX, offsetY); } catch (error) {}
          if (depth > 4) { return; }
          doc.querySelectorAll('iframe, frame').forEach((frame) => {
            try {
              if (frame.contentDocument) {
                const r = frame.getBoundingClientRect();
                visit(frame.contentDocument, offsetX + r.left + frame.clientLeft, offsetY + r.top + frame.clientTop, depth + 1);
              }
            } catch (error) {}
          });
        } catch (error) {}
      };
      visit(document, 0, 0, 0);
      return JSON.stringify({ rows: rows, text: texts.join('\\n'), boxes: boxes });
    })()
    """

    /// Scrollt den größten scrollbaren Bereich, in dem Aufgabennummern stehen, ein Stück weiter.
    /// Gibt `true` zurück, wenn sich etwas bewegt hat. Schickt zusätzlich ein Mausrad-Ereignis,
    /// falls die Tabelle eine eigene Bildlaufleiste hat.
    static let scrollScript = """
    (() => {
      const pattern = /[A-Z]{2,}[A-Z0-9]*[0-9]+-[0-9]+/;
      const docs = [document];
      const addFrames = (doc) => {
        try {
          doc.querySelectorAll('iframe, frame').forEach((frame) => {
            try { if (frame.contentDocument) { docs.push(frame.contentDocument); addFrames(frame.contentDocument); } } catch (error) {}
          });
        } catch (error) {}
      };
      addFrames(document);
      let best = null;
      let grid = null;
      for (const doc of docs) {
        for (const el of doc.querySelectorAll('*')) {
          if (el.clientHeight < 80) { continue; }
          const text = el.innerText || '';
          if (!grid && el.getAttribute && (el.getAttribute('role') === 'grid' || el.tagName === 'TABLE') && pattern.test(text)) { grid = el; }
          if (el.scrollHeight <= el.clientHeight + 20) { continue; }
          const style = doc.defaultView.getComputedStyle(el);
          if (!/(auto|scroll|overlay)/.test(style.overflowY)) { continue; }
          if (!pattern.test(text)) { continue; }
          if (!best || el.clientHeight * el.clientWidth > best.clientHeight * best.clientWidth) { best = el; }
        }
      }
      const target = best || document.scrollingElement;
      let moved = false;
      if (target) {
        const before = target.scrollTop;
        target.scrollTop = before + Math.max(200, target.clientHeight * 0.8);
        target.dispatchEvent(new Event('scroll', { bubbles: true }));
        moved = target.scrollTop > before + 1;
      }
      const wheelTarget = grid || best;
      if (wheelTarget) {
        wheelTarget.dispatchEvent(new WheelEvent('wheel', { deltaY: 600, bubbles: true, cancelable: true }));
      }
      return moved;
    })()
    """

    static let scrollToTopScript = """
    (() => {
      document.querySelectorAll('*').forEach((el) => { if (el.scrollTop > 0) { el.scrollTop = 0; } });
      window.scrollTo(0, 0);
      return true;
    })()
    """

    /// Setzt Benutzer und Passwort in die Anmeldeseite und schickt sie ab. Argumente: user, password.
    static let loginScript = """
    const passwordField = document.querySelector('input[type="password"]');
    if (!passwordField) { return 'kein-formular'; }
    const scope = passwordField.form || document;
    const visible = (el) => el && el.offsetParent !== null && !el.disabled;
    const userField = scope.querySelector('#logonuidfield, input[name="sap-user"], input[name="j_username"], input[autocomplete="username"], input[type="email"]')
      || Array.from(scope.querySelectorAll('input')).find((el) => ['text', 'email', ''].includes((el.type || '').toLowerCase()) && visible(el));
    const setValue = (el, value) => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      setter.call(el, value);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    if (userField && !userField.value) { setValue(userField, user); }
    setValue(passwordField, password);
    const button = scope.querySelector('#LOGON_BUTTON, #LOGIN_LINK, #logOnFormSubmit, button[type="submit"], input[type="submit"]')
      || Array.from(scope.querySelectorAll('button, a[role="button"]')).find(visible);
    if (button) { button.click(); return 'abgeschickt'; }
    if (passwordField.form) { passwordField.form.submit(); return 'abgeschickt'; }
    return 'ausgefuellt';
    """

    /// Aufgebaut wie die englische ByDesign-Liste: feste Spalte mit der Task ID links, der Rest in einer
    /// eigenen Tabelle daneben, mehrere Activities je Aufgabe und „Group By…“ in der Werkzeugleiste.
    static let html = """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><title>My Work Packages</title>
    <style>
      body { font: 15px -apple-system, Helvetica, sans-serif; margin: 0; color: #1d2d3e; background: #f5f6f7; }
      header { background: #354a5f; color: white; padding: 12px 20px; font-size: 16px; }
      main { padding: 20px; } .toolbar { margin-bottom: 12px; color: #556b82; display: flex; gap: 24px; }
      .split { display: flex; background: white; border: 1px solid #d9d9d9; border-radius: 6px; overflow: hidden; }
      .scroll { overflow-x: auto; flex: 1; }
      table { border-collapse: collapse; } .scroll table { width: 100%; }
      th, td { height: 22px; padding: 9px 14px; border-bottom: 1px solid #eee; text-align: left; white-space: nowrap; }
      th { font-weight: 600; background: #fafafa; } .fixed { border-right: 1px solid #e5e5e5; }
      a { color: #0a6ed1; text-decoration: none; }
    </style></head><body>
    <header>SAP Business ByDesign · Example</header>
    <main><div class="toolbar"><span>Show: My Current Work Packages</span><span>Group By…</span><span>Personalize</span></div>
    <div class="split">
      <table class="fixed" role="grid">
        <thead><tr><th>Task ID</th></tr></thead>
        <tbody>
          <tr><td><a href="#">CPSO8643-1</a></td></tr>
          <tr><td><a href="#">CPSO8643-1</a></td></tr>
          <tr><td><a href="#">CPSO8643-2</a></td></tr>
          <tr><td><a href="#">CPSO8643-5</a></td></tr>
          <tr><td><a href="#">CPSO8710-2</a></td></tr>
          <tr><td><a href="#">CPSO9001-3</a></td></tr>
          <tr><td><a href="#">CPSO9001-3</a></td></tr>
        </tbody>
      </table>
      <div class="scroll"><table role="grid">
        <thead><tr><th>Work Package Task</th><th>Activity</th><th>Category</th><th>Project ID</th></tr></thead>
        <tbody>
          <tr><td><span>Maintenance Contract 2026</span></td><td>Consulting</td><td>Project Task</td><td>CPSO8643</td></tr>
          <tr><td><span>Maintenance Contract 2026</span></td><td>Remote Support</td><td>Project Task</td><td>CPSO8643</td></tr>
          <tr><td><span>Incidents and Emergencies</span></td><td>Remote Support</td><td>Project Task</td><td>CPSO8643</td></tr>
          <tr><td><span>Migration Exchange Online</span></td><td>Consulting</td><td>Project Task</td><td>CPSO8643</td></tr>
          <tr><td><span>Workstation Rollout</span></td><td>Installation</td><td>Project Task</td><td>CPSO8710</td></tr>
          <tr><td><span>Team Meeting</span></td><td>Internal Meeting</td><td>Project Task</td><td>CPSO9001</td></tr>
          <tr><td><span>Team Meeting</span></td><td>Training</td><td>Project Task</td><td>CPSO9001</td></tr>
        </tbody>
      </table></div>
    </div></main></body></html>
    """
}

extension WKWebView {
    /// Wie `evaluateJavaScript`, aber ohne den Absturz der async-Variante von WebKit,
    /// wenn die Seite keinen Wert liefert (z. B. mitten in einer Weiterleitung).
    func tagwerkEvaluate(_ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }
}
