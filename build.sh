#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-release}
case "$mode" in
    release|universal|qa) ;;
    *) echo "usage: ./build.sh [release|universal|qa] [destination]" >&2; exit 2 ;;
esac
target_dir=${2:-build}
mkdir -p "$target_dir"
target_dir=$(cd "$target_dir" && pwd)
sources=(App/*.swift Audio/*.swift Chart/*.swift Engine/*.swift WorkshopModel/*.swift)
if [[ "$mode" == "qa" ]]; then
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -D MIST_POST_QA "${sources[@]}" Checks/*.swift -o "$target_dir/MistPostQA"
    exit 0
fi
app="$target_dir/雾信航局.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "$mode" == "universal" ]]; then
    stage=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-build.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    for arch in arm64 x86_64; do
        xcrun swiftc -swift-version 5 -O -whole-module-optimization -target "$arch-apple-macos13.0" "${sources[@]}" -o "$stage/$arch"
    done
    xcrun lipo -create "$stage/arm64" "$stage/x86_64" -output "$app/Contents/MacOS/MistPost"
else
    xcrun swiftc -swift-version 5 -O -whole-module-optimization -target "$(uname -m)-apple-macos13.0" "${sources[@]}" -o "$app/Contents/MacOS/MistPost"
fi
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/. "$app/Contents/Resources/"
codesign --force --sign - "$app"
echo "$app"
