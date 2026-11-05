---
name: new-project
description: >
  Scaffold a new Odra project with `cargo odra new`, or add Odra to an existing
  empty directory with `cargo odra init`. Use when the user says "new odra
  project", "create a project", "start a project", "scaffold", "set up odra",
  "init odra", or asks for a contract when no Odra project exists yet.
allowed-tools: Bash(cargo odra *), Bash(ls *), Bash(cat *), Bash(grep *), Read, Edit, AskUserQuestion, WebFetch
---

# Create a new Odra project

**Never hand-write an Odra project.** Always scaffold with `cargo odra new`. A project has
interlocking pieces — `Odra.toml`, `build.rs`, three `[[bin]]` targets, a pinned
`rust-toolchain.toml`, a `cfg(not(target_arch = "wasm32"))` dependency section — and hand-rolling
them produces a project that looks right and fails in non-obvious ways. The template is the source
of truth.

---

## Step 1 — Check there is no project already

```bash
ls Odra.toml
```

If `Odra.toml` exists, this is already an Odra project: stop, and use `smart-contract-writer` to add
a contract instead.

---

## Step 2 — Choose a template

```bash
cargo odra list-templates
```

Use the output, not memory — the set changes between releases. As of Odra 2.10 it is:

| Template    | Use when |
| ---         | --- |
| `full`      | Default. One crate, a sample `Flipper` contract, tests, and a CLI binary. |
| `blank`     | You want the wiring but none of the sample code. |
| `workspace` | Several contract crates plus a shared `cli` crate. |
| `cep18`     | Starting from a fungible token (CEP-18). |
| `cep95`     | Starting from an NFT (CEP-95). |

If the user has not said which they want, ask with `AskUserQuestion` — but pick `full` without asking
when they just said "a new project" and are clearly getting started.

---

## Step 3 — Scaffold

Pass a name that is already a valid Rust package name — lowercase, underscores, no hyphens:

```bash
cargo odra new --name my_project --template full
```

:::note
The directory is named **verbatim** from `--name`, while the Cargo package name is normalized.
`--name my-project` therefore creates `my-project/` containing a package called `my_project`, and
every `cd my_project` afterwards fails. Passing an underscore name keeps the two identical.
:::

To scaffold into the current directory instead (it must be empty), use `cargo odra init` with the
same flags.

Other flags worth knowing:
- `-s, --source` — pin the Odra version: a crates.io version, a git branch, a commit, or a local path
  (`-s ../odra`). Without it, `cargo odra` takes the version of the **latest GitHub release** of
  `odradev/odra` (cargo-odra 0.2.0 reads the `releases/latest` redirect, so it no longer hits the
  rate-limited GitHub API).
- `-r, --repo-uri` — a different template repository.

### Check the Odra version it picked

```bash
grep -m1 '^odra = ' my_project/Cargo.toml
```

The plugin's bundled reference targets **Odra 2.10**. The GitHub release can lag the crates.io
release by a few days, and then the default scaffold pins the previous version (and uses the older
template layout: a bare `rust-toolchain` file, no `.env.sample`, no `AGENTS.md`). If the generated
`odra` dependency is older than `2.10.0`, delete the directory and regenerate with the version
pinned:

```bash
cargo odra new --name my_project --template full -s 2.10.0
```

With cargo-odra 0.2.0 this matters most for the `workspace` template: 0.2.0 writes the wasm only to
the root `wasm/` directory, where Odra 2.10 looks and Odra 2.9 does not, so a workspace generated on
2.9.1 fails `cargo odra test -b casper` with `Failed to find wasm file`. Pin `-s 2.10.0` for a
workspace unless the default already resolved to 2.10.

---

## Step 4 — Verify it works before writing any code

```bash
cargo odra test
```

The first run is slow: the project pins a **nightly** toolchain via `rust-toolchain.toml`, and
rustup downloads it on demand. Later runs are seconds.

If this fails, it is an environment problem, not a code problem — run `/odra-plugin:check-env` and
install whatever it names. Do not start editing the generated code to make a failing build pass.

---

## Step 5 — Orient the user

Point out what was generated and what each piece is for (the `full` template; `blank`, `cep18` and
`cep95` have the same layout):

- `src/` — your contracts. Every new module needs `pub mod <name>;` in `src/lib.rs`.
- `Odra.toml` — the list of contracts to build to wasm. Each entry's `fqn` is the Rust path to the
  struct (`<module>::<Struct>`, or `<crate>::<module>::<Struct>` in a workspace; since 2.10 the
  first segment may also be a dependency crate, e.g. `odra_modules::erc20::Erc20`). A contract
  missing from here still passes OdraVM tests but never produces a wasm file.
- `bin/build_contract.rs`, `bin/build_schema.rs` — generated tooling; do not edit (except to add
  `use <dependency>;` when building a contract from a dependency crate — the comment inside says so).
- `bin/cli.rs` — your deploy script and scenarios; this one *is* meant to be edited. It builds the
  `<project>_cli` binary: `cargo run --bin my_project_cli -- deploy`.
- `.env.sample` — livenet configuration for the CLI, preset for a local NCTL node. Copy it to
  `.env` (or `<name>.env`, selected with `ODRA_CASPER_LIVENET_ENV=<name>`) and fill in the key path.
  `.gitignore` already ignores `.env`, `*.env` and `secret_key*.pem`.
- `AGENTS.md` and `CLAUDE.md` — instructions for AI agents working in the project. `CLAUDE.md` just
  imports `AGENTS.md`, which asks for this plugin to be installed, so nothing to do here.
- `build.rs`, `rust-toolchain.toml` — leave alone.
- `README.md`, `CHANGELOG.md` — the project's own; keep them current.
- `wasm/` — appears only after `cargo odra build` or `cargo odra test -b casper`.

In the `workspace` template, contracts live in `<crate>/src/`, the CLI in `cli/cli.rs`, and the
shared `wasm/` directory is at the workspace root (Odra 2.10 looks for wasm files in the working
directory and every directory above it).

Then hand off: `smart-contract-writer` to write contracts, `/odra-plugin:test-contracts` to run
tests, `/odra-plugin:deploy-to-livenet` to deploy.

---

## Reference

- [`docs-map.md`](../../reference/docs-map.md) — index of the whole documentation set; read it when
  something here is missing or looks out of date
- [Ubuntu / WSL setup](https://odra.dev/docs/getting-started/ubuntu-wsl-setup) and
  [macOS setup](https://odra.dev/docs/getting-started/macos-setup) — if scaffolding or the first
  build fails on a fresh machine, their troubleshooting tables are keyed by error message
- [Directory structure](https://odra.dev/docs/basics/directory-structure) and
  [Odra.toml](https://odra.dev/docs/basics/odra-toml) — the generated layout in full
- [Cargo Odra](https://odra.dev/docs/basics/cargo-odra) — every `cargo odra` command and flag
