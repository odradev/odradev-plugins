#!/usr/bin/env bash
# Checks if contract source code has changed since the last wasm build.
# Exit 0 = rebuild needed, Exit 1 = no rebuild needed.

set -euo pipefail

WASM_DIR="wasm"

if [ ! -d "$WASM_DIR" ]; then
  echo "rebuild needed: wasm directory does not exist"
  exit 0
fi

latest_wasm=$(find "$WASM_DIR" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1)

if [ -z "$latest_wasm" ]; then
  echo "rebuild needed: wasm directory is empty"
  exit 0
fi

latest_src=$(find src -name '*.rs' -printf '%T@\n' 2>/dev/null | sort -rn | head -1)

if [ -z "$latest_src" ]; then
  echo "no rebuild needed: no source files found"
  exit 1
fi

if awk "BEGIN { exit ($latest_src > $latest_wasm) ? 0 : 1 }"; then
  echo "rebuild needed: source is newer than wasm"
  exit 0
else
  echo "no rebuild needed: wasm is up to date"
  exit 1
fi
