---
name: check-env
description: >
  Validate the development environment for Odra smart contract development.
  Use when the user says "check env", "check setup", "check prerequisites",
  "verify environment", or "check-env".
allowed-tools: Bash(rustc *),Bash(rustup *),Bash(cargo odra *),Bash(wasm-opt *),Bash(wasm-strip *),Bash(docker *),Bash(cc *),Bash(pkg-config *),Bash(command -v *),Bash(cat *),Bash(uname *),Read,WebFetch
---

# Check Development Environment

Validates that all prerequisites for Odra development are installed.

**Run the checks from inside the project directory** when there is one. Two of them —
the Rust toolchain and the wasm target — resolve differently depending on the working
directory, and checking from the wrong place reports a healthy environment that cannot build.

Upstream reference: [Installation guide](https://odra.dev/docs/getting-started/installation), or
[Ubuntu / WSL setup](https://odra.dev/docs/getting-started/ubuntu-wsl-setup) for exact commands on
Linux and a troubleshooting table keyed by error message.
[`docs-map.md`](../../reference/docs-map.md) indexes the rest of the documentation.

---

## Step 1 — Check Each Prerequisite

Run these checks and collect results.

### C toolchain (linker)

```bash
command -v cc
```

Rust shells out to `cc` to link. Without it *every* build fails at
`error: linker 'cc' not found` — including `cargo install cargo-odra`, so this blocks setup
before anything else.

If missing:
- Debian/Ubuntu: `sudo apt install build-essential`
- Fedora: `sudo dnf install gcc`
- macOS: `xcode-select --install`

### pkg-config and OpenSSL headers

```bash
pkg-config --modversion openssl
```

`cargo-odra` depends on `openssl-sys`, which finds OpenSSL through `pkg-config` at build time.
Without it, installing `cargo-odra` fails with *"this requires the pkg-config utility to find
OpenSSL"*. Only needed to build `cargo-odra` itself — skip this check if `cargo odra --version`
already works.

If missing:
- Debian/Ubuntu: `sudo apt install pkg-config libssl-dev`
- Fedora: `sudo dnf install pkg-config openssl-devel`

### Rust toolchain

```bash
rustc --version
rustup show active-toolchain
cat rust-toolchain.toml 2>/dev/null || cat rust-toolchain 2>/dev/null
```

Odra projects pin a nightly. Projects generated from the Odra 2.10 templates do it in
`rust-toolchain.toml` (`channel = "nightly-2026-01-01"`, plus the `rust-analyzer` component);
older projects have a bare `rust-toolchain` file with just the channel name. Either way, inside the
project `rustup show active-toolchain` should report that pinned version with "overridden by" —
rustup installs it automatically on first use, which is why the first build is slow.

If rustup itself is missing:
- `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`, then
  `. "$HOME/.cargo/env"`

Do not suggest a distro-packaged `rustc` (`apt install rustc`). It cannot switch to the pinned
nightly.

### wasm32-unknown-unknown target

Check it against the **pinned** toolchain, not the default one. Run this **from inside the
project directory** — there, the active toolchain is the pinned one, whether it is pinned by
`rust-toolchain.toml` or by `rust-toolchain`:

```bash
rustup target list --installed
```

Outside a project (no `Odra.toml` around), the command reports the default toolchain, which is not
what the project builds with; say so in the report instead of calling it a pass.

If missing, the fix must be run **from inside the project directory**:

```bash
rustup target add wasm32-unknown-unknown
```

This is the single most common false positive. `rustup target add` applies to whichever toolchain
is active in the current directory, so running it from the home directory installs the target for
`stable` while the project keeps building with its pinned nightly. The user then sees
`wasm32-unknown-unknown target is not present` *after* running exactly the command the error told
them to run. If they report that, check which toolchain actually has the target.

### cargo-odra

```bash
cargo odra --version
```

If missing:
- Install: `cargo install cargo-odra --locked`

Requires the C toolchain and `pkg-config`/OpenSSL above — check those first, since this is where
their absence shows up.

Version: **0.2.0 or newer** is the current release and the one to install;
`cargo install cargo-odra --locked` also upgrades an older one. 0.1.8 still builds and tests a
single-crate Odra 2.10 project, but it cannot build contracts from dependency crates
(`fqn = "odra_modules::erc20::Erc20"` in `Odra.toml`) and it copies the wasm into every workspace
member, where a stale copy can shadow a fresh build. Report the version: below 0.1.8 is a failure,
0.1.8 is OLD.

Note the pairing with the Odra version: cargo-odra 0.2.0 writes the wasm of a workspace only to the
root `wasm/`, where Odra 2.10 looks and Odra 2.9 does not. A workspace project still on Odra 2.9
needs either the bump to 2.10 or cargo-odra 0.1.8. Single-crate projects are unaffected.

### wasm-opt (binaryen) — version matters

```bash
wasm-opt --version
```

**Binaryen must be version 121 or newer.** `cargo-odra` passes `--llvm-memory-copy-fill-lowering`
for any modern Rust toolchain, and older binaryen rejects the flag. The failure is misleading — it
reports `There was an error while running wasm-opt - is it installed?` when it *is* installed:

```
Unknown option '--llvm-memory-copy-fill-lowering'
🤦  ERROR : There was an error while running wasm-opt - is it installed?
```

Treat an installed-but-older-than-121 binaryen as a failure, not a pass.

Distribution packages are usually too old — Ubuntu 24.04 ships 108, Ubuntu 26.04 ships 120. Do not
recommend `apt install binaryen`.

If missing or too old:
- Linux: download a release from https://github.com/WebAssembly/binaryen/releases and install it,
  e.g.
  ```bash
  curl -sL https://github.com/WebAssembly/binaryen/releases/download/version_131/binaryen-version_131-x86_64-linux.tar.gz -o /tmp/binaryen.tar.gz
  sudo tar xzf /tmp/binaryen.tar.gz -C /usr/local --strip-components=1
  ```
  (use the `aarch64-linux` asset on ARM)
- macOS: `brew install binaryen` — Homebrew tracks upstream closely, so this is current

### wasm-strip (wabt)

```bash
wasm-strip --version
```

Any recent version works; distribution packages are fine here.

If missing:
- Debian/Ubuntu: `sudo apt install wabt`
- Fedora: `sudo dnf install wabt`
- macOS: `brew install wabt`

### Docker (optional)

```bash
docker --version
```

If missing, note it is optional — only needed for local NCTL node testing.
- Install from https://docs.docker.com/get-docker/
- On WSL, install Docker Desktop on Windows and enable WSL integration for the distribution

---

## Step 2 — Report Results

Present a summary table:

```
| Prerequisite              | Status     | Action needed      |
|---------------------------|------------|--------------------|
| C toolchain (cc)          | OK/MISSING | install command    |
| pkg-config + OpenSSL      | OK/MISSING | install command    |
| Rust toolchain (pinned)   | OK/MISSING | install command    |
| wasm32-unknown-unknown    | OK/MISSING | install command    |
| cargo-odra (>= 0.2.0)     | OK/OLD/MISSING | install command |
| wasm-opt (binaryen >= 121)| OK/OLD/MISSING | install command |
| wasm-strip (wabt)         | OK/MISSING | install command    |
| Docker (optional)         | OK/MISSING | install link       |
```

Report the binaryen version explicitly when it is present but older than 121 — "wasm-opt 120,
needs >= 121" tells the user something that "OK" would hide.

If everything is OK, report: "Environment is ready for Odra development."

If items are missing, list the install commands and explain what each tool is for:
- **C toolchain**: the linker every Rust build needs
- **pkg-config + OpenSSL**: build-time dependency of `cargo-odra`
- **Rust toolchain**: the pinned nightly the project compiles with (`rust-toolchain.toml`)
- **wasm32-unknown-unknown**: WebAssembly compilation target for smart contracts
- **cargo-odra**: Odra's build/test tool — wraps cargo with WASM compilation steps (0.2.0 goes with Odra 2.10)
- **wasm-opt**: optimizes WASM binaries for smaller contract size
- **wasm-strip**: strips debug info from WASM binaries
- **Docker**: runs a local Casper blockchain node for testing deployments

On Ubuntu or WSL, offer [Ubuntu / WSL setup](https://odra.dev/docs/getting-started/ubuntu-wsl-setup)
— it is the same list as a single copy-pasteable block.

---

## Note on `cargo odra test`

A missing wasm target or wasm tooling does **not** block `cargo odra test` on OdraVM — only
`cargo odra build`/`test -b casper` need them. If the user just wants to run tests and is blocked
on binaryen, tell them they can proceed on OdraVM meanwhile.

## Note on the project's Odra version

While in the project, also read the `odra` version from `Cargo.toml`. The plugin's bundled
reference targets Odra 2.10. A project on 2.9 or older still works with every skill, but point the
user at the [migration guide to 2.10.0](https://odra.dev/docs/migrations/to-2.10.0) — for most
projects it is a version bump — and prefer the matching versioned docs URL (see
[`docs-map.md`](../../reference/docs-map.md)) when looking things up for it.
