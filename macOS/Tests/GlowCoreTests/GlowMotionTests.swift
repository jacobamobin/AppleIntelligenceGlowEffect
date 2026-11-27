import XCTest
import GlowCore

final class GlowMotionTests: XCTestCase {
    private func loud() -> AudioFeatures {
        var value = AudioFeatures.silence
        value.bands = [Float](repeating:0.8,count:64)
        value.waveform = [Float](repeating:0.8,count:64)
        value.rms = 0.2; value.bass = 0.8; value.mids = 0.6; value.treble = 0.4; value.onset = 1
        return value
    }

    func testAbruptAudioChangesHaveAVisibleAttackAndRelease() {
        var motion = GlowMotion()
        let first = motion.update(loud(),elapsed:1/60)
        XCTAssertGreaterThan(first.bands[0],0.1)
        XCTAssertLessThan(first.bands[0],0.4)
        XCTAssertLessThan(first.rms,0.08)
        XCTAssertLessThan(first.onset,0.4)
        let released = motion.update(.silence,elapsed:1/60)
        XCTAssertGreaterThan(released.bands[0],first.bands[0]*0.85)
        XCTAssertGreaterThan(released.rms,first.rms*0.85)
    }

    func testResponseIsIndependentOfFrameRate() {
        var a = GlowMotion(), b = GlowMotion()
        var at60 = AudioFeatures.silence, at120 = AudioFeatures.silence
        for _ in 0..<30 { at60 = a.update(loud(),elapsed:1/60) }
        for _ in 0..<60 { at120 = b.update(loud(),elapsed:1/120) }
        // Cascaded adaptive gain may differ by less than one 8-bit intensity step.
        XCTAssertEqual(at60.bands[0],at120.bands[0],accuracy:0.002)
        XCTAssertEqual(at60.rms,at120.rms,accuracy:0.0001)
    }

    func testAlternatingPCMDoesNotStrobeTheGlow() {
        var motion = GlowMotion(), maximum: Float = 0
        for i in 0..<120 {
            var input = loud()
            input.waveform = [Float](repeating:i % 2 == 0 ? 0.8 : -0.8,count:64)
            maximum = max(maximum,abs(motion.update(input,elapsed:1/60).waveform[0]))
        }
        XCTAssertLessThan(maximum,0.16)
    }

    func testSustainedBassNormalizesInsteadOfPinningTheLeftSide() {
        var motion = GlowMotion()
        var input = loud(), output = AudioFeatures.silence
        input.bands = (0..<64).map { $0 < 18 ? 1 : 0.1 }
        input.bass = 1; input.onset = 0
        for _ in 0..<240 { output = motion.update(input,elapsed:1/60) }
        XCTAssertEqual(output.bands[8],0.55,accuracy:0.03)
        XCTAssertEqual(output.bass,0.55,accuracy:0.03)
        XCTAssertEqual(output.bands[40],0.1,accuracy:0.01)
    }
}
