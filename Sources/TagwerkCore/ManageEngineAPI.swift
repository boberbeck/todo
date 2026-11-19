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
        URL(string: trimmedBase) != nil && !trimmedBase.isEmpty && !technicianID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var trimmedBase: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    var isCloud: Bool { trimmedBase.contains("/app/") }
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

public enum ManageEngineError: Error, CustomStringConvertible, Equatable {
    case notConfigured
    case invalidURL
    case server(String)
    case unexpectedResponse

    public var description: String {
        switch self {
        case .notConfigured: return "ManageEngine ist noch nicht eingerichtet."
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
        let input: [String: Any] = [
            "list_info": [
                "row_count": rowCount,
                "start_index": 1,
                "sort_field": "created_time",
                "sort_order": "desc",
                "get_total_count": false,
                "search_criteria": [
                    ["field": "technician.id", "condition": "is", "value": config.technicianID],
                ],
            ] as [String: Any],
        ]
        return try get(path: "/api/v3/requests", input: input, config: config, token: token)
    }

    /// Kleinste Anfrage, um Adresse und Schlüssel zu prüfen.
    public static func connectionTest(config: ManageEngineConfig, token: String) throws -> URLRequest {
        try get(path: "/api/v3/requests", input: ["list_info": ["row_count": 1]], config: config, token: token)
    }

    /// Legt einen Worklog am Ticket an: Beschreibung, Dauer, Start und Ende.
    public static func addWorklog(
        config: ManageEngineConfig,
        token: String,
        requestKey: String,
        description: String,
        minutes: Int,
        start: Date
    ) throws -> URLRequest {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let worklog: [String: Any] = [
            "description": description,
            "owner": ["id": config.technicianID],
            "start_time": ["value": String(Int64(start.timeIntervalSince1970 * 1000))],
            "end_time": ["value": String(Int64(end.timeIntervalSince1970 * 1000))],
            "time_spent": ["hours": String(minutes / 60), "minutes": String(minutes % 60)],
        ]
        var request = try base(path: "/api/v3/requests/\(requestKey)/worklogs", query: nil, config: config, token: token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let json = try jsonString(["worklog": worklog])
        request.httpBody = "input_data=\(formEncode(json))".data(using: .utf8)
        return request
    }

    // MARK: Antworten lesen

    public static func parseTickets(_ data: Data, config: ManageEngineConfig) throws -> [ManageEngineTicket] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManageEngineError.unexpectedResponse
        }
        if let message = errorMessage(in: root) { throw ManageEngineError.server(message) }
        let requests = root["requests"] as? [[String: Any]] ?? []
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
            let text = messages.compactMap { ($0["message"] as? String) ?? stringValue($0["status_code"]) }.joined(separator: ", ")
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

    private static func get(path: String, input: [String: Any], config: ManageEngineConfig, token: String) throws -> URLRequest {
        var request = try base(path: path, query: [URLQueryItem(name: "input_data", value: try jsonString(input))], config: config, token: token)
        request.httpMethod = "GET"
        return request
    }

    private static func base(path: String, query: [URLQueryItem]?, config: ManageEngineConfig, token: String) throws -> URLRequest {
        guard config.isComplete else { throw ManageEngineError.notConfigured }
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
