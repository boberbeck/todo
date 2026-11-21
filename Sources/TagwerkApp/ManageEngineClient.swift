import Foundation
import Security
import TagwerkCore

/// Geheimnisse (API-Schlüssel) im macOS-Schlüsselbund.
enum Keychain {
    private static let service = "Tagwerk"

    static func set(_ value: String, account: String) {
        delete(account: account)
        guard !value.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Gibt es einen Eintrag? Liest nur die Merkmale, nicht das Geheimnis; macOS fragt dafür nicht nach.
    static func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Spricht mit ServiceDesk Plus. Zugangsdaten kommen aus den Einstellungen und dem Schlüsselbund.
@MainActor
final class ManageEngineClient {
    static let tokenAccount = "manageengine"

    var config: ManageEngineConfig {
        let defaults = UserDefaults.standard
        return ManageEngineConfig(
            baseURL: defaults.string(forKey: Preferences.meBaseURLKey) ?? "",
            authKind: ManageEngineConfig.AuthKind(rawValue: defaults.string(forKey: Preferences.meAuthKindKey) ?? "") ?? .authtoken,
            technicianID: defaults.string(forKey: Preferences.meTechnicianKey) ?? ""
        )
    }

    /// Der Schlüssel selbst wird erst gelesen, wenn Tagwerk wirklich mit ManageEngine spricht,
    /// und dann für die Laufzeit der App gemerkt. So fragt macOS höchstens einmal nach.
    private var cachedToken: String?
    private var cachedHasToken: Bool?

    /// Ist ein Schlüssel gespeichert? Ohne das Geheimnis zu lesen.
    var hasToken: Bool {
        if let cachedHasToken { return cachedHasToken }
        let exists = Keychain.exists(account: Self.tokenAccount)
        cachedHasToken = exists
        return exists
    }

    var isReady: Bool {
        config.isComplete && hasToken
    }

    func setToken(_ value: String) {
        Keychain.set(value, account: Self.tokenAccount)
        cachedToken = value.isEmpty ? nil : value
        cachedHasToken = !value.isEmpty
    }

    func fetchTickets() async throws -> [ManageEngineTicket] {
        let config = self.config
        let request = try ManageEngineAPI.assignedRequests(config: config, token: try requireToken())
        let data = try await send(request)
        return try ManageEngineAPI.parseTickets(data, config: config)
    }

    /// Ergebnis einer Ticketsuche, mit dem, was versucht wurde (für die Meldung, wenn nichts kommt).
    struct TicketSearch {
        var tickets: [ManageEngineTicket] = []
        var attempts: [String] = []
    }

    /// Sucht Tickets aller Techniker: eine Nummer direkt und über die Suche, sonst Text im Betreff.
    /// ServiceDesk Plus unterscheidet sich je nach Ausgabe; deshalb mehrere Wege nacheinander.
    func findTickets(_ query: String) async -> TicketSearch {
        var result = TicketSearch()
        let config = self.config
        let token: String
        do {
            token = try requireToken()
        } catch {
            result.attempts.append(String(describing: error))
            return result
        }
        let clean = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !clean.isEmpty else { return result }

        func attempt(_ label: String, _ build: () throws -> URLRequest, accept: ([ManageEngineTicket]) -> [ManageEngineTicket]) async -> Bool {
            do {
                let data = try await send(try build())
                let found = accept(try ManageEngineAPI.parseTickets(data, config: config))
                result.attempts.append("\(label): \(found.count) Treffer")
                if !found.isEmpty {
                    result.tickets = found.filter(\.isOpen) + found.filter { !$0.isOpen }
                    return true
                }
            } catch {
                result.attempts.append("\(label): \(error)")
            }
            return false
        }

        if clean.allSatisfy(\.isNumber) {
            let byNumber: ([ManageEngineTicket]) -> [ManageEngineTicket] = { tickets in
                let exact = tickets.filter { $0.number == clean || $0.key == clean }
                return exact.isEmpty && tickets.count == 1 ? tickets : exact
            }
            if await attempt("Direkt abgerufen", { try ManageEngineAPI.request(withID: clean, config: config, token: token) }, accept: { $0 }) { return result }
            if await attempt("Suche nach Nummer", { try ManageEngineAPI.requests(withDisplayID: clean, config: config, token: token) }, accept: byNumber) { return result }
            _ = await attempt("Suchfeld Nummer", { try ManageEngineAPI.requests(searchFields: ["display_id": clean], config: config, token: token) }, accept: byNumber)
        } else {
            if await attempt("Betreff enthält", { try ManageEngineAPI.requests(withSubjectContaining: clean, config: config, token: token) }, accept: { $0 }) { return result }
            _ = await attempt("Suchfeld Betreff", { try ManageEngineAPI.requests(searchFields: ["subject": clean], config: config, token: token) }, accept: { $0 })
        }
        return result
    }

    /// Legt den Worklog an und gibt seine ID zurück.
    func addWorklog(requestKey: String, description: String, minutes: Int, start: Date, worklogType: String?) async throws -> String? {
        let request = try ManageEngineAPI.addWorklog(
            config: config,
            token: try requireToken(),
            requestKey: requestKey,
            description: description,
            minutes: minutes,
            start: start,
            worklogType: worklogType
        )
        let data = try await send(request)
        return try ManageEngineAPI.parseWorklogID(data)
    }

    /// Prüft Adresse und Schlüssel und gibt die Techniker aus den letzten Tickets zurück.
    func testConnection() async throws -> [ManageEngineTechnician] {
        let request = try ManageEngineAPI.connectionTest(config: config, token: try requireToken())
        let data = try await send(request)
        return try ManageEngineAPI.parseTechnicians(data)
    }

    /// Sucht Techniker nach Name, Mail-Adresse oder Benutzername. Probiert nacheinander:
    /// Suche in der Technikerliste, die ganze Liste, die Benutzerliste und zuletzt Tickets mit diesem Techniker.
    func searchTechnicians(_ query: String) async throws -> [ManageEngineTechnician] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let config = self.config
        let token = try requireToken()
        var lastError: Error?

        func list(_ request: URLRequest) async -> (technicians: [ManageEngineTechnician], hasMore: Bool)? {
            do {
                return try ManageEngineAPI.parseTechnicianList(try await send(request))
            } catch {
                lastError = error
                return nil
            }
        }

        func matches(_ technicians: [ManageEngineTechnician]) -> [ManageEngineTechnician] {
            let found = ManageEngineAPI.technicians(matching: text, in: technicians)
            return Array(Set(found)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        for path in ["/api/v3/technicians", "/api/v3/users"] {
            // 1. Suche auf dem Server (Name oder Mail enthält den Text)
            if let result = await list(try ManageEngineAPI.technicianList(config: config, token: token, query: text, path: path)) {
                let found = matches(result.technicians)
                if !found.isEmpty { return found }
                // Der Server hat gefiltert, aber unsere Regeln passen nicht: alle Treffer zeigen
                if !result.technicians.isEmpty, result.technicians.count <= 25 { return result.technicians }
            }
            // 2. Ganze Liste holen und selbst suchen (findet auch „blulay“ → B. Lulay)
            var start = 1
            var collected: [ManageEngineTechnician] = []
            for _ in 0..<10 {
                guard let page = await list(try ManageEngineAPI.technicianList(config: config, token: token, startIndex: start, path: path)) else { break }
                collected += page.technicians
                guard page.hasMore, !page.technicians.isEmpty else { break }
                start += page.technicians.count
            }
            let found = matches(collected)
            if !found.isEmpty { return found }
            if !collected.isEmpty { break }
        }

        // 3. Tickets, deren Techniker so heißt
        if let data = try? await send(try ManageEngineAPI.requests(withTechnicianNamed: text, config: config, token: token)),
           let technicians = try? ManageEngineAPI.parseTechnicians(data), !technicians.isEmpty {
            let found = matches(technicians)
            return found.isEmpty ? technicians : found
        }
        if let lastError { throw lastError }
        return []
    }

    private func requireToken() throws -> String {
        if let cachedToken { return cachedToken }
        guard hasToken, let token = Keychain.get(account: Self.tokenAccount), !token.isEmpty else {
            throw ManageEngineError.notConfigured
        }
        cachedToken = token
        return token
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ManageEngineError.unexpectedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = root.flatMap { ManageEngineAPI.errorMessage(in: $0) } ?? "HTTP \(http.statusCode)"
            throw ManageEngineError.server(message)
        }
        return data
    }
}
