#!/usr/bin/env bash
# Runs odra contract tests.
# Usage: run_tests.sh [--rebuild]
#   --rebuild   Force rebuild of WASMs before running CasperVM tests.
#   No flag     Skip rebuild (use existing WASMs).

set -euo pipefail

REBUILD=false

for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [ "$REBUILD" = true ]; then
  echo "Running tests on CasperVM with rebuild..."
  cargo odra test -b casper
else
  echo "Running tests on CasperVM without rebuild..."
  cargo odra test -b casper -s
fi
