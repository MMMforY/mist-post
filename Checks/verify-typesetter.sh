#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-type.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cat > "$stage/main.swift" <<'SWIFT'
TypesetterCheck.run()
SWIFT
xcrun swiftc -swift-version 5 -O App/PrintShop.swift App/StationTypesetter.swift \
    Checks/TypesetterCheck.swift "$stage/main.swift" -o "$stage/check"
"$stage/check"
