#!/bin/bash
set -euo pipefail
app=${1:?supply the built 雾信航局.app path}
output=${2:?supply the destination .dmg path}
test -d "$app/Contents/MacOS"
codesign --verify --deep --strict "$app"
stage=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-image.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/disk"
ditto "$app" "$stage/disk/雾信航局.app"
ln -s /Applications "$stage/disk/Applications"
hdiutil create -quiet -fs HFS+ -format UDZO -volname "雾信航局" -srcfolder "$stage/disk" "$stage/MistPost.dmg"
hdiutil verify -quiet "$stage/MistPost.dmg"
mv "$stage/MistPost.dmg" "$output"
