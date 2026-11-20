import AppKit
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// Wohin die Aufgaben eines SAP-Projekts in Tagwerk gehören.
enum SAPCustomerChoice: Hashable {
    case skip
    case existing(UUID)
    case new(String)
}

/// Liest die Aufgabenliste aus ByDesign: Excel-Export (.xlsx, XML-.xls), CSV, HTML oder die Zwischenablage.
enum SAPImportLoader {
    enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case binaryExcel
        case noTasks

        var description: String {
            switch self {
            case .unreadable(let name):
                return "„\(name)“ lässt sich nicht lesen."
            case .binaryExcel:
                return "Diese .xls-Datei hat das alte Excel-Format. Öffne sie in Excel oder Numbers und sichere sie als .xlsx oder CSV."
            case .noTasks:
                return "Keine Aufgabennummern wie „CPSO8643-12“ gefunden. Ist die Spalte „Aufgabennummer“ dabei?"
            }
        }
    }

    static let fileTypes: [UTType] = [
        UTType(filenameExtension: "xlsx") ?? .spreadsheet,
        UTType(filenameExtension: "xls") ?? .spreadsheet,
        .commaSeparatedText, .tabSeparatedText, .plainText, .html, .image,
    ]

    static func rows(from url: URL) throws -> [SAPTaskRow] {
        let rows = try cells(from: url).flatMap { SAPImport.rows(fromCells: $0) }
        guard !rows.isEmpty else { throw LoadError.noTasks }
        return rows
    }

    /// Zeilen aus der Zwischenablage. Liefert der Browser eine HTML-Tabelle, wird die bevorzugt.
    static func rowsFromPasteboard() throws -> [SAPTaskRow] {
        let pasteboard = NSPasteboard.general
        if let html = pasteboard.string(forType: .html) {
            let rows = SAPImport.rows(fromCells: HTMLTable.cells(from: html))
            if !rows.isEmpty { return rows }
        }
        if let text = pasteboard.string(forType: .string) {
            let rows = SAPImport.rows(fromText: text)
            if !rows.isEmpty { return rows }
        }
        throw LoadError.noTasks
    }

    /// Eine Tabelle je Blatt.
    private static func cells(from url: URL) throws -> [[[String]]] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError.unreadable(url.lastPathComponent)
        }
        let isZip = data.starts(with: [0x50, 0x4B, 0x03, 0x04])
        if isZip {
            return try xlsxSheets(at: url)
        }
        if SpreadsheetML.isSpreadsheetML(data) {
            return [SpreadsheetML.cells(from: data)]
        }
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {
            throw LoadError.binaryExcel
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
        if text.range(of: "<table", options: .caseInsensitive) != nil {
            return [HTMLTable.cells(from: text)]
        }
        return [TableText.cells(from: text)]
    }

    /// .xlsx ist ein ZIP-Archiv. Entpackt wird mit dem `unzip` von macOS.
    private static func xlsxSheets(at url: URL) throws -> [[[String]]] {
        let listing = String(decoding: try unzip(["-Z1", url.path]), as: UTF8.self)
        let sheets = listing
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !sheets.isEmpty else { throw LoadError.unreadable(url.lastPathComponent) }
        var sharedStrings: Data?
        if listing.contains("xl/sharedStrings.xml") {
            sharedStrings = try? unzip(["-p", url.path, "xl/sharedStrings.xml"])
        }
        return try sheets.map { sheet in
            XLSXSheet.cells(sheet: try unzip(["-p", url.path, sheet]), sharedStrings: sharedStrings)
        }
    }

    private static func unzip(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LoadError.unreadable(URL(fileURLWithPath: arguments.last ?? "").lastPathComponent)
        }
        return data
    }
}

/// Abgleich mit SAP ByDesign: Aufgabenliste einlesen, Projekte Kunden zuordnen, PSP-Elemente übernehmen.
struct SAPSyncSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    var initialRows: [SAPTaskRow]?

    @State private var plan: SAPImport.Plan?
    @State private var choices: [String: SAPCustomerChoice] = [:]
    @State private var deactivateMissing = true
    @State private var problem: String?
    @State private var result: String?
    @State private var isTargeted = false
    @State private var showsFilePicker = false
    @State private var isReadingImage = false
    @State private var namingProject: String?
    @State private var newCustomerName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Abgleich mit SAP ByDesign")
                    .font(.title2.weight(.semibold))
                Text("Deine Projektaufgaben werden zu PSP-Elementen bei den Kunden. In SAP ändert sich nichts.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()

            Group {
                if let result {
                    finished(result)
                } else if let plan {
                    review(plan)
                } else {
                    start
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if let plan, result == nil {
                    Text(summary(plan))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if result != nil {
                    Button("Fertig") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    if plan != nil {
                        Button("Andere Liste") {
                            plan = nil
                            problem = nil
                        }
                    }
                    Button("Abbrechen") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    if let plan {
                        Button("Übernehmen") { apply(plan) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(changeCount(plan) == 0)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 760, height: 660)
        .onAppear {
            if plan == nil, let initialRows { show(initialRows) }
        }
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: SAPImportLoader.fileTypes) { picked in
            if case .success(let url) = picked { load(url) }
        }
    }

    // MARK: Schritte

    private var start: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Direkt aus ByDesign holen")
                        .font(.headline)
                    Text("Anmelden wie im Browser, Aufgabenliste öffnen, „Aufgaben holen“. Ohne Export.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("ByDesign öffnen") {
                    dismiss()
                    openWindow(id: "bydesign")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentSoft))

            VStack(spacing: 12) {
                Image(systemName: "tablecells.badge.ellipsis")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                Text("Oder: Excel-Export oder Bildschirmfoto der Liste hierher ziehen")
                    .font(.headline)
                HStack(spacing: 10) {
                    Button("Datei wählen …") { showsFilePicker = true }
                    Button("Aus Zwischenablage einfügen") { loadFromPasteboard() }
                        .keyboardShortcut("v", modifiers: .command)
                }
                if isReadingImage {
                    ProgressView("Texterkennung läuft …")
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in load(url) }
                }
                return true
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("So geht’s")
                    .font(.headline)
                step(1, "Öffne in ByDesign die Liste deiner Aufgaben (die mit Kategorie und Aufgabennummer).")
                step(2, "Blende über die Tabellen-Einstellungen am besten auch Aufgabenname, Projekt und Kunde ein. Dann ordnet Tagwerk die Aufgaben selbst den Kunden zu.")
                step(3, "Ohne Export: Bildschirmfoto der Liste machen (⇧⌘4, mit ⌃ landet es in der Zwischenablage) und hierher ziehen oder einfügen. Tagwerk liest die Nummern per Texterkennung.")
                Text("Du kannst den Abgleich jederzeit wiederholen. Bekannte Aufgaben werden aktualisiert, nichts wird doppelt angelegt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func review(_ plan: SAPImport.Plan) -> some View {
        List {
            ForEach(plan.groups) { group in
                Section {
                    ForEach(group.items) { item in
                        HStack(spacing: 12) {
                            Text(item.row.code)
                                .font(.body.monospacedDigit())
                                .frame(width: 150, alignment: .leading)
                            Text(item.row.title.isEmpty ? "ohne Bezeichnung" : item.row.title)
                                .foregroundStyle(item.row.title.isEmpty ? Color.secondary : Color.primary)
                                .lineLimit(1)
                            Spacer()
                            badge(for: item.change)
                        }
                    }
                } header: {
                    groupHeader(group)
                }
            }
            if !plan.missing.isEmpty {
                Section {
                    Toggle(isOn: $deactivateMissing) {
                        Text(plan.missing.count == 1
                             ? "Dieses PSP-Element deaktivieren (bleibt an alten Zeiten erhalten)"
                             : "Diese \(plan.missing.count) PSP-Elemente deaktivieren (bleiben an alten Zeiten erhalten)")
                    }
                    ForEach(plan.missing) { psp in
                        HStack(spacing: 12) {
                            Text(psp.code)
                                .font(.body.monospacedDigit())
                                .frame(width: 150, alignment: .leading)
                            Text(psp.title)
                                .lineLimit(1)
                            Spacer()
                            Text(model.customer(psp.customerID)?.name ?? "")
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Nicht mehr in der Liste")
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
    }

    private func groupHeader(_ group: SAPImport.ProjectGroup) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.project)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                let details = [group.projectName, group.customerName.map { "Kunde in SAP: \($0)" }].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            let choice = choices[group.project] ?? .skip
            Menu {
                ForEach(model.activeCustomers) { customer in
                    Button(customer.name) { choices[group.project] = .existing(customer.id) }
                }
                ForEach(pendingNewCustomers, id: \.self) { name in
                    Button("\(name) (wird angelegt)") { choices[group.project] = .new(name) }
                }
                if let name = group.customerName,
                   !model.activeCustomers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                   !pendingNewCustomers.contains(name) {
                    Button("Neuer Kunde „\(name)“") { choices[group.project] = .new(name) }
                }
                if !model.activeCustomers.isEmpty || !pendingNewCustomers.isEmpty {
                    Divider()
                }
                Button("Neuer Kunde …") {
                    newCustomerName = group.customerName ?? group.projectName ?? ""
                    namingProject = group.project
                }
                if choice != .skip {
                    Button("Diesen Kunden für alle Projekte ohne Kunde") {
                        for other in plan?.groups ?? [] where (choices[other.project] ?? .skip) == .skip {
                            choices[other.project] = choice
                        }
                    }
                }
                Divider()
                Button("Nicht übernehmen") { choices[group.project] = .skip }
            } label: {
                Text(label(for: choice))
            }
            .menuStyle(.button)
            .fixedSize()
            .foregroundStyle(choice == .skip ? Color.orange : Color.primary)
            .popover(isPresented: Binding(
                get: { namingProject == group.project },
                set: { if !$0 { namingProject = nil } }
            )) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Neuer Kunde für \(group.project)")
                        .font(.headline)
                    TextField("Name des Kunden", text: $newCustomerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit { confirmNewCustomer(for: group.project) }
                    HStack {
                        Spacer()
                        Button("Übernehmen") { confirmNewCustomer(for: group.project) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(newCustomerName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(14)
            }
        }
        .padding(.vertical, 4)
    }

    /// Neue Kunden, die in diesem Abgleich schon gewählt wurden (werden beim Übernehmen angelegt).
    private var pendingNewCustomers: [String] {
        Array(Set(choices.values.compactMap { choice -> String? in
            if case .new(let name) = choice { return name }
            return nil
        })).sorted()
    }

    private func label(for choice: SAPCustomerChoice) -> String {
        switch choice {
        case .skip: return "Kunde wählen …"
        case .existing(let id): return model.customer(id)?.name ?? "Kunde"
        case .new(let name): return "\(name) (neu)"
        }
    }

    private func confirmNewCustomer(for project: String) {
        let name = newCustomerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = model.activeCustomers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            choices[project] = .existing(existing.id)
        } else {
            choices[project] = .new(name)
        }
        namingProject = nil
    }

    @ViewBuilder
    private func badge(for change: SAPImport.Change) -> some View {
        switch change {
        case .new:
            tag("neu", color: .green)
        case .renamed(let old):
            tag("Bezeichnung geändert", color: .orange)
                .help(old.isEmpty ? "Bisher ohne Bezeichnung" : "Bisher: \(old)")
        case .reactivated:
            tag("wieder aktiv", color: .blue)
        case .unchanged:
            Text("schon da")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func finished(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(text)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Die PSP-Elemente stehen jetzt bei den Kunden und in jeder Aufgabe zur Auswahl.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    // MARK: Aktionen

    private func load(_ url: URL) {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
            readImage { try await ScreenTextReader.taskRows(fromImageAt: url) }
            return
        }
        do {
            show(try SAPImportLoader.rows(from: url))
        } catch {
            problem = String(describing: error)
        }
    }

    private func loadFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) == nil,
           let image = NSImage(pasteboard: pasteboard)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            readImage { try await ScreenTextReader.taskRows(from: image) }
            return
        }
        do {
            show(try SAPImportLoader.rowsFromPasteboard())
        } catch {
            problem = String(describing: error)
        }
    }

    /// Bildschirmfoto per Texterkennung lesen.
    private func readImage(_ read: @escaping () async throws -> [SAPTaskRow]) {
        isReadingImage = true
        problem = nil
        Task {
            defer { isReadingImage = false }
            do {
                let rows = try await read()
                if rows.isEmpty {
                    problem = "Auf dem Bild keine Aufgabennummern wie „CPSO8643-12“ gefunden."
                } else {
                    show(rows)
                }
            } catch {
                problem = String(describing: error)
            }
        }
    }

    private func show(_ rows: [SAPTaskRow]) {
        let plan = model.sapImportPlan(rows)
        var initial: [String: SAPCustomerChoice] = [:]
        for group in plan.groups {
            if let id = group.suggestedCustomerID {
                initial[group.project] = .existing(id)
            } else if let name = group.customerName {
                initial[group.project] = .new(name)
            }
        }
        choices = initial
        problem = nil
        self.plan = plan
    }

    private func apply(_ plan: SAPImport.Plan) {
        result = model.applySAPImport(plan, choices: choices, deactivateMissing: deactivateMissing)
    }

    private func changeCount(_ plan: SAPImport.Plan) -> Int {
        let chosen = plan.groups.filter { (choices[$0.project] ?? .skip) != .skip }
        let changes = chosen.reduce(0) { count, group in
            count + group.items.filter { item in
                if item.change != .unchanged { return true }
                // Projekt einem anderen Kunden zugeordnet
                if case .existing(let id) = choices[group.project], let existing = item.existing { return existing.customerID != id }
                return false
            }.count
        }
        return changes + (deactivateMissing ? plan.missing.count : 0)
    }

    private func summary(_ plan: SAPImport.Plan) -> String {
        let total = plan.groups.reduce(0) { $0 + $1.items.count }
        let new = plan.groups.reduce(0) { $0 + $1.newCount }
        let changed = plan.groups.reduce(0) { $0 + $1.changedCount }
        var parts = ["\(total) Aufgaben in \(plan.groups.count) \(plan.groups.count == 1 ? "Projekt" : "Projekten")"]
        if new > 0 { parts.append("\(new) neu") }
        if changed > 0 { parts.append("\(changed) geändert") }
        if new == 0, changed == 0 { parts.append("alles schon da") }
        return parts.joined(separator: " · ")
    }
}
