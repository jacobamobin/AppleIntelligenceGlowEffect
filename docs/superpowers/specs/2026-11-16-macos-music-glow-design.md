# macOS Music Glow

Build the requested Apple Intelligence style glow as a native, dependency-free macOS 14.2+ menu bar app. Retain the original platform snippets. This is a complete executable app, not another snippet.

## Behavior

- A click-through, nonactivating panel occupies only the bottom half-menu-bar height of the built-in, online, non-mirrored display. Glow runs straight to both horizontal edges without tapering. Never fall back to an external display, including clamshell mode. Reconcile display changes and sleep/wake. Use a floating level below the Dock and main menu.
- A single Metal full-screen triangle renders an analytic luminous edge and softly merging spectral plumes. A logical-resolution drawable avoids unnecessarily shading Retina pixels. 60 fps active, 30 fps Low Power Mode; stop drawing once faded out or screen unavailable.
- Read Music playback state and current artwork through Apple Events without launching Music or controlling playback. Extract a small harmonious, weighted palette from a 64x64 artwork sample, excluding near-black/white pixels. Use blue/ice/cyan when unavailable. Retry delayed artwork and discard stale responses.
- Blend palettes over 4 seconds, starting at the currently displayed color on interruption. Fade playback visibility in/out. No synthetic spectrum in live mode.
- A private, unmuted Core Audio process tap captures only Music. A bounded preallocated ring feeds Accelerate FFT analysis off the IO callback. Display 32 logarithmic bands with fast attack, slow release. Never record audio to disk or change output volume/device. Rebuild capture on process/device changes; destroy resources on pause/quit.
- Small menu: current track, capture status, toggle glow, retry permissions, visual preview, quit. Explicit permission descriptions for Apple Events and system audio. Missing/denied permissions remain visible and recoverable.

## Approaches

The existing SwiftUI blur stack is portable but redraws much more area and is not a native overlay host. A full-screen Metal layer avoids SwiftUI blur work but still shades unused pixels. The selected implementation is the requested Metal route in a shallow AppKit panel, using public Core Audio taps rather than microphone or whole-system capture.

## Validation and boundaries

Test palette extraction on chromatic/neutral/transparent fixtures, continuous transition retargeting, FFT silence/tone separation, and display eligibility. Build a signed local .app and exercise Metal rendering with deterministic preview and an offscreen image. Check real display/window geometry and measure CPU/GPU timing. Real Music authorization, protected-stream audio availability, full-screen Spaces behavior, and audible crossfade are separate live acceptance checks; do not claim them from preview. macOS exposes current-track artwork, not both crossfade tracks, so transition starts when metadata changes.

Implementation choices: half-menu-bar strip height (user correction; measured 16 points on this Mac), 4-second palette transition, 60/30 fps, 32 bands. Keep local build and source reviewable; do not publish or enable login startup.
