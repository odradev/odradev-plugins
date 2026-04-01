---
name: new-scenario
description: >
  Implement a new CLI scenario for interacting with deployed contracts.
  Use when the user says "new scenario", "add scenario", "cli scenario",
  "deployment scenario", or "new-scenario".
allowed-tools: Read,Edit,Bash(cargo *)
---

# Implement New CLI Scenario

Creates a new scenario in `cli/scenarios/{scenario-name}.rs` for interacting with deployed contracts on livenet.

---

## Step 1 — Gather Requirements

Ask the user for (skip any already provided):

1. **Scenario name** — PascalCase (e.g., `TransferTokens`, `MintNft`)
2. **Description** — one sentence explaining what the scenario does
3. **Which contracts** it interacts with (must already exist in the project)
4. **Arguments** — CLI arguments the scenario accepts:
   - Name, type, description, and whether required or optional
   - Available types: `NamedCLType::U64`, `NamedCLType::U256`, `NamedCLType::Key`, `NamedCLType::String`, etc.

Do not guess which contracts or arguments are needed.

---

## Step 2 — Generate the Scenario

Add to `cli/scenarios/{scenario-name}.rs`:

### Import the contracts used

```rust
use contracts::<module>::ModuleName;
```

### Implement the scenario struct

```rust
/// Description of what this scenario does.
pub struct ScenarioName;

impl Scenario for ScenarioName {
    fn args(&self) -> Vec<CommandArg> {
        vec![
            CommandArg::new("arg_name", "Argument description", NamedCLType::U256).required(),
            CommandArg::new("optional_arg", "Optional arg description", NamedCLType::Key),
        ]
    }

    fn run(
        &self,
        env: &HostEnv,
        container: &DeployedContractsContainer,
        args: Args,
    ) -> Result<(), Error> {
        let mut contract = container.contract_ref::<ModuleName>(env)?;

        // Read arguments
        let value = args.get_single::<U256>("arg_name")?;

        // Set gas for the operation
        env.set_gas(50_000_000);

        // Call contract methods
        contract.try_some_method(&value)?;

        Ok(())
    }
}

impl ScenarioMetadata for ScenarioName {
    const NAME: &'static str = "scenario_name_snake_case";
    const DESCRIPTION: &'static str = "Description of what this scenario does.";
}
```

### Add necessary imports

Ensure these are in the `use` block:

```rust
use odra_cli::{
    scenario::{Args, Error, Scenario, ScenarioMetadata},
    CommandArg,
};
```

### Register in the builder chain

In `cli/cli.rs`:

Import the scenario and add `.scenario(ScenarioName)` to the `OdraCli::new()` builder in `main()`.

---

## Step 3 — Verify

```bash
cargo build -p {{project-name}}-cli
```

---

## Step 4 — Report

Show the user:
- What was added to `cli/cli.rs`
- How to run: deploy contracts first, then `cargo run --bin {{project-name}}_cli -- scenario_name --arg_name value`
