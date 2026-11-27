import Accelerate
import Foundation

/// Reused FFT workspace. Call from one analysis queue, never the audio IO callback.
public final class SpectrumAnalyzer {
    public static let count = 64
    public static let windowSize = 2048
    private let setup: FFTSetup
    private var window = [Float](repeating: 0, count: 2048)
    private var input = [Float](repeating: 0, count: 2048)
    private var real = [Float](repeating: 0, count: 1024)
    private var imaginary = [Float](repeating: 0, count: 1024)
    private var powers = [Float](repeating: 0, count: 1024)
    private var frequencyMap: LogFrequencyMap?
    private var mapped = [Float](repeating: 0, count: 64)
    private var mappedSampleRate: Double = 0

    public init() {
        setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, 2048, Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    public func analyzeStereo(left: [Float], right: [Float], sampleRate: Double) -> [Float] {
        let a = analyze(samples: left, sampleRate: sampleRate)
        let b = analyze(samples: right, sampleRate: sampleRate)
        // Combine after the FFT: panned or opposite-phase material cannot cancel out.
        return zip(a, b).map { max($0, $1) }
    }

    public func analyze(samples: [Float], sampleRate: Double) -> [Float] {
        guard samples.count == 2048, sampleRate.isFinite, sampleRate > 0 else {
            return Array(repeating: 0, count: Self.count)
        }
        vDSP_vmul(samples, 1, window, 1, &input, 1, 2048)
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                input.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: 1024) {
                        vDSP_ctoz($0, 2, &split, 1, 1024)
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0 // packed Nyquist is not the DC imaginary component
                vDSP_zvmags(&split, 1, &powers, 1, 1024)
            }
        }
        if mappedSampleRate != sampleRate {
            frequencyMap = LogFrequencyMap(binCount: 1024, sampleRate: sampleRate, rowCount: Self.count, lowestHz: 40, highestHz: 16000)
            mappedSampleRate = sampleRate
        }
        for i in powers.indices {
            let amplitude = sqrt(max(0, powers[i])) / 2048
            powers[i] = 20 * log10(max(1e-8, amplitude))
        }
        frequencyMap!.apply(powers, into: &mapped)
        return mapped.map { min(1, max(0, ($0 + 65) / 55)) }
    }
}
