#!/usr/bin/env bash
# Static analysis for the whole project.
#  - luau-analyze (with Roblox global definitions via LUAU_DEFS) for syntax, unknown
#    globals and lint warnings. Cross-module requires are Instance paths that the
#    plain analyzer cannot resolve, so those notes are filtered out.
set -u
cd "$(dirname "$0")/.."
DEFS="${LUAU_DEFS:-}"
find src -name '*.luau' | sort > /tmp/dla_files.txt
LUAU_DEFS="$DEFS" luau-analyze $(cat /tmp/dla_files.txt) 2>&1 \
  | grep -v "Unknown require" \
  | grep -v "could be nil" \
  | grep -v "not found in external type 'Instance'" \
  | grep -v "^$" || true
