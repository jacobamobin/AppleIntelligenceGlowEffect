import XCTest
@testable import GlowCore

final class GlowCoreTests: XCTestCase {
    func testStereoSpectrumKeepsRightOnlyAndOppositePhaseAudio() {
        let analyzer = SpectrumAnalyzer()
        let tone = (0..<2048).map { 0.5 * sin(2 * Float.pi * 1000 * Float($0) / 48000) }
        let silence = [Float](repeating: 0, count: 2048)
        let rightOnly = analyzer.analyzeStereo(left: silence, right: tone, sampleRate: 48000)
        let oppositePhase = analyzer.analyzeStereo(left: tone, right: tone.map { -$0 }, sampleRate: 48000)
        XCTAssertGreaterThan(rightOnly.max() ?? 0, 0.5)
        XCTAssertEqual(rightOnly, oppositePhase)
    }
    func testPersistentHelperResponseDoesNotWaitForPipeEOF() throws {
        let pipe = Pipe()
        let reader = PipeLineReader(pipe.fileHandleForReading)
        let response = Data("{\"playing\":true}\n".utf8)
        let arrived = expectation(description: "small reply arrives while helper stays running")
        DispatchQueue.global().async {
            XCTAssertEqual(try? reader.next(), response)
            arrived.fulfill()
        }
        try pipe.fileHandleForWriting.write(contentsOf: response)
        wait(for: [arrived], timeout: 1)
        try pipe.fileHandleForWriting.close()
    }
    func testPlaybackNotificationInvalidatesAnOlderMetadataResponse() {
        var revision = MetadataRevision()
        let old = revision.current
        revision.invalidate()
        XCTAssertFalse(revision.accepts(old))
        XCTAssertTrue(revision.accepts(revision.current))
    }
    func testCaptureRetryDelaysOnlyFailuresAndNotResumeOrRouteChanges() {
        XCTAssertTrue(CaptureRecovery.shouldStart(targetChanged: true, secondsSinceFailure: 0))
        XCTAssertTrue(CaptureRecovery.shouldStart(targetChanged: false, secondsSinceFailure: nil))
        XCTAssertFalse(CaptureRecovery.shouldStart(targetChanged: false, secondsSinceFailure: 2))
        XCTAssertTrue(CaptureRecovery.shouldStart(targetChanged: false, secondsSinceFailure: 8))
    }
    func testGlowCeilingTracksTheBottomDock() {
        XCTAssertEqual(GlowGeometry.stripHeight(dockHeight: 87, tileSize: 61), 87)
        XCTAssertEqual(GlowGeometry.stripHeight(dockHeight: 100, tileSize: 64), 100)
        XCTAssertEqual(GlowGeometry.stripHeight(dockHeight: 0, tileSize: 61), 87)
    }
    func testPaletteIgnoresTransparentAndNeutralPixels() {
        let rgba: [UInt8] = [255,0,0,255, 240,20,10,255, 0,0,0,255, 255,255,255,255, 0,255,0,0]
        let palette = GlowPalette.extract(rgba: rgba)
        XCTAssertGreaterThan(palette.colors[0].x, palette.colors[0].z)
        XCTAssertEqual(GlowPalette.extract(rgba: [0,0,0,255]), .fallback)
        XCTAssertEqual(GlowPalette.extract(rgba: []), .fallback)
        XCTAssertEqual(GlowPalette.extract(rgba: [1,2]), .fallback)
    }

    func testTransitionRetargetsFromVisiblePalette() {
        let red = GlowPalette(colors: Array(repeating: SIMD3<Float>(1,0,0), count: 4))
        let green = GlowPalette(colors: Array(repeating: SIMD3<Float>(0,1,0), count: 4))
        var transition = PaletteTransition(initial: .fallback, duration: 4)
        transition.set(red, at: 0)
        let middle = transition.value(at: 2)
        XCTAssertNotEqual(middle, red)
        transition.set(green, at: 2)
        XCTAssertEqual(transition.value(at: 2), middle)
        XCTAssertEqual(transition.value(at: 6), green)
    }

    func testFFTSeparatesBassAndTrebleAndSilence() {
        let analyzer = SpectrumAnalyzer()
        let silence = analyzer.analyze(samples: Array(repeating: 0, count: 2048), sampleRate: 48000)
        XCTAssertEqual(silence.max(), 0)
        func tone(_ frequency: Float) -> [Float] {
            (0..<2048).map { 0.5 * sin(2 * .pi * frequency * Float($0) / 48000) }
        }
        let bass = analyzer.analyze(samples: tone(100), sampleRate: 48000)
        let treble = analyzer.analyze(samples: tone(6000), sampleRate: 48000)
        let bassPeak = bass.indices.max(by: { bass[$0] < bass[$1] })!
        let treblePeak = treble.indices.max(by: { treble[$0] < treble[$1] })!
        XCTAssertLessThan(bassPeak, 16)
        XCTAssertGreaterThan(treblePeak, 46)
        XCTAssertTrue(bass.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    func testDisplayNeverFallsBackToExternalOrMirrored() {
        XCTAssertFalse(DisplayPolicy.eligible(builtIn: false, online: true, mirrored: false))
        XCTAssertFalse(DisplayPolicy.eligible(builtIn: true, online: false, mirrored: false))
        XCTAssertFalse(DisplayPolicy.eligible(builtIn: true, online: true, mirrored: true))
        XCTAssertTrue(DisplayPolicy.eligible(builtIn: true, online: true, mirrored: false))
    }
}
