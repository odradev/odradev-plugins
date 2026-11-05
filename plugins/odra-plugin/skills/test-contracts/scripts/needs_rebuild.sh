#!/usr/bin/env bash
# Checks if contract source code has changed since the last wasm build.
# Exit 0 = rebuild needed, Exit 1 = no rebuild needed.
#
# The project root is the nearest directory (from the working directory upwards) with Odra.toml;
# the wasm directory is <root>/wasm (one directory for the whole project, also in a workspace).
# Sources are every *.rs, Odra.toml and Cargo.toml under the root, excluding target/ and wasm/.

set -euo pipefail

PROJECT_ROOT="$PWD"
while [ ! -f "$PROJECT_ROOT/Odra.toml" ]; do
  if [ "$PROJECT_ROOT" = "/" ]; then
    echo "rebuild needed: no Odra.toml found in $PWD or any parent directory"
    exit 0
  fi
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
cd "$PROJECT_ROOT"

WASM_DIR="wasm"

if [ ! -d "$WASM_DIR" ]; then
  echo "rebuild needed: $PROJECT_ROOT/$WASM_DIR does not exist"
  exit 0
fi

latest_wasm=$(find "$WASM_DIR" -type f -name '*.wasm' -printf '%T@\n' 2>/dev/null | sort -rn | head -1)

if [ -z "$latest_wasm" ]; then
  echo "rebuild needed: wasm directory is empty"
  exit 0
fi

latest_src=$(find . \( -path ./target -o -path "./$WASM_DIR" -o -path ./.git \) -prune -o \
  -type f \( -name '*.rs' -o -name 'Odra.toml' -o -name 'Cargo.toml' \) -printf '%T@\n' 2>/dev/null \
  | sort -rn | head -1)

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
