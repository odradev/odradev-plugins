# Odra Factory Pattern

The factory pattern enables a contract to deploy, manage, and track child contract instances
on-chain. The parent contract acts as a centralized registry for all child contracts it creates.
Since Odra 2.10 factories work on OdraVM as well as on CasperVM and livenet.

## Enabling Factory Support

Add `factory=on` to the `#[odra::module]` attribute on both the struct and impl block
of the **child** contract (the contract that will be deployed by the factory). It is the only
module argument allowed on an impl block:

```rust
use odra::prelude::*;

#[odra::module(factory=on)]
pub struct Counter {
    value: Var<u32>,
}

#[odra::module(factory=on)]
impl Counter {
    pub fn init(&mut self, value: u32) {
        self.value.set(value);
    }

    pub fn increment(&mut self) {
        self.value.set(self.value.get_or_default() + 1);
    }

    pub fn value(&self) -> u32 {
        self.value.get_or_default()
    }
}
```

## What `factory=on` Generates

For a contract named `Counter`, the macro generates a `CounterFactory` module with these
entry points and nothing else:

| Entry point | Description |
|---|---|
| `new_contract(contract_name: String, ...init_args) -> (Address, URef)` | Deploys a child. The name keys the child in the factory, so each child needs its own. Returns the child's address and its access URef. |
| `upgrade_child_contract(contract_name: String, ...upgrade_args)` | Upgrades one child to the factory's current code, calling the child's `upgrade` with the given arguments. |
| `batch_upgrade_child_contract(args: BTreeMap<String, T>) where T: Into<RuntimeArgs>` | Upgrades several children in one transaction; the map goes from child name to its `<Child>UpgradeArgs`. |

It also generates the event `CounterFactoryContractDeployed { contract_address, contract_name }`,
emitted on every `new_contract`. The children of a factory are exactly the contracts named in
these events — that is how odra-cli's `upgrade-children` finds them.

The factory is itself a regular contract — deploy it with `NoArgs`, and register **both** the
child and the factory in `Odra.toml`, otherwise their wasm files are never built:

```toml
[[contracts]]
fqn = "counter::Counter"

[[contracts]]
fqn = "counter::CounterFactory"
```

Only the account that installed the factory may upgrade its children (on OdraVM: the direct caller
must be the factory's deployer).

## Deploying Child Contracts

```rust
let (address, _access_uref) = factory_ref.new_contract(String::from("Counter"), 10);
```

Interact with the child through a `HostRef` built from the address (`HostRef::new` takes the
`HostEnv` by value, so clone it) — this registers the child with the environment, so its events and
offchain functions work too:

```rust
let mut counter_ref = CounterHostRef::new(address, env.clone());
counter_ref.increment();
assert_eq!(counter_ref.value(), 11);
```

From another contract, call the factory through its `ContractRef`
(`CounterFactoryContractRef::new(self.env(), factory_address).new_contract(name, 10)`); see
`dapp.md` for a spawner that also registers each child in a dapp.

## Testing a Factory

Runs on both backends: `cargo odra test` and `cargo odra test -b casper`.

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use odra::host::{Deployer, HostRef, NoArgs};

    #[test]
    fn test_factory() {
        let env = odra_test::env();
        let mut factory_ref = CounterFactory::deploy(&env, NoArgs);

        let (address, _access_uref) = factory_ref.new_contract(String::from("Counter"), 10);
        assert!(env.emitted_event(
            &factory_ref,
            CounterFactoryContractDeployed {
                contract_address: address,
                contract_name: String::from("Counter")
            }
        ));

        let mut counter_ref = CounterHostRef::new(address, env.clone());
        counter_ref.increment();
        assert_eq!(counter_ref.value(), 11);
    }
}
```

OdraVM mimics Casper: a child's `init` and `upgrade` see the caller of the factory as their caller,
the children's events are tracked, and a child whose `init` or `upgrade` reverts leaves nothing
behind. Still simplified on OdraVM: the access URef is a stand-in derived from the child's address,
the upgrade permission check compares the direct caller with the factory's deployer, and a factory
opened with `HostRefLoader::load` has no recorded deployer, so its children cannot be upgraded there.

## Upgrading Child Contracts

The children run the factory's code, so to upgrade them: deploy the factory upgradable, upgrade the
factory to the new version, then upgrade the children. The new child version implements `upgrade`:

```rust
#[odra::module(factory=on)]
pub struct CounterV2 { value: Var<u32> }

#[odra::module(factory=on)]
impl CounterV2 {
    // ... v1 methods ...
    pub fn upgrade(&mut self, new_value: u32) {
        self.value.set(new_value);
    }
}
```

```rust
use odra::host::{Deployer, HostRef, InstallConfig, NoArgs};

let mut factory = CounterFactory::deploy_with_cfg(&env, NoArgs, InstallConfig::upgradable::<CounterFactory>());
let (ten, _) = factory.new_contract(String::from("FromTen"), 10);
let (two, _) = factory.new_contract(String::from("FromTwo"), 2);

// Upgrade the factory itself
let mut factory = CounterV2Factory::try_upgrade(&env, factory.address(), NoArgs).unwrap();

// One child
factory.upgrade_child_contract(String::from("FromTen"), 122);

// Several children in one transaction
let args: BTreeMap<_, _> = [("FromTwo", 42u32)]
    .into_iter()
    .map(|(name, new_value)| (name.to_string(), CounterV2UpgradeArgs { new_value }))
    .collect();
factory.batch_upgrade_child_contract(args);

assert_eq!(CounterHostRef::new(ten, env.clone()).value(), 122);
```

Native event counts carry on across the upgrade of a child (2.10).

## From the CLI (odra-cli, 2.10)

With the factory registered in `bin/cli.rs` (`.contract::<CounterFactory>()`):

```sh
# one child, through the factory's entry points
cargo run --bin odra_cli -- contract CounterFactory new_contract --contract_name A --value 1 --gas 270cspr
cargo run --bin odra_cli -- contract CounterFactory upgrade_child_contract --contract_name A --new_value 5 --gas 300cspr

# the factory, then every child in one transaction (or --batch-size N per transaction)
cargo run --bin odra_cli -- upgrade CounterFactory --gas 500cspr
cargo run --bin odra_cli -- upgrade-children CounterFactory --new_value 42 --gas 900cspr
```

The `contract` command passes the `odra_cfg_*` arguments a factory expects on its own;
`batch_upgrade_child_contract`, whose arguments the schema cannot describe, is what
`upgrade-children` wraps.

## When to Use the Factory Pattern

- You need a contract that spawns multiple instances of another contract at runtime
- You want a centralized registry tracking all deployed child contracts
- You need to upgrade child contracts from the parent
- Combine with the `dapp` modules (`dapp.md`) when the children should be listed as members of a dapp
