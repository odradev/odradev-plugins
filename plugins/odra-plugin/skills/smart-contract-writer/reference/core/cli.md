# Odra CLI

The `odra-cli` crate lets you build command-line clients for deployed contracts.
Instead of crafting raw `casper-client` calls, you invoke contract methods by
name with typed arguments. Every generated project has one in `bin/cli.rs` (`cli/cli.rs` in a
workspace), built as the `<project>_cli` binary.

## Setup

A generated project already has this. By hand, add to `Cargo.toml` (outside wasm — `odra-cli`
brings the livenet backend with it, no `livenet` feature is needed):

```toml
[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
odra-cli = { version = "2.10.0", default-features = false }

[[bin]]
name = "my_project_cli"
path = "bin/cli.rs"
test = false
```

Run it with `cargo run --bin my_project_cli -- <command>`. The examples below write `odra_cli`
for the binary name.

## `OdraCli` Builder

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

Every app needs exactly one deploy script that implements the `DeployScript` trait. It defines how
contracts are deployed and initialized.

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

`cspr!(amount)` converts CSPR to motes. With a literal it is a constant expression
(`cspr!(350)` is `350_000_000_000`, `cspr!(2.5)` is `2_500_000_000`), so it can initialise a
`const`:

```rust
use odra_cli::cspr;

const DEPLOY_GAS: u64 = cspr!(350);
env.set_gas(cspr!(1.5));
```

## `load_or_deploy` Pattern

In your deploy script, use `ContractType::load_or_deploy(env, args, container, gas)`.
On first run it deploys (upgradable) and saves the address. On subsequent runs it loads the existing
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

## Loading a deployed contract elsewhere

Outside a deploy script — a plain livenet binary, a scenario that needs a contract the container
does not hold — `ContractLoaderExt` (2.10) reads the same file, so no package hash is pasted around:

```rust
use odra_cli::ContractLoaderExt;

// resources/contracts.toml, or resources/<chain>-contracts.toml when ODRA_CASPER_LIVENET_CHAIN_NAME is set
let token = MyToken::load_from_default_file(&env)?;
// any file, relative to the project root
let token = MyToken::load_from_file(&env, "resources/casper-test-contracts.toml")?;
// a contract registered under a custom name
let token = MyToken::load_from_file_named(&env, "resources/contracts.toml", Some("token-2".into()))?;
```

A missing or malformed file is an error, as is a contract that is not in it.

## Writing a Scenario

A scenario is a named set of actions against deployed contracts. Implement both
`Scenario` and `ScenarioMetadata` traits:

```rust
use odra_cli::{
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

Arguments support `CommandArg::new()`, `.list()` for multi-value, and `.required()` for mandatory
arguments. Prefer returning a `scenario::Error` over `assert!`: a returned error is reported as a
failed command, a panic tears the CLI down.

### Events in a scenario

A scenario does not capture events by default (on livenet that would cost node requests after
every call), so `last_call()` of a call made in a scenario has no events. Opt in per scenario:

```rust
impl Scenario for RenameScenario {
    fn captures_events(&self) -> bool { true }

    fn run(&self, env: &HostEnv, container: &DeployedContractsContainer, args: Args) -> Result<(), Error> {
        let mut dog = container.contract_ref::<DogContract>(env)?;
        dog.try_rename(args.get_single::<String>("name")?)?;
        if !dog.last_call().emitted("NameChanged") {
            return Err(Error::OdraError { message: "no NameChanged event".to_string() });
        }
        Ok(())
    }
}
```

## Commands

Besides `deploy`, `contract` and `scenario`, which you register yourself, every CLI gets these
built in:

| Command | What it does |
|---|---|
| `deploy` | runs the deploy script; writes `resources/<chain>-contracts.toml` |
| `contract <Name> <method> [--arg v..] [--gas ..]` | calls an entry point (also `new_contract` / `upgrade_child_contract` of a factory); `#[odra(offchain)]` functions are listed too and take no `--gas` |
| `scenario <name> [--arg v..]` | runs a registered scenario |
| `upgrade <Name> --gas .. [--upgrade args]` | upgrades the contract from the contracts file with `wasm/<Name>.wasm`, calling its `upgrade` entry point (2.10) |
| `upgrade-children <Factory> --gas .. [--upgrade args] [--batch-size N]` | upgrades every child of a factory with the factory's current code, one transaction per batch (2.10) |
| `status` | lists deployed contracts and their registration status |
| `inspect <Name>` | prints the entry points, arguments and types of a contract |
| `storage <Name> [<dotted.path>] [--key k..]` | reads the storage of a contract without calling it; without a path prints the storage layout (2.10) |
| `print-events <Name> [-n N]` | the most recent events of a contract |
| `transfer --to <addr> --amount <cspr>` | native CSPR transfer from the caller |
| `whoami` | the caller's account address and public key |
| `config` | the resolved livenet configuration; never prompts, shows what is missing |
| `completions <shell>` | shell completion script |
| `repl` | interactive session that keeps the host environment warm |

Global options:

| Option | Description |
|---|---|
| `-c, --contracts-toml <PATH>` | alternative contracts file, relative to the project root |
| `--json` | machine-readable output for read commands; errors and progress stay plain text, so parse the last JSON object in stdout |
| `--state-root-hash <HEX>` | answer every read from the chain state at that root; `deploy`, `transfer` and mutating calls fail while it is set (2.10) |

`contract` call options: `--gas <motes or 'X.Y cspr'>` (also `400cspr`), `--attached_value <U512>`
for payable entry points, `-p, --print-events`.

Examples:

```sh
cargo run --bin odra_cli -- contract DogContract rename --new_name "Doggy" --gas 2500000000
cargo run --bin odra_cli -- upgrade DogContract --gas 400cspr
cargo run --bin odra_cli -- upgrade-children CounterFactory --new_value 42 --gas 900cspr --batch-size 10
cargo run --bin odra_cli -- storage DogContract name
cargo run --bin odra_cli -- --state-root-hash <hex> contract DogContract name
```

`--help` (of any subcommand), `--version`, `completions` and `config` work without a livenet
configuration; the network commands ask for a missing `ODRA_CASPER_LIVENET_*` value and retry.

### `upgrade` options

They map to the fields of `UpgradeConfig`: `--force-create-upgrade-group` (contracts deployed with
Odra 2.2 or earlier, or not with Odra at all), `--allow-key-override [BOOL]` (default true),
`--package-named-key <NAME>` (default: the contract's name, or the `named_contract` name). The
package hash does not change, so the contracts file stays as it is. `upgrade` is no longer listed
among the entry points of the `contract` command.

## Deployment strategies

| Method | Behavior |
|---|---|
| `Contract::try_deploy()` | Deploy every time |
| `Contract::try_deploy_with_cfg()` | Deploy with custom `InstallConfig` |
| `Contract::try_upgrade(env, address, args)` | Upgrade a deployed, upgradable contract |
| `Contract::try_upgrade_with_runtime_args(..)` | Same, with upgrade arguments composed at runtime (2.10) |
| `DeployerExt::load_or_deploy()` | Deploy once (upgradable), then load from the contracts file on subsequent runs |

For upgradeable contracts use `InstallConfig::upgradable::<ContractType>()`. Since 2.10,
`#[odra::module(name = "..")]` also names the key the package hash is stored under
(`<name>_package_hash`).

## Contract file format

Default location: `resources/contracts.toml`, or `resources/<chain>-contracts.toml` when
`ODRA_CASPER_LIVENET_CHAIN_NAME` is set, so networks never overwrite each other.

```toml
last_updated = "2025-07-03T10:33:55Z"

[[contracts]]
name = "DogContract"
package_hash = "hash-..."
```

## Environment Variables

The livenet backend reads them from the process environment, from `<name>.env` when
`ODRA_CASPER_LIVENET_ENV=<name>` is set, and from `.env` for anything still missing. A generated
project ships `.env.sample` preset for a local NCTL node; `.gitignore` covers `.env`, `*.env` and
`secret_key*.pem`.

```env
ODRA_CASPER_LIVENET_SECRET_KEY_PATH=secret_key.pem
ODRA_CASPER_LIVENET_NODE_ADDRESS=http://localhost:11101
ODRA_CASPER_LIVENET_EVENTS_URL=http://localhost:18101/events
ODRA_CASPER_LIVENET_CHAIN_NAME=casper-net-1
# optional
# ODRA_CASPER_LIVENET_KEY_1=secret_key_1.pem      # env.get_account(1), _2 for (2), ...
# CSPR_CLOUD_AUTH_TOKEN=
# ODRA_LOG_LEVEL=info                              # none, error, warn, info, debug
# ODRA_CASPER_LIVENET_STATE_ROOT_HASH=             # pin every read to a past state; refuses transactions
# ODRA_MAX_THREADS=8                               # worker threads of HostEnv::concurrently
```

| Variable | Description |
|---|---|
| `SECRET_KEY_PATH` | Path to PEM file for signing transactions (account 0) |
| `NODE_ADDRESS` | RPC endpoint of the Casper node |
| `EVENTS_URL` | SSE events endpoint (for waiting on deploys) |
| `CHAIN_NAME` | `casper-net-1` (nctl), `casper-test` (testnet), `casper` (mainnet) |

## Network Differences

| Network | `CHAIN_NAME` | Node |
|---|---|---|
| nctl (local) | `casper-net-1` | Docker, `http://localhost:11101` — use `/odra-plugin:setup-nctl` |
| Testnet | `casper-test` | `https://node.testnet.cspr.cloud` or a peer |
| Mainnet | `casper` | `https://node.cspr.cloud` or a peer |

The plugin's `setup-nctl` skill extracts the NCTL keys to `.node-keys/secret_key.pem` (user-1) and
`.node-keys/secret_key_1.pem` (user-2) and writes `nctl.env`.

## Livenet behaviour worth knowing (2.10)

- A deploy or upgrade whose `init`/`upgrade` reverts returns the contract's own error, as in tests;
  out of gas is `OutOfGas`. `ContractDeploymentError` is left for a deployment that never ran
  (wasm not found, gas not set, node unreachable).
- Errors are named from the schemas in `resources/casper_contract_schemas/` (the called contract's
  schema first) — keep them current with `cargo odra schema`.
- Getters and `#[odra(offchain)]` functions run locally against the chain state; a revert comes
  back from `try_*` as `Err`.
- `env.gas_report()` and `env.last_call_gas_cost()` work; reads are cached per state root hash and
  retried with backoff on HTTP 429.
