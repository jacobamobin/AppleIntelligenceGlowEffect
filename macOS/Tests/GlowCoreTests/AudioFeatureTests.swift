import XCTest
@testable import GlowCore

final class AudioFeatureTests: XCTestCase {
    private func tone(_ hz: Float, amplitude: Float) -> [Float] {
        (0..<2048).map { amplitude*sin(2 * Float.pi * hz * Float($0) / 48000) }
    }
    func testSilenceHasNoFakePulseOrWaveform() {
        let analyzer = AudioFeatureAnalyzer()
        let zero = [Float](repeating: 0, count: 2048)
        let frame = analyzer.analyze(left: zero, right: zero, sampleRate: 48000, elapsed: 1/60)
        XCTAssertEqual(frame.rms, 0)
        XCTAssertEqual(frame.onset, 0)
        XCTAssertEqual(frame.bands.max(), 0)
        XCTAssertEqual(frame.waveform.max(), 0)
    }
    func testEqualLoudnessBassAndTrebleHaveDifferentSpectra() {
        let analyzer = AudioFeatureAnalyzer()
        let low = tone(100, amplitude: 0.3), high = tone(6000, amplitude: 0.3)
        let bass = analyzer.analyze(left: low, right: low, sampleRate: 48000, elapsed: 1/60)
        let treble = analyzer.analyze(left: high, right: high, sampleRate: 48000, elapsed: 1/60)
        XCTAssertEqual(bass.rms, treble.rms, accuracy: 0.01)
        XCTAssertGreaterThan(bass.bass, treble.bass + 0.2)
        XCTAssertGreaterThan(treble.treble, bass.treble + 0.2)
        XCTAssertNotEqual(bass.bands, treble.bands)
    }
    func testBassHitProducesAnOnsetAndThenDecays() {
        let analyzer = AudioFeatureAnalyzer()
        let low = tone(100, amplitude: 0.025), loud = tone(100, amplitude: 0.6)
        for _ in 0..<120 { _ = analyzer.analyze(left: low, right: low, sampleRate: 48000, elapsed: 1/60) }
        let hit = analyzer.analyze(left: loud, right: loud, sampleRate: 48000, elapsed: 1/60)
        var sustained = hit
        for _ in 0..<120 { sustained = analyzer.analyze(left: loud, right: loud, sampleRate: 48000, elapsed: 1/60) }
        XCTAssertGreaterThan(hit.onset, 0.2)
        XCTAssertLessThan(sustained.onset, hit.onset * 0.1)
        XCTAssertGreaterThan(hit.rms, 0.3)
    }
}
