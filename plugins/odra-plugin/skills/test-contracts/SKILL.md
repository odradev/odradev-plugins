---
name: test-contracts
description: >
  Run unit and integration test on in-memory OdraVM or (and) real WASMs on CasperVM
  and report results.
  Use when the user says "test contract", "verify contract(s)", "unit test".
allowed-tools: Bash(cargo odra *), Read, AskUserQuestion, WebFetch
---

Use `AskUserQuestion` tool to verify the user intent if not explicitly expressed:
whether the tests should be run on `OdraVM`, `CasperVM` or both.

Running tests on `OdraVM`:

```bash
cargo odra test
```

Running tests on `CasperVM`:

```bash
cargo odra test -b casper
```

This builds every contract in `Odra.toml` to wasm, runs `wasm-opt` and `wasm-strip` over each one,
and then executes the same tests against Casper's execution engine. `cargo odra` tracks whether the
wasm is stale, so there is no separate rebuild step to decide on — pass `--skip-build` (`-s`) only
when you have just built and want to reuse the existing wasm. In a workspace the wasm lands in the
one `wasm/` directory at the root (Odra 2.10 looks there from every member).

:::note
The templates do **not** generate a `scripts/` directory, and this skill ships none. Drive
`cargo odra test` directly. If a particular project happens to have its own `scripts/`, those are
the user's, not Odra's.
:::

CasperVM runs require the `wasm32-unknown-unknown` target plus `wasm-opt` and `wasm-strip` on
`PATH`; OdraVM requires none of them. If `-b casper` fails on tooling rather than on a test
assertion, run `/odra-plugin:check-env` before touching the contract.

Arguments after `--` go to the test binary, as after `cargo test --`:

```bash
cargo odra test -- flipping                       # run tests matching "flipping"
cargo odra test -b casper -s -- --nocapture       # show stdout, e.g. self.env().debug(..) output
cargo odra test -- --release -- --nocapture       # cargo's own arguments go before a second `--`
```

Only the name filter works with cargo-odra 0.2.0; the other two lines need 0.2.1 (`cargo odra
--version`). On 0.2.0 `-- --nocapture` fails with "unexpected argument"; run cargo directly instead:

```bash
cargo test -- --nocapture                         # OdraVM
ODRA_BACKEND=casper cargo test -- --nocapture     # CasperVM, after `cargo odra build`
```

Give these commands a long timeout (10 minutes): on a cold cache `cargo odra test -b casper`,
`cargo odra build` and `cargo odra schema` compile the Casper execution engine and can take several
minutes each; later runs take seconds.

If tests fail, help the user fix the issues. Explain any errors in context.

## Things worth knowing (Odra 2.10)

- **A test can pin its backend.** `odra_test::env()` follows `-b`; `odra_test::odra_env()` always
  uses OdraVM and `odra_test::casper_env()` always CasperVM. Use `odra_env()` for a module that is
  only a building block and is not in `Odra.toml` — under `-b casper` there is no wasm for it, so
  `deploy` would fail.
- **OdraVM rolls back a reverted call completely** — storage, balances, events, contracts it
  deployed, the code of a failed upgrade — like Casper. A test that counted events of a reverted
  call sees fewer events than it did on 2.9, and the same number as on CasperVM.
- **OdraVM does not model package locking.** A contract deployed without
  `InstallConfig::upgradable` can be upgraded on OdraVM but fails on CasperVM with
  `A locked contract cannot be upgraded`; an upgrade test must use `deploy_with_cfg`.
- **Panics print again.** Since 2.10 OdraVM no longer silences `unwrap`/`expect`/assertion
  panics after the first call; a bare `VmError(Panic)` in the output is a real panic in contract
  code (arithmetic overflow, `unwrap` on `None`), not a revert.
- **`self.env().debug(..)` prints on OdraVM.** On CasperVM it prints only if the contract crate
  enables the `test-support` feature of `odra`; run with `-- --nocapture` either way.
- **Factories run on OdraVM** since 2.10, so `new_contract` tests no longer need `-b casper`.
- **Snapshots** (`env.take_snapshot()` / `env.restore_snapshot()`) let several scenarios branch off
  one setup; see `reference/testing.md` in `smart-contract-writer`.

## Reference

- [Testing](https://odra.dev/docs/basics/testing) — test API, asserting on errors and events,
  snapshots, choosing the backend
- [OdraVM](https://odra.dev/docs/backends/odra-vm) vs [Casper](https://odra.dev/docs/backends/casper)
  — read these when a test passes on OdraVM but fails on CasperVM; the two do not model everything
  the same way
- [`docs-map.md`](../../reference/docs-map.md) — index of the whole documentation set
