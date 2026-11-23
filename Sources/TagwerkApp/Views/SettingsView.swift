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
                LabeledContent("Stand") {
                    Text(AppVersion.description)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Probleme") {
                    HStack(spacing: 8) {
                        Button("Protokoll zeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting([AppLog.file])
                        }
                        Button("Fehler melden …") { model.showsBugReport = true }
                    }
                }
            } header: {
                Text("Version")
            } footer: {
                SettingsFootnote("Die Nummer in Klammern steht auch beim Release „aktuell“ auf GitHub. Stimmt sie nicht, ist hier noch eine ältere Fassung installiert.")
            }

            UpdateSection()

            SigningSection()

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
        .settingsPage(height: 760)
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

            PomodoroSettingsSection()

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
        .settingsPage(height: 700)
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
    @AppStorage(Preferences.bydesignUserKey) private var bydesignUser = ""
    @AppStorage(Preferences.bydesignAutoFetchKey) private var bydesignAutoFetch = false
    @AppStorage(Preferences.bydesignTaskListURLKey) private var bydesignTaskList = ""
    @State private var bydesignPassword = ""

    private func saveByDesignPassword() {
        guard !bydesignPassword.isEmpty else { return }
        model.setByDesignPassword(bydesignPassword)
        bydesignPassword = ""
    }

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
                SettingsField(title: "Benutzer") {
                    SettingsTextField(prompt: "Benutzername in ByDesign", text: $bydesignUser, width: 200)
                }
                SettingsField(title: "Passwort", detail: model.hasByDesignPassword ? "im Schlüsselbund" : "liegt nur im Schlüsselbund dieses Macs") {
                    HStack(spacing: 8) {
                        SecureField("", text: $bydesignPassword, prompt: Text(model.hasByDesignPassword ? "•••••••• (gespeichert)" : "Passwort"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit(saveByDesignPassword)
                        Button("Sichern", action: saveByDesignPassword)
                            .disabled(bydesignPassword.isEmpty)
                        if model.hasByDesignPassword {
                            Button("Entfernen") { model.setByDesignPassword("") }
                        }
                    }
                }
                Toggle("Aufgaben einmal am Tag automatisch holen", isOn: $bydesignAutoFetch)
                LabeledContent {
                    Button("Jetzt holen") { model.startSAPAutoFetch() }
                        .disabled(bydesignTaskList.isEmpty || bydesignUser.isEmpty || !model.hasByDesignPassword)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatischer Abruf")
                        Text(model.sapAutoStatus ?? (bydesignTaskList.isEmpty ? "Noch keine Liste gemerkt: im ByDesign-Fenster „Diese Liste merken“." : "Liste gemerkt."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        .settingsPage(height: 700)
        .onChange(of: roundingStep) { model.settingsChanged() }
        .onChange(of: roundingMode) { model.settingsChanged() }
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
    @AppStorage(Preferences.defaultWorklogTypeKey) private var defaultWorklogType = "Ticketbearbeitung"

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
                Picker("Standard", selection: $defaultWorklogType) {
                    ForEach(Preferences.knownWorklogTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
            } header: {
                Text("Work Log Type")
            } footer: {
                SettingsFootnote("Heißen genau wie in ServiceDesk Plus. Pro Ticket wählst du ihn im Fokus, im Tagesabschluss oder per Rechtsklick; ohne Auswahl gilt dieser Standard.")
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
                LabeledContent {
                    Button(model.isSyncingTickets ? "Lädt …" : "Jetzt abrufen") {
                        Task { await model.importTickets() }
                    }
                    .disabled(!model.canUseManageEngine || model.isSyncingTickets)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tickets abrufen")
                        Text(model.ticketSyncDetail ?? "Noch kein Abruf seit dem Start.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        .settingsPage(height: 640)
        .onChange(of: baseURL) { model.settingsChanged() }
        .onChange(of: authKind) { model.settingsChanged() }
        .onChange(of: technician) { model.settingsChanged() }
        .onChange(of: defaultWorklogType) { model.settingsChanged() }
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
    @State private var testResult: (ok: Bool, message: String)?
    @State private var isTesting = false

    var body: some View {
        Form {
            if let warning = ClaudeIntegration.locationWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let other = ClaudeIntegration.otherConfiguredCommand {
                Section {
                    Label("Claude Desktop startet tagwerk-mcp aus einer anderen Kopie: \(other). Die kennt neuere Werkzeuge (z. B. Unteraufgaben) womöglich nicht. „Auf diese Kopie umstellen“ trägt die Kopie ein, die gerade läuft; danach Claude Desktop mit ⌘Q beenden und neu öffnen.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Button("Testen") {
                            isTesting = true
                            Task {
                                testResult = await ClaudeIntegration.testServer()
                                isTesting = false
                            }
                        }
                        .disabled(isTesting || ClaudeIntegration.serverURL == nil)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MCP-Server prüfen")
                        Text(testResult?.message ?? "Startet tagwerk-mcp so, wie Claude Desktop es tut (dieselbe Kopie), und fragt die Werkzeuge ab.")
                            .font(.caption)
                            .foregroundStyle(testResult.map { $0.ok ? Color.green : Color.red } ?? Color.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Prüfen")
            } footer: {
                SettingsFootnote("Claude liest die Werkzeuge nur beim Start: Nach einem Update von Tagwerk Claude Desktop mit ⌘Q beenden und neu öffnen. Klappt der Test, Claude aber nicht: In Claude Desktop unter Einstellungen › Entwickler steht der Status von „tagwerk“; das Protokoll liegt in ~/Library/Logs/Claude/mcp-server-tagwerk.log. Lokale MCP-Server gehen nur in Claude Desktop und Claude Code, nicht im Browser oder auf dem iPhone.")
            }
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
                        Button(ClaudeIntegration.otherConfiguredCommand == nil ? "In Claude Desktop eintragen" : "Auf diese Kopie umstellen") { installDesktop() }
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

            RemoteAccessSection()

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
        .settingsPage(height: 760)
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
            status = "Eingetragen. Beende Claude Desktop mit ⌘Q und öffne es neu, dann hat Claude die Werkzeuge dieser Fassung."
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
        configuredDesktopCommand == serverPath
    }

    /// Welches Programm Claude Desktop für „tagwerk“ startet.
    static var configuredDesktopCommand: String? {
        guard let data = try? Data(contentsOf: desktopConfigURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers[serverName] as? [String: Any] else { return nil }
        return entry["command"] as? String
    }

    /// Eingetragen ist eine andere Kopie als die, die gerade läuft (z. B. eine alte in „Downloads“).
    static var otherConfiguredCommand: String? {
        guard let configured = configuredDesktopCommand, serverURL != nil, configured != serverPath else { return nil }
        return configured
    }

    /// Ergänzt die Konfiguration von Claude Desktop um Tagwerk. Andere Einträge bleiben, wie sie sind.
    /// Hinweis, wenn Tagwerk nicht aus „Programme“ läuft: Der eingetragene Pfad wäre sonst bald falsch.
    static var locationWarning: String? {
        let path = Bundle.main.bundleURL.path
        if path.contains("/AppTranslocation/") {
            return "Tagwerk läuft gerade aus einem temporären Ordner, den macOS beim Öffnen aus „Downloads“ anlegt. Zieh Tagwerk in den Ordner „Programme“, öffne es von dort und trag es dann hier neu ein."
        }
        if !path.hasPrefix("/Applications/") {
            return "Tagwerk liegt nicht im Ordner „Programme“ (\(path)). Claude startet den Server über diesen Pfad; verschiebst oder löschst du diese Kopie, findet Claude ihn nicht mehr. Am besten Tagwerk nach „Programme“ ziehen und neu eintragen."
        }
        return nil
    }

    /// Startet tagwerk-mcp wie Claude und prüft die Antwort auf initialize und tools/list.
    /// Geprüft wird die Kopie, die in Claude Desktop eingetragen ist, sonst die neben dieser App.
    static func testServer() async -> (ok: Bool, message: String) {
        let configured = configuredDesktopCommand.map { URL(fileURLWithPath: $0) }
        if let configured, configured.path != serverPath, !FileManager.default.isExecutableFile(atPath: configured.path) {
            return (false, "In Claude Desktop ist \(configured.path) eingetragen, aber dort liegt kein Programm mehr. „Auf diese Kopie umstellen“ drücken.")
        }
        guard let url = configured ?? serverURL else { return (false, "tagwerk-mcp fehlt neben der App.") }
        let which = url.path == serverPath ? "" : " (eingetragene Kopie: \(url.path))"
        removeQuarantine(from: url)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = url
                let input = Pipe()
                let output = Pipe()
                let errors = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (false, "Startet nicht: \(error.localizedDescription)"))
                    return
                }
                let requests = [
                    #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"tagwerk-test","version":"1"}}}"#,
                    #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
                    #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
                ].joined(separator: "\n") + "\n"
                input.fileHandleForWriting.write(Data(requests.utf8))
                try? input.fileHandleForWriting.close()
                let deadline = Date().addingTimeInterval(8)
                while process.isRunning, Date() < deadline { usleep(50_000) }
                if process.isRunning { process.terminate() }
                let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let lines = out.split(separator: "\n").map(String.init)
                let version = lines.compactMap { line -> String? in
                    guard let data = line.data(using: .utf8),
                          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let result = root["result"] as? [String: Any],
                          let info = result["serverInfo"] as? [String: Any] else { return nil }
                    return info["version"] as? String
                }.first ?? "?"
                let hasSubtasks = out.contains("unteraufgabe_von")
                let toolCount = lines.compactMap { line -> Int? in
                    guard let data = line.data(using: .utf8),
                          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let result = root["result"] as? [String: Any],
                          let tools = result["tools"] as? [Any] else { return nil }
                    return tools.count
                }.first
                if let toolCount, !hasSubtasks {
                    continuation.resume(returning: (false, "Läuft, aber das ist eine ältere Fassung (Stand \(version))\(which): ohne Unteraufgaben, Tickets und Tätigkeit. Auf diese Kopie umstellen, dann Claude Desktop mit ⌘Q beenden und neu öffnen. (\(toolCount) Werkzeuge)"))
                } else if let toolCount {
                    continuation.resume(returning: (true, "Läuft: Stand \(version)\(which), \(toolCount) Werkzeuge, mit Unteraufgaben, Tickets und Tätigkeit. Sieht Claude sie nicht, Claude Desktop mit ⌘Q beenden und neu öffnen. \(err.contains("bereit") ? "" : err.trimmingCharacters(in: .whitespacesAndNewlines))"))
                } else {
                    let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (false, "Keine gültige Antwort. \(detail.isEmpty ? "Exit-Code \(process.terminationStatus)" : detail)"))
                }
            }
        }
    }

    /// Ein aus dem Internet geladenes Programm ist markiert; Claude darf es dann nicht starten.
    static func removeQuarantine(from url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", url.path]
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    static func installInDesktop() throws {
        guard let server = serverURL else { throw InstallError.serverMissing }
        removeQuarantine(from: server)
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

/// Stand der App: Version und der Commit, aus dem sie gebaut ist (wie beim Release „aktuell“).
enum AppVersion {
    static var description: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let date = info["TagwerkBuildDate"] as? String
        return "\(short) (\(build))" + (date.map { " · gebaut \($0)" } ?? "")
    }
}

/// Claude im Browser und auf dem Handy: Tagwerk über einen Tunnel als eigenen Connector in claude.ai.
struct RemoteAccessSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.remoteEnabledKey) private var enabled = false
    @AppStorage(Preferences.remotePortKey) private var port = 8765
    @AppStorage(Preferences.remotePublicURLKey) private var publicURL = ""
    @AppStorage(Preferences.remoteTunnelCommandKey) private var tunnelCommand = ""
    @State private var copied = false
    @State private var showsSecret = false

    private static let tunnelSuggestions: [(name: String, command: String, note: String)] = [
        ("Tailscale Funnel", "tailscale funnel {port}", "feste Adresse, kostenlos; Tailscale installieren und anmelden, Funnel einmal erlauben"),
        ("ngrok", "ngrok http --url=DEIN-NAME.ngrok-free.app {port} --log stdout", "feste Adresse mit kostenlosem Konto"),
        ("Cloudflare", "cloudflared tunnel --url http://127.0.0.1:{port}", "ohne Konto, aber neue Adresse bei jedem Start"),
    ]

    var body: some View {
        let remote = model.remote
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erreichbar, solange Tagwerk läuft")
                    Text(statusText(remote))
                        .font(.caption)
                        .foregroundStyle(statusColor(remote))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledContent("Port") {
                TextField("Port", value: $port, format: .number.grouping(.never))
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tunnel mitstarten")
                    Spacer()
                    Menu("Vorlage") {
                        ForEach(Self.tunnelSuggestions, id: \.name) { suggestion in
                            Button("\(suggestion.name): \(suggestion.note)") { tunnelCommand = suggestion.command }
                        }
                    }
                    .fixedSize()
                }
                TextField("z. B. tailscale funnel {port}", text: $tunnelCommand)
                    .font(.callout.monospaced())
                Text("Läuft im Terminal-Umfeld (zsh); {port} wird ersetzt. Leer lassen, wenn du den Tunnel selbst startest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = remote.tunnelState {
                    Text("Tunnel: \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            LabeledContent("Öffentliche Adresse") {
                TextField(remote.detectedPublicURL ?? "https://mein-mac.tailxxxx.ts.net", text: $publicURL)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adresse für claude.ai")
                        Text("Einstellungen › Connectors › Eigenen Connector hinzufügen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(showsSecret ? "Verbergen" : "Zeigen") { showsSecret.toggle() }
                    Button(copied ? "Kopiert" : "Kopieren") {
                        guard let url = remote.connectorURL else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        copied = true
                    }
                    .disabled(remote.connectorURL == nil)
                }
                Text(displayedURL(remote))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            }
            HStack {
                Button("Prüfen") { Task { await remote.check() } }
                    .disabled(!enabled)
                Button("Neuer Schlüssel") { remote.renewToken(); copied = false }
                    .help("Die bisherige Adresse funktioniert danach nicht mehr; in claude.ai neu eintragen.")
                Spacer()
            }
            if let message = remote.checkMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Claude im Browser und auf dem Handy")
        } footer: {
            SettingsFootnote("""
            So geht's: 1. Einen Tunnel einrichten (am einfachsten Tailscale Funnel), damit claude.ai deinen Mac erreicht. \
            2. Die Adresse oben in claude.ai unter Einstellungen › Connectors als eigenen Connector eintragen; danach steht Tagwerk \
            auch in der Claude-App auf dem Handy bereit. Der Mac muss an sein und Tagwerk laufen. \
            Wer die Adresse kennt, kann deine Aufgaben und Zeiten lesen und ändern: behandle sie wie ein Passwort. \
            Gebucht wird weiterhin nur hier in Tagwerk.
            """)
        }
        .onChange(of: enabled) {
            enabled ? remote.start() : remote.stop()
        }
        .onChange(of: port) {
            if enabled { remote.restart() }
        }
    }

    private func displayedURL(_ remote: RemoteAccess) -> String {
        guard let url = remote.connectorURL else {
            return "Erst eine öffentliche https-Adresse eintragen (oder den Tunnel starten, dann erkennt Tagwerk sie)."
        }
        if showsSecret { return url }
        let token = remote.token
        return url.replacingOccurrences(of: token, with: String(token.prefix(4)) + "…")
    }

    private func statusText(_ remote: RemoteAccess) -> String {
        switch remote.serverState {
        case .off: return "Aus. Claude Desktop auf diesem Mac geht auch ohne."
        case .running:
            let tunnel: String
            switch remote.tunnelState {
            case .running: tunnel = "Tunnel läuft"
            case .failed: tunnel = "Tunnel gestoppt"
            case .off: tunnel = "ohne eigenen Tunnel"
            }
            return "Läuft auf 127.0.0.1:\(port) · \(tunnel)"
        case .failed(let message): return "Fehler: \(message)"
        }
    }

    private func statusColor(_ remote: RemoteAccess) -> Color {
        switch remote.serverState {
        case .running: return .green
        case .failed: return .red
        case .off: return .secondary
        }
    }
}

/// Feste Signatur einrichten: Zertifikat erzeugen und als zwei Secrets bei GitHub hinterlegen.
struct SigningSection: View {
    @State private var bundle: SigningSetup.Secrets?
    @State private var error: String?
    @State private var copied: String?

    var body: some View {
        Section {
            LabeledContent("Diese Fassung") {
                Text(SigningSetup.currentSignature)
                    .foregroundStyle(SigningSetup.isFixed ? Color.green : Color.orange)
            }
            if !SigningSetup.isFixed {
                if let bundle {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Jetzt zwei Secrets bei GitHub anlegen (Seite öffnen, je Name und Wert einfügen, „Add secret“):")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("GitHub-Seite öffnen") { NSWorkspace.shared.open(SigningSetup.secretsURL) }
                            Spacer()
                        }
                        secretRow(name: "TAGWERK_SIGNING_P12", value: bundle.p12Base64)
                        secretRow(name: "TAGWERK_SIGNING_PASSWORD", value: bundle.password)
                        Text("Danach den nächsten Build abwarten (oder unter Actions „Run workflow“), die neue Fassung aus „aktuell“ installieren und den Kalender ein letztes Mal freigeben. Ab dann bleibt die Freigabe auch nach Updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack {
                        Button("Zertifikat erzeugen") {
                            do {
                                bundle = try SigningSetup.generate()
                                error = nil
                            } catch {
                                self.error = String(describing: error)
                            }
                        }
                        Spacer()
                    }
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Freigaben behalten")
        } footer: {
            SettingsFootnote(SigningSetup.isFixed
                ? "macOS behält die Freigaben für Kalender, Schlüsselbund und Musik auch nach Updates."
                : "macOS merkt sich die Kalenderfreigabe an der Signatur. Ohne festes Zertifikat ist jede neue Fassung für macOS eine andere App, und du musst den Kalender neu verbinden. Einmal einrichten, dann bleibt es.")
        }
    }

    private func secretRow(name: String, value: String) -> some View {
        HStack {
            Text(name)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Spacer()
            Button(copied == name ? "Name kopiert" : "Name kopieren") { copy(name, key: name) }
            Button(copied == name + "-wert" ? "Wert kopiert" : "Wert kopieren") { copy(value, key: name + "-wert") }
        }
    }

    private func copy(_ text: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = key
    }
}

/// Pomodoro-Zeiten: Arbeit, kurze und lange Pause, Runden bis zur langen Pause.
struct PomodoroSettingsSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.pomodoroWorkKey) private var work = 25
    @AppStorage(Preferences.pomodoroShortBreakKey) private var shortBreak = 5
    @AppStorage(Preferences.pomodoroLongBreakKey) private var longBreak = 15
    @AppStorage(Preferences.pomodoroRoundsKey) private var rounds = 4
    @AppStorage(Preferences.pomodoroAutoContinueKey) private var autoContinue = false
    @AppStorage(Preferences.pomodoroSoundKey) private var sound = true

    var body: some View {
        Section {
            Toggle("Pomodoro im Fokus", isOn: Binding(
                get: { model.isPomodoroEnabled },
                set: { model.setPomodoroEnabled($0) }
            ))
            minutesRow("Arbeiten", value: $work, range: 5...90, step: 5)
            minutesRow("Kurze Pause", value: $shortBreak, range: 1...30, step: 1)
            minutesRow("Lange Pause", value: $longBreak, range: 5...60, step: 5)
            LabeledContent("Lange Pause nach") {
                HStack(spacing: 6) {
                    Text("\(rounds) Runden")
                        .monospacedDigit()
                    Stepper("Runden", value: $rounds, in: 2...8)
                        .labelsHidden()
                }
            }
            Toggle("Nach der Pause automatisch weiter", isOn: $autoContinue)
            Toggle("Ton bei Pause und Weiter", isOn: $sound)
        } header: {
            Text("Pomodoro")
        } footer: {
            SettingsFootnote("Klassisch nach Francesco Cirillo: 25 Minuten arbeiten, 5 Minuten Pause, nach vier Runden 15 bis 30 Minuten. In der Pause stoppt die Zeit und die Musik; sie zählt herunter, danach kommt ein Signal. Ohne „automatisch weiter“ geht es mit „Weiter“ los.")
        }
        .onChange(of: work) { model.settingsChanged() }
        .onChange(of: shortBreak) { model.settingsChanged() }
        .onChange(of: longBreak) { model.settingsChanged() }
        .onChange(of: rounds) { model.settingsChanged() }
    }

    private func minutesRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("\(value.wrappedValue) Min.")
                    .monospacedDigit()
                Stepper(title, value: value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// Updates aus GitHub: Schlüssel (nur lesen), automatisch prüfen, jetzt prüfen.
struct UpdateSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.updateAutoCheckKey) private var autoCheck = true
    @State private var token = ""

    var body: some View {
        let updater = model.updater
        Section {
            if updater.hasToken {
                LabeledContent("GitHub-Schlüssel") {
                    HStack(spacing: 8) {
                        Label("im Schlüsselbund", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Entfernen") { updater.setToken("") }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("GitHub-Schlüssel (nur lesen)", text: $token)
                        Button("Sichern") {
                            updater.setToken(token)
                            token = ""
                            Task { await updater.check(userInitiated: true) }
                        }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Button("Schlüssel bei GitHub anlegen") { NSWorkspace.shared.open(Updater.tokenPage) }
                        Spacer()
                    }
                    Text("Bei GitHub: „Fine-grained token“, Repository access „Only select repositories“ › \(Updater.repository), Permissions › Contents: Read-only. Ablaufdatum nach Wunsch (z. B. 1 Jahr). Den Schlüssel hier einfügen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Automatisch nach Updates suchen", isOn: $autoCheck)
            HStack {
                Button(updater.isChecking ? "Prüft …" : "Jetzt prüfen") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(updater.isChecking || !updater.hasToken)
                if let status = updater.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        } header: {
            Text("Updates")
        } footer: {
            SettingsFootnote("Tagwerk schaut beim Start und alle sechs Stunden im Release „aktuell“ nach. Gibt es eine neue Fassung, fragt es; nach „Jetzt aktualisieren“ ersetzt es sich selbst und startet neu. Der Schlüssel liegt im Schlüsselbund und geht nur an GitHub.")
        }
    }
}
