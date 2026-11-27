import XCTest
import Metal
import GlowCore

/// Exercise the actual shader, including its visible thickness and motion, on the GPU.
final class GlowRenderTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private let width = 256
    private var height = 96

    override func setUpWithError() throws {
        guard let gpu = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal device unavailable") }
        device = gpu; queue = gpu.makeCommandQueue()!
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/MusicGlow/Glow.metal"))
        let library = try gpu.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "glowVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "glowFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try gpu.makeRenderPipelineState(descriptor: descriptor)
    }

    func testSilenceDoesNotInventAVisualizerOrBeat() throws {
        let a = try render(time: 4.2, energy: 0)
        let b = try render(time: 9.7, energy: 0)
        XCTAssertEqual(stride(from:3,to:a.count,by:4).map{a[$0]}, stride(from:3,to:b.count,by:4).map{b[$0]}, "A clock must not manufacture a waving spectrum in silence")
        let upperAlpha = stride(from: 3, to: width*(height/2)*4, by: 4).map { a[$0] }.max() ?? 0
        XCTAssertLessThan(upperAlpha, 8)
        let bottom = ((height-1)*width)*4+3
        XCTAssertEqual(a[bottom], a[bottom+(width/2)*4])
        XCTAssertEqual(a[bottom], a[bottom+(width-1)*4])
    }

    func testPaletteDriftsWithoutSimulatingAudioGeometry() throws {
        let a = try render(time: 4.2, energy: 0.35)
        let b = try render(time: 9.7, energy: 0.35)
        XCTAssertEqual(stride(from:3,to:a.count,by:4).map{a[$0]}, stride(from:3,to:b.count,by:4).map{b[$0]}, "Changing elapsed time must not simulate frequency motion")
        let colorDrift = zip(a,b).map{abs(Float($0)-Float($1))/255}.reduce(0,+)/Float(a.count)
        XCTAssertGreaterThan(colorDrift,0.002,"Artwork colors should drift gently from side to side")
    }

    func testAudioChangesTheHeightAndBrightnessOfTheGlow() throws {
        let quiet = try render(time: 4.2, energy: 0.05)
        let loud = try render(time: 4.2, energy: 0.8)
        // The normal body now occupies roughly the lower 30%; inspect its lower
        // half instead of requiring light to fill the empty peak headroom.
        let audioResponse = stride(from: width*(height/2)*4+3, to: quiet.count, by: 4).map { (Float(loud[$0])-Float(quiet[$0])) / 255 }.reduce(0,+) / Float(width*(height-height/2))
        XCTAssertGreaterThan(audioResponse, 0.18)
    }

    func testBassAndTrebleReshapeDifferentGlowRegions() throws {
        var low = [Float](repeating: 0, count: 64), high = low
        for i in 6...10 { low[i] = 0.85 }
        for i in 50...54 { high[i] = 0.85 }
        let a = try render(time: 4.2, energy: 0.4, bands: low)
        let b = try render(time: 4.2, energy: 0.4, bands: high)
        func mean(_ pixels: [UInt8], centre: Int) -> Float {
            var sum: Float = 0, count: Float = 0
            for y in (height/3)..<height { for x in (centre-8)...(centre+8) {
                sum += Float(pixels[(y*width+x)*4+3])/255; count += 1
            } }
            return sum/count
        }
        // Relative contrast remains meaningful with the user's lower 30% profile.
        XCTAssertGreaterThan(mean(a,centre:34),mean(b,centre:34)*1.35)
        XCTAssertGreaterThan(mean(b,centre:210),mean(a,centre:210)*1.35)
        XCTAssertGreaterThan(mean(a,centre:34)-mean(b,centre:34),0.04)
        XCTAssertGreaterThan(mean(b,centre:210)-mean(a,centre:210),0.04)
    }

    func testPCMChangesTheGlowDiffusion() throws {
        let flat = try render(time: 4.2, energy: 0.25)
        let wave = (0..<64).map { Float(0.65)*sin(Float($0)*0.35) }
        let pcm = try render(time: 4.2, energy: 0.25, waveform: wave)
        let difference = zip(flat, pcm).map { abs(Float($0)-Float($1))/255 }.reduce(0,+)/Float(flat.count)
        XCTAssertGreaterThan(difference, 0.005)
    }

    func testEqualLoudnessPCMProducesDifferentRenderedSpectra() throws {
        func analyze(_ frequency: Double) -> AudioFeatures {
            let samples = (0..<2048).map { Float(sin(2*Double.pi*frequency*Double($0)/48000)*0.3) }
            return AudioFeatureAnalyzer().analyze(left: samples, right: samples, sampleRate: 48000, elapsed: 1/60)
        }
        let low = analyze(100), high = analyze(6000)
        XCTAssertEqual(low.rms,high.rms,accuracy:0.003)
        let a = try render(time:4.2,energy:low.loudness,bands:low.bands,waveform:low.waveform)
        let b = try render(time:4.2,energy:high.loudness,bands:high.bands,waveform:high.waveform)
        // Inspect each tone's actual frequency region, rather than diluting a narrow
        // treble peak across an entire quarter of the screen.
        func regionAlpha(_ pixels: [UInt8], columns: Range<Int>) -> Float {
            var sum: Float = 0
            for y in (height/3)..<height { for x in columns { sum += Float(pixels[(y*width+x)*4+3])/255 } }
            return sum/Float(columns.count*(height-height/3))
        }
        let lowBin = low.bands.indices.max { low.bands[$0] < low.bands[$1] }!
        let highBin = high.bands.indices.max { high.bands[$0] < high.bands[$1] }!
        let lowX = (lowBin*4+2)
        XCTAssertGreaterThan(regionAlpha(a,columns:(lowX-6)..<(lowX+6)),regionAlpha(b,columns:(lowX-6)..<(lowX+6))+0.04)
        XCTAssertGreaterThan(highBin,lowBin+30)
        // Bass deliberately lifts BOTH wings. Equal loudness must still yield
        // a substantially different silhouette instead of a volume-only pulse.
        let difference = stride(from:3,to:a.count,by:4).map { abs(Float(a[$0])-Float(b[$0]))/255 }.reduce(0,+)/Float(width*height)
        XCTAssertGreaterThan(difference,0.025)
    }

    func testGlowRisesHigherAtBothEdgesThanBehindDock() throws {
        let pixels = try render(time:4.2,energy:0.65)
        func visibleHeight(_ x: Int) -> Float {
            let first = (0..<height).first { pixels[($0*width+x)*4+3] > 24 } ?? height
            return Float(height-first)/Float(height)
        }
        let middle = visibleHeight(width/2)
        XCTAssertGreaterThan(visibleHeight(8),middle+0.10)
        XCTAssertGreaterThan(visibleHeight(width-9),middle+0.10)
    }

    func testBassAlsoLiftsTheRightWingWhenTrebleIsQuiet() throws {
        let quiet = try render(time:4.2,energy:0.4,bands:[Float](repeating:0,count:64))
        var low = [Float](repeating:0,count:64)
        for i in 6...10 { low[i] = 0.7 }
        let bass = try render(time:4.2,energy:0.4,bands:low)
        var delta: Float = 0, baseline: Float = 0
        for y in (height/2)..<height { for x in 240..<256 {
            delta += (Float(bass[(y*width+x)*4+3])-Float(quiet[(y*width+x)*4+3]))/255
            baseline += Float(quiet[(y*width+x)*4+3])/255
        } }
        XCTAssertGreaterThan(delta/Float((height-height/2)*16),0.04)
        XCTAssertGreaterThan(delta,baseline*0.5)
    }

    func testEdgesCropThroughTheSameSoftFieldWithoutSideStrokes() throws {
        let pixels = try render(time:4.2,energy:0.65)
        for y in [height/4,height/2,height*3/4] {
            func alpha(_ x: Int) -> Float { Float(pixels[(y*width+x)*4+3])/255 }
            XCTAssertEqual(alpha(0),alpha(4),accuracy:0.025,"The left edge must not become a vertical border")
            XCTAssertEqual(alpha(width-1),alpha(width-5),accuracy:0.025,"The right edge must not become a vertical border")
        }
    }

    func testGlowStaysTranslucentAndHasNoHardBottomStripe() throws {
        let pixels = try render(time:4.2,energy:0.8)
        let alpha = stride(from:3,to:pixels.count,by:4).map { Float(pixels[$0])/255 }
        XCTAssertLessThan(alpha.max() ?? 1,0.75)
        var steepest: Float = 0
        for y in 1..<height { for x in 0..<width {
            steepest = max(steepest,abs(alpha[y*width+x]-alpha[(y-1)*width+x]))
        } }
        XCTAssertLessThan(steepest,0.045,"Diffusion must not resolve into a crisp bottom stripe")
    }

    func testMusicCanLiftLeftCentreAndRight() throws {
        let quiet = try render(time:4.2,energy:0.04)
        let loud = try render(time:4.2,energy:0.75)
        for centre in [20,width/2,width-21] {
            var delta: Float = 0
            for y in (height/2)..<height { for x in (centre-8)..<(centre+8) {
                delta += (Float(loud[(y*width+x)*4+3])-Float(quiet[(y*width+x)*4+3]))/255
            } }
            XCTAssertGreaterThan(delta/Float((height-height/2)*16),0.14)
        }
    }

    func testTopFeathersBeforeWindowBoundaryAtActualStripResolution() throws {
        height = 87
        let pixels = try render(time:4.2,energy:0.85)
        var steepest: Float = 0
        for y in 1..<(height/3) { for x in 0..<width {
            let a = Float(pixels[(y*width+x)*4+3])/255
            let b = Float(pixels[((y-1)*width+x)*4+3])/255
            steepest = max(steepest,abs(a-b))
        } }
        XCTAssertLessThan(steepest,0.025,"The upper feather needs enough room at the real Dock-height render resolution")
        XCTAssertLessThan(stride(from:3,to:width*2*4,by:4).map{pixels[$0]}.max() ?? 255,3,"Light must become transparent before it reaches the top boundary")
    }

    func testCursorInfluenceIsSubtleAndLocal() throws {
        let baseline = try render(time:4.2,energy:0.4)
        let hovered = try render(time:4.2,energy:0.4,pointer:SIMD4(0.25,1,0.6,0.2))
        func difference(_ columns: Range<Int>) -> Float {
            var total: Float = 0
            for y in 0..<height { for x in columns {
                total += abs(Float(hovered[(y*width+x)*4+3])-Float(baseline[(y*width+x)*4+3]))/255
            } }
            return total/Float(height*columns.count)
        }
        XCTAssertGreaterThan(difference(48..<80),0.002)
        XCTAssertLessThan(difference(0..<width),0.012)
        XCTAssertLessThan(difference(192..<224),0.001)
    }

    private func render(time: Float, energy: Float, bands: [Float]? = nil, waveform: [Float]? = nil, pointer: SIMD4<Float> = .zero) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]; descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        var values = [SIMD4<Float>](repeating: .zero, count: 56)
        values[0] = SIMD4(time, 1, 1728, 87)
        values[55] = pointer
        values[1] = SIMD4(energy, 0, 1.45, 0)
        let source = bands ?? [Float](repeating: energy, count: 64)
        values[2] = SIMD4(source[0..<18].max() ?? 0, energy, source[46..<64].max() ?? 0, energy*0.2)
        for i in 0..<4 { values[i+3] = SIMD4(GlowPalette.fallback.colors[i], 1) }
        for i in 0..<16 {
            values[i+7] = SIMD4(source[i*4],source[i*4+1],source[i*4+2],source[i*4+3])
            values[i+23] = values[i+7]
            let wave = waveform ?? [Float](repeating: 0, count: 64)
            values[i+39] = SIMD4(wave[i*4],wave[i*4+1],wave[i*4+2],wave[i*4+3])
        }
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(pipeline)
        values.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var pixels = [UInt8](repeating: 0, count: width*height*4)
        texture.getBytes(&pixels, bytesPerRow: width*4, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0)
        return pixels
    }
}
