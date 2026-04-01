#!/usr/bin/env bash
# Check if the NCTL Docker container is running.
# Exits 0 if running, 1 if not.

set -euo pipefail

if docker ps --filter name=mynctl --format '{{.Names}}' | grep -q mynctl; then
  echo "NCTL container is running." >&2
  exit 0
else
  echo "Error: NCTL container is not running. Start it first with /start-nctl." >&2
  exit 1
fi
