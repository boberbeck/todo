import AppKit
import SwiftUI
import TagwerkCore

/// Text in der Menüleiste: laufende Zeit und Aufgabe, sonst nur ein Symbol.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let task = model.runningTask {
            Text("▶ \(TimeMath.format(model.tracked(taskID: task.id, now: model.now))) \(String(task.title.prefix(20)))")
        } else {
            Image(systemName: "checklist")
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = model.runningTask {
                Text("Läuft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(TimeMath.format(model.tracked(taskID: task.id, now: model.now), showSeconds: true))
                    .font(.title2.monospacedDigit())
                HStack {
                    Button("Stoppen") { model.stopTimer() }
                    Button("Erledigt") { model.complete(task.id) }
                }
            } else {
                Text("Kein Timer aktiv")
                    .foregroundStyle(.secondary)
            }

            Divider()

            let open = model.todayTasks.filter { !$0.isDone && !model.isRunning($0.id) }
            if !open.isEmpty {
                Text("Heute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(open.prefix(8))) { task in
                    Button {
                        model.startTimer(task.id)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.secondary)
                            Text(task.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }

            Button("Tagwerk öffnen") {
                openWindow(id: "main")
                NSApp.activate()
            }
            Button("Beenden") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.workdayStartKey) private var workdayStart = Preferences.defaultWorkdayStart
    @AppStorage(Preferences.workdayEndKey) private var workdayEnd = Preferences.defaultWorkdayEnd
    @AppStorage(Preferences.focusGoalMinutesKey) private var focusGoalMinutes = Preferences.defaultFocusGoalMinutes
    @AppStorage(Preferences.writeBlocksKey) private var writeBlocks = false
    @AppStorage(Preferences.planningOnLaunchKey) private var planningOnLaunch = true
    @AppStorage(Preferences.roundingStepKey) private var roundingStep = 15
    @AppStorage(Preferences.roundingModeKey) private var roundingMode = RoundingMode.nearest.rawValue
    @AppStorage(Preferences.meBaseURLKey) private var meBaseURL = ""
    @AppStorage(Preferences.meAuthKindKey) private var meAuthKind = ManageEngineConfig.AuthKind.authtoken.rawValue
    @AppStorage(Preferences.meTechnicianKey) private var meTechnician = ""
    @AppStorage(Preferences.meAutoFetchKey) private var meAutoFetch = true
    @State private var meToken = ""
    @State private var meTestResult: String?

    var body: some View {
        Form {
            Section("Arbeitszeit") {
                DatePicker("Beginn", selection: timeBinding($workdayStart), displayedComponents: .hourAndMinute)
                DatePicker("Ende", selection: timeBinding($workdayEnd), displayedComponents: .hourAndMinute)
                Stepper(value: $focusGoalMinutes, in: 30...720, step: 15) {
                    LabeledContent("Tagesziel Fokuszeit", value: "\(TimeMath.format(minutes: focusGoalMinutes)) h")
                }
            }

            Section("Tagesplanung") {
                Toggle("Beim ersten Öffnen am Tag zeigen", isOn: $planningOnLaunch)
            }

            Section("Kalender") {
                switch model.calendarAccess {
                case .granted:
                    ForEach(model.calendarList) { calendar in
                        Picker(selection: Binding(
                            get: { calendar.mode },
                            set: { model.setCalendarMode($0, for: calendar.id) }
                        )) {
                            ForEach(CalendarDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(calendar.title)
                                Text(calendar.sourceTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Toggle("Zeitblöcke in den Kalender „Tagwerk“ schreiben", isOn: $writeBlocks)
                case .notDetermined:
                    Button("Zugriff auf Kalender erlauben") {
                        Task { await model.requestCalendarAccess() }
                    }
                case .denied:
                    Text("Kein Zugriff. Erlaube ihn in den Systemeinstellungen unter Datenschutz & Sicherheit › Kalender.")
                        .foregroundStyle(.secondary)
                case .unavailable:
                    Text("Kalender gehen nur, wenn Tagwerk als App läuft (scripts/make-app.sh).")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Buchung") {
                Picker("Runden auf", selection: $roundingStep) {
                    ForEach([5, 10, 15, 30], id: \.self) { step in
                        Text("\(step) Minuten").tag(step)
                    }
                }
                Picker("Rundung", selection: $roundingMode) {
                    Text("kaufmännisch").tag(RoundingMode.nearest.rawValue)
                    Text("immer aufrunden").tag(RoundingMode.up.rawValue)
                }
                ForEach(WorkType.allCases) { workType in
                    ServiceProductField(workType: workType)
                }
            }

            Section("ManageEngine") {
                TextField("Adresse", text: $meBaseURL, prompt: Text("https://helpdesk.firma.de"))
                Picker("Anmeldung", selection: $meAuthKind) {
                    ForEach(ManageEngineConfig.AuthKind.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                TextField("Techniker-ID", text: $meTechnician, prompt: Text("deine ID in ServiceDesk Plus"))
                HStack {
                    SecureField(model.hasManageEngineToken ? "Schlüssel gespeichert" : "API-Schlüssel", text: $meToken)
                        .onSubmit(saveToken)
                    Button("Speichern", action: saveToken)
                        .disabled(meToken.isEmpty)
                }
                Toggle("Tickets alle 5 Minuten abrufen", isOn: $meAutoFetch)
                HStack {
                    Button("Verbindung testen") {
                        Task { meTestResult = await model.testManageEngine() }
                    }
                    if let meTestResult {
                        Text(meTestResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Text("Den API-Schlüssel erzeugst du in ServiceDesk Plus unter deinem Profil (On-Premises) bzw. als Zoho-OAuth-Token (Cloud). Er liegt nur im Schlüsselbund dieses Macs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Daten") {
                LabeledContent("Speicherort", value: "~/Library/Application Support/Tagwerk")
                Button("Im Finder zeigen") {
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Tagwerk", isDirectory: true)
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 560)
        .onChange(of: workdayStart) { model.settingsChanged() }
        .onChange(of: workdayEnd) { model.settingsChanged() }
        .onChange(of: writeBlocks) { model.settingsChanged() }
        .onChange(of: roundingStep) { model.settingsChanged() }
        .onChange(of: roundingMode) { model.settingsChanged() }
        .onChange(of: meBaseURL) { model.settingsChanged() }
        .onChange(of: meAuthKind) { model.settingsChanged() }
        .onChange(of: meTechnician) { model.settingsChanged() }
    }

    private func saveToken() {
        model.setManageEngineToken(meToken)
        meToken = ""
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { FreeTime.date(on: LocalDate.today(), minutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = FreeTime.minutesSinceMidnight($0) }
        )
    }
}

/// Leistung in SAP für eine Arbeitsart.
struct ServiceProductField: View {
    @Environment(AppModel.self) private var model
    let workType: WorkType
    @State private var value = ""

    var body: some View {
        TextField("Leistung für \(workType.label)", text: $value, prompt: Text("Leistungs-ID in ByDesign"))
            .onAppear {
                value = UserDefaults.standard.string(forKey: Preferences.serviceKey(for: workType)) ?? ""
            }
            .onChange(of: value) {
                UserDefaults.standard.set(value.trimmingCharacters(in: .whitespaces), forKey: Preferences.serviceKey(for: workType))
                model.settingsChanged()
            }
    }
}
