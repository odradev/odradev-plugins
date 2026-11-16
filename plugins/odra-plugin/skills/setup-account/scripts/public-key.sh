#!/usr/bin/env bash
# Print the public key (hex, as wallets and explorers show it) of a Casper secret key file.
# Usage: public-key.sh <secret-key-path>
# ed25519 keys only (the kind new-key.sh and Casper Wallet create by default): `01` + 32 bytes.
set -euo pipefail

KEY_PATH="${1:?Usage: public-key.sh <secret-key-path>}"
[ -f "$KEY_PATH" ] || { echo "Error: $KEY_PATH not found." >&2; exit 1; }

DER_HEX=$(openssl pkey -in "$KEY_PATH" -pubout -outform DER 2>/dev/null | od -An -v -tx1 | tr -d ' \n')
# An ed25519 SubjectPublicKeyInfo is a fixed 12-byte header followed by the 32-byte key.
if [ "${#DER_HEX}" -ne 88 ] || [ "${DER_HEX:0:24}" != "302a300506032b6570032100" ]; then
  echo "Error: $KEY_PATH is not an ed25519 key. For a secp256k1 key use: casper-client account-address / the wallet." >&2
  exit 1
fi
echo "01${DER_HEX:24}"
