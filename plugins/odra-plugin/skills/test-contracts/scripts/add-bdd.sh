#!/usr/bin/env bash
# Add scenario (BDD) tests to an Odra contract crate: tests/bdd.rs, tests/common/, tests/steps/,
# tests/features/, the dev-dependencies (odra-bdd, cucumber) and the `bdd` test target.
# Needs Odra 2.11 or newer: odra-bdd of 2.10 does not fail a run whose scenario failed.
# Usage: add-bdd.sh [crate-dir]
#   [crate-dir]  the contract crate; default is the current directory. In a workspace project
#                run it once per contract crate that gets scenarios.
# Refuses to touch a crate that already has tests/bdd.rs.
set -euo pipefail

CRATE="${1:-.}"
TEMPLATE="$(cd "$(dirname "$0")/../template/bdd" && pwd)"
fail() { echo "Error: $*" >&2; exit 1; }

[ -f "$CRATE/Cargo.toml" ] || fail "no Cargo.toml in $CRATE."
cd "$CRATE"
grep -q '^\[package\]' Cargo.toml \
  || fail "$CRATE is a workspace root; pass a contract crate (add-bdd.sh <crate-dir>)."
grep -Eq '^odra-test *=' Cargo.toml \
  || fail "$CRATE does not depend on odra-test: not an Odra contract crate."
[ ! -e tests/bdd.rs ] || fail "tests/bdd.rs already exists."
for path in tests/common tests/steps tests/features; do
  [ ! -e "$path" ] || fail "$path already exists; move it away or add the files by hand."
done

# odra-bdd must come from where odra-test comes from: the registry, a git repository or a path.
ODRA_TEST=$(cargo tree -p odra-test --depth 0 --prefix none 2>/dev/null | head -1) \
  || fail "cargo cannot resolve the dependencies of this crate (run 'cargo check')."
VERSION=$(echo "$ODRA_TEST" | sed -n 's/^odra-test v\([^ ]*\).*/\1/p')
SOURCE=$(echo "$ODRA_TEST" | sed -n 's/^odra-test v[^ ]* (\(.*\))$/\1/p')
[ -n "$VERSION" ] || fail "cannot read the odra-test version from: $ODRA_TEST"

case "$SOURCE" in
  "")
    case "$VERSION" in
      0.*|1.*|2.[0-9].*|2.10.*) fail "Odra $VERSION is too old for scenario tests; bump odra* to 2.11 first." ;;
    esac
    cargo add --quiet --dev "odra-bdd@$VERSION" ;;
  http*|ssh*|git@*)
    URL="${SOURCE%%[?#]*}"
    REF=()
    case "$SOURCE" in
      *\?branch=*) REF=(--branch "$(echo "$SOURCE" | sed 's/.*?branch=\([^#&]*\).*/\1/')") ;;
      *\?tag=*)    REF=(--tag "$(echo "$SOURCE" | sed 's/.*?tag=\([^#&]*\).*/\1/')") ;;
      *\?rev=*)    REF=(--rev "$(echo "$SOURCE" | sed 's/.*?rev=\([^#&]*\).*/\1/')") ;;
    esac
    cargo add --quiet --dev odra-bdd --git "$URL" "${REF[@]}" ;;
  *)
    [ -f "$SOURCE/../odra-bdd/Cargo.toml" ] || fail "no odra-bdd next to odra-test at $SOURCE."
    cargo add --quiet --dev odra-bdd --path "$SOURCE/../odra-bdd" ;;
esac

# The step macros must be the cucumber odra-bdd was built with, or its parameter types
# ({account}, {cspr_amount}) do not fit them.
CUCUMBER=$(cargo tree -p odra-bdd --depth 1 --prefix none | sed -n 's/^cucumber v\([0-9]*\.[0-9]*\).*/\1/p' | head -1)
[ -n "$CUCUMBER" ] || fail "cannot find the cucumber version odra-bdd uses."
cargo add --quiet --dev "cucumber@$CUCUMBER"

printf '\n[[test]]\nname = "bdd"\nharness = false\n' >> Cargo.toml
mkdir -p tests
cp -r "$TEMPLATE/tests/." tests/

echo "Added scenario tests to $(pwd): tests/features/*.feature (odra-bdd $VERSION, cucumber $CUCUMBER)." >&2
echo "Run them: cargo odra test    (only them: cargo test --test bdd)" >&2
