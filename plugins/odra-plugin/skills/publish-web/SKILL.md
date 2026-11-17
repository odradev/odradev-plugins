---
name: publish-web
description: >
  Put the web app of an Odra project on the internet: build it for testnet or mainnet and publish
  it to GitHub Pages, so anyone with the link and a wallet can use it. Use when the user says
  "publish the app", "put it online", "host the site", "deploy the frontend", "share a link",
  "GitHub Pages", "make it public", or "publish-web".
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/*),Bash(${CLAUDE_SKILL_DIR}/../web-app/scripts/*),Bash(gh *),Bash(git *),Bash(curl *),Bash(npm *),Bash(ls *),Bash(cat *),Bash(grep *),Read,Write,Edit,AskUserQuestion,WebFetch
---

# Publish the web app

The web app is a folder of static files (`web/dist/`); it needs a place that serves files, nothing
more. The default here is **GitHub Pages**: free, no new account beyond GitHub, driven by `gh`.

One site holds both versions, and publishing one never touches the other:

| Version | Address | Talks to |
| --- | --- | --- |
| testnet | `https://<owner>.github.io/<repo>/testnet/` | the testnet contracts, free test CSPR |
| mainnet | `https://<owner>.github.io/<repo>/` | the mainnet contracts, real CSPR |

Until mainnet is published, the site root forwards to the testnet page. Publish testnet as soon
as the page works locally — a link to show people is worth more than a screenshot — and mainnet
as part of `/odra-plugin:go-mainnet`.

**Prerequisites:** the page works locally (`/odra-plugin:web-app`, `npm run build` passes,
`check-reads.mjs` passes), the contracts are deployed to the network being published, `gh` is
installed and signed in (`gh auth status`).

---

## Step 1 — Say what becomes public, and get a yes

Publishing is the user's decision. Tell them, then ask:

> The site will be reachable by anyone with the link. On a free GitHub account the repository
> behind it has to be public too, so the project's source code becomes readable by everyone.
> Secret keys and `.env` files are not part of the repository and stay on this machine.

If the user wants the code private: a paid GitHub plan serves Pages from a private repository, or
use one of the hosts under "Other hosts" — they take the built folder without the source.

## Step 2 — The GitHub repository

```bash
git remote get-url origin        # exists? then skip to Step 3
git ls-files | grep -E '\.pem$|\.env$'   # must print nothing
gh repo create <project_name> --public --source . --push
```

Commit first (`git status` clean). The address of the site is now known:
`https://<owner>.github.io/<project_name>/` — `gh repo view --json owner,name`.

## Step 3 — The CSPR.click app id (the user's step)

The development id in the template works on `localhost` only; a published page needs its own or
wallets do not connect. Give the user these steps and wait for the id:

1. Open <https://console.cspr.build> and sign up (free).
2. Create a CSPR.click application for this project. Where the console asks for the site's
   address, it is the one from Step 2.
3. Copy the application id and paste it here.

The id is not a secret — it ships in the page. Keep it in `GUIDE.md` so the next publish has it.
Use the same id for the testnet and the mainnet build unless the console issues one per network.

## Step 4 — Publish

From the project root:

```bash
${CLAUDE_SKILL_DIR}/scripts/publish-pages.sh testnet <app id>
# ...
# https://<owner>.github.io/<project_name>/testnet/
```

It copies the deployed addresses into the page, builds it for that network with the app id, puts
the result on the `gh-pages` branch, turns GitHub Pages on at the first run and waits until the
site serves this build. The last line is the address. `mainnet` in place of `testnet` publishes the
mainnet page — only after `go-mainnet` deployed the contracts and the reader account is funded
there, and it is a separate yes.

Run it again after every change to the page and after every redeploy of the contracts (new
addresses). The first publish of a repository can take a few minutes to appear.

## Step 5 — Check the live site

1. **You:** the contracts file is the right one —
   `curl -s <address>contracts.casper-test.json` shows the package hash of
   `resources/casper-test-contracts.toml`.
2. **You, if you can drive a browser:** the page shows contract state without a wallet.
3. **The user:** opens the address, connects Casper Wallet (set to Testnet for the testnet page)
   and performs one action. Only this proves the app id — you cannot approve it for them. If the
   sign-in dialog does not open or reports an unknown application, the id or the address
   registered for it in the console is wrong.

Report which of the three were done.

## Step 6 — Tell the user

The address (both, when both exist), that the testnet page is safe to share and costs visitors
nothing but test CSPR from the faucet, and how to update it (this skill again). Add the addresses
and the app id to `GUIDE.md`.

---

## When it fails

| Message | Cause |
| --- | --- |
| `GitHub Pages could not be turned on` | the repository is private on a free plan, or `gh` lacks rights to it |
| `does not serve this build after 3 minutes` | Pages is still building (first publish), or the build failed: `gh api repos/<owner>/<repo>/pages/builds/latest` |
| the page loads, state does not | the reader account is not funded on that network, or the client was not rebuilt — the table in `web-app` |
| state loads, the wallet does not connect | the app id (Step 3) |
| a blank page at the address | the site was built without the template's `base: "./"` in `vite.config.ts` |

## Other hosts

`web/dist/` after `VITE_NETWORK=<testnet|mainnet> VITE_CSPR_CLICK_APP_ID=<id> npm run build` is the
whole site; any static host serves it. Without publishing the source: Netlify and Cloudflare Pages
accept the folder as an upload from their dashboards — the user's account, their step. One folder
is one network there: use two sites, or copy the testnet build into `dist/testnet/` before
uploading. Register the final address for the app id.

**A domain of their own:** set it in the repository's *Settings → Pages* (GitHub writes a `CNAME`
file to the branch, which the script keeps) and update the address registered for the app id.

## Reference

- [GitHub Pages](https://docs.github.com/en/pages) — limits, custom domains
- [CSPR.click documentation](https://docs.cspr.click) — the app id
- [`web-app`](../web-app/SKILL.md) — the page itself and its checks
