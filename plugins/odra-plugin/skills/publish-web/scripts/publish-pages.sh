#!/usr/bin/env bash
# Build the web app for one network and publish it to GitHub Pages (branch gh-pages of origin).
# Usage: publish-pages.sh <testnet|mainnet> <CSPR.click app id> [web-dir]
# Run from the Odra project root. The two networks share one site:
#   mainnet  ->  https://<owner>.github.io/<repo>/
#   testnet  ->  https://<owner>.github.io/<repo>/testnet/
# Publishing one never touches the other. Until mainnet is published, the site root forwards to
# the testnet page.
set -euo pipefail

NETWORK="${1:-}"; APP_ID="${2:-}"; WEB_DIR="${3:-web}"
case "$NETWORK" in
  testnet) CHAIN=casper-test ;;
  mainnet) CHAIN=casper ;;
  *) echo "Usage: publish-pages.sh <testnet|mainnet> <CSPR.click app id> [web-dir]" >&2; exit 1 ;;
esac
[ -f Odra.toml ] || { echo "Error: run this from the Odra project root (no Odra.toml here)." >&2; exit 1; }
[ -f "$WEB_DIR/package.json" ] || { echo "Error: no web app in $WEB_DIR/ (run the web-app skill first)." >&2; exit 1; }
[ -f "resources/$CHAIN-contracts.toml" ] || { echo "Error: resources/$CHAIN-contracts.toml is missing: nothing is deployed to $NETWORK yet." >&2; exit 1; }
if [ -z "$APP_ID" ] || [ "$APP_ID" = "csprclick-template" ]; then
  echo "Error: give the site's own CSPR.click app id (from https://console.cspr.build)." >&2
  echo "The development id csprclick-template works on localhost only: wallets would not connect." >&2
  exit 1
fi
ORIGIN="$(git remote get-url origin 2>/dev/null)" || { echo "Error: the project has no 'origin' remote. Create the GitHub repository first (see the skill)." >&2; exit 1; }
if git ls-files | grep -qE '\.pem$|(^|/)[^/]*\.env$'; then
  echo "Error: a key or .env file is tracked by git. Remove it from the repository before publishing." >&2; exit 1
fi

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$PWD"
MARKER="odra-plugin:testnet-redirect"

SLUG="$(printf '%s' "$ORIGIN" | sed -nE 's#^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//')"

# 0. Is the app id registered for the address the site will have, and for this network?
# CSPR.click answers the page's own request for the application only from a registered origin.
if [ -n "$SLUG" ]; then
  SITE_ORIGIN="$(gh api "repos/$SLUG/pages" -q .html_url 2>/dev/null | sed -E 's#^(https?://[^/]+).*#\1#' || true)"
  [ -n "$SITE_ORIGIN" ] || SITE_ORIGIN="https://$(printf '%s' "${SLUG%%/*}" | tr '[:upper:]' '[:lower:]').github.io"
  APP_JSON="$(curl -sS -m 20 -H "Origin: $SITE_ORIGIN" "https://accounts.cspr.click/api/application/$APP_ID.json" 2>/dev/null || true)"
  case "$APP_JSON" in
    *'"wrong application id"'*)
      echo "Error: CSPR.click does not know the app id $APP_ID. Copy it again from https://console.cspr.build." >&2; exit 1 ;;
    *'"wrong origin'*)
      echo "Error: the app id $APP_ID is not registered for $SITE_ORIGIN." >&2
      echo "In https://console.cspr.build open the application and add exactly $SITE_ORIGIN (no path) to its allowed origins, then run this again." >&2
      exit 1 ;;
    *'"chain_name"'*)
      APP_CHAIN="$(printf '%s' "$APP_JSON" | sed -nE 's/.*"chain_name": *"([^"]*)".*/\1/p')"
      if [ "$APP_CHAIN" != "$CHAIN" ]; then
        echo "Error: the app id $APP_ID is set to the network $APP_CHAIN in console.cspr.build; the $NETWORK page needs one set to $CHAIN." >&2
        exit 1
      fi
      echo "CSPR.click app id: registered for $SITE_ORIGIN on $CHAIN." >&2 ;;
    *) echo "Warning: could not check the app id with CSPR.click; the wallet connection is unverified." >&2 ;;
  esac
fi

# 1. Build.
"$SCRIPTS/../../web-app/scripts/sync-contracts.sh" "$WEB_DIR"
( cd "$WEB_DIR"
  [ -d node_modules ] || npm install
  VITE_NETWORK="$NETWORK" VITE_CSPR_CLICK_APP_ID="$APP_ID" npm run build )
DIST="$ROOT/$WEB_DIR/dist"
[ -f "$DIST/index.html" ] && [ -f "$DIST/contracts.$CHAIN.json" ] || { echo "Error: the build did not produce $WEB_DIR/dist with contracts.$CHAIN.json." >&2; exit 1; }

# 2. Put it into the gh-pages branch, next to what is already published.
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export GIT_TERMINAL_PROMPT=0
git init -q -b gh-pages "$WORK"
git -C "$WORK" remote add origin "$ORIGIN"
if git -C "$WORK" fetch -q --depth 1 origin gh-pages 2>/dev/null; then
  git -C "$WORK" reset -q --hard FETCH_HEAD
fi
touch "$WORK/.nojekyll"
if [ "$NETWORK" = testnet ]; then
  rm -rf "$WORK/testnet"; mkdir "$WORK/testnet"; cp -R "$DIST/." "$WORK/testnet/"
  if [ ! -f "$WORK/index.html" ] || grep -q "$MARKER" "$WORK/index.html"; then
    printf '<!doctype html><!-- %s --><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=testnet/"><a href="testnet/">Testnet version</a>\n' "$MARKER" > "$WORK/index.html"
  fi
else
  find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git ! -name testnet ! -name CNAME ! -name .nojekyll -exec rm -rf {} +
  cp -R "$DIST/." "$WORK/"
fi
git -C "$WORK" add -A
if git -C "$WORK" diff --cached --quiet; then
  echo "Nothing changed since the last publish of $NETWORK." >&2
else
  git -C "$WORK" -c user.name="$(git config user.name || echo publish-pages)" \
      -c user.email="$(git config user.email || echo publish-pages@localhost)" \
      commit -q -m "Publish $NETWORK ($(git rev-parse --short HEAD 2>/dev/null || echo unversioned))"
  git -C "$WORK" push -q origin gh-pages
  echo "Pushed the $NETWORK site to the gh-pages branch." >&2
fi

# 3. Turn GitHub Pages on and wait until the site is served.
if [ -z "$SLUG" ]; then
  echo "origin is not a GitHub repository: serve the gh-pages branch with your host's static hosting." >&2
  exit 0
fi
# GitHub may turn Pages on by itself when a gh-pages branch appears; then the request answers 409.
if ! gh api "repos/$SLUG/pages" >/dev/null 2>&1; then
  if ! OUT="$(gh api -X POST "repos/$SLUG/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' 2>&1)" \
     && ! printf '%s' "$OUT" | grep -q '"status":"409"'; then
    echo "Error: GitHub Pages could not be turned on for $SLUG:" >&2; echo "$OUT" >&2
    echo "A private repository needs a paid GitHub plan for Pages; make the repository public or use another host." >&2
    exit 1
  fi
fi
SITE="$(gh api "repos/$SLUG/pages" -q .html_url)"; SITE="${SITE%/}"
[ "$NETWORK" = testnet ] && PAGE="$SITE/testnet/" || PAGE="$SITE/"
WANT="$(grep -o '"package_hash": *"[^"]*"' "$DIST/contracts.$CHAIN.json" | head -n1 | sed 's/.*"\(hash-[^"]*\)"/\1/')"
echo "Waiting for GitHub to serve $PAGE ..." >&2
for _ in $(seq 1 36); do
  if curl -fsS "${PAGE}contracts.$CHAIN.json?$(date +%s)" 2>/dev/null | grep -q "${WANT:-package_hash}"; then
    echo "$PAGE"; exit 0
  fi
  sleep 5
done
echo "Error: $PAGE does not serve this build after 3 minutes. Build status: $(gh api "repos/$SLUG/pages/builds/latest" -q .status 2>/dev/null || echo unknown)" >&2
exit 1
