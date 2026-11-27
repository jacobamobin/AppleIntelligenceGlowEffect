import Foundation
import simd

public struct GlowPalette: Equatable {
    public let colors: [SIMD3<Float>]
    public init(colors: [SIMD3<Float>]) {
        self.colors = colors.count == 4 ? colors : Self.fallback.colors
    }
    public static let fallback = GlowPalette(colors: [
        SIMD3(0.04, 0.24, 1), SIMD3(0.12, 0.63, 1),
        SIMD3(0.40, 0.82, 1), SIMD3(0.10, 0.38, 0.96)
    ])

    /// Quantized population with chroma weighting; neutral/transparent pixels cannot dominate.
    public static func extract(rgba: [UInt8]) -> GlowPalette {
        guard rgba.count >= 4, rgba.count % 4 == 0 else { return .fallback }
        var buckets: [Int: (sum: SIMD3<Float>, weight: Float)] = [:]
        for i in stride(from: 0, to: rgba.count, by: 4) {
            guard rgba[i + 3] > 180 else { continue }
            let c = SIMD3(Float(rgba[i]), Float(rgba[i+1]), Float(rgba[i+2])) / 255
            let hi = max(c.x, max(c.y, c.z)), lo = min(c.x, min(c.y, c.z))
            let chroma = hi - lo
            guard hi > 0.12, lo < 0.92, chroma > 0.09 else { continue }
            let key = (Int(c.x * 7) << 6) | (Int(c.y * 7) << 3) | Int(c.z * 7)
            let weight = 0.25 + chroma
            let old = buckets[key] ?? (.zero, 0)
            buckets[key] = (old.sum + c * weight, old.weight + weight)
        }
        let candidates = buckets.values.sorted { $0.weight > $1.weight }.map { $0.sum / $0.weight }
        guard let dominant = candidates.first else { return .fallback }
        var chosen = [dominant]
        for c in candidates.dropFirst() {
            // Perceptual distance rejects near-duplicates without inventing unrelated hues.
            if chosen.allSatisfy({ simd_distance(oklab($0), oklab(c)) > 0.11 }) {
                chosen.append(c)
            }
            if chosen.count == 4 { break }
        }
        let originals = chosen
        while chosen.count < 4 {
            let c = originals[(chosen.count - originals.count) % originals.count]
            chosen.append(simd_mix(c, SIMD3<Float>(repeating: 1), SIMD3<Float>(repeating: 0.10)))
        }
        return GlowPalette(colors: chosen)
    }

    private static func oklab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func linear(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(c.x), g = linear(c.y), b = linear(c.z)
        let l = cbrt(0.41222147*r + 0.53633254*g + 0.05144599*b)
        let m = cbrt(0.21190350*r + 0.68069955*g + 0.10739696*b)
        let s = cbrt(0.08830246*r + 0.28171884*g + 0.62997870*b)
        return SIMD3(0.21045426*l + 0.79361779*m - 0.00407205*s,
                     1.97799850*l - 2.42859221*m + 0.45059371*s,
                     0.02590404*l + 0.78277177*m - 0.80867577*s)
    }
}

public struct PaletteTransition {
    private var from: GlowPalette
    private var to: GlowPalette
    private var start: Double = 0
    private let duration: Double
    public init(initial: GlowPalette = .fallback, duration: Double = 4) {
        from = initial; to = initial; self.duration = max(duration, 0.001)
    }
    public mutating func set(_ palette: GlowPalette, at time: Double) {
        guard palette != to else { return }
        from = value(at: time); to = palette; start = time
    }
    public func value(at time: Double) -> GlowPalette {
        let p = Float(min(1, max(0, (time - start) / duration)))
        let t = p*p*(3-2*p)
        return GlowPalette(colors: zip(from.colors, to.colors).map { $0 + ($1 - $0) * t })
    }
}

public enum DisplayPolicy {
    public static func eligible(builtIn: Bool, online: Bool, mirrored: Bool) -> Bool {
        builtIn && online && !mirrored
    }
}

public enum GlowGeometry {
    public static func stripHeight(dockHeight: Double, tileSize: Double = 64) -> Double {
        // visibleFrame supplies the Dock reservation; tile size covers auto-hidden Docks.
        let measured = dockHeight.isFinite && dockHeight > 0 ? dockHeight : max(24, tileSize) + 26
        // Full-Dock transparent ceiling; the shader keeps the usual light much lower.
        return measured
    }
}

public enum CaptureRecovery {
    public static func shouldStart(targetChanged: Bool, secondsSinceFailure: Double?) -> Bool {
        targetChanged || secondsSinceFailure == nil || secondsSinceFailure! >= 8
    }
}

public struct MetadataRevision {
    public private(set) var current: UInt64 = 0
    public init() { }
    public mutating func invalidate() { current &+= 1 }
    public func accepts(_ request: UInt64) -> Bool { request == current }
}
