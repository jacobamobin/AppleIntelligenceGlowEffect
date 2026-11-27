# Music glow revision

Final direction from the user, including November 19 refinements: preserve the original continuous Apple Intelligence glow, without bars, stacked contour lines, firm bottom strokes, or vertical side borders. Render a diffuse field extending beyond both lateral screen edges. The usual glow should sit around 30% of the bottom Dock height; allow occasional taller musical blooms, with a transparent ceiling at the full Dock height and a gentle 90–100% fade. Treat 30% as a visual tuning target, not an invariant measured median across all music.

Use genuine Music audio: 64 logarithmic bands, RMS, band energies, positive bass onset, peak decay and PCM. Smooth all changing inputs to prevent flicker. Normalize sustained bass slowly, preserving transients and avoiding a pegged left side. Audio clouds vary the left, middle and right. Artwork supplies the colors with blue/cyan fallback, a four-second track transition and subtle sideways color drift.

The cursor should add a subtle localized influence when hovering, dragging or moving near the glow. Poll position, without event interception or new input permissions; preserve click-through behavior. Honor Reduce Motion and pause all rendering/cursor sampling during sleep.

Keep the overlay on the built-in screen only, below Dock/menu windows, and suspend in clamshell or mirrored configurations. Preserve Music-only local capture and existing metadata handling. Reuse Nowsee frequency mapping/interpolation under MIT with pinned attribution and license in the bundle. Aurora and AppleIntelligenceForSwiftUI supply visual research; their code and binaries are not dependencies.

Validation: real shader tests for border absence, lateral continuation, translucency, top feathering, spectral/amplitude/PCM response, peak headroom and local cursor bounds; motion tests for attack/release, frame-rate behavior, PCM flicker suppression and sustained-bass normalization. Native captures and diagnostics verify running playback/artwork and panel configuration. Subjective appearance and audible synchronization remain user acceptance.
