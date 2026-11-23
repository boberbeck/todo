import Foundation

/// Woher die Musik im Fokus kommt.
public enum MusicSource: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Playlist aus der Musik-App (Apple Music)
    case appleMusic
    /// Internetradio, z. B. ein ruhiger Sender von SomaFM
    case radio
    /// YouTube-Video, -Playlist oder -Livestream mit kleinem Player im Fokus
    case youtube

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .radio: return "Internetradio"
        case .youtube: return "YouTube"
        }
    }
}

/// Ein Radiosender mit direkter Stream-Adresse (MP3 oder AAC).
public struct RadioStation: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var detail: String
    public var url: URL

    public var id: String { url.absoluteString }

    public init(name: String, detail: String, url: URL) {
        self.name = name
        self.detail = detail
        self.url = url
    }

    /// Ruhige Sender zum Arbeiten, werbefrei und hörerfinanziert (SomaFM).
    public static let builtIn: [RadioStation] = [
        RadioStation(name: "Groove Salad", detail: "Entspannte Elektronik, Downtempo", url: URL(string: "https://ice2.somafm.com/groovesalad-128-mp3")!),
        RadioStation(name: "Fluid", detail: "Instrumentaler Hip-Hop, Lo-Fi", url: URL(string: "https://ice2.somafm.com/fluid-128-mp3")!),
        RadioStation(name: "Drone Zone", detail: "Ambient ohne Takt", url: URL(string: "https://ice2.somafm.com/dronezone-128-mp3")!),
        RadioStation(name: "Deep Space One", detail: "Tiefer Ambient, Space", url: URL(string: "https://ice2.somafm.com/deepspaceone-128-mp3")!),
    ]

    /// Eigene Adresse aus einem Eingabefeld; nur http(s) mit Host.
    public static func custom(_ text: String) -> RadioStation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return RadioStation(name: host, detail: "Eigene Adresse", url: url)
    }
}

/// Ein YouTube-Link, wie man ihn aus dem Browser kopiert: Video, Playlist (auch „Mix“) oder Livestream.
public struct YouTubeLink: Codable, Hashable, Sendable {
    public var videoID: String?
    public var listID: String?

    public init(videoID: String?, listID: String?) {
        self.videoID = videoID
        self.listID = listID
    }

    /// Erkennt youtube.com/watch?v=…, youtu.be/…, /live/…, /shorts/…, /embed/…, /playlist?list=…
    /// und eine nackte Video-ID. Gibt `nil` zurück, wenn weder Video noch Playlist drinsteht.
    public static func parse(_ text: String) -> YouTubeLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isVideoID(trimmed) {
            return YouTubeLink(videoID: trimmed, listID: nil)
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: withScheme),
              let host = components.host?.lowercased() else { return nil }
        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }
        let path = components.path.split(separator: "/").map(String.init)

        var video: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            video = path.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if path.first == "watch" {
                video = value("v")
            } else if let first = path.first, ["live", "shorts", "embed", "v"].contains(first), path.count > 1 {
                video = path[1]
            }
        } else {
            return nil
        }
        let list = value("list")
        let link = YouTubeLink(
            videoID: video.flatMap { isVideoID($0) ? $0 : nil },
            listID: list.flatMap { isListID($0) ? $0 : nil }
        )
        return link.videoID == nil && link.listID == nil ? nil : link
    }

    /// Video-IDs sind 11 Zeichen aus Buchstaben, Ziffern, „-“ und „_“.
    public static func isVideoID(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func isListID(_ text: String) -> Bool {
        text.count >= 2 && text.count <= 64 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Kurze Beschreibung für die Einstellungen.
    public var summary: String {
        switch (videoID, listID) {
        case (.some, .some): return "Video mit Playlist"
        case (.some, .none): return "Video oder Livestream"
        case (.none, .some): return "Playlist"
        case (.none, .none): return ""
        }
    }
}
