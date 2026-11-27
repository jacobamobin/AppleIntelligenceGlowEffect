# Music Glow release packaging

Goal: publish the existing Music Glow app with an Apple Silicon download, screenshots, animated native-renderer preview, and useful setup instructions. Keep all existing platform examples and human contribution credit. No AI author or co-author identity in new commits.

- Import the existing macOS sources and tests without changing playback/capture behavior.
- Verify the release build, unit/GPU tests, AppleScript compilation, and ad-hoc signature.
- Package a versioned ZIP with installation notes and licenses, plus SHA-256 checksums and a repeatable packaging script. Label architecture and notarization accurately.
- Add README download/setup section and a dedicated macOS guide. Include an actual app screenshot and a labeled native Metal animation driven by generated input.
- Verify links, archive contents, extracted signature, unchanged pre-existing source trees, and clean commit metadata.
- Publish main using an exact force-with-lease for the attribution repair, then create the tagged binary release. Read back the published commit and assets. GitHub sign-in must be refreshed first.
