import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Eine Projektaufgabe aus SAP ByDesign, z. B. „CPSO8643-12“, mit einer Tätigkeit.
/// Hat eine Aufgabe mehrere Tätigkeiten (Activities), gibt es je Tätigkeit eine Zeile.
public struct SAPTaskRow: Hashable, Sendable {
    /// Aufgabennummer, wird in Tagwerk zum PSP-Element
    public var code: String
    public var title: String
    /// Projekt-ID, sonst der Teil der Aufgabennummer vor dem letzten „-“
    public var project: String
    public var projectName: String?
    public var customerName: String?
    public var category: String?
    /// Tätigkeit aus SAP (Activity), z. B. „Beratung“ oder „Interne Besprechung“
    public var activity: String?

    public init(code: String, title: String = "", project: String? = nil, projectName: String? = nil, customerName: String? = nil, category: String? = nil, activity: String? = nil) {
        self.code = code
        self.title = title
        self.project = project ?? SAPImport.projectKey(of: code)
        self.projectName = projectName
        self.customerName = customerName
        self.category = category
        self.activity = activity
    }

    /// Aufgabe und Tätigkeit zusammen: „CPSO8643-12|beratung“
    public var key: String { SAPImport.key(code: code, activity: activity) }

    var hasActivity: Bool { !(activity?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }

    /// Ergänzt leere Angaben aus einer zweiten Lesung derselben Zeile.
    mutating func fillMissing(from other: SAPTaskRow) {
        if title.isEmpty || SAPImport.isNoise(title), !other.title.isEmpty, !SAPImport.isNoise(other.title) { title = other.title }
        if projectName == nil { projectName = other.projectName }
        if customerName == nil { customerName = other.customerName }
        if category == nil { category = other.category }
        if !hasActivity, other.hasActivity { activity = other.activity }
    }
}

/// Liest die Aufgabenliste aus ByDesign (Webseite, Excel-Export oder kopierte Tabelle) und gleicht sie
/// mit den PSP-Elementen in Tagwerk ab. Ohne API-Zugriff auf SAP. Versteht die deutsche und die englische Oberfläche.
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

    /// Schlüssel aus Aufgabennummer und Tätigkeit, unabhängig von Groß- und Kleinschreibung.
    public static func key(code: String, activity: String?) -> String {
        let normalized = activity?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return "\(code.uppercased())|\(normalized)"
    }

    /// Findet eine Aufgabennummer irgendwo im Text.
    static func firstTaskID(in text: String) -> String? {
        text.split(whereSeparator: { $0.isWhitespace || $0 == ";" || $0 == "," || $0 == "|" || $0 == "(" || $0 == ")" || $0 == "[" || $0 == "]" || $0 == ":" })
            .map(String.init)
            .first(where: looksLikeTaskID)
    }

    // MARK: Tabellen lesen

    /// Zeilen aus einer Tabelle. Erkennt die Kopfzeile (Task ID, Work Package Task, Activity, Aufgabenname, Tätigkeit …).
    /// Die Spalte mit den Aufgabennummern wird an ihrem Inhalt erkannt: die mit den meisten Nummern.
    public static func rows(fromCells cells: [[String]]) -> [SAPTaskRow] {
        let table = cells
            .map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in row.contains { !$0.isEmpty } }
        guard !table.isEmpty else { return [] }

        var columns = Columns()
        var bodyStart = 0
        var bestScore = 0
        for (index, row) in table.prefix(40).enumerated() where !row.contains(where: { firstTaskID(in: $0) != nil }) {
            let detected = Columns(header: row)
            let score = detected.recognized + (detected.code != nil ? 1 : 0)
            if score > bestScore, detected.recognized >= 2 || detected.code != nil {
                bestScore = score
                columns = detected
                bodyStart = index + 1
            }
        }

        let body = Array(table.dropFirst(bodyStart))
        if let best = codeColumn(in: body), columns.recognized > 0 {
            let current = columns.code.map { idCount(in: body, column: $0) } ?? (exact: 0, embedded: 0)
            let found = idCount(in: body, column: best)
            if columns.code == nil || found.exact > current.exact || (current.exact == 0 && found.embedded > current.embedded) {
                columns.code = best
            }
        }
        if columns.title == columns.code { columns.title = nil }

        return merged(body.compactMap { parse($0, columns: columns) })
    }

    /// Spalte mit den meisten Aufgabennummern (erst ganze Zellen, sonst Nummern im Text).
    static func codeColumn(in rows: [[String]]) -> Int? {
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return nil }
        let counts = (0..<width).map { idCount(in: rows, column: $0) }
        guard let best = counts.indices.max(by: { (counts[$0].exact, counts[$0].embedded, -$0) < (counts[$1].exact, counts[$1].embedded, -$1) }),
              counts[best].exact + counts[best].embedded > 0 else { return nil }
        return best
    }

    static func idCount(in rows: [[String]], column: Int) -> (exact: Int, embedded: Int) {
        var exact = 0
        var embedded = 0
        for row in rows where column < row.count {
            if looksLikeTaskID(row[column]) {
                exact += 1
            } else if firstTaskID(in: row[column]) != nil {
                embedded += 1
            }
        }
        return (exact, embedded)
    }

    /// Text aus der Zwischenablage oder einer CSV-Datei: Tabulator, Semikolon oder Komma als Trenner.
    public static func rows(fromText text: String) -> [SAPTaskRow] {
        let cells = TableText.cells(from: text)
        if cells.allSatisfy({ $0.count <= 1 }) {
            return rows(fromLines: cells.compactMap(\.first))
        }
        return rows(fromCells: cells)
    }

    /// Text-Schnipsel einer Webseite mit ihrer Lage auf dem Bildschirm: wird zu einer Tabelle wie auf dem Bildschirm.
    public static func rows(fromLayout boxes: [TextBox]) -> [SAPTaskRow] {
        rows(fromCells: LayoutTable.cells(from: boxes))
    }

    /// Text ohne Spalten, z. B. von einer Webseite abgelesen: jede Zelle eine Zeile.
    /// Steht in der Zeile nur die Aufgabennummer, ist die nächste Zeile meist der Aufgabenname.
    public static func rows(fromLines lines: [String]) -> [SAPTaskRow] {
        let clean = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var result: [SAPTaskRow] = []
        for (index, line) in clean.enumerated() {
            guard let code = firstTaskID(in: line) else { continue }
            var title = cleanTitle(remainder(of: line, without: code))
            if title.isEmpty || isNoise(title), index + 1 < clean.count {
                let next = clean[index + 1]
                if firstTaskID(in: next) == nil, !isNoise(next), next.count <= 140, next.contains(where: \.isLetter) {
                    title = next
                }
            }
            if isNoise(title) { title = "" }
            result.append(SAPTaskRow(code: code, title: title))
        }
        return merged(result)
    }

    /// Von mehreren Lesarten derselben Seite die ergiebigste: die meisten Aufgabennummern,
    /// dann die meisten Zeilen mit Tätigkeit, dann die meisten mit Namen. Bei Gleichstand gewinnt die erste.
    public static func best(of candidates: [[SAPTaskRow]]) -> [SAPTaskRow] {
        func score(_ rows: [SAPTaskRow]) -> (Int, Int, Int) {
            (Set(rows.map { $0.code.uppercased() }).count,
             rows.filter(\.hasActivity).count,
             rows.filter { !$0.title.isEmpty && !isNoise($0.title) }.count)
        }
        var result: [SAPTaskRow] = []
        for candidate in candidates where score(candidate) > score(result) {
            result = candidate
        }
        return result
    }

    /// Fasst doppelt gelesene Zeilen zusammen (z. B. beim Scrollen): eine Zeile je Aufgabe und Tätigkeit.
    /// Zeilen ohne Tätigkeit entfallen, wenn dieselbe Aufgabe auch mit Tätigkeit gelesen wurde.
    public static func merged(_ rows: [SAPTaskRow]) -> [SAPTaskRow] {
        var order: [String] = []
        var byKey: [String: SAPTaskRow] = [:]
        for row in rows {
            let key = row.key
            if var existing = byKey[key] {
                existing.fillMissing(from: row)
                byKey[key] = existing
            } else {
                order.append(key)
                byKey[key] = row
            }
        }
        let all = order.compactMap { byKey[$0] }
        let codesWithActivity = Set(all.filter(\.hasActivity).map { $0.code.uppercased() })
        var titles: [String: String] = [:]
        for row in all where !row.title.isEmpty && !isNoise(row.title) {
            titles[row.code.uppercased()] = titles[row.code.uppercased()] ?? row.title
        }
        return all.compactMap { row in
            if !row.hasActivity, codesWithActivity.contains(row.code.uppercased()) { return nil }
            var copy = row
            if copy.title.isEmpty || isNoise(copy.title) { copy.title = titles[copy.code.uppercased()] ?? "" }
            return copy
        }
    }

    // MARK: Texterkennung

    /// Bereinigt eine Zelle aus der Texterkennung: „CPSO8643 – 12“ → „CPSO8643-12“.
    public static func repairOCRCell(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = value
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
        if !looksLikeTaskID(value), looksLikeTaskID(joined) { return joined }
        return value
    }

    /// Die Texterkennung verwechselt gern Buchstaben und Ziffern („CPS08643“ statt „CPSO8643“).
    /// Haben die meisten Nummern dieselbe Buchstabenfolge vorne, werden Ausreißer daran angeglichen.
    public static func repairOCRCodes(_ rows: [SAPTaskRow]) -> [SAPTaskRow] {
        func letterPrefix(_ code: String) -> String { String(code.prefix { $0.isLetter }) }
        let counts = Dictionary(rows.map { (letterPrefix($0.code), 1) }, uniquingKeysWith: +)
        // Bei Gleichstand die längere Buchstabenfolge: verlesen wird eher ein Buchstabe zur Ziffer als umgekehrt.
        guard let dominant = counts.max(by: { ($0.value, $0.key.count) < ($1.value, $1.key.count) })?.key,
              !dominant.isEmpty else { return rows }
        // Gibt es eine längere Folge, die mit der häufigsten beginnt („CPSO“ neben „CPS“), ist sie die richtige,
        // auch wenn die meisten Nummern verlesen sind („CPS08643“).
        let target = counts.keys.filter { $0.hasPrefix(dominant) }.max { $0.count < $1.count } ?? dominant
        let lookalike: [Character: Character] = ["O": "0", "I": "1", "S": "5", "B": "8", "Z": "2", "G": "6"]
        let repaired: [SAPTaskRow] = rows.compactMap { row in
            var code = row.code
            let prefix = letterPrefix(code)
            if prefix != target, target.hasPrefix(prefix) {
                let missing = target.dropFirst(prefix.count)
                let misread = String(missing.map { lookalike[$0] ?? $0 })
                let rest = code.dropFirst(prefix.count)
                if rest.hasPrefix(misread) {
                    code = target + rest.dropFirst(misread.count)
                }
            }
            guard looksLikeTaskID(code) else { return nil }
            guard code != row.code else { return row }
            return SAPTaskRow(code: code, title: row.title, projectName: row.projectName, customerName: row.customerName, category: row.category, activity: row.activity)
        }
        return merged(repaired)
    }

    private static func parse(_ row: [String], columns: Columns) -> SAPTaskRow? {
        func cell(_ index: Int?) -> String? {
            guard let index, index < row.count else { return nil }
            let value = row[index]
            return value.isEmpty ? nil : value
        }

        if let codeColumn = columns.code {
            guard let raw = cell(codeColumn) else { return nil }
            let code: String
            var rest = ""
            if looksLikeTaskID(raw) {
                code = raw
            } else if let found = firstTaskID(in: raw) {
                code = found
                rest = cleanTitle(remainder(of: raw, without: found))
            } else {
                return nil
            }
            var title = cell(columns.title).map { value in
                firstTaskID(in: value).map { cleanTitle(remainder(of: value, without: $0)) } ?? value
            } ?? ""
            if isNoise(title) { title = "" }
            if title.isEmpty, !rest.isEmpty, !isNoise(rest) { title = rest }
            let activity = cell(columns.activity).flatMap { isNoise($0) || looksLikeTaskID($0) ? nil : $0 }
            if title.isEmpty {
                // Erste sinnvolle Textspalte, die nicht schon belegt ist
                let used = Set([columns.code, columns.project, columns.projectName, columns.customer, columns.category, columns.activity].compactMap { $0 })
                title = row.enumerated().first { index, value in
                    !used.contains(index) && !value.isEmpty && firstTaskID(in: value) == nil && value.contains(where: \.isLetter) && !isNoise(value)
                }?.element ?? ""
            }
            if title.isEmpty, let activity { title = activity }
            let project = cell(columns.project).flatMap { looksLikeTaskID($0) ? projectKey(of: $0) : $0 }
            return SAPTaskRow(
                code: code,
                title: title,
                project: project ?? projectKey(of: code),
                projectName: cell(columns.projectName),
                customerName: cell(columns.customer),
                category: cell(columns.category),
                activity: activity
            )
        }

        // Ohne Kopfzeile: Aufgabennummer suchen, der längste übrige Text ist der Name.
        guard let codeIndex = row.firstIndex(where: looksLikeTaskID) else {
            // Eine Zeile Fließtext, z. B. aus dem Browser kopiert
            guard let index = row.firstIndex(where: { firstTaskID(in: $0) != nil }), let code = firstTaskID(in: row[index]) else { return nil }
            let rest = cleanTitle(remainder(of: row[index], without: code))
            let others = row.enumerated().filter { $0.offset != index && !$0.element.isEmpty && $0.element.contains(where: \.isLetter) }.map(\.element)
            let title = ([rest] + others).filter { !$0.isEmpty && !isNoise($0) }.max { $0.count < $1.count } ?? ""
            return SAPTaskRow(code: code, title: title)
        }
        let code = row[codeIndex]
        let others = row.enumerated()
            .filter { $0.offset != codeIndex && !$0.element.isEmpty && $0.element.contains(where: \.isLetter) && firstTaskID(in: $0.element) == nil }
            .map(\.element)
        let title = others.filter { !isNoise($0) }.max { $0.count < $1.count } ?? ""
        return SAPTaskRow(code: code, title: title, category: others.first(where: isCategory))
    }

    /// Text ohne die Aufgabennummer und ohne Trennzeichen drumherum.
    static func remainder(of text: String, without code: String) -> String {
        text.replacingOccurrences(of: code, with: " ")
            .replacingOccurrences(of: "()", with: " ")
            .replacingOccurrences(of: "[]", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–·:|;()[]")))
    }

    private static func isCategory(_ text: String) -> Bool {
        let folded = text.lowercased().trimmingCharacters(in: .whitespaces)
        return folded.hasPrefix("projektaufgabe") || folded.hasPrefix("serviceauftrag") || folded == "aufgabe"
            || ["project task", "service order", "service order task", "work package", "phase", "milestone", "task", "meilenstein"].contains(folded)
    }

    /// Überschriften und Bedienelemente, die kein Aufgabenname sind.
    private static let interfaceWords: Set<String> = [
        "task id", "task", "task name", "work package", "work package task", "work package task id", "activity", "activities",
        "project", "project id", "project name", "customer", "category", "description", "status", "service",
        "aufgabe", "aufgabennummer", "aufgabenname", "tätigkeit", "projekt", "kunde", "bezeichnung", "kategorie",
        "new", "edit", "actions", "export", "personalize", "find", "advanced", "show", "go", "reset", "refresh", "more",
        "neu", "bearbeiten", "aktionen", "exportieren", "personalisieren", "suchen", "erweitert", "anzeigen", "zurücksetzen", "aktualisieren",
    ]

    /// Text, der kein Aufgabenname ist: Kategorie, Gruppenzeilen, Überschriften der ByDesign-Liste.
    static func isNoise(_ text: String) -> Bool {
        let folded = text.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":…."))
            .trimmingCharacters(in: .whitespaces)
        return isCategory(text)
            || interfaceWords.contains(folded)
            || folded.hasPrefix("kategorie")
            || folded.hasPrefix("category:")
            || folded.hasPrefix("gruppieren nach")
            || folded.hasPrefix("group by")
            || folded.hasPrefix("aktuelle arbeitspakete")
            || folded.hasPrefix("current work package")
            || folded.hasPrefix("my work package")
            || folded.contains("(null)")
            || folded.contains("projektaufgabenbestätigung")
            || folded.contains("project task confirmation")
    }

    private static func cleanTitle(_ text: String) -> String {
        var value = text
        for word in ["Projektaufgabenbestätigung", "Project Task Confirmation", "Projektaufgabe", "Project Task"] where value.hasPrefix(word) {
            value = String(value.dropFirst(word.count))
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// Welche Spalte was enthält, erkannt an der Kopfzeile (deutsch oder englisch).
    struct Columns {
        var code: Int?
        var title: Int?
        var project: Int?
        var projectName: Int?
        var customer: Int?
        var category: Int?
        var activity: Int?

        init() {}

        var recognized: Int {
            [code, title, project, projectName, customer, category, activity].compactMap { $0 }.count
        }

        static func normalize(_ raw: String) -> String {
            raw.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
                .filter { $0.isLetter || $0.isNumber }
        }

        init(header: [String]) {
            for (index, raw) in header.enumerated() {
                let name = Self.normalize(raw)
                guard !name.isEmpty, name.count <= 40 else { continue }
                switch name {
                case "aufgabennummer", "aufgabenid", "aufgabeid", "aufgabennr", "projektaufgabenid", "projektaufgabennummer",
                     "taskid", "tasknumber", "tasknr", "projecttaskid", "workpackageid", "workpackagetaskid", "psp", "pspelement", "id":
                    if code == nil { code = index }
                case "aufgabenname", "aufgabenbezeichnung", "aufgabe", "projektaufgabe", "bezeichnung", "beschreibung", "name", "kurzbeschreibung", "titel",
                     "taskname", "task", "taskdescription", "workpackagetask", "workpackage", "workpackagename", "workpackagetaskname",
                     "workpackagedescription", "projecttask", "projecttaskname", "description", "title":
                    if title == nil { title = index }
                case "projekt", "projektid", "projektnummer", "projektnr", "project", "projectid", "projectnumber":
                    if project == nil { project = index }
                case "projektname", "projektbezeichnung", "projectname", "projectdescription":
                    if projectName == nil { projectName = index }
                case "kunde", "kundenname", "kundenid", "auftraggeber", "account", "accountname", "customer", "customername", "client", "kontoname", "konto":
                    if customer == nil { customer = index }
                case "kategorie", "category", "typ", "art", "type", "tasktype", "tasktyp":
                    if category == nil { category = index }
                case "tatigkeit", "taetigkeit", "tatigkeitsart", "tatigkeiten", "aktivitat", "aktivitaten", "leistung", "leistungsart",
                     "activity", "activities", "activityname", "activitydescription", "activitytype", "service", "serviceprodukt",
                     "serviceproduct", "serviceproductdescription", "servicedescription":
                    if activity == nil { activity = index }
                default:
                    if code == nil, name.hasPrefix("aufgabennummer") || name.hasPrefix("aufgabenid") || name.hasPrefix("taskid") { code = index }
                    else if activity == nil, name.hasPrefix("tatigkeit") || name.hasPrefix("leistung") || name.hasPrefix("activity") || name.hasPrefix("serviceproduct") { activity = index }
                    else if title == nil, name.hasPrefix("aufgabenname") || name.hasPrefix("aufgabenbezeichnung") || name.hasPrefix("workpackagetask") || name.hasPrefix("taskname") { title = index }
                    else if customer == nil, name.hasPrefix("kunde") || name.hasPrefix("customer") { customer = index }
                    else if projectName == nil, name.hasPrefix("projektname") || name.hasPrefix("projectname") { projectName = index }
                }
            }
        }
    }

    // MARK: Abgleich

    public enum Change: Equatable, Sendable {
        /// Noch nicht in Tagwerk
        case new
        /// Bezeichnung oder Tätigkeit in SAP geändert (alter Titel)
        case renamed(String)
        /// War deaktiviert und taucht wieder auf
        case reactivated
        case unchanged
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String { row.key }
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
        var groups: [String: ProjectGroup] = [:]
        var order: [String] = []
        var claimed = Set<UUID>()
        /// Aufgaben, die ohne Tätigkeit gelesen wurden: alle ihre Tätigkeiten gelten als noch vorhanden.
        var seenWithoutActivity = Set<String>()

        for row in rows {
            let sameCode = existing.filter { $0.code.caseInsensitiveCompare(row.code) == .orderedSame && !claimed.contains($0.id) }
            let known: PSPElement?
            if row.hasActivity {
                known = sameCode.first(where: { PSPElement.sameActivity($0.activity, row.activity) })
                    ?? sameCode.first(where: { ($0.activity ?? "").trimmingCharacters(in: .whitespaces).isEmpty })
            } else {
                known = sameCode.first
                seenWithoutActivity.insert(row.code.uppercased())
            }
            if let known { claimed.insert(known.id) }
            let change: Change
            if let known {
                if !known.isActive {
                    change = .reactivated
                } else if !row.title.isEmpty, row.title != known.title {
                    change = .renamed(known.title)
                } else if row.hasActivity, !PSPElement.sameActivity(row.activity, known.activity) {
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

        let importedProjects = Set(rows.map(\.project))
        let missing = existing.filter { psp in
            psp.isActive
                && !claimed.contains(psp.id)
                && !seenWithoutActivity.contains(psp.code.uppercased())
                && importedProjects.contains(projectKey(of: psp.code))
        }

        return Plan(groups: order.compactMap { groups[$0] }, missing: missing.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending })
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
                    if let activity = item.row.activity, !activity.isEmpty, psp.activity != activity { psp.activity = activity; changed = true }
                    if !psp.isActive { psp.isActive = true; changed = true }
                    if psp.customerID != customerID { psp.customerID = customerID; changed = true }
                    if changed { result.append(psp) }
                } else {
                    result.append(PSPElement(customerID: customerID, code: item.row.code, title: item.row.title, activity: item.row.activity))
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

    public static func decodeEntities(_ text: String) -> String {
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
