import AVFoundation
import Foundation
import TagwerkCore

/// Spielt die Klangwelt: erzeugt sie in Echtzeit aus den Regeln in `Soundscape` und passt sie alle paar Sekunden an
/// (Tageszeit, Tippen). Endlos, offline, ohne Aufnahmen.
@MainActor
final class SoundscapePlayer {
    private let engine = AVAudioEngine()
    private let synth = SoundscapeSynth()
    private var node: AVAudioSourceNode?
    private var updateTask: Task<Void, Never>?
    private(set) var isPlaying = false

    /// Liefert die aktuelle Stimmung; wird beim Start und danach regelmäßig gefragt.
    var moodProvider: (() -> SoundscapeMood)?

    func start() {
        guard let mood = moodProvider?() else { return }
        apply(mood)
        do {
            try prepareIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            synth.setVolume(0.8)
            isPlaying = true
        } catch {
            AppLog.warning("Klangwelt", "Audio startet nicht: \(error.localizedDescription)")
            isPlaying = false
            return
        }
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                guard self.isPlaying, let mood = self.moodProvider?() else { continue }
                self.apply(mood)
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        updateTask?.cancel()
        updateTask = nil
        synth.setVolume(0)
        // ausklingen lassen, dann anhalten
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
        }
    }

    private func apply(_ mood: SoundscapeMood) {
        synth.setParameters(SoundscapeSynth.Parameters(
            chords: Soundscape.progression.indices.map { Soundscape.chord(mood: mood, step: $0) },
            bellNotes: Soundscape.bellNotes(mood: mood),
            bellsPerSecond: mood.bellsPerMinute / 60,
            brightness: mood.brightness,
            padLevel: Float(mood.padLevel),
            bellLevel: Float(mood.bellLevel),
            noiseLevel: Float(mood.noiseLevel),
            chordSeconds: mood.chordSeconds
        ))
    }

    private func prepareIfNeeded() throws {
        guard node == nil else { return }
        let output = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        synth.prepare(sampleRate: sampleRate)
        let node = Self.makeNode(format: format, synth: synth)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        self.node = node
    }

    /// Außerhalb des Hauptthreads gebaut: der Block läuft im Audio-Thread.
    private nonisolated static func makeNode(format: AVAudioFormat, synth: SoundscapeSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            synth.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }
}

/// Der Klangerzeuger im Audio-Thread: Klangteppich aus vier gleitenden Stimmen, vereinzelte Glocken,
/// gefiltertes Rauschen und ein leiser Raumhall. Neue Werte kommen über `setParameters` und werden weich übernommen.
private final class SoundscapeSynth: @unchecked Sendable {
    struct Parameters {
        var chords: [[Double]]
        var bellNotes: [Double]
        var bellsPerSecond: Double
        var brightness: Double
        var padLevel: Float
        var bellLevel: Float
        var noiseLevel: Float
        var chordSeconds: Double
    }

    private struct Bell {
        var active = false
        var frequency: Double = 0
        var phase: Double = 0
        var partialPhase: Double = 0
        var amplitude: Float = 0
        var envelope: Float = 0
        var attack: Float = 0
        var decay: Float = 0.9999
        var partialDecay: Float = 0.9998
        var partialLevel: Float = 0.3
        var pan: Float = 0
    }

    // Übergabe vom Hauptthread
    private let lock = NSLock()
    private var pending: Parameters?
    private var targetVolume: Float = 0

    // Zustand im Audio-Thread
    private var parameters: Parameters?
    private var sampleRate: Double = 48_000
    private var volume: Float = 0
    private var padFrequencies: [Double] = [65.4, 130.8, 164.8, 220]
    private var padTargets: [Double] = [65.4, 130.8, 164.8, 220]
    private var padPhases: [Double] = [0, 0, 0, 0]
    private var padDetunePhases: [Double] = [0, 0, 0, 0]
    private var padLFOPhases: [Double] = [0, 1.3, 2.6, 3.9]
    private let padLFORates: [Double] = [0.05, 0.07, 0.09, 0.11]
    private let padPans: [Float] = [-0.4, -0.15, 0.15, 0.4]
    private var chordIndex = 0
    private var samplesUntilChord: Double = 0
    private var bells = [Bell](repeating: Bell(), count: 8)
    private var brown: Float = 0
    private var noiseSwellPhase: Double = 0
    private var filterLeft: Float = 0
    private var filterRight: Float = 0
    private var noiseFilter: Float = 0
    private var filterCoefficient: Float = 0.2
    private var randomState: UInt32 = 0x2545_F491

    // Raumhall: zwei Verzögerungen mit Rückkopplung
    private var delayLeft: UnsafeMutablePointer<Float>?
    private var delayRight: UnsafeMutablePointer<Float>?
    private var delayLengthLeft = 1
    private var delayLengthRight = 1
    private var delayIndexLeft = 0
    private var delayIndexRight = 0
    private var dampLeft: Float = 0
    private var dampRight: Float = 0

    deinit {
        delayLeft?.deallocate()
        delayRight?.deallocate()
    }

    func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        delayLengthLeft = max(1, Int(sampleRate * 0.41))
        delayLengthRight = max(1, Int(sampleRate * 0.53))
        let left = UnsafeMutablePointer<Float>.allocate(capacity: delayLengthLeft)
        left.initialize(repeating: 0, count: delayLengthLeft)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: delayLengthRight)
        right.initialize(repeating: 0, count: delayLengthRight)
        delayLeft = left
        delayRight = right
    }

    func setParameters(_ new: Parameters) {
        lock.lock()
        pending = new
        lock.unlock()
    }

    func setVolume(_ value: Float) {
        lock.lock()
        targetVolume = value
        lock.unlock()
    }

    private func random() -> Float {
        randomState = randomState &* 1_664_525 &+ 1_013_904_223
        return Float(randomState >> 8) / Float(1 << 24)
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count >= 2,
              let outLeft = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let outRight = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        // Neue Werte übernehmen, ohne den Audio-Thread zu blockieren
        var target: Float = volume
        if lock.try() {
            if let pending {
                let first = parameters == nil
                parameters = pending
                self.pending = nil
                let cutoff = 350 + pending.brightness * 3200
                filterCoefficient = Float(1 - exp(-2 * Double.pi * cutoff / sampleRate))
                if first, let chord = pending.chords.first {
                    padFrequencies = chord
                    padTargets = chord
                    samplesUntilChord = pending.chordSeconds * sampleRate
                }
            }
            target = targetVolume
            lock.unlock()
        }

        guard let parameters, let delayLeft, let delayRight else {
            for frame in 0..<frames {
                outLeft[frame] = 0
                outRight[frame] = 0
            }
            return
        }

        let twoPi = 2 * Double.pi
        let glide = 1 / (6 * sampleRate)
        let volumeStep: Float = Float(1 / (1.2 * sampleRate))
        let bellChance = Float(parameters.bellsPerSecond / sampleRate)

        for frame in 0..<frames {
            // Lautstärke weich angleichen
            if volume < target {
                volume = min(target, volume + volumeStep)
            } else if volume > target {
                volume = max(target, volume - volumeStep)
            }

            // Akkordwechsel: Teppich gleitet zum nächsten Akkord
            samplesUntilChord -= 1
            if samplesUntilChord <= 0, !parameters.chords.isEmpty {
                chordIndex = (chordIndex + 1) % parameters.chords.count
                padTargets = parameters.chords[chordIndex]
                samplesUntilChord = parameters.chordSeconds * sampleRate
            }

            // Klangteppich
            var padLeft: Float = 0
            var padRight: Float = 0
            for voice in 0..<4 {
                padFrequencies[voice] += (padTargets[voice] - padFrequencies[voice]) * glide * 4
                let frequency = padFrequencies[voice]
                padPhases[voice] += twoPi * frequency / sampleRate
                padDetunePhases[voice] += twoPi * frequency * 1.004 / sampleRate
                padLFOPhases[voice] += twoPi * padLFORates[voice] / sampleRate
                if padPhases[voice] > twoPi { padPhases[voice] -= twoPi }
                if padDetunePhases[voice] > twoPi { padDetunePhases[voice] -= twoPi }
                if padLFOPhases[voice] > twoPi { padLFOPhases[voice] -= twoPi }
                let swell = Float(0.65 + 0.35 * sin(padLFOPhases[voice]))
                let tone = Float(sin(padPhases[voice]) + 0.6 * sin(padDetunePhases[voice]) + 0.15 * sin(2 * padPhases[voice]))
                let sample = tone * swell * (voice == 0 ? 0.8 : 0.55)
                padLeft += sample * (1 - padPans[voice]) * 0.5
                padRight += sample * (1 + padPans[voice]) * 0.5
            }
            padLeft *= parameters.padLevel * 0.22
            padRight *= parameters.padLevel * 0.22

            // Glocken: selten, zufällig, aus der Tonleiter
            if !parameters.bellNotes.isEmpty, random() < bellChance,
               let free = bells.firstIndex(where: { !$0.active }) {
                let note = parameters.bellNotes[Int(random() * Float(parameters.bellNotes.count)) % parameters.bellNotes.count]
                let seconds = 2.5 + Double(random()) * 3
                bells[free] = Bell(
                    active: true,
                    frequency: note,
                    amplitude: 0.5 + random() * 0.5,
                    attack: Float(1 / (0.012 * sampleRate)),
                    decay: Float(exp(-1 / (seconds * sampleRate))),
                    partialDecay: Float(exp(-1 / (seconds * 0.35 * sampleRate))),
                    partialLevel: 0.2 + random() * 0.2,
                    pan: random() * 1.6 - 0.8
                )
            }
            var bellLeft: Float = 0
            var bellRight: Float = 0
            for index in bells.indices where bells[index].active {
                var bell = bells[index]
                if bell.attack > 0 {
                    bell.envelope = min(1, bell.envelope + bell.attack)
                    if bell.envelope >= 1 { bell.attack = 0 }
                } else {
                    bell.envelope *= bell.decay
                    bell.partialLevel *= bell.partialDecay
                }
                bell.phase += twoPi * bell.frequency / sampleRate
                bell.partialPhase += twoPi * bell.frequency * 2.756 / sampleRate
                if bell.phase > twoPi { bell.phase -= twoPi }
                if bell.partialPhase > twoPi { bell.partialPhase -= twoPi }
                let sample = (Float(sin(bell.phase)) + Float(sin(bell.partialPhase)) * bell.partialLevel) * bell.envelope * bell.amplitude
                bellLeft += sample * (1 - bell.pan) * 0.5
                bellRight += sample * (1 + bell.pan) * 0.5
                if bell.attack == 0, bell.envelope < 0.0005 { bell.active = false }
                bells[index] = bell
            }
            bellLeft *= parameters.bellLevel * 0.18
            bellRight *= parameters.bellLevel * 0.18

            // Rauschen wie fernes Wasser, langsam an- und abschwellend
            let white = random() * 2 - 1
            brown = (brown + 0.02 * white) / 1.02
            noiseFilter += (brown - noiseFilter) * 0.08
            noiseSwellPhase += twoPi * 0.04 / sampleRate
            if noiseSwellPhase > twoPi { noiseSwellPhase -= twoPi }
            let noise = noiseFilter * 3.5 * parameters.noiseLevel * Float(0.6 + 0.4 * sin(noiseSwellPhase))

            // Helligkeit über einen weichen Tiefpass
            let dryLeft = padLeft + bellLeft + noise
            let dryRight = padRight + bellRight + noise
            filterLeft += (dryLeft - filterLeft) * filterCoefficient
            filterRight += (dryRight - filterRight) * filterCoefficient

            // Raumhall
            let echoLeft = delayLeft[delayIndexLeft]
            let echoRight = delayRight[delayIndexRight]
            dampLeft += (echoRight - dampLeft) * 0.3
            dampRight += (echoLeft - dampRight) * 0.3
            delayLeft[delayIndexLeft] = filterLeft + dampLeft * 0.45
            delayRight[delayIndexRight] = filterRight + dampRight * 0.45
            delayIndexLeft = (delayIndexLeft + 1) % delayLengthLeft
            delayIndexRight = (delayIndexRight + 1) % delayLengthRight

            outLeft[frame] = (filterLeft + echoLeft * 0.35) * volume
            outRight[frame] = (filterRight + echoRight * 0.35) * volume
        }
    }
}
