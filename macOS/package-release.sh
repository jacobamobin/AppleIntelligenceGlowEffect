#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
architecture=$(uname -m)
name="Music-Glow-${version}-macOS-${architecture}"
staging=$(mktemp -d "${TMPDIR:-/tmp/}music-glow.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/$name"
ditto "dist/Music Glow.app" "$staging/$name/Music Glow.app"
cp INSTALL.txt ../LICENSE "$staging/$name/"
ditto -c -k --sequesterRsrc --keepParent "$staging/$name" "dist/$name.zip"
(cd dist && shasum -a 256 "$name.zip" > "$name.zip.sha256")
printf '\nRelease: %s/dist/%s.zip\n' "$PWD" "$name"
