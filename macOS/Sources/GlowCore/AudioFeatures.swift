import Accelerate
import Foundation

public struct AudioFeatures {
    public var bands: [Float]
    public var waveform: [Float]
    public var rms: Float
    public var bass: Float
    public var mids: Float
    public var treble: Float
    public var onset: Float
    public var loudness: Float { min(1, pow(max(0, rms)*4, 0.7)) }
    public static var silence: AudioFeatures {
        AudioFeatures(bands: Array(repeating: 0, count: 64), waveform: Array(repeating: 0, count: 64), rms: 0, bass: 0, mids: 0, treble: 0, onset: 0)
    }
}

/// Absolute PCM loudness, spectrum and positive bass onset. No clock-generated motion.
public final class AudioFeatureAnalyzer {
    private let spectrum = SpectrumAnalyzer()
    private var bassBaseline: Float = 0
    private var pulse: Float = 0
    public init() { }

    public func analyze(left: [Float], right: [Float], sampleRate: Double, elapsed: Float) -> AudioFeatures {
        guard left.count == 2048, right.count == 2048 else { return .silence }
        var leftRMS: Float = 0, rightRMS: Float = 0
        vDSP_rmsqv(left, 1, &leftRMS, 2048); vDSP_rmsqv(right, 1, &rightRMS, 2048)
        let rms = sqrt((leftRMS*leftRMS + rightRMS*rightRMS)*0.5)
        let dt = max(0.001, min(0.25, elapsed))
        let raw = spectrum.analyzeStereo(left: left, right: right, sampleRate: sampleRate)
        // Restore contrast lost to the wide logarithmic display range; music dynamics stay visible.
        let bands = raw.map { pow($0, 2.4) }
        let bass = bands[0..<18].max() ?? 0
        let mids = bands[18..<46].max() ?? 0
        let treble = bands[46..<64].max() ?? 0
        let onset = min(1, max(0, bass-bassBaseline-0.015)*2.8)
        bassBaseline += (bass-bassBaseline)*(1-exp(-dt/0.35))
        pulse = max(onset, pulse*exp(-dt/0.13))
        let source = leftRMS >= rightRMS ? left : right
        let waveform = (0..<64).map { index -> Float in
            var sum: Float = 0
            for i in (index*32)..<((index+1)*32) { sum += source[i] }
            return max(-1, min(1, sum/32*4))
        }
        return AudioFeatures(bands: bands, waveform: waveform, rms: rms,
                             bass: bass, mids: mids, treble: treble, onset: pulse)
    }
}
