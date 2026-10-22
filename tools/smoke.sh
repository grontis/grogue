#!/usr/bin/env bash
# tools/smoke.sh -- compile every file gRogue.toc loads, then run tools/smoke.lua against
# the stub. Needs luajit (WoW's Lua is 5.1). Exit status is the test's.
set -euo pipefail
cd "$(dirname "$0")/.."

# The TOC's file lines, without the CR this repo's checkouts leave on them.
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    luajit -bl "$line" > /dev/null
done < gRogue.toc
echo "PASS every file in gRogue.toc compiles"

luajit tools/smoke.lua .
