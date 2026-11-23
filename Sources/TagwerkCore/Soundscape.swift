import Foundation

/// Stimmung der Klangwelt, die der Nutzer wählt.
public enum SoundscapeMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// sanfte Glockentöne über warmem Klangteppich
    case focus
    /// fast nur Klangteppich, sehr wenig Bewegung
    case deep
    /// weich und langsam, zum Lesen oder für ruhige Arbeit
    case calm

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .focus: return "Fokus"
        case .deep: return "Tiefe Konzentration"
        case .calm: return "Ruhig"
        }
    }

    public var detail: String {
        switch self {
        case .focus: return "sanfte Glockentöne über warmem Klangteppich"
        case .deep: return "fast nur Klangteppich, kaum Bewegung"
        case .calm: return "weich und langsam, zum Lesen"
        }
    }
}

/// Tageszeit, nach der sich die Klangwelt richtet.
public enum DayPhase: String, Sendable {
    case morning, midday, afternoon, evening, night

    public static func at(hour: Int) -> DayPhase {
        switch hour {
        case 5..<10: return .morning
        case 10..<13: return .midday
        case 13..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    public var label: String {
        switch self {
        case .morning: return "Morgen"
        case .midday: return "Mittag"
        case .afternoon: return "Nachmittag"
        case .evening: return "Abend"
        case .night: return "Nacht"
        }
    }
}

/// Einstellungen der Klangwelt.
public struct SoundscapeSettings: Codable, Equatable, Sendable {
    public var mode: SoundscapeMode = .focus
    /// morgens heller, abends tiefer und langsamer
    public var adaptToTime = true
    /// beim Tippen lebendiger, beim Lesen und Nachdenken ruhiger
    public var adaptToActivity = true

    public init() {}
}

/// Was die Klangwelt gerade spielt: Tonart, Dichte, Helligkeit, Anteile. Wird regelmäßig neu berechnet.
public struct SoundscapeMood: Equatable, Sendable {
    /// Grundton des Klangteppichs in Hertz
    public var root: Double
    /// Tonleiter als Halbtonschritte über dem Grundton
    public var scale: [Int]
    /// Glockentöne pro Minute im Mittel
    public var bellsPerMinute: Double
    /// 0 = dunkel/weich, 1 = hell
    public var brightness: Double
    public var padLevel: Double
    public var bellLevel: Double
    public var noiseLevel: Double
    /// Sekunden je Akkord, bevor der Teppich weitergleitet
    public var chordSeconds: Double
    /// Anzeige, z. B. „Nachmittag · C-Dur, hell“
    public var description: String
}

/// Die Regeln der Klangwelt, ohne Ton: daraus erzeugt die App den Klang.
public enum Soundscape {
    public static let majorPentatonic = [0, 2, 4, 7, 9]
    public static let minorPentatonic = [0, 3, 5, 7, 10]
    /// Akkordfolge als Stufen der Tonleiter; wiederholt sich, klingt durch die Glocken aber nie gleich
    public static let progression = [0, 3, 1, 4, 2, 3]

    public static func mood(mode: SoundscapeMode, hour: Int, activity: Double, settings: SoundscapeSettings) -> SoundscapeMood {
        let phase = settings.adaptToTime ? DayPhase.at(hour: hour) : .afternoon
        var root: Double
        var minor = false
        var bells: Double
        var brightness: Double
        var noise: Double
        var chord: Double
        var key: String
        switch phase {
        case .morning:
            root = 146.83; key = "D"; bells = 7; brightness = 0.75; noise = 0.12; chord = 24
        case .midday:
            root = 130.81; key = "C"; bells = 6; brightness = 0.65; noise = 0.14; chord = 28
        case .afternoon:
            root = 130.81; key = "C"; bells = 5; brightness = 0.6; noise = 0.16; chord = 30
        case .evening:
            root = 110.0; key = "A"; minor = true; bells = 4; brightness = 0.45; noise = 0.2; chord = 34
        case .night:
            root = 98.0; key = "G"; minor = true; bells = 2.5; brightness = 0.35; noise = 0.24; chord = 40
        }

        var pad = 0.5
        var bellLevel = 0.35
        switch mode {
        case .focus:
            break
        case .deep:
            bells *= 0.35; brightness -= 0.1; pad = 0.6; bellLevel = 0.25
        case .calm:
            bells *= 0.6; brightness -= 0.15; chord *= 1.4; noise += 0.05
        }

        if settings.adaptToActivity {
            let level = min(1, max(0, activity))
            bells *= 0.75 + 0.5 * level
            brightness += 0.1 * (level - 0.5)
        }

        let tone = brightness >= 0.55 ? "hell" : (brightness >= 0.4 ? "warm" : "dunkel")
        return SoundscapeMood(
            root: root,
            scale: minor ? minorPentatonic : majorPentatonic,
            bellsPerMinute: bells,
            brightness: min(1, max(0.1, brightness)),
            padLevel: pad,
            bellLevel: bellLevel,
            noiseLevel: noise,
            chordSeconds: chord,
            description: "\(phase.label) · \(key)-\(minor ? "Moll" : "Dur"), \(tone)"
        )
    }

    /// Frequenz einer Stufe der Tonleiter; Stufen über die Tonleiter hinaus liegen in höheren Oktaven.
    public static func frequency(root: Double, scale: [Int], degree: Int, octave: Int = 0) -> Double {
        guard !scale.isEmpty else { return root }
        let count = scale.count
        let wrapped = ((degree % count) + count) % count
        let octaves = (degree - wrapped) / count + octave
        let semitones = Double(scale[wrapped] + 12 * octaves)
        return root * pow(2, semitones / 12)
    }

    /// Vier Töne des Klangteppichs für einen Schritt der Akkordfolge: Grundton eine Oktave tiefer, dazu drei Stufen.
    public static func chord(mood: SoundscapeMood, step: Int) -> [Double] {
        let degree = progression[((step % progression.count) + progression.count) % progression.count]
        return [
            frequency(root: mood.root, scale: mood.scale, degree: degree, octave: -1),
            frequency(root: mood.root, scale: mood.scale, degree: degree),
            frequency(root: mood.root, scale: mood.scale, degree: degree + 2),
            frequency(root: mood.root, scale: mood.scale, degree: degree + 4),
        ]
    }

    /// Töne für die Glocken: zwei Oktaven über dem Teppich, aus derselben Tonleiter (klingt nie schief).
    public static func bellNotes(mood: SoundscapeMood) -> [Double] {
        (0..<(mood.scale.count * 2)).map { frequency(root: mood.root, scale: mood.scale, degree: $0, octave: 2) }
    }
}
