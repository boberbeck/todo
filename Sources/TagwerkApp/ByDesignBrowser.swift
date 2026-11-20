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
                return collected
            }
        }
        return collected
    }

    private func pageHasPasswordField() async -> Bool {
        let result = try? await webView?.evaluateJavaScript("document.querySelector('input[type=\"password\"]') !== null") as? Bool
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
        if let json = try? await webView.evaluateJavaScript(ByDesignDemoPage.extractionScript) as? String,
           let data = json.data(using: .utf8),
           let page = try? JSONDecoder().decode(PageContent.self, from: data) {
            found = SAPImport.rows(fromCells: page.rows)
            if found.isEmpty {
                found = SAPImport.rows(fromText: page.text)
            }
        }
        if found.isEmpty, allowsTextRecognition, let image = await snapshot(of: webView) {
            source = "Texterkennung"
            found = (try? await ScreenTextReader.taskRows(from: image)) ?? []
        }

        let before = collected.count
        merge(found)
        let added = collected.count - before
        if found.isEmpty {
            status = "Auf dieser Seite keine Aufgabennummern gefunden. Ist die Liste mit „Aufgabennummer“ offen?"
        } else {
            status = "\(found.count) Aufgaben gelesen (\(source)), \(added) davon neu. Lange Liste? Weiterblättern und erneut holen."
        }
        return found.count
    }

    /// Bekannte Nummern werden ergänzt (z. B. ein Name, der beim ersten Lesen fehlte).
    private func merge(_ rows: [SAPTaskRow]) {
        for row in rows {
            if let index = collected.firstIndex(where: { $0.code == row.code }) {
                var existing = collected[index]
                if existing.title.isEmpty || existing.title.count < row.title.count, !row.title.isEmpty { existing.title = row.title }
                if existing.customerName == nil { existing.customerName = row.customerName }
                if existing.projectName == nil { existing.projectName = row.projectName }
                collected[index] = existing
            } else {
                collected.append(row)
            }
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

    private struct PageContent: Decodable {
        let rows: [[String]]
        let text: String
    }
}

/// Fenster mit ByDesign.
struct ByDesignBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Preferences.bydesignURLKey) private var savedAddress = ""
    @AppStorage(Preferences.bydesignTaskListURLKey) private var taskListAddress = ""
    @State private var browser = ByDesignBrowserModel()
    @State private var address = ""
    @State private var isAutomaticRun = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
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
                    .onSubmit(open)
                Button("Öffnen", action: open)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    taskListAddress = browser.currentURL
                } label: {
                    Label(taskListAddress == browser.currentURL && !taskListAddress.isEmpty ? "Liste gemerkt" : "Diese Liste merken",
                          systemImage: taskListAddress == browser.currentURL && !taskListAddress.isEmpty ? "bookmark.fill" : "bookmark")
                }
                .disabled(browser.currentURL.isEmpty || browser.currentURL.hasPrefix("about:"))
                .help("Diese Seite öffnet Tagwerk beim automatischen Abruf")
            }
            .padding(10)

            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(browser.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                if !browser.collected.isEmpty {
                    Text("\(browser.collected.count) gesammelt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Leeren") { browser.reset() }
                }
                Button {
                    Task { await browser.readTasks() }
                } label: {
                    Label(browser.isReading ? "Liest …" : "Aufgaben holen", systemImage: "square.and.arrow.down")
                }
                .disabled(browser.isReading)
                .help("Liest die Aufgabennummern und Namen der sichtbaren Liste")
                Button {
                    model.sapSyncRows = browser.collected
                    model.showsSAPSync = true
                    model.selection = .customers
                    dismissWindow(id: "bydesign")
                } label: {
                    Label("Zum Abgleich", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(browser.collected.isEmpty)
                .help("Projekten Kunden zuordnen und als PSP-Elemente übernehmen")
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
            // Im Build: Beispielseite lesen, einmal über den Seiteninhalt und einmal per Texterkennung
            guard SnapshotMode.directory != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            let count = await browser.readTasks()
            SnapshotMode.log("ByDesign-Beispiel aus dem Seiteninhalt: \(count) Aufgaben \(browser.collected.map(\.code))")
            if let image = await browser.pageImage(), let rows = try? await ScreenTextReader.taskRows(from: image) {
                SnapshotMode.log("ByDesign-Beispiel per Texterkennung: \(rows.map(\.code)) \(rows.map(\.title))")
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
        let cells = try await cells(from: image)
        let repaired = cells.map { $0.map(SAPImport.repairOCRCell) }
        var rows = SAPImport.rows(fromCells: repaired)
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
            return group(items)
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
    /// Sammelt Tabellenzeilen (auch ARIA-Raster aus Div-Elementen) und den Text der Seite samt Rahmen.
    static let extractionScript = """
    (() => {
      const rows = [];
      const texts = [];
      const cellSelector = '[role="gridcell"], [role="cell"], [role="columnheader"], [role="rowheader"], td, th';
      const visit = (doc) => {
        try {
          if (doc.body) { texts.push(doc.body.innerText || ''); }
          doc.querySelectorAll('[role="row"], tr').forEach((row) => {
            const cells = Array.from(row.querySelectorAll(cellSelector))
              .filter((cell) => cell.closest('[role="row"], tr') === row)
              .map((cell) => (cell.innerText || cell.textContent || '').trim());
            if (cells.length > 0) { rows.push(cells); }
          });
          doc.querySelectorAll('iframe, frame').forEach((frame) => {
            try { if (frame.contentDocument) { visit(frame.contentDocument); } } catch (error) {}
          });
        } catch (error) {}
      };
      visit(document);
      return JSON.stringify({ rows: rows, text: texts.join('\\n') });
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

    static let html = """
    <!doctype html><html lang="de"><head><meta charset="utf-8"><title>Meine Aufgaben</title>
    <style>
      body { font: 15px -apple-system, Helvetica, sans-serif; margin: 0; color: #1d2d3e; background: #f5f6f7; }
      header { background: #354a5f; color: white; padding: 12px 20px; font-size: 16px; }
      main { padding: 20px; } .toolbar { margin-bottom: 12px; color: #556b82; }
      .grid { background: white; border: 1px solid #d9d9d9; border-radius: 6px; display: table; width: 100%; }
      .row { display: table-row; } .cell { display: table-cell; padding: 10px 14px; border-bottom: 1px solid #eee; }
      .head .cell { font-weight: 600; background: #fafafa; }
    </style></head><body>
    <header>SAP Business ByDesign · Beispiel</header>
    <main><div class="toolbar">Gruppieren nach: Kategorie</div>
    <div class="grid" role="grid">
      <div class="row head" role="row"><div class="cell" role="columnheader">Kategorie</div><div class="cell" role="columnheader">Aufgabennummer</div><div class="cell" role="columnheader">Aufgabenname</div><div class="cell" role="columnheader">Projekt</div></div>
      <div class="row" role="row"><div class="cell" role="gridcell">Projektaufgabenbestätigung</div><div class="cell" role="gridcell">CPSO8643-1</div><div class="cell" role="gridcell">Wartungsvertrag 2026</div><div class="cell" role="gridcell">CPSO8643</div></div>
      <div class="row" role="row"><div class="cell" role="gridcell">Projektaufgabenbestätigung</div><div class="cell" role="gridcell">CPSO8643-2</div><div class="cell" role="gridcell">Störungen und Notfälle</div><div class="cell" role="gridcell">CPSO8643</div></div>
      <div class="row" role="row"><div class="cell" role="gridcell">Projektaufgabenbestätigung</div><div class="cell" role="gridcell">CPSO8643-5</div><div class="cell" role="gridcell">Migration Exchange Online</div><div class="cell" role="gridcell">CPSO8643</div></div>
      <div class="row" role="row"><div class="cell" role="gridcell">Projektaufgabenbestätigung</div><div class="cell" role="gridcell">CPSO8710-2</div><div class="cell" role="gridcell">Rollout Arbeitsplätze</div><div class="cell" role="gridcell">CPSO8710</div></div>
    </div></main></body></html>
    """
}
