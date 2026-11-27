# Music Glow Revision Plan

**Goal:** Continuous Apple Intelligence glow driven by real Music, with diffuse edges, low usual height, taller transient blooms and subtle cursor response.
**Spec:** ../specs/2026-11-16-dock-spectrum-revision.md
**Architecture:** Preserve AppKit, metadata helper and private process tap. Add 64-band audio features, smoothed visual envelopes, adaptive bass normalization and one Metal pass.

1. [x] Add meaningful regression tests and 64-band features using licensed Nowsee frequency mapping.
2. [x] Replace hard bars/borders with continuous Gaussian diffusion and flowing artwork color fields; add bounded cursor influence.
3. [x] Reserve full-Dock headroom, tune usual glow toward 30%, feather 90–100%, smooth all audio-driven changes, and normalize sustained bass.
4. [x] Finish source review and native verification, save current evidence, commit locally and leave the app running.

Review focus: native resource lifetime, sleep/preview races, stereo/freshness, normalized dynamics, 56-vector Swift/Metal layout, click-through cursor polling, transparent window boundaries and measured performance limits.
