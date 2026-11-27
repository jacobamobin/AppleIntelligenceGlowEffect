import Foundation

/// Frame-rate-independent envelopes keep FFT, waveform phase and loudness changes fluid.
public struct GlowMotion {
    private var frame = AudioFeatures.silence
    private var bassReference: Float = 0.55
    public init() { }

    public mutating func update(_ input: AudioFeatures, elapsed: Float) -> AudioFeatures {
        guard input.bands.count == 64, input.waveform.count == 64 else { return frame }
        let dt = elapsed.isFinite ? max(0,min(0.1,elapsed)) : 0
        func blend(_ value: Float, _ target: Float, attack: Float, release: Float) -> Float {
            value+(target-value)*(1-exp(-dt/(target > value ? attack : release)))
        }
        // A slow reference trims sustained low-end energy, preserving short hits.
        let bassPeak = max(input.bass,input.bands[0..<18].max() ?? 0)
        bassReference = blend(bassReference,bassPeak,attack:0.35,release:4)
        let bassGain = min(1,0.55/max(0.55,bassReference))
        for i in 0..<64 {
            let fade = max(0,min(1,(Float(i)-14)/12))
            let bassWeight = 1-fade*fade*(3-2*fade)
            let target = input.bands[i]*(1-(1-bassGain)*bassWeight)
            frame.bands[i] = blend(frame.bands[i],target,attack:0.065,release:0.24)
            frame.waveform[i] = blend(frame.waveform[i],input.waveform[i],attack:0.10,release:0.10)
        }
        frame.rms = blend(frame.rms,input.rms,attack:0.08,release:0.28)
        frame.bass = blend(frame.bass,input.bass*bassGain,attack:0.08,release:0.28)
        frame.mids = blend(frame.mids,input.mids,attack:0.08,release:0.28)
        frame.treble = blend(frame.treble,input.treble,attack:0.08,release:0.28)
        frame.onset = blend(frame.onset,input.onset,attack:0.055,release:0.22)
        return frame
    }
}
