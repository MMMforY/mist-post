#!/bin/sh
set -eu
engine=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-engine.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

for source in "$engine"/Tests/*.swift.in; do
    name=$(basename "$source" .in)
    if [ "$name" = Verification.swift ]; then name=main.swift; fi
    cp "$source" "$scratch/$name"
done

long_run=false
for option do
    if [ "$option" = --long-charts ]; then long_run=true; fi
done
run() {
    if [ "$long_run" = true ]; then
        nice -n 10 "$@"
    else
        "$@"
    fi
}
run swiftc -O -whole-module-optimization "$engine"/*.swift "$scratch"/*.swift -o "$scratch/verify"
run "$scratch/verify" "$@"
