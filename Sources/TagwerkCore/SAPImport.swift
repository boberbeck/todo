import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Eine Projektaufgabe aus SAP ByDesign, z. B. „CPSO8643-12“.
public struct SAPTaskRow: Hashable, Sendable {
    /// Aufgabennummer, wird in Tagwerk zum PSP-Element
    public var code: String
    public var title: String
    /// Projekt-ID, sonst der Teil der Aufgabennummer vor dem letzten „-“
    public var project: String
    public var projectName: String?
    public var customerName: String?
    public var category: String?

    public init(code: String, title: String = "", project: String? = nil, projectName: String? = nil, customerName: String? = nil, category: String? = nil) {
        self.code = code
        self.title = title
        self.project = project ?? SAPImport.projectKey(of: code)
        self.projectName = projectName
        self.customerName = customerName
        self.category = category
    }
}

/// Liest die Aufgabenliste aus ByDesign (Excel-Export oder kopierte Tabelle) und gleicht sie
/// mit den PSP-Elementen in Tagwerk ab. Ohne API-Zugriff auf SAP.
public enum SAPImport {
    // MARK: Aufgabennummern

    /// „CPSO8643-12“, „P1000-3“, „CPSO8643-12-1“. Großbuchstaben, Ziffern, mindestens ein Bindestrich mit Zahl dahinter.
    public static func looksLikeTaskID(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 4, value.count <= 40 else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 2, let head = parts.first, !head.isEmpty else { return false }
        guard head.first?.isLetter == true, head.contains(where: \.isNumber) else { return false }
        guard head.allSatisfy({ ($0.isLetter && $0.isUppercase) || $0.isNumber }) else { return false }
        return parts.dropFirst().allSatisfy { part in !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber } }
            && parts.last?.allSatisfy(\.isNumber) == true
    }

    /// „CPSO8643-12“ → „CPSO8643“
    public static func projectKey(of code: String) -> String {
        guard let dash = code.lastIndex(of: "-") else { return code }
        return String(code[..<dash])
    }

    /// Findet eine Aufgabennummer irgendwo im Text.
    static func firstTaskID(in text: String) -> String? {
        text.split(whereSeparator: { $0.isWhitespace || $0 == ";" || $0 == "," || $0 == "|" || $0 == "(" || $0 == ")" })
            .map(String.init)
            .first(where: looksLikeTaskID)
    }

    // MARK: Tabellen lesen

    /// Zeilen aus einer Tabelle. Erkennt die Kopfzeile (Aufgabennummer, Aufgabenname, Projekt, Kunde …);
    /// ohne Kopfzeile wird die Spalte mit den Aufgabennummern gesucht.
    public static func rows(fromCells cells: [[String]]) -> [SAPTaskRow] {
        let table = cells
            .map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in row.contains { !$0.isEmpty } }
        guard !table.isEmpty else { return [] }

        var columns = Columns()
        var bodyStart = 0
        for (index, row) in table.prefix(10).enumerated() {
            let detected = Columns(header: row)
            if detected.code != nil, !row.contains(where: looksLikeTaskID) {
                columns = detected
                bodyStart = index + 1
                break
            }
        }

        var result: [SAPTaskRow] = []
        var seen = Set<String>()
        for row in table.dropFirst(bodyStart) {
            guard let parsed = parse(row, columns: columns), !seen.contains(parsed.code) else { continue }
            seen.insert(parsed.code)
            result.append(parsed)
        }
        return result
    }

    /// Text aus der Zwischenablage oder einer CSV-Datei: Tabulator, Semikolon oder Komma als Trenner.
    public static func rows(fromText text: String) -> [SAPTaskRow] {
        rows(fromCells: TableText.cells(from: text))
    }

    private static func parse(_ row: [String], columns: Columns) -> SAPTaskRow? {
        func cell(_ index: Int?) -> String? {
            guard let index, index < row.count else { return nil }
            let value = row[index]
            return value.isEmpty ? nil : value
        }

        if let codeColumn = columns.code {
            guard let code = cell(codeColumn), looksLikeTaskID(code) else { return nil }
            var title = cell(columns.title) ?? ""
            if title.isEmpty {
                // Erste sinnvolle Textspalte, die nicht schon belegt ist
                let used = Set([columns.code, columns.project, columns.projectName, columns.customer, columns.category].compactMap { $0 })
                title = row.enumerated().first { index, value in
                    !used.contains(index) && !value.isEmpty && !looksLikeTaskID(value) && value.contains(where: \.isLetter)
                }?.element ?? ""
            }
            let project = cell(columns.project).flatMap { looksLikeTaskID($0) ? projectKey(of: $0) : $0 }
            return SAPTaskRow(
                code: code,
                title: title,
                project: project ?? projectKey(of: code),
                projectName: cell(columns.projectName),
                customerName: cell(columns.customer),
                category: cell(columns.category)
            )
        }

        // Ohne Kopfzeile: Aufgabennummer suchen, der längste übrige Text ist der Name.
        guard let codeIndex = row.firstIndex(where: looksLikeTaskID) else {
            // Eine Zeile Fließtext, z. B. aus dem Browser kopiert
            guard row.count == 1, let code = firstTaskID(in: row[0]) else { return nil }
            let rest = row[0].replacingOccurrences(of: code, with: " ")
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–·:|;")))
            return SAPTaskRow(code: code, title: cleanTitle(rest))
        }
        let code = row[codeIndex]
        let others = row.enumerated()
            .filter { $0.offset != codeIndex && !$0.element.isEmpty && $0.element.contains(where: \.isLetter) && !looksLikeTaskID($0.element) }
            .map(\.element)
        let title = others.filter { !isCategory($0) }.max { $0.count < $1.count } ?? ""
        return SAPTaskRow(code: code, title: title, category: others.first(where: isCategory))
    }

    private static func isCategory(_ text: String) -> Bool {
        let folded = text.lowercased()
        return folded.hasPrefix("projektaufgabe") || folded.hasPrefix("serviceauftrag") || folded == "aufgabe"
    }

    private static func cleanTitle(_ text: String) -> String {
        var value = text
        for word in ["Projektaufgabenbestätigung", "Projektaufgabe"] where value.hasPrefix(word) {
            value = String(value.dropFirst(word.count))
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// Welche Spalte was enthält, erkannt an der Kopfzeile.
    struct Columns {
        var code: Int?
        var title: Int?
        var project: Int?
        var projectName: Int?
        var customer: Int?
        var category: Int?

        init() {}

        init(header: [String]) {
            for (index, raw) in header.enumerated() {
                let name = raw.lowercased()
                    .folding(options: .diacriticInsensitive, locale: nil)
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "_", with: "")
                switch name {
                case "aufgabennummer", "aufgabenid", "aufgabeid", "aufgabennr", "projektaufgabe", "projektaufgabenid", "taskid", "tasknumber", "psp", "pspelement", "id":
                    if code == nil { code = index }
                case "aufgabenname", "aufgabenbezeichnung", "aufgabe", "bezeichnung", "beschreibung", "name", "taskname", "kurzbeschreibung", "titel":
                    if title == nil { title = index }
                case "projekt", "projektid", "projektnummer", "projektnr", "project", "projectid":
                    if project == nil { project = index }
                case "projektname", "projektbezeichnung", "projectname":
                    if projectName == nil { projectName = index }
                case "kunde", "kundenname", "kundenid", "auftraggeber", "account", "customer", "kontoname", "konto":
                    if customer == nil { customer = index }
                case "kategorie", "category", "typ", "art":
                    if category == nil { category = index }
                default:
                    if code == nil, name.hasPrefix("aufgabennummer") || name.hasPrefix("aufgabenid") { code = index }
                    if title == nil, name.hasPrefix("aufgabenname") || name.hasPrefix("aufgabenbezeichnung") { title = index }
                    if customer == nil, name.hasPrefix("kunde") { customer = index }
                    if projectName == nil, name.hasPrefix("projektname") { projectName = index }
                }
            }
        }
    }

    // MARK: Abgleich

    public enum Change: Equatable, Sendable {
        /// Noch nicht in Tagwerk
        case new
        /// Bezeichnung in SAP geändert (alter Titel)
        case renamed(String)
        /// War deaktiviert und taucht wieder auf
        case reactivated
        case unchanged
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String { row.code }
        public var row: SAPTaskRow
        public var change: Change
        public var existing: PSPElement?
    }

    /// Eine Gruppe von Aufgaben eines Projekts. Ein Projekt gehört zu genau einem Kunden.
    public struct ProjectGroup: Identifiable, Equatable, Sendable {
        public var id: String { project }
        public var project: String
        public var projectName: String?
        /// Kundenname aus SAP, falls die Tabelle eine Kundenspalte hat
        public var customerName: String?
        /// Vorschlag für den Kunden in Tagwerk
        public var suggestedCustomerID: UUID?
        public var items: [Item]

        public var newCount: Int { items.filter { $0.change == .new }.count }
        public var changedCount: Int { items.filter { $0.change != .new && $0.change != .unchanged }.count }
    }

    public struct Plan: Equatable, Sendable {
        public var groups: [ProjectGroup]
        /// Aktive PSP-Elemente aus denselben Projekten, die in SAP nicht mehr auftauchen
        public var missing: [PSPElement]

        public var isEmpty: Bool { groups.isEmpty }
    }

    public static func plan(rows: [SAPTaskRow], existing: [PSPElement], customers: [Customer]) -> Plan {
        let byCode = Dictionary(existing.map { ($0.code.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: ProjectGroup] = [:]
        var order: [String] = []

        for row in rows {
            let known = byCode[row.code.uppercased()]
            let change: Change
            if let known {
                if !known.isActive {
                    change = .reactivated
                } else if !row.title.isEmpty, row.title != known.title {
                    change = .renamed(known.title)
                } else {
                    change = .unchanged
                }
            } else {
                change = .new
            }
            if groups[row.project] == nil {
                order.append(row.project)
                groups[row.project] = ProjectGroup(project: row.project, projectName: row.projectName, customerName: row.customerName, suggestedCustomerID: nil, items: [])
            }
            groups[row.project]?.items.append(Item(row: row, change: change, existing: known))
            if groups[row.project]?.projectName == nil { groups[row.project]?.projectName = row.projectName }
            if groups[row.project]?.customerName == nil { groups[row.project]?.customerName = row.customerName }
        }

        let active = customers.filter { !$0.isArchived }
        for key in order {
            guard var group = groups[key] else { continue }
            group.suggestedCustomerID = suggestCustomer(for: group, existing: existing, customers: active)
            groups[key] = group
        }

        let importedCodes = Set(rows.map { $0.code.uppercased() })
        let importedProjects = Set(rows.map(\.project))
        let missing = existing.filter { psp in
            psp.isActive
                && !importedCodes.contains(psp.code.uppercased())
                && importedProjects.contains(projectKey(of: psp.code))
        }

        return Plan(groups: order.compactMap { groups[$0] }, missing: missing.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending })
    }

    /// Kunde für ein Projekt: wie bei schon bekannten Aufgaben des Projekts, sonst nach Kundenname in SAP.
    static func suggestCustomer(for group: ProjectGroup, existing: [PSPElement], customers: [Customer]) -> UUID? {
        let ids = Set(customers.map(\.id))
        if let known = group.items.compactMap(\.existing).first(where: { ids.contains($0.customerID) }) {
            return known.customerID
        }
        if let sibling = existing.first(where: { projectKey(of: $0.code) == group.project && ids.contains($0.customerID) }) {
            return sibling.customerID
        }
        let texts = [group.customerName, group.projectName].compactMap { $0 }.map(fold)
        guard !texts.isEmpty else { return nil }
        let matches = customers.filter { customer in
            let names = [customer.name, customer.manageEngineAccount].compactMap { $0 }.map(fold).filter { $0.count >= 3 }
            return names.contains { name in texts.contains { $0 == name || $0.contains(name) || name.contains($0) } }
        }
        return matches.count == 1 ? matches[0].id : nil
    }

    /// Vergleichbarer Name ohne Rechtsform: „Müller Logistik GmbH“ → „mullerlogistik“.
    private static func fold(_ text: String) -> String {
        let legalForms: Set<String> = ["gmbh", "ag", "kg", "co", "mbh", "ug", "se", "ohg", "ev", "gbr", "kgaa"]
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !legalForms.contains($0) }
            .joined()
    }

    /// Wendet den Plan an. `customerFor` liefert pro Projekt den gewählten Kunden (nil = Projekt überspringen).
    /// Gibt die zu speichernden PSP-Elemente zurück.
    public static func apply(
        _ plan: Plan,
        customerFor: (ProjectGroup) -> UUID?,
        deactivateMissing: Bool
    ) -> [PSPElement] {
        var result: [PSPElement] = []
        for group in plan.groups {
            guard let customerID = customerFor(group) else { continue }
            for item in group.items {
                if var psp = item.existing {
                    var changed = false
                    if !item.row.title.isEmpty, psp.title != item.row.title { psp.title = item.row.title; changed = true }
                    if !psp.isActive { psp.isActive = true; changed = true }
                    if psp.customerID != customerID { psp.customerID = customerID; changed = true }
                    if changed { result.append(psp) }
                } else {
                    result.append(PSPElement(customerID: customerID, code: item.row.code, title: item.row.title))
                }
            }
        }
        if deactivateMissing {
            for var psp in plan.missing {
                psp.isActive = false
                result.append(psp)
            }
        }
        return result
    }
}

// MARK: - Tabellenformate

/// Text mit Tabulator, Semikolon oder Komma als Trenner; Anführungszeichen wie in CSV.
public enum TableText {
    public static func cells(from text: String) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let sample = normalized.prefix(4000)
        let separator: Character
        if sample.contains("\t") {
            separator = "\t"
        } else if sample.filter({ $0 == ";" }).count >= sample.filter({ $0 == "\n" }).count, sample.contains(";") {
            separator = ";"
        } else if sample.filter({ $0 == "," }).count >= max(1, sample.filter({ $0 == "\n" }).count) {
            separator = ","
        } else {
            return normalized.split(separator: "\n", omittingEmptySubsequences: true).map { [String($0)] }
        }
        return parseDelimited(normalized, separator: separator)
    }

    static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text)
        var index = 0
        if iterator.first == "\u{FEFF}" { iterator.removeFirst() }
        while index < iterator.count {
            let character = iterator[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < iterator.count, iterator[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"", field.isEmpty {
                inQuotes = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

/// Tabellen aus HTML, z. B. wenn der Browser beim Kopieren eine Tabelle mitliefert.
public enum HTMLTable {
    public static func cells(from html: String) -> [[String]] {
        func find(_ tag: String, in range: Range<String.Index>) -> Range<String.Index>? {
            html.range(of: tag, options: .caseInsensitive, range: range)
        }
        var rows: [[String]] = []
        var searchStart = html.startIndex
        while let rowStart = find("<tr", in: searchStart..<html.endIndex) {
            let rowEnd = find("</tr", in: rowStart.upperBound..<html.endIndex)?.lowerBound ?? html.endIndex
            var cells: [String] = []
            var cellSearch = rowStart.upperBound
            while cellSearch < rowEnd {
                let open = [find("<td", in: cellSearch..<rowEnd), find("<th", in: cellSearch..<rowEnd)]
                    .compactMap { $0 }
                    .min { $0.lowerBound < $1.lowerBound }
                guard let open, let contentStart = html.range(of: ">", range: open.upperBound..<rowEnd)?.upperBound else { break }
                let close = [find("</td", in: contentStart..<rowEnd), find("</th", in: contentStart..<rowEnd)]
                    .compactMap { $0 }
                    .min { $0.lowerBound < $1.lowerBound }?.lowerBound ?? rowEnd
                cells.append(text(fromHTML: String(html[contentStart..<close])))
                cellSearch = close < rowEnd ? html.index(after: close) : rowEnd
            }
            if !cells.isEmpty { rows.append(cells) }
            searchStart = rowEnd < html.endIndex ? html.index(after: rowEnd) : html.endIndex
        }
        return rows
    }

    static func text(fromHTML html: String) -> String {
        var result = ""
        var inTag = false
        for character in html {
            if character == "<" { inTag = true; continue }
            if character == ">" { inTag = false; continue }
            if !inTag { result.append(character) }
        }
        return decodeEntities(result)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß"]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        // numerisch: &#228; oder &#xE4;
        while let start = result.range(of: "&#"), let end = result.range(of: ";", range: start.upperBound..<result.endIndex),
              result.distance(from: start.upperBound, to: end.lowerBound) <= 7 {
            let body = result[start.upperBound..<end.lowerBound]
            let scalar = body.hasPrefix("x") || body.hasPrefix("X")
                ? UInt32(body.dropFirst(), radix: 16)
                : UInt32(body)
            let replacement = scalar.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? ""
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: replacement)
        }
        return result
    }
}

/// Liest das erste Tabellenblatt einer Excel-Datei. Die .xlsx-Datei ist ein ZIP-Archiv;
/// entpackt wird außerhalb (in der App mit /usr/bin/unzip), hier nur das XML gelesen.
public enum XLSXSheet {
    /// `sheet` = xl/worksheets/sheet1.xml, `sharedStrings` = xl/sharedStrings.xml (falls vorhanden)
    public static func cells(sheet: Data, sharedStrings: Data?) -> [[String]] {
        let strings = sharedStrings.map(SharedStringsParser.parse) ?? []
        return SheetParser.parse(sheet, sharedStrings: strings)
    }

    /// Spaltenbuchstaben einer Zellreferenz („C12“ → 2).
    static func columnIndex(of reference: String) -> Int? {
        var value = 0
        var found = false
        for character in reference.uppercased() {
            guard let ascii = character.asciiValue, character.isLetter else { break }
            value = value * 26 + Int(ascii - 64)
            found = true
        }
        return found ? value - 1 : nil
    }

    private final class SharedStringsParser: NSObject, XMLParserDelegate {
        var strings: [String] = []
        var current = ""
        var inItem = false
        var inText = false

        static func parse(_ data: Data) -> [String] {
            let delegate = SharedStringsParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return delegate.strings
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            switch localName(elementName) {
            case "si": inItem = true; current = ""
            case "t": inText = inItem
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch localName(elementName) {
            case "si": strings.append(current); inItem = false
            case "t": inText = false
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current += string }
        }
    }

    private final class SheetParser: NSObject, XMLParserDelegate {
        var rows: [[String]] = []
        var row: [String] = []
        var column = 0
        var cellType = ""
        var value = ""
        var collecting = false
        var inRow = false
        let sharedStrings: [String]

        init(sharedStrings: [String]) {
            self.sharedStrings = sharedStrings
        }

        static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
            let delegate = SheetParser(sharedStrings: sharedStrings)
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return delegate.rows
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            switch localName(elementName) {
            case "row":
                inRow = true
                row = []
                column = 0
            case "c":
                cellType = attributeDict["t"] ?? ""
                if let reference = attributeDict["r"], let index = XLSXSheet.columnIndex(of: reference) {
                    column = index
                }
                value = ""
            case "v", "t":
                collecting = inRow
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch localName(elementName) {
            case "v", "t":
                collecting = false
            case "c":
                var text = value
                if cellType == "s", let index = Int(value), index < sharedStrings.count {
                    text = sharedStrings[index]
                }
                while row.count < column { row.append("") }
                if row.count == column { row.append(text) } else { row[column] = text }
                column += 1
            case "row":
                rows.append(row)
                inRow = false
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collecting { value += string }
        }
    }
}

/// Excel-Tabelle im älteren XML-Format („XML-Kalkulationstabelle 2003“, oft mit Endung .xls).
public enum SpreadsheetML {
    public static func isSpreadsheetML(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        return head.contains("urn:schemas-microsoft-com:office:spreadsheet")
    }

    public static func cells(from data: Data) -> [[String]] {
        let delegate = Parser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var rows: [[String]] = []
        var row: [String] = []
        var value = ""
        var collecting = false
        var pendingIndex: Int?
        var inFirstTable = true
        var tables = 0

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            switch localName(elementName) {
            case "Table":
                tables += 1
                inFirstTable = tables == 1
            case "Row":
                row = []
            case "Cell":
                value = ""
                let index = attributeDict["ss:Index"] ?? attributeDict["Index"]
                pendingIndex = index.flatMap(Int.init).map { $0 - 1 }
            case "Data":
                collecting = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch localName(elementName) {
            case "Data":
                collecting = false
            case "Cell":
                if let pendingIndex { while row.count < pendingIndex { row.append("") } }
                row.append(value)
            case "Row":
                if inFirstTable { rows.append(row) }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collecting { value += string }
        }
    }
}

private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
}
