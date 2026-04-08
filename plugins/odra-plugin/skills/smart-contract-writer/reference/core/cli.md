# Odra CLI

The `odra-cli` crate lets you build command-line clients for deployed contracts.
Instead of crafting raw `casper-client` calls, you invoke contract methods by
name with typed arguments.

## Setup

Add to `Cargo.toml`:

```toml
[dependencies]
odra-cli = "2.6.0"

[[bin]]
name = "cli"
path = "bin/cli.rs"
```

## `OdraCli` Builder

Wire up the CLI in `cli/cli.rs`:

```rust
OdraCli::new()
    .about("My project CLI")
    .deploy(ContractsDeployScript)                  // deploy script
    .contract::<MyToken>()                          // expose contract entry points as commands
    .named_contract::<MyToken>("token".to_string()) // expose with custom name
    .scenario(CheckBalance)                         // register a scenario
    .build()
    .run();
```
## DeployScript

Every app needs exactly one deploy script that implements the `DeployScript` trait. It defines how contracts are deployed and initialized.

```rust
use odra_cli::{deploy::DeployScript, DeployedContractsContainer};
use odra::host::HostEnv;

pub struct ContractsDeployScript;

impl DeployScript for ContractsDeployScript {
    fn deploy(
        &self,
        env: &HostEnv,
        container: &mut DeployedContractsContainer,
    ) -> Result<(), odra_cli::deploy::Error> {
        todo!()
    }
}
```

## cspr! Macro

Use `cspr!(amount)` to specify CSPR amounts in a human-friendly way. It converts to motes under the hood.

```rust
use odra_cli::cspr;

// Attach 1.5 CSPR to a call
env.set_gas(cspr!(1.5));
```

## `load_or_deploy` Pattern

In your deploy script, use `ContractType::load_or_deploy(env, args, container, gas)`.
On first run it deploys and saves the address. On subsequent runs it loads the existing
contract from `resources/<chain>-contracts.toml`:

```rust
use odra_cli::DeployerExt;

fn deploy(&self, env: &HostEnv, container: &mut DeployedContractsContainer)
    -> Result<(), Error>
{
    let _token = MyToken::load_or_deploy(
        env,
        MyTokenInitArgs {
            name: "My Token".to_string(),
            symbol: "MTK".to_string(),
            decimals: 18,
            initial_supply: Some(1_000_000.into()),
        },
        container,
        cspr!(350),   // gas budget in motes; cspr!(350) = 350 CSPR
    )?;
    Ok(())
}
```

## Writing a Scenario

A scenario is a named set of actions against deployed contracts. Implement both
`Scenario` and `ScenarioMetadata` traits:

```rust
use odra_cli::{
    deploy::DeployScript,
    scenario::{Args, Error, Scenario, ScenarioMetadata},
    CommandArg, ContractProvider, DeployedContractsContainer,
};
use odra::schema::casper_contract_schema::NamedCLType;

pub struct CheckBalanceScenario;

impl Scenario for CheckBalanceScenario {
    fn args(&self) -> Vec<CommandArg> {
        vec![
            CommandArg::new("account", "Account address to check", NamedCLType::Key)
                .required(),
        ]
    }

    fn run(
        &self,
        env: &HostEnv,
        container: &DeployedContractsContainer,
        args: Args,
    ) -> Result<(), Error> {
        let token = container.contract_ref::<MyToken>(env)?;
        let account: Address = args.get_single::<Address>("account")?;
        env.set_gas(50_000_000);
        let balance = token.try_balance_of(&account)?;
        odra_cli::log(format!("Balance: {}", balance));
        Ok(())
    }
}

impl ScenarioMetadata for CheckBalanceScenario {
    const NAME: &'static str = "check-balance";
    const DESCRIPTION: &'static str = "Check the token balance of an account";
}
```

Arguments support `CommandArg::new()`, `.list()` for multi-value, and
`.required()` for mandatory arguments.

## Commands

### `deploy` — deploy contracts

```sh
cargo run --bin cli deploy
```

Runs the deploy script registered via `.deploy(DeployScript)`. Produces a
`resources/contracts.toml` file mapping contract names to package hashes.

| Flag | Description |
|---|---|
| `-c, --contracts-toml <PATH>` | Alternative path for the contracts file |

### `contract` — call a contract method

```sh
cargo run --bin cli contract <CONTRACT_NAME> <METHOD> [OPTIONS]
```

Commands are auto-generated from the contract's public entry points.

| Option | Description |
|---|---|
| `--gas <U64>` | Gas in motes (minimum 2,500,000,000) |
| `--attached_value <U512>` | CSPRs attached to payable calls |
| `-p, --print-events` | Display emitted events after the call |

Example:

```sh
cargo run --bin cli contract DogContract rename --new_name "Doggy" --gas 2500000000
```

### `print-events` — show recent events

```sh
cargo run --bin cli print-events <CONTRACT_NAME>
```

| Option | Description |
|---|---|
| `-n, --number <N>` | Number of events to display (default: 10) |

### `scenario` — run a user-defined scenario

```sh
cargo run --bin cli scenario <SCENARIO_NAME> [ARGS]
```

### `whoami` — show current caller

```sh
cargo run --bin cli whoami
```

Prints the current caller's account address and public key. Automatically
included in every `OdraCli` build.

## Deployment strategies

| Method | Behavior |
|---|---|
| `Contract::try_deploy()` | Deploy every time |
| `Contract::try_deploy_with_cfg()` | Deploy with custom `InstallConfig` |
| `DeployerExt::load_or_deploy()` | Deploy once, then load from `contracts.toml` on subsequent runs |

For upgradeable contracts use `InstallConfig::upgradable::<ContractType>()`.

## Contract file format

Default location: `resources/contracts.toml`

```toml
last_updated = "2025-07-03T10:33:55Z"

[[contracts]]
name = "DogContract"
package_hash = "hash-..."
```

## Environment Variables

Set these before running the CLI binary against a live node. Copy `.env.sample` to `.env`
and fill in your values:

```env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=/path/to/secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=http://localhost:11101
ODRA_CASPER_LIVENET_EVENTS_URL=http://localhost:18101/events/main
ODRA_CASPER_LIVENET_CHAIN_NAME=casper-net-1
```

| Variable | Description |
|---|---|
| `SECRET_KEY_PATH` | Path to PEM file for signing transactions |
| `NODE_ADDRESS` | RPC endpoint of the Casper node |
| `EVENTS_URL` | SSE events endpoint (for waiting on deploys) |
| `CHAIN_NAME` | `casper-net-1` (nctl), `casper-test` (testnet), `casper` (mainnet) |

## Network Differences

| Network | `CHAIN_NAME` | Node setup |
|---|---|---|
| nctl (local) | `casper-net-1` | Docker — use `/start-nctl` skill |
| Testnet | `casper-test` | Public node or self-hosted |
| Mainnet | `casper` | Public node or self-hosted |

Keys for nctl are in `nctl/assets/users/user-1/secret_key.pem` after NCTL starts.