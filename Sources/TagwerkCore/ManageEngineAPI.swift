import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Zugangsdaten für ServiceDesk Plus (REST-API v3). Der Schlüssel selbst liegt im Schlüsselbund.
public struct ManageEngineConfig: Equatable, Codable, Sendable {
    public enum AuthKind: String, Codable, CaseIterable, Sendable, Identifiable {
        /// On-Premises: persönlicher API-Schlüssel (Header `authtoken`)
        case authtoken
        /// Cloud: OAuth-Token über Zoho (Header `Authorization: Zoho-oauthtoken …`)
        case zohoOAuth

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .authtoken: return "API-Schlüssel (On-Premises)"
            case .zohoOAuth: return "Zoho-OAuth (Cloud)"
            }
        }
    }

    /// z. B. https://helpdesk.firma.de oder https://sdpondemand.manageengine.eu/app/itdesk
    public var baseURL: String
    public var authKind: AuthKind
    /// ID des eigenen Technikers; Worklogs laufen auf ihn, Tickets werden nach ihm gefiltert.
    public var technicianID: String

    public init(baseURL: String = "", authKind: AuthKind = .authtoken, technicianID: String = "") {
        self.baseURL = baseURL
        self.authKind = authKind
        self.technicianID = technicianID
    }

    public var isComplete: Bool {
        hasAddress && !trimmedTechnician.isEmpty
    }

    public var hasAddress: Bool {
        URL(string: trimmedBase) != nil && !trimmedBase.isEmpty
    }

    var trimmedTechnician: String {
        technicianID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Die API erwartet die interne Nummer des Technikers, nicht den Anmeldenamen.
    public var technicianIDIsNumeric: Bool {
        !trimmedTechnician.isEmpty && trimmedTechnician.allSatisfy(\.isNumber)
    }

    var trimmedBase: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    public var isCloud: Bool { trimmedBase.contains("/app/") }
}

public struct ManageEngineTicket: Equatable, Sendable {
    /// interne ID für API-Aufrufe
    public var key: String
    /// Nummer, die Menschen sehen
    public var number: String
    public var subject: String
    public var accountName: String?
    public var statusName: String
    public var isOpen: Bool
    public var webURL: String?
}

/// Ein Techniker, wie er in Tickets steht. Hilft, die eigene Techniker-ID zu finden.
public struct ManageEngineTechnician: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var email: String?
    /// Anmeldename, falls ServiceDesk Plus ihn mitliefert (z. B. „blulay“)
    public var loginName: String?

    public init(id: String, name: String, email: String? = nil, loginName: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.loginName = loginName
    }
}

public enum ManageEngineError: Error, CustomStringConvertible, Equatable {
    case notConfigured
    case technicianNotNumeric
    case invalidURL
    case server(String)
    case unexpectedResponse

    public var description: String {
        switch self {
        case .notConfigured: return "ManageEngine ist noch nicht eingerichtet."
        case .technicianNotNumeric: return "Die Techniker-ID ist eine Zahl, nicht der Anmeldename. „Verbindung testen“ in den Einstellungen findet sie."
        case .invalidURL: return "Die Adresse von ManageEngine ist ungültig."
        case .server(let message): return "ManageEngine meldet: \(message)"
        case .unexpectedResponse: return "Unerwartete Antwort von ManageEngine."
        }
    }
}

/// Baut Anfragen an die ServiceDesk-Plus-API und liest die Antworten. Ohne Netzwerkzugriff, damit es testbar bleibt.
///
/// Grundlage ist die öffentliche Beschreibung der API v3. Feldnamen können je nach Ausgabe
/// (On-Premises, Cloud, MSP) abweichen und werden beim ersten echten Test abgeglichen.
public enum ManageEngineAPI {
    public static let acceptHeader = "application/vnd.manageengine.sdp.v3+json"

    /// Offene Tickets, die dem eigenen Techniker zugewiesen sind.
    public static func assignedRequests(config: ManageEngineConfig, token: String, rowCount: Int = 100) throws -> URLRequest {
        guard config.isComplete else { throw ManageEngineError.notConfigured }
        guard config.technicianIDIsNumeric else { throw ManageEngineError.technicianNotNumeric }
        let input: [String: Any] = [
            "list_info": [
                "row_count": rowCount,
                "start_index": 1,
                "sort_field": "created_time",
                "sort_order": "desc",
                "get_total_count": false,
                "search_criteria": [
                    ["field": "technician.id", "condition": "is", "value": config.trimmedTechnician],
                ],
            ] as [String: Any],
        ]
        return try get(path: "/api/v3/requests", input: input, config: config, token: token)
    }

    /// Prüft Adresse und Schlüssel. Holt dazu die letzten Tickets, um die Techniker darin zu zeigen.
    /// Braucht noch keine Techniker-ID.
    public static func connectionTest(config: ManageEngineConfig, token: String, rowCount: Int = 100) throws -> URLRequest {
        let input: [String: Any] = [
            "list_info": [
                "row_count": rowCount,
                "start_index": 1,
                "sort_field": "created_time",
                "sort_order": "desc",
            ] as [String: Any],
        ]
        return try get(path: "/api/v3/requests", input: input, config: config, token: token, requireTechnician: false)
    }

    /// Legt einen Worklog am Ticket an: Beschreibung, Dauer, Start und Ende.
    public static func addWorklog(
        config: ManageEngineConfig,
        token: String,
        requestKey: String,
        description: String,
        minutes: Int,
        start: Date,
        worklogType: String? = nil,
        variant: WorklogVariant = .standard
    ) throws -> URLRequest {
        guard config.isComplete else { throw ManageEngineError.notConfigured }
        guard config.technicianIDIsNumeric else { throw ManageEngineError.technicianNotNumeric }
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        var worklog: [String: Any] = [
            "description": description,
            "owner": ["id": config.trimmedTechnician],
            "start_time": ["value": String(Int64(start.timeIntervalSince1970 * 1000))],
            "end_time": ["value": String(Int64(end.timeIntervalSince1970 * 1000))],
        ]
        if variant.sendsTimeSpent {
            worklog["time_spent"] = ["hours": String(minutes / 60), "minutes": String(minutes % 60)]
        }
        // „Work Log Type“ ist in vielen Installationen ein Pflichtfeld; der Feldname unterscheidet sich je nach Ausgabe.
        if let field = variant.typeField, let worklogType = worklogType?.trimmingCharacters(in: .whitespaces), !worklogType.isEmpty {
            worklog[field] = ["name": worklogType]
        }
        var request = try base(path: "/api/v3/requests/\(requestKey)/worklogs", query: nil, config: config, token: token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let json = try jsonString(["worklog": worklog])
        request.httpBody = "input_data=\(formEncode(json))".data(using: .utf8)
        return request
    }

    /// Ein Ticket über die Nummer, die Menschen sehen. Bei der lokalen Installation ist sie meist die Request-ID.
    public static func request(withID id: String, config: ManageEngineConfig, token: String) throws -> URLRequest {
        let clean = id.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !clean.isEmpty, clean.allSatisfy(\.isNumber) else { throw ManageEngineError.unexpectedResponse }
        var request = try base(path: "/api/v3/requests/\(clean)", query: nil, config: config, token: token, requireTechnician: false)
        request.httpMethod = "GET"
        return request
    }

    /// Sucht ein Ticket über seine angezeigte Nummer (für die Cloud, wo Nummer und Request-ID verschieden sind).
    public static func requests(withDisplayID number: String, config: ManageEngineConfig, token: String) throws -> URLRequest {
        let clean = number.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let input: [String: Any] = [
            "list_info": [
                "row_count": 5,
                "start_index": 1,
                "search_criteria": [
                    ["field": "display_id", "condition": "is", "value": clean],
                ],
            ] as [String: Any],
        ]
        return try get(path: "/api/v3/requests", input: input, config: config, token: token, requireTechnician: false)
    }

    /// Sucht Tickets aller Techniker nach einem Text im Betreff, neueste zuerst.
    public static func requests(withSubjectContaining text: String, config: ManageEngineConfig, token: String, rowCount: Int = 25) throws -> URLRequest {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ManageEngineError.unexpectedResponse }
        let input: [String: Any] = [
            "list_info": [
                "row_count": rowCount,
                "start_index": 1,
                "sort_field": "created_time",
                "sort_order": "desc",
                "search_criteria": [
                    ["field": "subject", "condition": "contains", "value": clean],
                ],
            ] as [String: Any],
        ]
        return try get(path: "/api/v3/requests", input: input, config: config, token: token, requireTechnician: false)
    }

    /// Liste über `search_fields` (manche Ausgaben von ServiceDesk Plus suchen nur so), z. B. ["display_id": "4711"].
    public static func requests(searchFields: [String: String], config: ManageEngineConfig, token: String, rowCount: Int = 25) throws -> URLRequest {
        let input: [String: Any] = [
            "list_info": [
                "row_count": rowCount,
                "start_index": 1,
                "sort_field": "created_time",
                "sort_order": "desc",
                "search_fields": searchFields,
            ] as [String: Any],
        ]
        return try get(path: "/api/v3/requests", input: input, config: config, token: token, requireTechnician: false)
    }

    // MARK: Antworten lesen

    public static func parseTickets(_ data: Data, config: ManageEngineConfig) throws -> [ManageEngineTicket] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManageEngineError.unexpectedResponse
        }
        if let message = errorMessage(in: root) { throw ManageEngineError.server(message) }
        var requests = root["requests"] as? [[String: Any]] ?? []
        if requests.isEmpty, let single = root["request"] as? [String: Any] { requests = [single] }
        return requests.compactMap { item in
            guard let key = stringValue(item["id"]) else { return nil }
            let status = item["status"] as? [String: Any]
            let statusName = status?["name"] as? String ?? ""
            let inProgress = status?["in_progress"] as? Bool
            let closedNames = ["closed", "resolved", "geschlossen", "gelöst", "erledigt", "cancelled", "storniert"]
            let isOpen = inProgress ?? !closedNames.contains(statusName.lowercased())
            let account = (item["account"] as? [String: Any])?["name"] as? String
                ?? (item["site"] as? [String: Any])?["name"] as? String
            return ManageEngineTicket(
                key: key,
                number: displayNumber(item["display_id"]) ?? key,
                subject: item["subject"] as? String ?? "Ticket \(key)",
                accountName: account,
                statusName: statusName,
                isOpen: isOpen,
                webURL: webURL(for: key, config: config)
            )
        }
    }

    /// Technikerliste von ServiceDesk Plus, optional gefiltert nach Name oder Mail-Adresse.
    /// `path` ist `/api/v3/technicians` oder, bei manchen Ausgaben, `/api/v3/users`.
    public static func technicianList(
        config: ManageEngineConfig,
        token: String,
        query: String? = nil,
        startIndex: Int = 1,
        rowCount: Int = 100,
        path: String = "/api/v3/technicians"
    ) throws -> URLRequest {
        var listInfo: [String: Any] = ["row_count": rowCount, "start_index": startIndex]
        if let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty {
            listInfo["search_criteria"] = [
                ["field": "name", "condition": "contains", "value": query],
                ["field": "email_id", "condition": "contains", "value": query, "logical_operator": "or"],
            ]
        }
        return try get(path: path, input: ["list_info": listInfo], config: config, token: token, requireTechnician: false)
    }

    /// Tickets, deren Techniker so heißt (auch ältere). Dient als letzter Weg, die eigene ID zu finden.
    public static func requests(withTechnicianNamed name: String, config: ManageEngineConfig, token: String) throws -> URLRequest {
        let input: [String: Any] = [
            "list_info": [
                "row_count": 50,
                "start_index": 1,
                "search_criteria": [
                    ["field": "technician.name", "condition": "contains", "value": name],
                ],
            ] as [String: Any],
        ]
        return try get(path: "/api/v3/requests", input: input, config: config, token: token, requireTechnician: false)
    }

    /// Liest eine Techniker- oder Benutzerliste. Benutzer ohne Technikerrolle fallen weg.
    public static func parseTechnicianList(_ data: Data) throws -> (technicians: [ManageEngineTechnician], hasMore: Bool) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManageEngineError.unexpectedResponse
        }
        if let message = errorMessage(in: root) { throw ManageEngineError.server(message) }
        let items = root["technicians"] as? [[String: Any]] ?? root["users"] as? [[String: Any]] ?? []
        let technicians = items.compactMap { item -> ManageEngineTechnician? in
            if let isTechnician = item["is_technician"] as? Bool, !isTechnician { return nil }
            guard let id = stringValue(item["id"]) else { return nil }
            let login = item["login_name"] as? String
                ?? (item["login"] as? [String: Any])?["name"] as? String
                ?? item["user_name"] as? String
            return ManageEngineTechnician(id: id, name: item["name"] as? String ?? id, email: item["email_id"] as? String, loginName: login)
        }
        let listInfo = root["list_info"] as? [String: Any]
        let hasMore = listInfo?["has_more_rows"] as? Bool ?? false
        return (technicians, hasMore)
    }

    /// Alle Techniker, die in den Tickets der Antwort vorkommen, nach Name sortiert.
    public static func parseTechnicians(_ data: Data) throws -> [ManageEngineTechnician] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManageEngineError.unexpectedResponse
        }
        if let message = errorMessage(in: root) { throw ManageEngineError.server(message) }
        var byID: [String: ManageEngineTechnician] = [:]
        for item in root["requests"] as? [[String: Any]] ?? [] {
            guard let technician = item["technician"] as? [String: Any],
                  let id = stringValue(technician["id"]) else { continue }
            let name = technician["name"] as? String ?? id
            byID[id] = ManageEngineTechnician(id: id, name: name, email: technician["email_id"] as? String)
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Techniker, die zu einer Eingabe wie „blulay“, „Lulay“ oder einer Mail-Adresse passen.
    /// „blulay“ passt z. B. auf „Björn Lulay“ (erster Buchstabe des Vornamens + Nachname).
    public static func technicians(matching query: String, in technicians: [ManageEngineTechnician]) -> [ManageEngineTechnician] {
        let key = fold(query)
        guard !key.isEmpty else { return [] }
        if let exact = technicians.first(where: { $0.id == query.trimmingCharacters(in: .whitespaces) }) {
            return [exact]
        }
        return technicians.filter { technician in
            let parts = technician.name.split(whereSeparator: { $0 == " " || $0 == "," }).map { fold(String($0)) }.filter { !$0.isEmpty }
            var candidates = [fold(technician.name)]
            if let login = technician.loginName {
                candidates.append(fold(login))
                candidates.append(fold(String(login.split(separator: "\\").last ?? "")))
            }
            if let email = technician.email {
                candidates.append(fold(String(email.split(separator: "@").first ?? "")))
                candidates.append(fold(email))
            }
            if let first = parts.first, let last = parts.last, parts.count > 1 {
                candidates.append(String(first.prefix(1)) + last)
                candidates.append(first + last)
                candidates.append(last)
            }
            return candidates.contains { $0 == key || (key.count >= 4 && $0.contains(key)) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == "@" || $0 == "." }
    }

    /// ID des angelegten Worklogs.
    public static func parseWorklogID(_ data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManageEngineError.unexpectedResponse
        }
        if let message = errorMessage(in: root) { throw ManageEngineError.server(message) }
        for key in ["worklog", "request_worklog", "worklogs"] {
            if let object = root[key] as? [String: Any], let id = stringValue(object["id"]) {
                return id
            }
        }
        return nil
    }

    /// Fehlermeldung aus `response_status`, falls die Antwort einen Fehler meldet.
    /// Wie der Worklog aufgebaut wird. ServiceDesk Plus erwartet je nach Ausgabe andere Felder;
    /// Tagwerk probiert die Varianten der Reihe nach und merkt sich die passende.
    public enum WorklogVariant: String, CaseIterable, Sendable {
        case standard
        case worklogTypeField
        case withoutType
        case withoutTimeSpent

        var typeField: String? {
            switch self {
            case .standard, .withoutTimeSpent: return "type"
            case .worklogTypeField: return "worklog_type"
            case .withoutType: return nil
            }
        }

        var sendsTimeSpent: Bool { self != .withoutTimeSpent }

        public var label: String {
            switch self {
            case .standard: return "Feld „type“"
            case .worklogTypeField: return "Feld „worklog_type“"
            case .withoutType: return "ohne Work Log Type"
            case .withoutTimeSpent: return "ohne „time_spent“"
            }
        }
    }

    public static func errorMessage(in root: [String: Any]) -> String? {
        let statuses: [[String: Any]]
        if let single = root["response_status"] as? [String: Any] {
            statuses = [single]
        } else {
            statuses = root["response_status"] as? [[String: Any]] ?? []
        }
        for status in statuses {
            let code = (status["status_code"] as? Int) ?? Int(stringValue(status["status_code"]) ?? "") ?? 2000
            let state = (status["status"] as? String)?.lowercased()
            guard code >= 4000 || state == "failed" else { continue }
            let messages = status["messages"] as? [[String: Any]] ?? []
            let text = messages.compactMap { message -> String? in
                let body = (message["message"] as? String) ?? stringValue(message["status_code"])
                let field = (message["field"] as? String) ?? (message["fields"] as? [String])?.joined(separator: ", ")
                guard let body else { return field.map { "Feld „\($0)“" } }
                return field.map { "\(body) (Feld „\($0)“)" } ?? body
            }.joined(separator: ", ")
            return text.isEmpty ? "Fehler \(code)" : text
        }
        return nil
    }

    public static func webURL(for key: String, config: ManageEngineConfig) -> String {
        config.isCloud
            ? "\(config.trimmedBase)/ui/requests/\(key)/details"
            : "\(config.trimmedBase)/WorkOrder.do?woMode=viewWO&woID=\(key)"
    }

    // MARK: Hilfen

    private static func get(path: String, input: [String: Any], config: ManageEngineConfig, token: String, requireTechnician: Bool = true) throws -> URLRequest {
        var request = try base(path: path, query: [URLQueryItem(name: "input_data", value: try jsonString(input))], config: config, token: token, requireTechnician: requireTechnician)
        request.httpMethod = "GET"
        return request
    }

    private static func base(path: String, query: [URLQueryItem]?, config: ManageEngineConfig, token: String, requireTechnician: Bool = true) throws -> URLRequest {
        guard requireTechnician ? config.isComplete : config.hasAddress else { throw ManageEngineError.notConfigured }
        guard var components = URLComponents(string: config.trimmedBase + path) else { throw ManageEngineError.invalidURL }
        components.queryItems = query
        guard let url = components.url else { throw ManageEngineError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        switch config.authKind {
        case .authtoken:
            request.setValue(token, forHTTPHeaderField: "authtoken")
        case .zohoOAuth:
            request.setValue("Zoho-oauthtoken \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func formEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func stringValue(_ any: Any?) -> String? {
        switch any {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        case let int as Int: return String(int)
        default: return nil
        }
    }

    private static func displayNumber(_ any: Any?) -> String? {
        if let object = any as? [String: Any] {
            return stringValue(object["display_value"]) ?? stringValue(object["value"])
        }
        return stringValue(any)
    }
}
