import Foundation

/// Fokus-Frequenz, die Tagwerk selbst erzeugt: ein Schwebungston (binaural mit Kopfhörern,
/// sonst pulsierend) oder nur braunes Rauschen. Liegt leise unter der Musik oder klingt allein.
public enum FocusTone: String, Codable, CaseIterable, Sendable, Identifiable {
    case alpha
    case beta
    case gamma
    case noise

    public var id: String { rawValue }

    /// Frequenz der Schwebung in Hertz (0 = kein Ton, nur Rauschen)
    public var beatFrequency: Double {
        switch self {
        case .alpha: return 10
        case .beta: return 16
        case .gamma: return 40
        case .noise: return 0
        }
    }

    /// Grundton, auf dem die Schwebung liegt; tief und weich, damit er nicht stört.
    public var carrierFrequency: Double {
        self == .noise ? 0 : 200
    }

    public var label: String {
        switch self {
        case .alpha: return "Alpha 10 Hz"
        case .beta: return "Beta 16 Hz"
        case .gamma: return "Gamma 40 Hz"
        case .noise: return "Braunes Rauschen"
        }
    }

    public var detail: String {
        switch self {
        case .alpha: return "entspannt konzentriert"
        case .beta: return "wach, für Denkarbeit"
        case .gamma: return "stark fokussiert"
        case .noise: return "gleichmäßiges Rauschen ohne Ton"
        }
    }

    /// Frequenzen für das linke und rechte Ohr. Binaural: rechts um die Schwebung höher, das Gehirn hört die Differenz.
    /// Ohne Kopfhörer: beide gleich, die Schwebung entsteht als Pulsieren der Lautstärke.
    public func earFrequencies(binaural: Bool) -> (left: Double, right: Double) {
        guard carrierFrequency > 0 else { return (0, 0) }
        return binaural ? (carrierFrequency, carrierFrequency + beatFrequency) : (carrierFrequency, carrierFrequency)
    }
}

/// Einstellungen der Fokus-Frequenz.
public struct FocusToneSettings: Codable, Equatable, Sendable {
    /// Unter die Musik legen bzw. allein abspielen
    public var isEnabled = false
    public var tone: FocusTone = .alpha
    /// Mit Kopfhörern: binauraler Beat; ohne: pulsierender Ton über Lautsprecher
    public var binaural = true
    /// Leises braunes Rauschen darunter, damit es nicht nach reinem Ton klingt
    public var withNoise = true
    /// Lautstärke 0…1, bewusst leise voreingestellt
    public var volume = 0.25

    public init() {}

    public var summary: String {
        tone == .noise ? tone.label : "\(tone.label)\(binaural ? " · Kopfhörer" : "")"
    }
}
