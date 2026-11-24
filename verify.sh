#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
suite=$(mktemp -d "${TMPDIR:-/tmp}/mistpost-verify.XXXXXX")
trap 'rm -rf "$suite"' EXIT
Engine/Tests/verify.sh --optimal
WorkshopModel/Tests/verify.sh
Chart/Tests/verify.sh
Audio/Checks/check.sh
Checks/verify-typesetter.sh
./build.sh qa "$suite"
unset MIST_POST_SAVE
export MIST_POST_RESOURCES="$PWD/Resources"
"$suite/MistPostQA" --qa --store
"$suite/MistPostQA" --snapshot "$suite/screens"
"$suite/MistPostQA" --qa --accessibility
for phase in prepare reopen; do
    MIST_POST_SAVE="$suite/completed.json" "$suite/MistPostQA" --qa --finale-return "$phase" "$suite/album"
done
for case_number in 0 1 2 3; do
    export MIST_POST_SAVE="$suite/save-$case_number.json"
    "$suite/MistPostQA" --qa --cold-launch write "$case_number"
    "$suite/MistPostQA" --qa --cold-launch resume "$case_number"
done
echo "PASS all application and source checks"
