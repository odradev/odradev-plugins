---
name: test-contracts
description: >
  Run unit and integration test on in-memory OdraVM or (and) real WASMs on CasperVM
  and report results.
  Use when the user says "test contract", "verify contract(s)", "unit test".
allowed-tools: Bash(cargo odra *)
---

Use `AskUserQuestion` tool to verify the use intent if not explicite expressed.
If the tests be run on `OdraVM`, `CasperVM` or both.

Running test on `OdraVM`:

```bash
cargo odra test
```

Running tests on `CasperVM` with rebuild:

```bash
cargo odra test -b casper
```

Running tests on `CasperVM` without build:

```bash
cargo odra test -b casper -s
```

Before you run tests on `CasperVM` check if really need to rebuild contracts.
Use the following logic:
If the contracts source code has changed since the last change in `wasm` directory,
then test with rebuild.


If tests fail, help the user fix the issues. Explain any errors in context.
