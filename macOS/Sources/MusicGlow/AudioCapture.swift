import AppKit
import CoreAudio
import GlowCore

/// IO callback only copies Float32 samples into preallocated storage. It never waits for the FFT.
private final class AudioRing {
    let lock = NSLock()
    let capacity = 8192
    let storage = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    let rightStorage = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    var cursor = 0
    var total = 0
    var lastRead = 0
    init() { storage.initialize(repeating: 0, count: 8192); rightStorage.initialize(repeating: 0, count: 8192) }
    deinit {
        storage.deinitialize(count: 8192); storage.deallocate()
        rightStorage.deinitialize(count: 8192); rightStorage.deallocate()
    }

    func push(_ list: UnsafePointer<AudioBufferList>) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(1, Int(first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        let values = data.assumingMemoryBound(to: Float.self)
        let separateRight = buffers.count > 1 ? buffers[1] : first
        let rightValues = separateRight.mData?.assumingMemoryBound(to: Float.self)
        let rightChannels = max(1, Int(separateRight.mNumberChannels))
        let rightFrames = Int(separateRight.mDataByteSize) / MemoryLayout<Float>.size / rightChannels
        for frame in 0..<frames {
            let sample = values[frame * channels]
            let right: Float
            if channels > 1 { right = values[frame * channels + 1] }
            else if let rightValues, frame < rightFrames { right = rightValues[frame * rightChannels] }
            else { right = sample }
            storage[cursor] = sample.isFinite ? sample : 0
            rightStorage[cursor] = right.isFinite ? right : 0
            cursor = (cursor + 1) % capacity
        }
        total &+= frames
    }

    func latest() -> (left: [Float], right: [Float])? {
        lock.lock(); defer { lock.unlock() }
        guard total >= 2048, total != lastRead else { return nil }
        lastRead = total
        let start = (cursor - 2048 + capacity) % capacity
        return ((0..<2048).map { storage[(start + $0) % capacity] },
                (0..<2048).map { rightStorage[(start + $0) % capacity] })
    }
}

final class AudioCapture {
    var onFeatures: ((AudioFeatures) -> Void)?
    private(set) var status = "Audio idle"
    private let captureQueue = DispatchQueue(label: "MusicGlow.capture", qos: .userInitiated)
    // Only captureQueue touches the native session. All other state belongs to main.
    private var session: AudioTapSession?
    private var pid: pid_t = 0
    private var outputDevice: AudioObjectID = 0
    private var generation = 0
    private var pending = false
    private var lastFailure: Date?
    private var lastAttempt = Date.distantPast
    private var lastBuffer = Date.distantPast
    private(set) var active = false

    func reconcile(playing: Bool) {
        guard playing, let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            if pid != 0 || pending || active { stop() }
            status = "Audio idle"; return
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var currentOutput: AudioObjectID = 0, size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &currentOutput)
        let changed = pid != app.processIdentifier || outputDevice != currentOutput
        if !changed && pending { return }
        if !changed && active && (Date().timeIntervalSince(lastBuffer) < 3 || Date().timeIntervalSince(lastAttempt) < 8) { return }
        guard CaptureRecovery.shouldStart(targetChanged: changed, secondsSinceFailure: lastFailure.map { Date().timeIntervalSince($0) }) else { return }
        stop()
        pid = app.processIdentifier; outputDevice = currentOutput; pending = true
        lastAttempt = Date(); lastBuffer = Date()
        status = "Connecting Music audio…"
        let token = generation, targetPID = pid
        captureQueue.async { [self] in
            let next = AudioTapSession()
            session = next
            do {
                try next.start(pid: targetPID) { [weak self] features, message, fresh in
                    DispatchQueue.main.async {
                        guard let self, token == self.generation else { return }
                        if fresh { self.lastBuffer = Date() }
                        self.status = message; self.onFeatures?(features)
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
                    self.pending = false; self.active = true
                }
            } catch {
                next.stop(); session = nil
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation else { return }
                    self.pending = false; self.active = false; self.lastFailure = Date()
                    self.status = "Audio unavailable: \(message)"
                }
            }
        }
    }

    func retry() { stop() }
    func stop() {
        generation += 1; pid = 0; outputDevice = 0; pending = false; active = false; lastFailure = nil
        status = "Audio idle"
        onFeatures?(.silence)
        captureQueue.async { [self] in session?.stop(); session = nil }
    }
}

/// Native resource lifetime is serialized off the UI thread, including permission/start waits.
private final class AudioTapSession {
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var ring: AudioRing?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "MusicGlow.fft", qos: .userInitiated)

    func start(pid: pid_t, deliver: @escaping (AudioFeatures, String, Bool) -> Void) throws {
        var processID: AudioObjectID = 0, processPID = pid
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &processPID, &size, &processID))
        guard processID != 0 else { throw CaptureError.message("Music has no audio process yet") }
        let description = CATapDescription(stereoMixdownOfProcesses: [processID])
        description.name = "MusicGlow Music spectrum"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap))

        var format = AudioStreamBasicDescription()
        address.mSelector = kAudioTapPropertyFormat
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
            throw CaptureError.message("Unsupported tap format")
        }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MusicGlow private analysis",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            // Do not wait for the source's first audio: buffering/silence must stay nonblocking.
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
        ]
        try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &device))
        let buffer = AudioRing(); ring = buffer
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { _, input, _, _, _ in buffer.push(input) })
        try check(AudioDeviceStart(device, ioProc))
        let analyzer = AudioFeatureAnalyzer(), sampleRate = format.mSampleRate
        let clock = DispatchSource.makeTimerSource(queue: queue)
        clock.schedule(deadline: .now(), repeating: 1.0 / 60, leeway: .milliseconds(1))
        var lastSignal = Date()
        var lastFrame = AudioFeatures.silence
        var lastSampleTime = ProcessInfo.processInfo.systemUptime
        clock.setEventHandler {
            let now = ProcessInfo.processInfo.systemUptime
            let samples = buffer.latest()
            if let samples {
                lastFrame = analyzer.analyze(left: samples.left, right: samples.right, sampleRate: sampleRate, elapsed: Float(now-lastSampleTime))
                lastSampleTime = now
            } else if now-lastSampleTime > 0.10 { lastFrame = .silence }
            let hasSignal = lastFrame.rms > 0.00001
            if hasSignal { lastSignal = Date() }
            let quiet = Date().timeIntervalSince(lastSignal) > 6
            deliver(lastFrame, quiet ? "No audio signal · check Audio Recording permission" : "Music audio tap connected", samples != nil)
        }
        timer = clock; clock.resume()
    }

    func stop() {
        timer?.cancel(); timer = nil
        if device != 0 {
            if let ioProc { AudioDeviceStop(device, ioProc); AudioDeviceDestroyIOProcID(device, ioProc) }
            AudioHardwareDestroyAggregateDevice(device)
        }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        ioProc = nil; device = 0; tap = 0; ring = nil
    }
    private func check(_ code: OSStatus) throws {
        if code != noErr { throw CaptureError.message("Core Audio \(code); check Audio Recording permission") }
    }
    deinit { stop() }
}

private enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
