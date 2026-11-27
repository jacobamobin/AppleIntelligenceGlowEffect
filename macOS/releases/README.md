# Music Glow 1.0.0

[Download for Apple Silicon](Music-Glow-1.0.0-macOS-arm64.zip) · [Install guide](../README.md) · [Checksum](Music-Glow-1.0.0-macOS-arm64.zip.sha256)

A native menu bar visualizer for Apple Music. Album artwork colors a soft glow along the bottom of the built-in MacBook display; Music-only audio analysis moves it in real time.

- macOS 14.2+, Metal, built-in unmirrored display.
- This prebuilt package is arm64 / Apple Silicon. Intel execution is untested.
- Ad-hoc signed; not Developer ID signed or notarized. First-launch help is in the install guide and the archive's `INSTALL.txt`.
- Includes `Music Glow.app`, installation notes, and the project MIT license. Third-party license and provenance are inside the app bundle.
- Rebuild with `cd macOS && ./package-release.sh`. A local rebuild is not expected to produce a byte-identical ZIP.

Verify the downloaded ZIP and checksum file in the same directory:

```sh
shasum -a 256 -c Music-Glow-1.0.0-macOS-arm64.zip.sha256
```
