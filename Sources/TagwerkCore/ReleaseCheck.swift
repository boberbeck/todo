import Foundation

/// Die neueste Fassung im Release „aktuell“ auf GitHub: aus welchem Commit, wann, wo die DMG liegt.
public struct ReleaseInfo: Equatable, Sendable {
    /// Commit, aus dem gebaut wurde (voller Hash)
    public var commit: String
    public var publishedAt: Date?
    /// API-Adresse der DMG (lädt mit `Accept: application/octet-stream`)
    public var dmgURL: URL?
    public var dmgSize: Int

    public var shortCommit: String { String(commit.prefix(7)) }

    /// Ist das eine andere Fassung als die laufende (`CFBundleVersion` = kurzer Hash)?
    public func isNewer(thanBuild build: String?) -> Bool {
        guard let build, !build.isEmpty, build != "lokal", build != "?" else { return false }
        guard commit.count >= 7, dmgURL != nil else { return false }
        return !commit.lowercased().hasPrefix(build.lowercased())
    }
}

public enum ReleaseCheck {
    public static let apiBase = "https://api.github.com"

    /// Anfrage für das Release mit dem Tag (z. B. „aktuell“).
    public static func releaseRequest(repository: String, tag: String, token: String) -> URLRequest {
        request(path: "/repos/\(repository)/releases/tags/\(tag)", token: token)
    }

    /// Das Repository selbst (um zu prüfen, ob der Schlüssel es überhaupt sieht).
    public static func repositoryRequest(repository: String, token: String) -> URLRequest {
        request(path: "/repos/\(repository)", token: token)
    }

    /// Commits zwischen der laufenden und der neuen Fassung (für „Was ist neu“).
    public static func compareRequest(repository: String, base: String, head: String, token: String) -> URLRequest {
        request(path: "/repos/\(repository)/compare/\(base)...\(head)", token: token)
    }

    /// Lädt eine Datei des Releases (die API leitet zu einem vorab signierten Download weiter).
    public static func assetRequest(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Tagwerk", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func request(path: String, token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: apiBase + path)!, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Tagwerk", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func parseRelease(_ data: Data) throws -> ReleaseInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReleaseError.unexpected
        }
        if let message = root["message"] as? String, root["assets"] == nil {
            throw ReleaseError.server(message)
        }
        let assets = root["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        let formatter = ISO8601DateFormatter()
        return ReleaseInfo(
            commit: root["target_commitish"] as? String ?? "",
            publishedAt: (root["published_at"] as? String).flatMap { formatter.date(from: $0) },
            dmgURL: (dmg?["url"] as? String).flatMap(URL.init(string:)),
            dmgSize: dmg?["size"] as? Int ?? 0
        )
    }

    /// Erste Zeilen der Commit-Nachrichten, neueste zuerst, ohne automatische Screenshot-Commits.
    public static func parseChanges(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commits = root["commits"] as? [[String: Any]] else { return [] }
        return commits.compactMap { commit -> String? in
            guard let message = (commit["commit"] as? [String: Any])?["message"] as? String else { return nil }
            let first = message.split(separator: "\n").first.map(String.init) ?? ""
            let clean = first.replacingOccurrences(of: "[screenshots]", with: "").replacingOccurrences(of: "[skip ci]", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, !clean.hasPrefix("Screenshots aktualisieren"), !clean.hasPrefix("Merge branch") else { return nil }
            return clean
        }
        .reversed()
    }

    public enum ReleaseError: Error, CustomStringConvertible, Equatable {
        case unexpected
        case server(String)

        public var description: String {
            switch self {
            case .unexpected: return "Unerwartete Antwort von GitHub."
            case .server(let message): return "GitHub meldet: \(message)"
            }
        }
    }
}
