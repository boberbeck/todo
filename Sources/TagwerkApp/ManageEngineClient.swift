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

    var token: String? { Keychain.get(account: Self.tokenAccount) }

    var isReady: Bool {
        config.isComplete && !(token ?? "").isEmpty
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

    func testConnection() async throws {
        let request = try ManageEngineAPI.connectionTest(config: config, token: try requireToken())
        let data = try await send(request)
        _ = try ManageEngineAPI.parseTickets(data, config: config)
    }

    private func requireToken() throws -> String {
        guard let token, !token.isEmpty else { throw ManageEngineError.notConfigured }
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
