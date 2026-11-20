import AppKit
import SwiftUI
import TagwerkCore

/// Einstellungen in Tabs, wie bei Mac-Apps üblich.
struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, focus, calendar, booking, manageEngine, claude, data
    }

    static let tabKey = "settingsTab"
    @AppStorage(SettingsView.tabKey) private var tab = Tab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
                .tag(Tab.general.rawValue)
            FocusSettings()
                .tabItem { Label("Fokus", systemImage: "scope") }
                .tag(Tab.focus.rawValue)
            CalendarSettings()
                .tabItem { Label("Kalender", systemImage: "calendar") }
                .tag(Tab.calendar.rawValue)
            BookingSettings()
                .tabItem { Label("Buchung", systemImage: "clock.badge.checkmark") }
                .tag(Tab.booking.rawValue)
            ManageEngineSettings()
                .tabItem { Label("ManageEngine", systemImage: "ticket") }
                .tag(Tab.manageEngine.rawValue)
            ClaudeSettings()
                .tabItem { Label("Claude", systemImage: "sparkles") }
                .tag(Tab.claude.rawValue)
            DataSettings()
                .tabItem { Label("Daten", systemImage: "externaldrive") }
                .tag(Tab.data.rawValue)
        }
        .frame(width: 620)
    }
}

// MARK: Bausteine

/// Zeile mit Beschriftung links und einem Eingabefeld mit Rahmen rechts.
/// So sieht man sofort, wo man tippen kann, und Platzhalter wirken nicht wie Werte.
struct SettingsField<Field: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var field: () -> Field

    var body: some View {
        LabeledContent {
            field()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Textfeld mit Rahmen für die Einstellungen.
struct SettingsTextField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat = 220
    var monospaced = false

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .font(monospaced ? .body.monospacedDigit() : .body)
            .frame(width: width)
    }
}

/// Erklärung unter einem Abschnitt.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func settingsPage(height: CGFloat) -> some View {
        formStyle(.grouped)
            .frame(width: 620, height: height)
    }
}

// MARK: Allgemein

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.workdayStartKey) private var workdayStart = Preferences.defaultWorkdayStart
    @AppStorage(Preferences.workdayEndKey) private var workdayEnd = Preferences.defaultWorkdayEnd
    @AppStorage(Preferences.planningOnLaunchKey) private var planningOnLaunch = true
    @AppStorage(Preferences.idleMinutesKey) private var idleMinutes = 10

    var body: some View {
        Form {
            Section {
                DatePicker("Beginn", selection: timeBinding($workdayStart), displayedComponents: .hourAndMinute)
                DatePicker("Ende", selection: timeBinding($workdayEnd), displayedComponents: .hourAndMinute)
            } header: {
                Text("Arbeitszeit")
            } footer: {
                SettingsFootnote("Daraus berechnet Tagwerk die freien Lücken zwischen deinen Terminen.")
            }

            Section("Tagesplanung") {
                Toggle("Beim ersten Öffnen am Tag zeigen", isOn: $planningOnLaunch)
            }

            Section {
                Picker("Bei Pause nachfragen nach", selection: $idleMinutes) {
                    Text("nie").tag(0)
                    ForEach([5, 10, 15, 30], id: \.self) { minutes in
                        Text("\(minutes) Minuten").tag(minutes)
                    }
                }
            } header: {
                Text("Pausen")
            } footer: {
                SettingsFootnote("Läuft ein Timer und du warst länger weg, fragt Tagwerk, ob die Zeit zählt.")
            }

            Section {
                LabeledContent("Schnell erfassen") {
                    Text("⌃ ⌥ Leertaste")
                        .font(.body.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                }
            } header: {
                Text("Erfassen")
            } footer: {
                SettingsFootnote("Funktioniert in jeder App. Mails ziehst du aus Outlook einfach in den Eingang; sie werden zur Aufgabe mit Betreff und Absender.")
            }
        }
        .settingsPage(height: 580)
        .onChange(of: workdayStart) { model.settingsChanged() }
        .onChange(of: workdayEnd) { model.settingsChanged() }
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { FreeTime.date(on: LocalDate.today(), minutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = FreeTime.minutesSinceMidnight($0) }
        )
    }
}

// MARK: Fokus

struct FocusSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.focusGoalMinutesKey) private var focusGoalMinutes = Preferences.defaultFocusGoalMinutes
    @AppStorage(FocusMusic.autoPlayKey) private var autoPlay = true
    @AppStorage(FocusMusic.pauseWithTimerKey) private var pauseWithTimer = true
    @AppStorage(FocusMusic.shuffleKey) private var shuffle = false

    var body: some View {
        let music = model.music
        Form {
            Section {
                LabeledContent("Tagesziel Fokuszeit") {
                    HStack(spacing: 6) {
                        Text("\(TimeMath.format(minutes: focusGoalMinutes)) h")
                            .monospacedDigit()
                        Stepper("Tagesziel Fokuszeit", value: $focusGoalMinutes, in: 30...720, step: 15)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Fokuszeit")
            } footer: {
                SettingsFootnote("Das Wochenziel im Kalender und im Rückblick ist das Fünffache.")
            }

            Section {
                LabeledContent("Playlist") {
                    HStack(spacing: 8) {
                        Picker("Playlist", selection: Binding(
                            get: { music.selectedPlaylist },
                            set: { music.selectedPlaylist = $0 }
                        )) {
                            Text("Keine Musik").tag(String?.none)
                            if let selected = music.selectedPlaylist, !music.playlists.contains(selected) {
                                Text(selected).tag(String?.some(selected))
                            }
                            ForEach(music.playlists, id: \.self) { name in
                                Text(name).tag(String?.some(name))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                        Button(music.isLoadingPlaylists ? "Lädt …" : "Playlists laden") {
                            music.loadPlaylists()
                        }
                        .disabled(music.isLoadingPlaylists)
                    }
                }
                Toggle("Beim Start des Timers im Fokus abspielen", isOn: $autoPlay)
                Toggle("Beim Stoppen des Timers anhalten", isOn: $pauseWithTimer)
                Toggle("Zufällige Reihenfolge", isOn: $shuffle)
                if let problem = music.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Musik im Fokus")
            } footer: {
                SettingsFootnote("Tagwerk steuert die Musik-App von macOS (Apple Music). Beim ersten Mal fragt macOS, ob Tagwerk die Musik-App steuern darf. Die Playlist wählst du auch direkt im Fokus über das Notensymbol.")
            }
        }
        .settingsPage(height: 520)
        .onChange(of: focusGoalMinutes) { model.settingsChanged() }
    }
}

// MARK: Kalender

struct CalendarSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.writeBlocksKey) private var writeBlocks = false

    var body: some View {
        Form {
            switch model.calendarAccess {
            case .granted:
                Section {
                    ForEach(model.calendarList) { calendar in
                        Picker(selection: Binding(
                            get: { calendar.mode },
                            set: { model.setCalendarMode($0, for: calendar.id) }
                        )) {
                            ForEach(CalendarDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title)
                                Text(calendar.sourceTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Kalender in der Tagesplanung")
                } footer: {
                    SettingsFootnote("„Als belegt“ blockt die Zeit, zeigt aber keinen Titel. Gut für private Termine.")
                }
                Section {
                    Toggle("Zeitblöcke in den Kalender „Tagwerk“ schreiben", isOn: $writeBlocks)
                } footer: {
                    SettingsFootnote("Eingeplante Aufgaben erscheinen dann auch in Outlook und auf dem iPhone, wenn der Kalender dort sichtbar ist.")
                }
            case .notDetermined:
                Section {
                    Button("Zugriff auf Kalender erlauben") {
                        Task { await model.requestCalendarAccess() }
                    }
                } footer: {
                    SettingsFootnote("Tagwerk liest Termine aus allen Kalendern dieses Macs, auch Outlook, wenn das Konto unter Systemeinstellungen › Internetaccounts eingerichtet ist.")
                }
            case .denied:
                Section {
                    Text("Kein Zugriff auf die Kalender.")
                    Button("Systemeinstellungen öffnen") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } footer: {
                    SettingsFootnote("Erlaube den Zugriff unter Datenschutz & Sicherheit › Kalender.")
                }
            case .unavailable:
                Section {
                    Text("Kalender gehen nur, wenn Tagwerk als App läuft (scripts/make-app.sh).")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsPage(height: 480)
        .onChange(of: writeBlocks) { model.settingsChanged() }
    }
}

// MARK: Buchung

struct BookingSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.roundingStepKey) private var roundingStep = 15
    @AppStorage(Preferences.roundingModeKey) private var roundingMode = RoundingMode.nearest.rawValue
    @AppStorage(Preferences.bydesignURLKey) private var bydesignURL = ""

    var body: some View {
        Form {
            Section {
                Picker("Runden auf", selection: $roundingStep) {
                    ForEach([5, 10, 15, 30], id: \.self) { step in
                        Text("\(step) Minuten").tag(step)
                    }
                }
                Picker("Rundung", selection: $roundingMode) {
                    Text("kaufmännisch").tag(RoundingMode.nearest.rawValue)
                    Text("immer aufrunden").tag(RoundingMode.up.rawValue)
                }
            } header: {
                Text("Rundung")
            } footer: {
                SettingsFootnote("Gilt für SAP und ManageEngine. Jede Buchung hat mindestens einen Schritt.")
            }

            Section {
                ForEach(WorkType.allCases) { workType in
                    ServiceProductField(workType: workType)
                }
            } header: {
                Text("Leistung je Arbeitsart")
            } footer: {
                SettingsFootnote("Steht im SAP-Assistenten neben jeder Zeile. Leer lassen, wenn ByDesign die Leistung aus der Projektaufgabe übernimmt.")
            }

            Section {
                SettingsField(title: "Adresse von ByDesign", detail: "wie im Browser, z. B. https://my123456.sapbydesign.com") {
                    SettingsTextField(prompt: "https://my…sapbydesign.com", text: $bydesignURL, width: 280)
                }
                LabeledContent {
                    Button("Abgleichen …") {
                        model.showsSAPSync = true
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Projektaufgaben aus ByDesign")
                        Text("\(model.pspElements.filter(\.isActive).count) aktive PSP-Elemente")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("SAP ByDesign")
            } footer: {
                SettingsFootnote("„Abgleichen“ holt deine Aufgaben direkt aus ByDesign (Anmeldung im Tagwerk-Fenster), aus einem Excel-Export oder einem Bildschirmfoto. In SAP ändert sich dabei nichts.")
            }
        }
        .settingsPage(height: 640)
        .onChange(of: roundingStep) { model.settingsChanged() }
        .onChange(of: roundingMode) { model.settingsChanged() }
    }
}

/// Work Log Type in ManageEngine für eine Arbeitsart.
struct WorklogTypePicker: View {
    @Environment(AppModel.self) private var model
    let workType: WorkType?
    let title: String
    @State private var value = ""

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .onAppear {
            value = model.worklogType(for: workType)
        }
        .onChange(of: value) {
            UserDefaults.standard.set(value, forKey: Preferences.worklogTypeKey(for: workType))
            model.settingsChanged()
        }
    }

    private var options: [String] {
        var list = Preferences.knownWorklogTypes
        if !value.isEmpty, !list.contains(value) { list.insert(value, at: 0) }
        return list
    }
}

/// Leistung in SAP für eine Arbeitsart.
struct ServiceProductField: View {
    @Environment(AppModel.self) private var model
    let workType: WorkType
    @State private var value = ""

    var body: some View {
        SettingsField(title: workType.label) {
            SettingsTextField(prompt: "Leistungs-ID", text: $value, width: 180, monospaced: true)
        }
        .onAppear {
            value = UserDefaults.standard.string(forKey: Preferences.serviceKey(for: workType)) ?? ""
        }
        .onChange(of: value) {
            UserDefaults.standard.set(value.trimmingCharacters(in: .whitespaces), forKey: Preferences.serviceKey(for: workType))
            model.settingsChanged()
        }
    }
}

// MARK: ManageEngine

struct ManageEngineSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.meBaseURLKey) private var baseURL = ""
    @AppStorage(Preferences.meAuthKindKey) private var authKind = ManageEngineConfig.AuthKind.authtoken.rawValue
    @AppStorage(Preferences.meTechnicianKey) private var technician = ""
    @AppStorage(Preferences.meAutoFetchKey) private var autoFetch = true
    @State private var token = ""
    @State private var editingToken = false
    @State private var check: AppModel.ManageEngineCheck?
    @State private var isChecking = false
    @State private var searchText = ""

    var body: some View {
        let config = ManageEngineConfig(baseURL: baseURL, authKind: ManageEngineConfig.AuthKind(rawValue: authKind) ?? .authtoken, technicianID: technician)
        Form {
            Section {
                SettingsField(title: "Adresse") {
                    SettingsTextField(prompt: "https://helpdesk.firma.de", text: $baseURL, width: 300)
                }
                Picker("Anmeldung", selection: $authKind) {
                    ForEach(ManageEngineConfig.AuthKind.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                tokenRow
            } header: {
                Text("Zugang")
            } footer: {
                SettingsFootnote("Den API-Schlüssel erzeugst du in ServiceDesk Plus über dein Profil › API-Schlüssel generieren. Er liegt nur im Schlüsselbund dieses Macs.")
            }

            Section {
                SettingsField(title: "Techniker-ID", detail: "Eine Zahl, nicht der Anmeldename") {
                    HStack(spacing: 8) {
                        if !technician.isEmpty, !config.technicianIDIsNumeric {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("Die API braucht die Nummer des Technikers. „Verbindung testen“ findet sie.")
                        }
                        SettingsTextField(prompt: "z. B. 1234", text: $technician, width: 140, monospaced: true)
                    }
                }
                Toggle("Neue Tickets alle 5 Minuten abrufen", isOn: $autoFetch)
            } header: {
                Text("Deine Tickets")
            } footer: {
                SettingsFootnote("Tagwerk holt die Tickets, die dir zugewiesen sind, und bucht Worklogs auf diese Techniker-ID.")
            }

            Section {
                WorklogTypePicker(workType: nil, title: "Ohne Arbeitsart")
                ForEach(WorkType.allCases) { workType in
                    WorklogTypePicker(workType: workType, title: workType.label)
                }
            } header: {
                Text("Work Log Type je Arbeitsart")
            } footer: {
                SettingsFootnote("Pflichtfeld beim Worklog in ServiceDesk Plus. Tagwerk wählt ihn nach der Arbeitsart der Aufgabe.")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            isChecking = true
                            check = await model.testManageEngine()
                            isChecking = false
                        }
                    } label: {
                        Text("Verbindung testen")
                    }
                    .disabled(!config.hasAddress || !model.hasManageEngineToken || isChecking)
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
                SettingsField(title: "Techniker suchen", detail: "Name, Mail-Adresse oder Benutzername") {
                    HStack(spacing: 8) {
                        SettingsTextField(prompt: "z. B. Lulay oder blulay", text: $searchText, width: 190)
                            .onSubmit(search)
                        Button("Suchen", action: search)
                            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || !config.hasAddress || !model.hasManageEngineToken || isChecking)
                    }
                }
                if let check {
                    Label(check.message, systemImage: check.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(check.ok ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(check.suggestions) { suggestion in
                        LabeledContent {
                            Button("Übernehmen") {
                                technician = suggestion.id
                                self.check = AppModel.ManageEngineCheck(ok: true, message: "Techniker-ID \(suggestion.id) für \(suggestion.name) eingetragen.")
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                Text([suggestion.loginName, suggestion.email, "ID \(suggestion.id)"].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Prüfen")
            } footer: {
                SettingsFootnote("„Verbindung testen“ sucht dich in den letzten Tickets. Bist du dort nicht dabei, such nach deinem Namen; Tagwerk schaut dann in der Technikerliste von ServiceDesk Plus.")
            }
        }
        .settingsPage(height: 700)
        .onChange(of: baseURL) { model.settingsChanged() }
        .onChange(of: authKind) { model.settingsChanged() }
        .onChange(of: technician) { model.settingsChanged() }
        .onAppear {
            if searchText.isEmpty, !technician.isEmpty, !config.technicianIDIsNumeric { searchText = technician }
        }
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task {
            isChecking = true
            check = await model.searchTechnicians(query)
            isChecking = false
        }
    }

    @ViewBuilder
    private var tokenRow: some View {
        if model.hasManageEngineToken, !editingToken {
            LabeledContent("API-Schlüssel") {
                HStack(spacing: 10) {
                    Label("im Schlüsselbund", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Ändern …") { editingToken = true }
                    Button("Entfernen", role: .destructive) {
                        model.setManageEngineToken("")
                        check = nil
                    }
                }
            }
        } else {
            SettingsField(title: "API-Schlüssel") {
                HStack(spacing: 8) {
                    SecureField("", text: $token, prompt: Text("Schlüssel einfügen"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 220)
                        .onSubmit(saveToken)
                    Button("Sichern", action: saveToken)
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editingToken {
                        Button("Abbrechen") {
                            token = ""
                            editingToken = false
                        }
                    }
                }
            }
        }
    }

    private func saveToken() {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.setManageEngineToken(token)
        token = ""
        editingToken = false
        check = nil
    }
}

// MARK: Claude

struct ClaudeSettings: View {
    @State private var status: String?
    @State private var statusIsError = false
    @State private var installed = ClaudeIntegration.isInstalledInDesktop
    @State private var copied: String?

    var body: some View {
        Form {
            Section {
                Text("Claude kann über MCP direkt mit Tagwerk arbeiten: den Tag zusammenfassen, Aufgaben anlegen und ändern, Timer starten und stoppen, Zeiten auswerten und sagen, was beim Tagesabschluss noch fehlt.")
                    .fixedSize(horizontal: false, vertical: true)
                Label("Gebucht wird nur hier in Tagwerk. Claude schickt nichts an SAP oder ManageEngine.", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Was Claude kann")
            }

            Section {
                LabeledContent {
                    if installed {
                        Label("eingetragen", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("In Claude Desktop eintragen") { installDesktop() }
                            .disabled(ClaudeIntegration.serverURL == nil)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Desktop")
                        Text("Danach Claude Desktop einmal beenden und neu öffnen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let status {
                    Label(status, systemImage: statusIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                copyRow(title: "Eintrag von Hand", detail: "für claude_desktop_config.json", value: ClaudeIntegration.desktopSnippet, key: "desktop")
            } header: {
                Text("Claude Desktop")
            }

            Section {
                copyRow(title: "Befehl fürs Terminal", detail: nil, value: ClaudeIntegration.claudeCodeCommand, key: "code")
            } header: {
                Text("Claude Code")
            } footer: {
                SettingsFootnote("Einmal ausführen, dann steht Tagwerk in jedem Projekt zur Verfügung.")
            }

            Section {
                if let url = ClaudeIntegration.serverURL {
                    LabeledContent("Programm") {
                        Text(url.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                } else {
                    Label("tagwerk-mcp fehlt neben der App. Baue sie mit scripts/make-app.sh.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Technik")
            } footer: {
                SettingsFootnote("Liegt Tagwerk woanders, z. B. nach dem Verschieben in „Programme“, trag es hier neu ein.")
            }
        }
        .settingsPage(height: 680)
        .onAppear { installed = ClaudeIntegration.isInstalledInDesktop }
    }

    private func copyRow(title: String, detail: String?, value: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(copied == key ? "Kopiert" : "Kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = key
                }
            }
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
        }
    }

    private func installDesktop() {
        do {
            try ClaudeIntegration.installInDesktop()
            installed = true
            statusIsError = false
            status = "Eingetragen. Starte Claude Desktop neu, dann taucht Tagwerk bei den Werkzeugen auf."
        } catch {
            statusIsError = true
            status = String(describing: error)
        }
    }
}

/// Verbindet Claude Desktop und Claude Code mit dem MCP-Server neben der App.
enum ClaudeIntegration {
    enum InstallError: Error, CustomStringConvertible {
        case serverMissing
        case unreadableConfig

        var description: String {
            switch self {
            case .serverMissing:
                return "tagwerk-mcp wurde neben der App nicht gefunden."
            case .unreadableConfig:
                return "Die Datei claude_desktop_config.json ist kein gültiges JSON. Tagwerk ändert sie nicht; trag den Eintrag bitte von Hand ein."
            }
        }
    }

    static let serverName = "tagwerk"

    /// Liegt in Tagwerk.app/Contents/MacOS neben der App, bei `swift run` im selben Build-Ordner.
    static var serverURL: URL? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let url = executable.deletingLastPathComponent().appendingPathComponent("tagwerk-mcp")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var serverPath: String {
        serverURL?.path ?? "/Applications/Tagwerk.app/Contents/MacOS/tagwerk-mcp"
    }

    static var desktopConfigURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json")
    }

    static var desktopSnippet: String {
        """
        {
          "mcpServers": {
            "\(serverName)": {
              "command": "\(serverPath)"
            }
          }
        }
        """
    }

    static var claudeCodeCommand: String {
        "claude mcp add --scope user \(serverName) -- \"\(serverPath)\""
    }

    static var isInstalledInDesktop: Bool {
        guard let data = try? Data(contentsOf: desktopConfigURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers[serverName] as? [String: Any] else { return false }
        return entry["command"] as? String == serverPath
    }

    /// Ergänzt die Konfiguration von Claude Desktop um Tagwerk. Andere Einträge bleiben, wie sie sind.
    static func installInDesktop() throws {
        guard let server = serverURL else { throw InstallError.serverMissing }
        let url = desktopConfigURL
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.unreadableConfig
            }
            root = existing
            try? data.write(to: url.appendingPathExtension("vor-tagwerk"))
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[serverName] = ["command": server.path]
        root["mcpServers"] = servers
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

// MARK: Daten

struct DataSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Speicherort") {
                    Text("~/Library/Application Support/Tagwerk")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Im Finder") {
                    Button("Zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.dataFolder])
                    }
                }
            } header: {
                Text("Daten")
            } footer: {
                SettingsFootnote("Alles liegt nur auf diesem Mac, in einer SQLite-Datei.")
            }

            Section {
                LabeledContent("Sicherungen", value: "\(model.backupCount) von höchstens 14")
                LabeledContent("Ordner") {
                    Button("Zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.backupFolder])
                    }
                }
            } header: {
                Text("Sicherung")
            } footer: {
                SettingsFootnote("Tagwerk sichert einmal am Tag und behält die letzten 14 Tage.")
            }
        }
        .settingsPage(height: 380)
    }
}
