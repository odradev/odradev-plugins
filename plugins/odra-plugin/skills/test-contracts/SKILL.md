---
name: test-contracts
description: >
  Run unit and integration test on in-memory OdraVM or (and) real WASMs on CasperVM
  and report results.
  Use when the user says "test contract", "verify contract(s)", "unit test".
allowed-tools: Bash(cargo odra *), Bash(${CLAUDE_SKILL_DIR}/scripts/*), Read, AskUserQuestion, WebFetch
---

Use `AskUserQuestion` tool to verify the user intent if not explicitly expressed:
whether the tests should be run on `OdraVM`, `CasperVM` or both.

Running tests on `OdraVM`:

```bash
cargo odra test
```

Running tests on `CasperVM`:

First, check if WASMs need to be rebuilt (the script finds the project root by `Odra.toml` and
compares every `*.rs`, `Odra.toml` and `Cargo.toml` with the newest file in `wasm/`):

```bash
${CLAUDE_SKILL_DIR}/scripts/needs_rebuild.sh
```

Then run tests with the appropriate flag based on the result:

```bash
# If rebuild is needed (needs_rebuild.sh exited 0):
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --rebuild

# If no rebuild is needed (needs_rebuild.sh exited 1):
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh
```

Arguments after `--` go to `cargo test`, so a single test or printed output work as usual:

```bash
cargo odra test -- flipping                       # run tests matching "flipping"
cargo odra test -b casper -s -- --nocapture       # show stdout, e.g. self.env().debug(..) output
```

If tests fail, help the user fix the issues. Explain any errors in context.

## Things worth knowing (Odra 2.10)

- **A test can pin its backend.** `odra_test::env()` follows `-b`; `odra_test::odra_env()` always
  uses OdraVM and `odra_test::casper_env()` always CasperVM. Use `odra_env()` for a module that is
  only a building block and is not in `Odra.toml` — under `-b casper` there is no wasm for it, so
  `deploy` would fail.
- **OdraVM rolls back a reverted call completely** — storage, balances, events, contracts it
  deployed, the code of a failed upgrade — like Casper. A test that counted events of a reverted
  call sees fewer events than it did on 2.9, and the same number as on CasperVM.
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
