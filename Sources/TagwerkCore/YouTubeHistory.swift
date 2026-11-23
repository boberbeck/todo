import Foundation

/// Ein zuletzt gespielter YouTube-Link mit seinem Titel (sobald der Player ihn kennt).
public struct YouTubeHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public var link: String
    public var title: String?
    public var lastPlayed: Date

    public init(link: String, title: String? = nil, lastPlayed: Date) {
        self.link = link
        self.title = title
        self.lastPlayed = lastPlayed
    }

    /// Gleiches Video und gleiche Playlist gelten als derselbe Eintrag, egal wie der Link geschrieben ist.
    public var id: String {
        guard let parsed = YouTubeLink.parse(link) else { return link }
        return "\(parsed.videoID ?? "-")|\(parsed.listID ?? "-")"
    }

    /// Anzeige: Titel, sonst der Link ohne „https://www.“
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        var short = link
        for prefix in ["https://", "http://", "www.", "m."] where short.hasPrefix(prefix) {
            short.removeFirst(prefix.count)
        }
        return short
    }
}

/// Verlauf der YouTube-Links im Fokus: neueste zuerst, ohne Doppelte, begrenzt.
public enum YouTubeHistory {
    public static let limit = 12

    /// Link vorne einreihen. Ein bekannter Eintrag rückt nach vorne und behält seinen Titel.
    public static func adding(_ link: String, at date: Date, to entries: [YouTubeHistoryEntry], limit: Int = limit) -> [YouTubeHistoryEntry] {
        let clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard YouTubeLink.parse(clean) != nil else { return entries }
        var entry = YouTubeHistoryEntry(link: clean, lastPlayed: date)
        let key = entry.id
        if let existing = entries.first(where: { $0.id == key }) {
            entry.title = existing.title
        }
        let rest = entries.filter { $0.id != key }
        return Array(([entry] + rest).prefix(limit))
    }

    /// Titel nachtragen, sobald der Player ihn meldet.
    public static func settingTitle(_ title: String, for link: String, in entries: [YouTubeHistoryEntry]) -> [YouTubeHistoryEntry] {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return entries }
        let key = YouTubeHistoryEntry(link: link, lastPlayed: Date()).id
        return entries.map { entry in
            guard entry.id == key, entry.title != clean else { return entry }
            var copy = entry
            copy.title = clean
            return copy
        }
    }
}
