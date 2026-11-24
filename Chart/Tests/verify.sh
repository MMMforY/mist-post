#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
stage=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-chart.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp Chart/Tests/RenderChecks.swift.in "$stage/RenderChecks.swift"
xcrun swiftc -swift-version 5 -O -whole-module-optimization \
    Engine/*.swift Chart/*.swift "$stage/RenderChecks.swift" -o "$stage/check"
"$stage/check"
