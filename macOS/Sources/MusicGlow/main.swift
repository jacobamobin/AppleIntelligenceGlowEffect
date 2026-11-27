import AppKit
import MetalKit

if CommandLine.arguments.contains("--check-scripts") {
    do { try MusicScripts.validate(); print("Music AppleScripts compile successfully") }
    catch { fputs("\(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--music-worker") {
    runMusicWorker()
} else if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index+1 {
    do {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.unavailable }
        let renderer = try GlowRenderer(device: device)
        let milliseconds = try renderer.renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
        print(String(format: "120 Metal frames · mean GPU %.3f ms · %@", milliseconds, device.name))
    } catch { fputs("\(error)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppController()
    app.delegate = delegate
    app.run()
}
