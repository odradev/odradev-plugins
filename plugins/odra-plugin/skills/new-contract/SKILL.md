---
name: new-contract
description: >
  Scaffold a new Odra contract module in the contracts crate.
  Use when the user says "new contract", "create a contract", "scaffold a module",
  "add a contract", "new module", or "new-contract".
allowed-tools: Read,Edit,Write
---

# Scaffold New Contract

Creates a new Odra contract module in the `contracts/` crate.

---

## Step 1 — Gather Requirements

Ask the user for (skip any they've already provided):

1. **Module name** — PascalCase (e.g., `Counter`, `Vault`, `TokenSale`)
2. **Brief description** — one sentence describing what the contract does
3. **Storage fields** — what state it needs. Suggest appropriate types:
   - `Var<T>` for single values (e.g., `Var<u32>`, `Var<Address>`, `Var<U256>`)
   - `Mapping<K, V>` for key-value storage (e.g., `Mapping<Address, U256>`)
4. **SubModules** — composing existing modules (e.g., `SubModule<Ownable>`, `SubModule<Erc20>`)
   - If used, ask which methods to delegate via `delegate!`
5. **External contracts** — cross-contract calls via `External<ContractRef>`
   - If used, ask which external contract and which methods to call
6. **Events** — what events the contract should emit (name + fields)
7. **Errors** — what error conditions exist (name + variants)

Do not guess or infer any of these. If the user hasn't specified something, ask.

---

## Step 2 — Generate the Contract File

Create `contracts/src/<snake_name>.rs` with a scaffolded Odra contract module based on the gathered requirements. Use the Odra documentation for reference on syntax and patterns. 

---

## Step 3 — Register the Contract

### 3a — Add to contracts/src/lib.rs

Add to `contracts/src/lib.rs`:

```rust
pub mod <snake_name>;
```

### 3b — Register in Odra.toml

Add to the root `Odra.toml`:

```toml
[[contracts]]
fqn = "contracts::<snake_name>::ModuleName"
```

### 3c — Wire into CLI

In `cli/cli.rs`:

1. Add import: `use contracts::<snake_name>::ModuleName;` and `use odra_cli::cspr;`
2. Add deployment in `ContractsDeployScript::deploy()`:
   ```rust
   let _ = ModuleName::load_or_deploy(&env, ModuleNameInitArgs { /* args */ }, container, cspr!(500))?;
   ```
   Use `NoArgs` instead of `ModuleNameInitArgs` if `init()` takes no arguments.
3. Register in the builder chain: `.contract::<ModuleName>()`

Add necessary imports (`odra_cli::DeployerExt`, `odra_cli::ContractProvider`, `odra::host::NoArgs` if needed) to the `use` block.

---

## Step 4 — Verify

Run the tests:

```bash
cargo odra test
```

Fix any compilation errors before reporting success.

---

## Step 5 — Report

Show the user:
- Files created/modified
