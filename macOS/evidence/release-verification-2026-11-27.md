# Release packaging verification — 2026-11-27

- Imported the existing local Music Glow source into the prepared main branch without changing runtime capture, playback, or renderer code.
- `swift test --package-path macOS`: 29 tests, zero failures, including actual Metal render tests on this development Mac.
- `./package-release.sh`: release build and precompiled Metal library succeeded. The generated arm64 ZIP contains the app, installation notes, and project license; the app contains Nowsee's MIT license and provenance.
- Packaged executable `--check-scripts`: Music AppleScripts compile successfully.
- Extracted the release ZIP with `ditto`; `codesign --verify --strict` passes on the extracted app. `file` reports arm64. SHA-256 verification passes.
- The published binary is ad-hoc signed, not notarized. Fresh downloaded/quarantined first launch, Intel execution, and other Macs remain untested.
- Captured a live app-panel screenshot and generated a six-second illustration with the actual Metal shader and generated input. The illustration is labeled accordingly.
- Attribution repair changed author/committer metadata for three previously Claude-authored commits to the human PR submitter, and removed the Claude co-author trailers. The complete tree before adding Music Glow was identical to the original main tree. Original history is retained in a local rollback bundle.

Remote publication is a separate step requiring valid GitHub authentication. This file records local verification, not a claim of successful publication.
