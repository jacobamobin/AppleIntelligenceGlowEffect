import AppKit
import MetalKit
import GlowCore

final class GlowRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    var palette = PaletteTransition()
    var playing = false
    var preview = false
    var reducedMotion = false
    var features = AudioFeatures.silence
    var sensitivity: Float = 1.45
    private var motion = GlowMotion()
    private var peaks = [Float](repeating: 0, count: 64)
    private var uniforms = [SIMD4<Float>](repeating: .zero, count: 56)
    private var pointer = SIMD4<Float>(0.5,0,0,0)
    private var previousMouse: NSPoint?
    private var opacity: Float = 0
    private var lastTime = CACurrentMediaTime()
    private let epoch = CACurrentMediaTime()
    private(set) var frames = 0
    private(set) var totalGPUTime = 0.0

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RenderError.unavailable }
        commandQueue = queue
        let library: MTLLibrary
        if let url = Bundle.main.url(forResource: "default", withExtension: "metallib") {
            library = try device.makeLibrary(URL: url)
        } else {
            let url = Bundle.module.url(forResource: "Glow", withExtension: "metal")!
            library = try device.makeLibrary(source: String(contentsOf: url), options: nil)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "glowVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "glowFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime(), dt = Float(min(0.1, max(0, now-lastTime)))
        lastTime = now
        let target: Float = (playing || preview) ? 1 : 0
        opacity += (target-opacity) * (1-exp(-dt / (target > opacity ? 0.65 : 1.15)))
        // Suspend even if a sleeping/removed display cannot provide a drawable.
        if target == 0 && opacity < 0.002 { opacity = 0; view.isPaused = true }
        let elapsed = Float(now-epoch)
        var source = features
        if preview {
            source = .silence
            source.rms = 0.12; source.bass = 0.5; source.mids = 0.4; source.treble = 0.3
            source.onset = pow(max(0,sin(elapsed*5)), 8)
            for i in 0..<64 {
                source.bands[i] = max(0,0.35+0.3*sin(elapsed*3.5-Float(i)*0.4))
                source.waveform[i] = sin(Float(i)*0.4+elapsed*3)*0.45
            }
        }
        source = motion.update(source,elapsed:dt)
        let bands = source.bands
        for i in 0..<64 { peaks[i] = max(bands[i],peaks[i]*exp(-dt/0.44)) }
        let colors = palette.value(at: now).colors
        uniforms[0] = SIMD4(reducedMotion ? 0 : elapsed, opacity, Float(view.bounds.width), Float(view.bounds.height))
        uniforms[1] = SIMD4(source.loudness,source.onset,sensitivity,0)
        uniforms[2] = SIMD4(source.bass,source.mids,source.treble,source.rms)
        for i in 0..<4 { uniforms[i+3] = SIMD4(colors[i], 1) }
        for i in 0..<16 {
            uniforms[i+7] = SIMD4(bands[i*4],bands[i*4+1],bands[i*4+2],bands[i*4+3])
            uniforms[i+23] = SIMD4(peaks[i*4],peaks[i*4+1],peaks[i*4+2],peaks[i*4+3])
            uniforms[i+39] = SIMD4(source.waveform[i*4],source.waveform[i*4+1],source.waveform[i*4+2],source.waveform[i*4+3])
        }
        updatePointer(in: view, elapsed: dt)
        uniforms[55] = pointer
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = commandQueue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(encoder, uniforms: uniforms)
        encoder.endEncoding(); command.present(drawable)
        command.addCompletedHandler { [weak self] buffer in
            let time = max(0, buffer.gpuEndTime-buffer.gpuStartTime)
            DispatchQueue.main.async { self?.frames += 1; self?.totalGPUTime += time }
        }
        command.commit()
    }

    func wake(_ view: MTKView) { lastTime = CACurrentMediaTime(); view.isPaused = false }
    private func updatePointer(in view: MTKView, elapsed dt: Float) {
        guard let frame = view.window?.frame else { return }
        // Position polling needs no event tap, input interception, or extra permission.
        let mouse = NSEvent.mouseLocation
        let horizontal = max(0,max(frame.minX-mouse.x,mouse.x-frame.maxX))
        let vertical = max(0,mouse.y-frame.minY-frame.height*0.4)
        let proximity = Float(exp(-pow(vertical/85,2)-pow(horizontal/60,2)))
        let x = Float((mouse.x-frame.minX)/max(1,frame.width))
        let depth = Float((mouse.y-frame.minY)/max(1,frame.height))
        var speed: Float = 0
        if let previousMouse, dt > 0 {
            speed = min(1,Float(hypot(mouse.x-previousMouse.x,mouse.y-previousMouse.y))/max(0.001,dt)/900)
        }
        previousMouse = mouse
        let target = SIMD4(max(-0.1,min(1.1,x)),proximity*(reducedMotion ? 0.4 : 1),reducedMotion ? 0 : speed,depth)
        pointer += (target-pointer)*(1-exp(-dt/0.14))
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    private func encode(_ encoder: MTLRenderCommandEncoder, uniforms: [SIMD4<Float>]) {
        encoder.setRenderPipelineState(pipeline)
        uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func renderPreview(to url: URL) throws -> Double {
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false }
        let width = Int(screen?.frame.width ?? 1728)
        let bottomInset = screen.map { Double($0.visibleFrame.minY-$0.frame.minY) } ?? 87
        let tile = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["tilesize"] as? Double ?? 64
        let height = Int(ceil(GlowGeometry.stripHeight(dockHeight: bottomInset, tileSize: tile)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.unavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        var values = [SIMD4<Float>](repeating: .zero, count: 56)
        values[0] = SIMD4(4.2, 1, Float(width), Float(height))
        values[1] = SIMD4(0.65,0.4,1.45,0); values[2] = SIMD4(0.7,0.4,0.3,0.12)
        for i in 0..<4 { values[i+3] = SIMD4(GlowPalette.fallback.colors[i], 1) }
        var sample = [Float](repeating:0,count:64), wave = sample
        for i in 0..<64 {
            let x = Float(i)
            sample[i] = 0.08+0.62*exp(-pow((x-9)/4,2))+0.4*exp(-pow((x-30)/7,2))+0.25*exp(-pow((x-53)/5,2))
            wave[i] = sin(x*0.42)*0.4
        }
        for i in 0..<16 {
            values[i+7] = SIMD4(sample[i*4],sample[i*4+1],sample[i*4+2],sample[i*4+3])
            values[i+23] = values[i+7]+SIMD4(repeating:0.04)
            values[i+39] = SIMD4(wave[i*4],wave[i*4+1],wave[i*4+2],wave[i*4+3])
        }
        var gpu = 0.0
        for _ in 0..<120 {
            guard let command = commandQueue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RenderError.unavailable }
            encode(encoder, uniforms: values); encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            gpu += command.gpuEndTime-command.gpuStartTime
        }
        var pixels = [UInt8](repeating: 0, count: width*height*4)
        texture.getBytes(&pixels, bytesPerRow: width*4, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: width*4, bitsPerPixel: 32)!
        for y in 0..<height { for x in 0..<width {
            let src = (y*width+x)*4
            bitmap.bitmapData![src] = pixels[src+2]; bitmap.bitmapData![src+1] = pixels[src+1]
            bitmap.bitmapData![src+2] = pixels[src]; bitmap.bitmapData![src+3] = pixels[src+3]
        } }
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return gpu / 120 * 1000
    }
}

enum RenderError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Metal is unavailable on this Mac" }
}
