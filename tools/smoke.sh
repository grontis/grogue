#!/usr/bin/env bash
# tools/smoke.sh -- compile every file gRogue.toc loads, lint the kit's copies in Kit/ with
# gkit's tools/kit-lint.lua, then run tools/smoke.lua against the stub. Needs luajit (WoW's Lua
# is 5.1) and the gkit checkout beside this one. Exit status is the first failing step's.
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

# Kit/ holds gkit's runtime as synced (Kit/MANIFEST.lock): gkit's tools/kit-lint.lua fails on a
# copy edited here and checks gRogue.toc loads the copies in order. gkit is the checkout beside
# this one (forever-addons/gkit), found from here or from a worktree under
# forever-addons/_worktrees; GKIT names another.
gkit="${GKIT:-}"
if [[ -z "$gkit" ]]; then
    for dir in .. ../.. ../../..; do
        if [[ -f "$dir/gkit/tools/kit-lint.lua" ]]; then
            gkit="$dir/gkit"
            break
        fi
    done
fi
if [[ -z "$gkit" ]]; then
    echo "FAIL kit-lint: no gkit checkout beside this one (set GKIT to its folder)"
    exit 1
fi
luajit "$gkit/tools/kit-lint.lua" . --toc gRogue.toc

luajit tools/smoke.lua .
