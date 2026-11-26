import XCTest
@testable import TagwerkCore

final class ChimeSynthTests: XCTestCase {
    func testEveryChimeIsAudibleAndEndsQuietly() {
        for chime in Chime.allCases {
            let samples = ChimeSynth.samples(chime)
            XCTAssertFalse(samples.isEmpty, chime.label)
            let loudest = samples.map(abs).max() ?? 0
            XCTAssertEqual(loudest, ChimeSynth.peak, accuracy: 0.001, "\(chime.label): auf gleiche Lautstärke gebracht")
            XCTAssertLessThan(abs(samples.last ?? 1), 0.001, "\(chime.label): blendet aus, kein Knacken am Ende")
            XCTAssertLessThan(abs(samples.first ?? 1), 0.01, "\(chime.label): setzt weich ein")
        }
        // Gong klingt länger als der Holzblock
        XCTAssertGreaterThan(ChimeSynth.samples(.gong).count, ChimeSynth.samples(.woodblock).count * 4)
    }

    func testWavHeader() {
        let samples = ChimeSynth.samples(.bell)
        let data = ChimeSynth.wav(.bell)
        XCTAssertEqual(data.count, 44 + samples.count * 2)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data.subdata(in: 36..<40), encoding: .ascii), "data")
        let rate = data.subdata(in: 24..<28).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        XCTAssertEqual(rate, UInt32(ChimeSynth.sampleRate))
        let size = data.subdata(in: 40..<44).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        XCTAssertEqual(Int(size), samples.count * 2)
    }
}
