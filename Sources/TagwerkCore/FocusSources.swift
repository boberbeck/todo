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
    /// Musikrichtung für die Gruppierung im Menü (eigene Adressen haben keine)
    public var genre: String?

    public var id: String { url.absoluteString }

    public init(name: String, detail: String, url: URL, genre: String? = nil) {
        self.name = name
        self.detail = detail
        self.url = url
        self.genre = genre
    }

    public static let ambient = "Ambient & Chill"
    public static let jazz = "Jazz & Piano"
    public static let electronic = "Elektro & Synthwave"

    /// Richtungen in der Reihenfolge fürs Menü.
    public static let genres = [ambient, jazz, electronic]

    /// Werbefreie Sender zum Arbeiten: SomaFM (hörerfinanziert, San Francisco) und Radio Swiss (öffentlich-rechtlich).
    public static let builtIn: [RadioStation] = [
        soma("groovesalad", "Groove Salad", "Downtempo, entspannte Elektronik", ambient),
        soma("dronezone", "Drone Zone", "Ambient ohne Takt, sehr ruhig", ambient),
        soma("deepspaceone", "Deep Space One", "Tiefer Ambient, Weltraumklänge", ambient),
        soma("spacestation", "Space Station Soma", "Ambient mit sanftem Takt", ambient),
        soma("fluid", "Fluid", "Instrumentaler Hip-Hop, Lo-Fi", ambient),

        RadioStation(name: "Radio Swiss Jazz", detail: "Jazz und Soul, ohne Moderation", url: URL(string: "https://stream.srg-ssr.ch/m/rsj/mp3_128")!, genre: jazz),
        RadioStation(name: "Radio Swiss Classic", detail: "Klassik, viel Klavier, ohne Moderation", url: URL(string: "https://stream.srg-ssr.ch/m/rsc_de/mp3_128")!, genre: jazz),
        soma("sonicuniverse", "Sonic Universe", "Moderner Jazz, Nu-Jazz", jazz),
        soma("secretagent", "Secret Agent", "Lounge, Jazz mit Spannung", jazz),

        soma("beatblender", "Beat Blender", "Deep House, Downtempo für den späten Abend", electronic),
        soma("thetrip", "The Trip", "Progressive House, Trance", electronic),
        soma("vaporwaves", "Vaporwaves", "Vaporwave, Retro-Synthesizer", electronic),
        soma("synphaera", "Synphaera", "Moderne Elektronik, Synth-Ambient", electronic),
        soma("defcon", "DEF CON Radio", "Elektronik zum Konzentrieren", electronic),
    ]

    public static func stations(in genre: String) -> [RadioStation] {
        builtIn.filter { $0.genre == genre }
    }

    private static func soma(_ channel: String, _ name: String, _ detail: String, _ genre: String) -> RadioStation {
        RadioStation(name: name, detail: detail, url: URL(string: "https://ice2.somafm.com/\(channel)-128-mp3")!, genre: genre)
    }

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
