import AppKit
import MetalKit
import GlowCore

private final class GlowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppController: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let trackItem = NSMenuItem(title: "Waiting for Music", action: nil, keyEquivalent: "")
    private let audioItem = NSMenuItem(title: "Audio idle", action: nil, keyEquivalent: "")
    private let displayItem = NSMenuItem(title: "Built-in display only", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Glow enabled", action: #selector(toggle), keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "Visual Preview (30 seconds)", action: #selector(preview), keyEquivalent: "")
    private var panel: GlowPanel?
    private var view: MTKView?
    private var renderer: GlowRenderer?
    private let monitor = MusicMonitor()
    private let audio = AudioCapture()
    private var snapshot = MusicSnapshot()
    private var lastArt: Data?
    private var enabled = true
    private var sleeping = false
    private var previewToken = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var diagnosticsTimer: Timer?
    private var trace: FileHandle?
    private let traceQueue = DispatchQueue(label: "MusicGlow.trace", qos: .utility)
    private var sensitivityItems: [NSMenuItem] = []
    private let args = CommandLine.arguments

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Music Glow")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Music Glow", action: nil, keyEquivalent: ""))
        menu.addItem(trackItem); menu.addItem(audioItem); menu.addItem(displayItem)
        menu.addItem(.separator())
        toggleItem.target = self; toggleItem.state = .on; menu.addItem(toggleItem)
        previewItem.target = self; menu.addItem(previewItem)
        let sensitivities = NSMenu()
        for (index, title) in ["Balanced", "Punchy", "Extra Punchy"].enumerated() {
            let choice = NSMenuItem(title: title, action: #selector(changeSensitivity(_:)), keyEquivalent: "")
            choice.tag = index; choice.target = self; sensitivityItems.append(choice); sensitivities.addItem(choice)
        }
        let sensitivityMenu = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: ""); sensitivityMenu.submenu = sensitivities; menu.addItem(sensitivityMenu)
        let retry = NSMenuItem(title: "Retry Music & Audio", action: #selector(retry), keyEquivalent: "")
        retry.target = self; menu.addItem(retry)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Music Glow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.unavailable }
            renderer = try GlowRenderer(device: device)
        } catch {
            trackItem.title = error.localizedDescription; return
        }
        monitor.onChange = { [weak self] in self?.receive($0) }
        let sensitivity = UserDefaults.standard.object(forKey: "visualizerSensitivity") as? Int ?? 1
        renderer?.sensitivity = [Float(1), 1.45, 2][max(0,min(2,sensitivity))]
        for item in sensitivityItems { item.state = item.tag == sensitivity ? .on : .off }
        if let index = args.firstIndex(of: "--audio-trace"), args.count > index+1 {
            _ = FileManager.default.createFile(atPath: args[index+1], contents: nil)
            trace = FileHandle(forWritingAtPath: args[index+1])
        }
        audio.onFeatures = { [weak self] features in
            self?.renderer?.features = features
            self?.record(features)
        }
        watch(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.reconcileDisplay() }
        let workspace = NSWorkspace.shared.notificationCenter
        watch(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.sleep() }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.sleep() }
        watch(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.wake() }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.wake() }
        watch(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.sleep() }
        watch(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.wake() }
        watch(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { [weak self] in self?.updateQuality() }
        reconcileDisplay()
        if args.contains("--preview") { preview() } else { monitor.start() }
        if let index = args.firstIndex(of: "--quit-after"), args.count > index+1, let seconds = Double(args[index+1]) {
            DispatchQueue.main.asyncAfter(deadline: .now()+seconds) { NSApp.terminate(nil) }
        }
        if args.contains("--diagnostics") {
            diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.writeDiagnostics() }
            writeDiagnostics()
        }
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }))
    }

    private func receive(_ new: MusicSnapshot) {
        if new.key != snapshot.key {
            lastArt = nil; renderer?.palette.set(.fallback, at: CACurrentMediaTime())
        }
        snapshot = new
        if let data = new.rgba, data != lastArt {
            lastArt = data
            renderer?.palette.set(GlowPalette.extract(rgba: Array(data)), at: CACurrentMediaTime())
        }
        trackItem.title = new.error ?? (new.title.isEmpty ? "Waiting for Music" : "\(new.title) — \(new.artist)")
        if let screen = panel?.screen, let panel {
            let ceiling = ceil(GlowGeometry.stripHeight(dockHeight: dockHeight(screen)))
            if abs(panel.frame.height-ceiling) > 0.5 { reconcileDisplay() }
        }
        updatePlayback()
    }

    private func updatePlayback() {
        let playing = enabled && !sleeping && panel != nil && snapshot.playing && renderer?.preview != true
        audio.reconcile(playing: playing)
        audioItem.title = audio.status
        guard let renderer, let view else { return }
        if renderer.playing != playing {
            renderer.playing = playing
            if !sleeping { renderer.wake(view) }
        }
    }

    private func reconcileDisplay() {
        let builtIn = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let id = CGDirectDisplayID(number.uint32Value)
            return DisplayPolicy.eligible(builtIn: CGDisplayIsBuiltin(id) != 0,
                                          online: CGDisplayIsOnline(id) != 0 && CGDisplayIsActive(id) != 0,
                                          mirrored: CGDisplayIsInMirrorSet(id) != 0)
        }
        guard let screen = builtIn, let renderer, !sleeping else {
            view?.isPaused = true; panel?.orderOut(nil); panel = nil; view = nil
            audio.stop(); displayItem.title = "No eligible built-in display · glow suspended"
            return
        }
        let height = ceil(GlowGeometry.stripHeight(dockHeight: dockHeight(screen)))
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
        if panel == nil {
            let overlay = GlowPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
            overlay.title = "Music Glow — built-in bottom edge"
            overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = false
            overlay.ignoresMouseEvents = true; overlay.hidesOnDeactivate = false; overlay.isReleasedWhenClosed = false
            overlay.level = .floating
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let metalView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: renderer.device)
            metalView.colorPixelFormat = .bgra8Unorm
            metalView.clearColor = MTLClearColorMake(0,0,0,0)
            metalView.layer?.isOpaque = false
            metalView.framebufferOnly = true; metalView.autoResizeDrawable = false
            metalView.delegate = renderer
            overlay.contentView = metalView
            panel = overlay; view = metalView
        }
        panel?.setFrame(frame, display: false)
        view?.frame = NSRect(origin: .zero, size: frame.size)
        view?.drawableSize = frame.size // analytic glow needs logical pixels, not a 4x Retina workload
        panel?.orderFrontRegardless()
        displayItem.title = "Built-in display · soft peaks up to Dock height"
        updateQuality(); updatePlayback()
        if renderer.preview, let view { renderer.wake(view) }
    }

    private func updateQuality() {
        view?.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        renderer?.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private func sleep() {
        sleeping = true; monitor.stop(); audio.stop(); view?.isPaused = true; panel?.orderOut(nil)
    }
    private func wake() {
        guard sleeping else { return }
        sleeping = false; reconcileDisplay()
        if !args.contains("--preview") { monitor.start() }
        if let renderer, let view { renderer.wake(view) }
    }
    @objc private func toggle() {
        enabled.toggle(); toggleItem.state = enabled ? .on : .off
        if !enabled { renderer?.preview = false; previewToken += 1 }
        updatePlayback()
        if let renderer, let view { renderer.wake(view) }
    }
    @objc private func preview() {
        guard let renderer, let view else { return }
        previewToken += 1
        let token = previewToken
        enabled = true; toggleItem.state = .on
        renderer.preview = true; renderer.palette.set(.fallback, at: CACurrentMediaTime())
        audio.stop(); audioItem.title = "Visual Preview · generated spectrum"
        renderer.wake(view)
        DispatchQueue.main.asyncAfter(deadline: .now()+30) { [weak self] in
            guard let self, token == self.previewToken else { return }
            self.renderer?.preview = false; self.updatePlayback()
            if !self.sleeping, self.panel?.isVisible == true, let renderer = self.renderer, let view = self.view { renderer.wake(view) }
        }
    }
    @objc private func retry() { audio.retry(); monitor.restart(); updatePlayback() }

    private func dockHeight(_ screen: NSScreen) -> Double {
        let bottom = Double(screen.visibleFrame.minY-screen.frame.minY)
        let tile = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["tilesize"] as? Double ?? 64
        return bottom > 0 ? bottom : max(24,tile)+26
    }
    @objc private func changeSensitivity(_ sender: NSMenuItem) {
        renderer?.sensitivity = [Float(1), 1.45, 2][sender.tag]
        UserDefaults.standard.set(sender.tag, forKey: "visualizerSensitivity")
        for item in sensitivityItems { item.state = item.tag == sender.tag ? .on : .off }
    }
    private func record(_ features: AudioFeatures) {
        guard let trace else { return }
        let values: [String: Any] = ["time": ProcessInfo.processInfo.systemUptime, "rms": features.rms,
                                   "bass": features.bass, "mids": features.mids, "treble": features.treble,
                                   "onset": features.onset, "bands": features.bands]
        if let json = try? JSONSerialization.data(withJSONObject: values) {
            traceQueue.async { try? trace.write(contentsOf: json + Data([10])) }
        }
    }

    private func writeDiagnostics() {
        guard let index = args.firstIndex(of: "--diagnostics"), args.count > index+1 else { return }
        let data: [String: Any] = [
            "frame": panel.map { NSStringFromRect($0.frame) } ?? "none",
            "menuBarHeight": max(NSStatusBar.system.thickness, panel?.screen?.safeAreaInsets.top ?? 0),
            "dockHeight": panel?.screen.map { dockHeight($0) } ?? 0,
            "heightInBackingPixels": (panel?.frame.height ?? 0)*(panel?.screen?.backingScaleFactor ?? 1),
            "windowLevel": panel?.level.rawValue ?? -1,
            "ignoresMouse": panel?.ignoresMouseEvents ?? false,
            "screen": panel?.screen?.localizedName ?? "none",
            "drawable": view.map { NSStringFromSize($0.drawableSize) } ?? "none",
            "paused": view?.isPaused ?? true,
            "fps": view?.preferredFramesPerSecond ?? 0,
            "frames": renderer?.frames ?? 0,
            "meanGPUms": (renderer?.totalGPUTime ?? 0) / Double(max(1, renderer?.frames ?? 0)) * 1000,
            "preview": renderer?.preview ?? false,
            "playing": snapshot.playing,
            "spectrumPeak": renderer?.features.bands.max() ?? 0,
            "rms": renderer?.features.rms ?? 0,
            "bass": renderer?.features.bass ?? 0,
            "onset": renderer?.features.onset ?? 0,
            "metadataError": snapshot.error ?? "",
            "artworkLoaded": lastArt != nil,
            "audio": audio.status
        ]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: URL(fileURLWithPath: args[index+1]), options: .atomic)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        diagnosticsTimer?.invalidate(); monitor.stop(); audio.stop(); view?.isPaused = true
        for (center, observer) in observers { center.removeObserver(observer) }
        panel?.close()
    }
}
