# macOS Music Glow Implementation Plan

> Execute inline with superpowers:executing-plans. Keep a task ledger below.

**Goal:** Deliver a working native bottom-edge Music glow on the built-in screen.

**Architecture:** AppKit hosts a shallow transparent Metal view. Music metadata, palette extraction, and per-process audio analysis feed its small uniform buffer; render state transitions are continuous.

**Tech Stack:** SwiftPM, AppKit, MetalKit, Core Audio, Accelerate, Apple Events.

**Spec:** ../specs/2026-11-16-macos-music-glow-design.md

## Global Constraints

macOS 14.2+, no third-party dependencies, no external-display fallback, no audio recording or playback mutation, blue/cyan loading palette, preserve existing snippets.

## Review Focus

- Music exits or changes process/output: tear down and retry without leaking taps.
- Artwork appears late or changes during a transition: retry and retarget without jumping.
- Pause, sleep, display removal: fade/stop GPU and audio work.
- Silence and denied permissions: never present synthetic audio as a real spectrum.
- Transparent artwork and colorless artwork: avoid black/white or invalid palettes.

## Tasks

1. [x] Add SwiftPM core and behavior tests first. Observe missing-feature failure, implement `GlowPalette`, `PaletteTransition`, `SpectrumAnalyzer`, `DisplayPolicy`; run `swift test`.
2. [x] Implement Music snapshot helper and monitored metadata service, private Core Audio tap and bounded sample ring. Build and verify error paths.
3. [x] Add Metal shader, renderer, display-aware panel, lifecycle, menu controls, permission descriptions and packaging script. Build `.app`; render deterministic preview and offscreen shader artifact.
4. [x] Run suite and release build, inspect images and live geometry, measure performance, self-review lifecycle and integration. Document exact verification boundaries and deliver launchable local app.

## Ledger

- Fresh dedicated clone at original HEAD `5f388f1`; branch `codex/macos-music-glow`. No existing package/test harness. Work in this isolated clone.
- Native implementation selected from user's request for macOS/Metal performance. Bottom means physical bottom edge, underneath Dock/menu window levels.
- User correction: no side taper; exactly half the actual menu bar height. Implemented using the larger of status bar thickness and built-in safe area top, divided by two. Verified 16 pt on this Mac.
- Core tests observed missing-feature RED then GREEN; persistent-pipe regression observed actual 1-second timeout RED then passed after replacing fill-length reads with available-data framing.
- Independent read-only review identified synchronous tap start, success-throttled resume, stale metadata, and preview expiry during sleep. Fixed with queued native tap lifecycle, failure-only backoff, metadata revisions, and suspension-aware expiry. Also fixed optional metadata properties and stereo cancellation/panning.
- Native preview and actual artwork-colored live app observed through CUA. Final screenshots show the thin strip reaching both edges.
- Final validation: 9/9 tests, release build, signature/plist checks, script compilation, native PNG alpha assertions, and live nonzero stereo spectrum with artwork. Final app running from macOS/dist/Music Glow.app. See macOS/evidence/verification.md for exact performance samples and untested physical lifecycle boundaries. Keep this local feature branch; no remote integration requested.
