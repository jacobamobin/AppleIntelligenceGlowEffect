# Verification — 2026-11-19

Branch: `codex/macos-music-glow`.

The final visual direction is a continuous, translucent Apple Intelligence glow: no bars, stacked contours, hard bottom stripe, vertical side strokes or lateral fade. The panel reserves the full bottom Dock height so taller musical blooms have room; normal diffusion is tuned toward roughly 30%, and the final 90–100% fades completely. The 30% value is a visual tuning target, not a measured median for every song. A small smoothed cursor influence bends only a nearby part of the field.

## Current checks

- `swift test`: **29 tests passed**, zero failures. New RED→GREEN cases reproduced solid corner posts, opaque bottom strokes, the short top feather, missing cursor influence, abrupt visual input and sustained bass pegging.
- Actual Metal output is tested for edge continuation, translucency, vertical softness, top transparency at the 87-pixel render height, distinct spectrum/PCM responses and bounded local cursor deformation. The normal-body response checks focus below the empty peak headroom.
- Motion tests cover attack/release, frame-rate behavior, alternating PCM suppression and sustained-bass normalization. A four-second full-level bass input settles near 0.55 rather than 1 while higher-frequency bins remain unchanged.
- `./build-app.sh`: release executable and precompiled Metal library built; ad-hoc signature verified. The pinned Nowsee MIT license and attribution are included in the bundle. No signing certificate or permission switches were changed in this retry.
- `--check-scripts`: Music AppleScripts compile against the installed scripting dictionary.
- Final packaged `--render-preview`: 120 frames, **0.139 ms mean GPU command time/frame** on Apple M5 Pro. This is a static offline fixture, not a compositor or battery benchmark.
- Native CUA observed the running final glow with the enlarged transparent panel and soft lower diffusion. Earlier user screenshots established the firm-side and clipped-top defects; the matching shader regressions fail on the old implementation and pass now.
- [Live diagnostics](live-diagnostics.json): Music playing, artwork loaded, real tap connected, preview disabled; built-in Retina display; frame `{0,0,1728,87}`, drawable `1728×87`, 174 backing pixels high; 60 fps; level 3; clicks pass through. Final snapshot mean GPU command time: **0.516 ms/frame over 3,817 frames**.
- [Live audio summary](live-audio-features.json): 900 tap snapshots across 17.049 s, 896 frames with a band change greater than0.02. RMS spans 0–0.294, bass 0–1, and onset 0–1 before visual normalization. This proves changing capture input, not subjective audible synchronization.
- [CPU sample](cpu-sample.json) records a five-second sample of the final running app and metadata helper. Values are percentages of one core and resident MiB; they exclude WindowServer and do not predict battery life.

## Lifecycle and acceptance boundaries

Capture remains Music-only, private, unmuted and serialized off the UI thread. Stereo channels are analyzed before combining to prevent phase cancellation. Missing buffers retain features briefly, then become silence; visual filtering softens both transitions. Sleep/preview source review caught and fixed a delayed preview callback that could wake drawing while suspended. Cursor position is polled only while rendering, with no event tap or click interception.

Source review found no remaining Important issue in the final changes. Tests and native snapshots do not establish the user's subjective preference, a precise visual median for all music, or audible AutoMix synchronization. Cursor localization is GPU-tested and native polling is implemented, but automated desktop dragging was not performed. Lid/cable changes, every full-screen Space, denied/protected capture and every unusual metadata source remain manual checks. Color transitions begin when Music publishes current-track metadata. No playback controls, system audio device, login item, remote publication or external message was changed.
