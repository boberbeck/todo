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

    /// Legt den Worklog an und gibt seine ID zurück.
    func addWorklog(requestKey: String, description: String, minutes: Int, start: Date) async throws -> String? {
        let request = try ManageEngineAPI.addWorklog(
            config: config,
            token: try requireToken(),
            requestKey: requestKey,
            description: description,
            minutes: minutes,
            start: start
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
