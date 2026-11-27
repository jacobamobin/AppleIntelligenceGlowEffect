import AppKit
import GlowCore

struct MusicSnapshot: Codable {
    var key = ""
    var title = ""
    var artist = ""
    var playing = false
    var rgba: Data?
    var error: String?
}

/// AppleScript runs only in this persistent child process; the UI never waits on Apple Events.
func runMusicWorker() {
    var cachedKey = ""
    var cachedArt: Data?
    let metadataScript = NSAppleScript(source: MusicScripts.metadata)!
    let artworkScript = NSAppleScript(source: MusicScripts.artwork)!
    while readLine() != nil {
        autoreleasepool {
            var snapshot = MusicSnapshot()
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
                cachedKey = ""; cachedArt = nil
                emit(snapshot); return
            }
            var error: NSDictionary?
            let result = metadataScript.executeAndReturnError(&error)
            if let error {
                let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                snapshot.error = number == -1743 ? "Allow Music access in Privacy & Security → Automation" : "Music unavailable (\(number))"
                emit(snapshot); return
            }
            snapshot.playing = result.atIndex(1)?.stringValue == "playing"
            snapshot.key = result.atIndex(2)?.stringValue ?? ""
            snapshot.title = result.atIndex(3)?.stringValue ?? ""
            snapshot.artist = result.atIndex(4)?.stringValue ?? ""
            if snapshot.key != cachedKey { cachedKey = snapshot.key; cachedArt = nil }
            if !snapshot.key.isEmpty && cachedArt == nil {
                // Recheck identity with the image so a fast skip cannot apply the previous track's art.
                let artwork = artworkScript.executeAndReturnError(nil)
                if artwork.atIndex(1)?.stringValue == snapshot.key,
                   let data = artwork.atIndex(2)?.data, let image = NSImage(data: data),
                   let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
                    pixels.withUnsafeMutableBytes { bytes in
                        if let context = CGContext(data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                                                   bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                            context.interpolationQuality = .medium
                            context.draw(cg, in: CGRect(x: 0, y: 0, width: 64, height: 64))
                        }
                    }
                    cachedArt = Data(pixels)
                }
            }
            snapshot.rgba = cachedArt
            emit(snapshot)
        }
    }
}

private func emit(_ snapshot: MusicSnapshot) {
    if let data = try? JSONEncoder().encode(snapshot) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

final class MusicMonitor {
    var onChange: ((MusicSnapshot) -> Void)?
    private var timer: Timer?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var busy = false
    private var generation = 0
    private var requestID = 0
    private var revision = MetadataRevision()
    private var pendingRefresh = false
    private let queue = DispatchQueue(label: "MusicGlow.metadata", qos: .utility)
    private var notification: NSObjectProtocol?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        notification = DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.revision.invalidate()
            if self.busy { self.pendingRefresh = true } else { self.poll() }
        }
        poll()
    }

    func poll() {
        guard !busy else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            onChange?(MusicSnapshot()); return
        }
        if process?.isRunning != true {
            let child = Process(), stdin = Pipe(), stdout = Pipe()
            child.executableURL = Bundle.main.executableURL
            child.arguments = ["--music-worker"]
            child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
            do { try child.run() } catch {
                onChange?(MusicSnapshot(error: "Could not start Music helper")); return
            }
            process = child; input = stdin; output = stdout
        }
        busy = true
        let token = generation
        requestID += 1
        let request = requestID
        let metadataVersion = revision.current
        guard let writer = input?.fileHandleForWriting, let reader = output?.fileHandleForReading else { busy = false; return }
        queue.async { [weak self] in
            var data = Data()
            do {
                try writer.write(contentsOf: Data([10]))
                data = try PipeLineReader(reader).next() ?? Data()
            } catch { }
            let result = (try? JSONDecoder().decode(MusicSnapshot.self, from: data)) ?? MusicSnapshot(error: "Music helper disconnected; retrying")
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.busy = false
                if !self.revision.accepts(metadataVersion) || self.pendingRefresh {
                    self.pendingRefresh = false; self.poll()
                } else { self.onChange?(result) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self, self.busy, self.generation == token, self.requestID == request else { return }
            self.restart()
            self.onChange?(MusicSnapshot(error: "Music access timed out; use Retry Music & Audio"))
        }
    }

    func restart() { stopWorker(); poll() }
    private func stopWorker() {
        generation += 1; busy = false; pendingRefresh = false
        try? input?.fileHandleForWriting.close()
        process?.terminate(); process = nil; input = nil; output = nil
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let notification { DistributedNotificationCenter.default().removeObserver(notification) }
        notification = nil; stopWorker()
    }
    deinit { stop() }
}
