#!/bin/sh
set -eu
model=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-workshop.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
cp "$model/Tests/Verification.swift.in" "$scratch/main.swift"
swiftc -O -whole-module-optimization "$model"/../Engine/*.swift "$model"/*.swift "$scratch/main.swift" -o "$scratch/workshop-check"
"$scratch/workshop-check" "$model/Tests/Fixtures/tide-bridge.mistchart"
