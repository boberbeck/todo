import Foundation
import Security
import TagwerkCore

/// Geheimnisse (API-Schlüssel, Passwort, Tokens) im macOS-Schlüsselbund, alle in **einem** Eintrag
/// „Tagwerk“ / „zugangsdaten“. Gelesen wird er höchstens einmal pro Start; danach kommt alles aus dem Speicher.
/// So fragt macOS nach einem Update nur noch einmal statt für jeden Schlüssel einzeln.
/// Welche Schlüssel es gibt, steht unverschlüsselt im Kommentar des Eintrags; dafür fragt macOS nicht.
enum Keychain {
    private static let service = "Tagwerk"
    private static let vaultAccount = "zugangsdaten"
    /// Frühere einzelne Einträge; werden beim ersten Lesen übernommen und gelöscht.
    private static let legacyAccounts = ["manageengine", "bydesign", "github-update-token", "remote-mcp-token"]
    private static let lock = NSLock()
    private static var cache: [String: String]?
    private static var cachedNames: Set<String>?

    static func get(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return loadIfNeeded()?[account]
    }

    static func set(_ value: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        guard var vault = loadIfNeeded() else {
            AppLog.warning("Schlüsselbund", "nicht gespeichert, Zugriff verweigert (\(account))")
            return
        }
        if value.isEmpty {
            vault.removeValue(forKey: account)
        } else {
            vault[account] = value
        }
        save(vault)
    }

    /// Gibt es einen Eintrag? Liest nur die Merkmale, nicht das Geheimnis; macOS fragt dafür nicht nach.
    static func exists(account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache[account] != nil }
        return names().contains(account)
    }

    static func delete(account: String) {
        set("", account: account)
    }

    // MARK: Ein Eintrag für alles

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Namen der gespeicherten Schlüssel, ohne das Geheimnis zu lesen.
    private static func names() -> Set<String> {
        if let cachedNames { return cachedNames }
        var query = baseQuery(vaultAccount)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess {
            let comment = (result as? [String: Any])?[kSecAttrComment as String] as? String ?? ""
            let found = Set(comment.split(separator: ",").map(String.init))
            cachedNames = found
            return found
        }
        // Noch der alte Aufbau mit einzelnen Einträgen
        let found = Set(legacyAccounts.filter(legacyExists))
        cachedNames = found
        return found
    }

    /// Liest den Eintrag (einmal pro Start). `nil`, wenn der Zugriff verweigert wurde.
    private static func loadIfNeeded() -> [String: String]? {
        if let cache { return cache }
        var query = baseQuery(vaultAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let data = result as? Data ?? Data()
            let vault = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            cache = vault
            cachedNames = Set(vault.keys)
            adoptForFixedSignature(vault)
            return vault
        case errSecItemNotFound:
            // Umzug der einzelnen Einträge in den gemeinsamen
            var vault: [String: String] = [:]
            for account in legacyAccounts where legacyExists(account) {
                if let value = legacyGet(account) { vault[account] = value }
            }
            if !vault.isEmpty {
                save(vault)
                for account in vault.keys { SecItemDelete(baseQuery(account) as CFDictionary) }
                AppLog.info("Schlüsselbund", "\(vault.count) Einträge in einen zusammengefasst")
            } else {
                cache = [:]
                cachedNames = []
            }
            return vault
        default:
            AppLog.warning("Schlüsselbund", "Zugriff nicht möglich (Status \(status))")
            return nil
        }
    }

    /// Legt den Eintrag einmal neu an, sobald Tagwerk fest signiert ist. Dann gehört er der signierten App,
    /// und macOS fragt auch nach Updates (gleiches Zertifikat) nicht mehr. Vorher gehörte er einer
    /// ad hoc signierten Fassung, die macOS bei jeder neuen Fassung für eine andere App hält.
    private static func adoptForFixedSignature(_ vault: [String: String]) {
        let flag = "keychainAdoptedForFixedSignature"
        guard SigningSetup.isFixed, !UserDefaults.standard.bool(forKey: flag) else { return }
        SecItemDelete(baseQuery(vaultAccount) as CFDictionary)
        save(vault)
        if cache != nil {
            UserDefaults.standard.set(true, forKey: flag)
            AppLog.info("Schlüsselbund", "Eintrag für die feste Signatur neu angelegt")
        }
    }

    private static func save(_ vault: [String: String]) {
        let data = (try? JSONEncoder().encode(vault)) ?? Data()
        let comment = vault.keys.sorted().joined(separator: ",")
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrComment as String: comment,
            kSecAttrLabel as String: "Tagwerk Zugangsdaten",
        ]
        var status = SecItemUpdate(baseQuery(vaultAccount) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(vaultAccount)
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status == errSecSuccess {
            cache = vault
            cachedNames = Set(vault.keys)
        } else {
            AppLog.error("Schlüsselbund", "Speichern fehlgeschlagen (Status \(status))")
        }
    }

    private static func legacyExists(_ account: String) -> Bool {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    private static func legacyGet(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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
        // Nur Methode und Pfad ins Protokoll, nie Kopfzeilen (dort steht der Schlüssel)
        let label = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "?")"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AppLog.error("ManageEngine", "\(label): \(error.localizedDescription)")
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw ManageEngineError.unexpectedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = root.flatMap { ManageEngineAPI.errorMessage(in: $0) } ?? "HTTP \(http.statusCode)"
            AppLog.warning("ManageEngine", "\(label): HTTP \(http.statusCode) \(message)")
            throw ManageEngineError.server(message)
        }
        AppLog.info("ManageEngine", "\(label): HTTP \(http.statusCode), \(data.count) Bytes")
        return data
    }
}
