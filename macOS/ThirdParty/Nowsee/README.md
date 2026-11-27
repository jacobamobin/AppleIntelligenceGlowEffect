# Nowsee attribution

Source: [Sergio-prog/Nowsee](https://github.com/Sergio-prog/Nowsee)

Pinned revision: `9b38bb3b5a55a5a0dddc862e1ee9cbc18721d8b2`

Copyright (c) 2026 Sergey (Sergio-prog). Used under the MIT License in [LICENSE](LICENSE).

- `Sources/NowseeCore/LogFrequencyMap.swift` is reproduced in `Sources/GlowCore/LogFrequencyMap.swift`, with an attribution header. Music Glow configures it for 64 rows, 40 Hz–16 kHz, rather than Nowsee's default 256 rows.
- Catmull-Rom `curveSample` interpolation from `Sources/Nowsee/SpectrogramRenderer.swift` is adapted in `Sources/MusicGlow/Glow.metal`. Texture lookups became packed uniform-array reads; the result is spatially smoothed and composed with artwork colors, spectral haze, continuous edge diffusion and PCM deformation in a short bottom-edge panel with taller outer wings.
- Frame-independent attack/release and peak-decay expressions from `Sources/NowseeCore/StereoSpectrumAnalyzer.swift` inform `Sources/GlowCore/GlowMotion.swift` and `Sources/MusicGlow/GlowRenderer.swift`, with Music Glow's own response times and buffers.

Music Glow's Music metadata helper, process tap, artwork palette, transient/RMS/PCM analysis, display policy, color drift, and AppKit panel remain local implementations. No code from unlicensed visualizer references was copied. The full license and this attribution are included in the packaged app's Resources/ThirdParty/Nowsee directory.
