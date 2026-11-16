#!/usr/bin/env bash
# Create a Casper account key (ed25519) with nothing but openssl.
# Usage: new-key.sh <secret-key-path>      e.g. new-key.sh keys/testnet_secret_key.pem
# Writes the secret key (mode 600) and prints the public key - the account's address - to stdout.
# Refuses to overwrite an existing file: a lost secret key is a lost account.
set -euo pipefail

KEY_PATH="${1:?Usage: new-key.sh <secret-key-path>}"
if [ -e "$KEY_PATH" ]; then
  echo "Error: $KEY_PATH already exists; not overwriting a secret key." >&2
  exit 1
fi
command -v openssl >/dev/null || { echo "Error: openssl is not installed." >&2; exit 1; }

mkdir -p "$(dirname "$KEY_PATH")"
(umask 077 && openssl genpkey -algorithm ed25519 -out "$KEY_PATH")
"$(dirname "$0")/public-key.sh" "$KEY_PATH"
