import AVFoundation
import Foundation
import TagwerkCore

/// Erzeugt die Fokus-Frequenz in Echtzeit mit AVAudioEngine: Schwebungston (binaural oder pulsierend)
/// und auf Wunsch braunes Rauschen. Lautstärke und Ton wechseln weich, ohne Knacken.
@MainActor
final class ToneGenerator {
    private let engine = AVAudioEngine()
    private let voice = ToneVoice()
    private var node: AVAudioSourceNode?
    private(set) var isPlaying = false

    func start(_ settings: FocusToneSettings) {
        apply(settings)
        do {
            try prepareIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            voice.targetVolume = Float(settings.volume)
            isPlaying = true
        } catch {
            AppLog.warning("Fokus-Frequenz", "Audio startet nicht: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    /// Einstellungen ändern, während er spielt (Ton, Kopfhörer, Rauschen, Lautstärke).
    func update(_ settings: FocusToneSettings) {
        apply(settings)
        if isPlaying {
            voice.targetVolume = Float(settings.volume)
        }
    }

    func pause() {
        guard isPlaying else { return }
        voice.targetVolume = 0
        isPlaying = false
        // Kurz ausklingen lassen, dann die Engine anhalten (spart Strom)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
        }
    }

    private func apply(_ settings: FocusToneSettings) {
        let ears = settings.tone.earFrequencies(binaural: settings.binaural)
        voice.leftFrequency = ears.left
        voice.rightFrequency = ears.right
        voice.pulseFrequency = settings.binaural ? 0 : settings.tone.beatFrequency
        voice.toneLevel = settings.tone == .noise ? 0 : 0.5
        voice.noiseLevel = settings.tone == .noise ? 0.9 : (settings.withNoise ? 0.35 : 0)
    }

    private func prepareIfNeeded() throws {
        guard node == nil else { return }
        let output = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        voice.sampleRate = sampleRate
        let node = Self.makeNode(format: format, voice: voice)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        self.node = node
    }

    /// Außerhalb des Hauptthreads gebaut: der Block läuft im Audio-Thread.
    private nonisolated static func makeNode(format: AVAudioFormat, voice: ToneVoice) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            voice.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }
}

/// Der eigentliche Klang; läuft im Audio-Thread. Werte werden vom Hauptthread gesetzt und weich angeglichen.
private final class ToneVoice: @unchecked Sendable {
    var sampleRate: Double = 48_000
    var leftFrequency: Double = 200
    var rightFrequency: Double = 210
    /// Pulsieren ohne Kopfhörer (0 = aus)
    var pulseFrequency: Double = 0
    var toneLevel: Float = 0.5
    var noiseLevel: Float = 0.35
    var targetVolume: Float = 0

    private var volume: Float = 0
    private var leftPhase: Double = 0
    private var rightPhase: Double = 0
    private var pulsePhase: Double = 0
    private var brown: Float = 0
    private var randomState: UInt32 = 0x9E37_79B9

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        let twoPi = 2 * Double.pi
        let leftStep = twoPi * leftFrequency / sampleRate
        let rightStep = twoPi * rightFrequency / sampleRate
        let pulseStep = twoPi * pulseFrequency / sampleRate
        // Lautstärke in etwa 0,3 Sekunden angleichen, damit nichts knackt
        let smoothing: Float = Float(1 / (0.3 * sampleRate))

        for frame in 0..<frames {
            volume += (targetVolume - volume) * min(1, smoothing * 6)

            var gate: Float = 1
            if pulseFrequency > 0 {
                // weiche Pulse statt hartem An/Aus
                let pulse = Float(0.5 * (1 + sin(pulsePhase)))
                gate = pulse * pulse
                pulsePhase += pulseStep
                if pulsePhase > twoPi { pulsePhase -= twoPi }
            }

            // braunes Rauschen: aufsummiertes, gedämpftes weißes Rauschen
            randomState = randomState &* 1_664_525 &+ 1_013_904_223
            let white = Float(Int32(bitPattern: randomState)) / Float(Int32.max)
            brown = (brown + 0.02 * white) / 1.02
            let noise = brown * 3.5 * noiseLevel

            let toneLeft = Float(sin(leftPhase)) * toneLevel * gate
            let toneRight = Float(sin(rightPhase)) * toneLevel * gate
            leftPhase += leftStep
            rightPhase += rightStep
            if leftPhase > twoPi { leftPhase -= twoPi }
            if rightPhase > twoPi { rightPhase -= twoPi }

            left[frame] = (toneLeft + noise) * volume * 0.5
            right[frame] = (toneRight + noise) * volume * 0.5
        }
    }
}
