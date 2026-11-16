#!/usr/bin/env bash
# Print the account hash (account-hash-...) of a Casper account: the form contracts and the
# Odra CLI use for an account address.
# Usage: account-hash.sh <public-key-hex | secret-key-path>
set -euo pipefail

WHO="${1:?Usage: account-hash.sh <public-key-hex | secret-key-path>}"
if [ -f "$WHO" ]; then
  WHO=$("$(dirname "$0")/public-key.sh" "$WHO")
fi
command -v python3 >/dev/null || { echo "Error: python3 is needed to compute an account hash." >&2; exit 1; }
python3 - "$WHO" <<'PY'
import hashlib, sys
key = sys.argv[1].lower()
algorithms = {"01": ("ed25519", 32), "02": ("secp256k1", 33)}
if key[:2] not in algorithms or len(key) != 2 + 2 * algorithms[key[:2]][1]:
    sys.exit("Error: not a Casper public key (expected 01 + 64 hex digits or 02 + 66 hex digits).")
name, _ = algorithms[key[:2]]
digest = hashlib.blake2b(name.encode() + b"\x00" + bytes.fromhex(key[2:]), digest_size=32)
print("account-hash-" + digest.hexdigest())
PY
