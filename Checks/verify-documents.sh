#!/bin/bash
set -euo pipefail
source_app=${1:?supply the path to the built macOS application}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-documents.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
app="$fixture/MistPostDocumentCheck.app"
ditto "$source_app" "$app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier studio.mistpost.document-check' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDocumentTypes:0:LSHandlerRank Alternate' "$app/Contents/Info.plist"
codesign --force --sign - "$app"
cd "$(dirname "$0")"
xcrun swiftc -swift-version 5 -parse-as-library LaunchServices/OpenDocuments.swift -o "$fixture/probe"
"$fixture/probe" "$app" ../Resources/TideBridge.mistchart "$fixture"
