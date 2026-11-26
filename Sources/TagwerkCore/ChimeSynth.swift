import Foundation

/// Eigene Klänge für Pomodoro-Signale, in Tagwerk erzeugt (keine Dateien nötig).
public enum Chime: String, CaseIterable, Sendable {
    case gong
    case bowl
    case bell
    case woodblock

    public var label: String {
        switch self {
        case .gong: return "Gong"
        case .bowl: return "Klangschale"
        case .bell: return "Glöckchen"
        case .woodblock: return "Holzblock"
        }
    }
}

/// Erzeugt die Klänge als WAV (16 Bit, mono): Teiltöne, die unterschiedlich schnell abklingen.
public enum ChimeSynth {
    public static let sampleRate = 44_100
    /// Lautester Punkt; etwas Luft nach oben, damit nichts verzerrt.
    public static let peak: Float = 0.8

    struct Partial {
        /// Frequenz als Vielfaches des Grundtons
        let ratio: Double
        let amplitude: Double
        /// Abklingzeit in Sekunden (nach dieser Zeit noch rund ein Drittel)
        let decay: Double
    }

    struct Voice {
        let base: Double
        let duration: Double
        let attack: Double
        let partials: [Partial]
    }

    static func voice(_ chime: Chime) -> Voice {
        switch chime {
        case .gong:
            // tief und lang, unharmonische Teiltöne wie bei einem Tamtam
            return Voice(base: 98, duration: 4.5, attack: 0.012, partials: [
                Partial(ratio: 0.5, amplitude: 0.35, decay: 2.6),
                Partial(ratio: 1.0, amplitude: 1.0, decay: 2.2),
                Partial(ratio: 1.47, amplitude: 0.6, decay: 1.8),
                Partial(ratio: 2.09, amplitude: 0.5, decay: 1.4),
                Partial(ratio: 2.56, amplitude: 0.35, decay: 1.1),
                Partial(ratio: 3.37, amplitude: 0.25, decay: 0.8),
                Partial(ratio: 4.17, amplitude: 0.15, decay: 0.6),
            ])
        case .bowl:
            // Klangschale: weich angeschlagen, langsames Schweben durch zwei fast gleiche Töne
            return Voice(base: 293.66, duration: 5, attack: 0.03, partials: [
                Partial(ratio: 1.0, amplitude: 1.0, decay: 3.5),
                Partial(ratio: 1.004, amplitude: 0.5, decay: 3.5),
                Partial(ratio: 2.76, amplitude: 0.45, decay: 2.2),
                Partial(ratio: 5.4, amplitude: 0.2, decay: 1.2),
                Partial(ratio: 8.9, amplitude: 0.08, decay: 0.7),
            ])
        case .bell:
            return Voice(base: 880, duration: 2.5, attack: 0.003, partials: [
                Partial(ratio: 1.0, amplitude: 1.0, decay: 1.2),
                Partial(ratio: 2.0, amplitude: 0.5, decay: 0.8),
                Partial(ratio: 3.0, amplitude: 0.3, decay: 0.5),
                Partial(ratio: 4.2, amplitude: 0.2, decay: 0.35),
                Partial(ratio: 5.4, amplitude: 0.1, decay: 0.25),
            ])
        case .woodblock:
            // kurz und trocken, zweimal hintereinander klingt es wie „tock-tock“; hier ein einzelner Schlag
            return Voice(base: 760, duration: 0.6, attack: 0.001, partials: [
                Partial(ratio: 1.0, amplitude: 1.0, decay: 0.06),
                Partial(ratio: 2.3, amplitude: 0.4, decay: 0.03),
                Partial(ratio: 3.9, amplitude: 0.2, decay: 0.02),
            ])
        }
    }

    /// Die Abtastwerte zwischen -`peak` und `peak`; die letzten 50 ms werden ausgeblendet.
    public static func samples(_ chime: Chime) -> [Float] {
        let voice = voice(chime)
        let count = Int(voice.duration * Double(sampleRate))
        let fadeOut = min(count, sampleRate / 20)
        var values = [Float](repeating: 0, count: count)
        var loudest: Float = 0
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            var value = 0.0
            for partial in voice.partials {
                value += partial.amplitude * exp(-time / partial.decay) * sin(2 * .pi * voice.base * partial.ratio * time)
            }
            value *= min(1, time / voice.attack)
            let remaining = count - index
            if remaining < fadeOut {
                value *= Double(remaining) / Double(fadeOut)
            }
            let sample = Float(value)
            values[index] = sample
            loudest = max(loudest, abs(sample))
        }
        guard loudest > 0 else { return values }
        let scale = peak / loudest
        return values.map { $0 * scale }
    }

    /// Fertige WAV-Datei.
    public static func wav(_ chime: Chime) -> Data {
        wav(samples: samples(chime))
    }

    static func wav(samples: [Float]) -> Data {
        var data = Data()
        let bytesPerSample = 2
        let dataSize = UInt32(samples.count * bytesPerSample)
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF")
        append32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1) // PCM
        append16(1) // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * bytesPerSample))
        append16(UInt16(bytesPerSample))
        append16(16)
        append("data")
        append32(dataSize)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append16(UInt16(bitPattern: Int16(clamped * Float(Int16.max))))
        }
        return data
    }
}
