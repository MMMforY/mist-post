#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-audio.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
xcrun swiftc -O -swift-version 6 -D MISTPOST_AUDIO_OFFLINE_TEST "$here/HarborAudio.swift" "$here/HarborScore.swift" "$here/Checks/AudioCheck.swift" "$here/Checks/AudioSoak.swift" -o "$build_dir/check"
"$build_dir/check" "$@"
