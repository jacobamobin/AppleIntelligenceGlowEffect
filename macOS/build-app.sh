#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="$PWD/dist/Music Glow.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/MusicGlow" "$app/Contents/MacOS/MusicGlow"
cp Info.plist "$app/Contents/Info.plist"
cp ../LICENSE "$app/Contents/Resources/LICENSE"
mkdir -p "$app/Contents/Resources/ThirdParty/Nowsee"
cp ThirdParty/Nowsee/LICENSE ThirdParty/Nowsee/README.md "$app/Contents/Resources/ThirdParty/Nowsee/"
# Precompile once; no runtime shader compilation in the packaged app.
xcrun -sdk macosx metal -mmacosx-version-min=14.2 -O2 -c Sources/MusicGlow/Glow.metal -o "$PWD/.build/Glow.air"
xcrun -sdk macosx metallib "$PWD/.build/Glow.air" -o "$app/Contents/Resources/default.metallib"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --entitlements MusicGlow.entitlements "$app"
codesign --verify --strict "$app"
printf '\nBuilt: %s\n' "$app"
