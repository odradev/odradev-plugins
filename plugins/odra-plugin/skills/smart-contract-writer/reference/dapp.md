# Dapp Registry (`odra_modules::dapp`, Odra 2.10)

A dapp on Casper is usually more than one contract: a token, a vault, a governance contract, a few
contracts deployed later by a factory. Wallets and explorers see them as unrelated package hashes.
The `dapp` modules group them: a **registry** contract describes the dapp and lists the contracts
that belong to it, and every **member** contract points back to its registry, so membership can be
verified from both sides.

## Overview

| Item | Kind | Purpose |
|---|---|---|
| `DappRegistryBase` | module | Stores the dapp metadata and the list of member contracts. |
| `DappContractBase` | module | Stores the address of the registry a contract belongs to. |
| `OwnedDappRegistry` | contract | A ready-to-deploy registry: `DappRegistryBase` guarded by `Ownable`. |
| `DappRegistry` | external contract trait | The registry interface (`DappRegistryContractRef`), to call a registry by address. |
| `DappContract` | external contract trait | The member interface, to call a member by address. |
| `DappMetadata` | type | `name`, `description`, `website_url`, `icon_url` of the dapp. |

The registry always belongs to the dapp: `get_dapp_contracts` returns it first and
`is_dapp_contract` is `true` for its own address. A contract belongs to at most one dapp.

### Verification

When a contract is added, the registry calls `get_dapp_registry` on it and reverts with
`DappRegistryMismatch` unless the contract returns the registry's address. Every member must
therefore expose a `get_dapp_registry` entry point (delegate it from `DappContractBase`). Adding an
account address reverts with `NotAContract`.

### Registrars

A contract added with `is_registrar = true` may add other contracts — typically a contract that
creates contracts through a factory. `OwnedDappRegistry` lets the owner add any contract, and a
registrar add contracts that are not registrars themselves. Removing a contract also removes its
registrar permission.

### Authorization

`DappRegistryBase` and `DappContractBase` do not check who calls them. Their read-only functions
are entry points; the functions that change state (`set_dapp_metadata`, `add_dapp_contract`,
`remove_dapp_contract`, `set_dapp_registry`) are plain Rust methods. The contract that composes the
module decides who may call them — `Ownable`, `AccessControl` or its own rules. A contract composing
`DappRegistryBase` calls its `init`.

### Storage

The dapp data of a contract lives in one dictionary under the `__dapp` named key, every item a
whole value (`__dapp->registry`, `__dapp->name`, the `__dapp->contracts` and `__dapp->registrars`
lists, ...), so it is readable from the chain without calling the contracts.

## Deploying a registry

`OwnedDappRegistry` is the quickest way to start. The deployer becomes the owner.

```rust
use odra::host::{Deployer, HostRef, NoArgs};
use odra_modules::dapp::{DappMetadata, OwnedDappRegistry};

let mut registry = OwnedDappRegistry::deploy(&env, NoArgs);
registry.set_dapp_metadata(DappMetadata {
    name: "My Dapp".to_string(),
    description: "Lending on Casper".to_string(),
    website_url: "https://mydapp.io".to_string(),
    icon_url: "https://mydapp.io/icon.png".to_string()
});
```

Its entry points:

- `set_dapp_metadata`, `remove_dapp_contract`: owner only.
- `add_dapp_contract(&address, is_registrar)`: the owner, or a registrar adding a non-registrar.
- `get_dapp_metadata`, `get_dapp_contracts`, `is_dapp_contract`, `is_dapp_registrar`, `get_dapp_registry`.
- `get_owner`, `transfer_ownership`, `renounce_ownership` from `Ownable`.

## Writing a member contract

Compose `DappContractBase`, set the registry in `init`, delegate `get_dapp_registry` so the registry
can verify the contract. Exposing `set_dapp_registry` is optional; if you do, guard it.

```rust
use odra::prelude::*;
use odra_modules::access::Ownable;
use odra_modules::dapp::DappContractBase;

#[odra::module]
pub struct Vault {
    ownable: SubModule<Ownable>,
    dapp: SubModule<DappContractBase>
}

#[odra::module]
impl Vault {
    pub fn init(&mut self, registry: Address) {
        let owner = self.env().caller();
        self.ownable.init(owner);
        self.dapp.set_dapp_registry(&registry);
    }

    pub fn set_dapp_registry(&mut self, registry: &Address) {
        self.ownable.assert_owner(&self.env().caller());
        self.dapp.set_dapp_registry(registry);
    }

    delegate! {
        to self.dapp {
            fn get_dapp_registry(&self) -> Address;
        }
    }
}
```

Then deploy the member with the registry address and add it:

```rust
let vault = Vault::deploy(&env, VaultInitArgs { registry: registry.address() });
registry.add_dapp_contract(&vault.address(), false);

assert_eq!(registry.get_dapp_contracts(), vec![registry.address(), vault.address()]);
```

## Building your own registry

To use other rules than a single owner, compose `DappRegistryBase` with another access module:

```rust
use odra::prelude::*;
use odra_modules::access::{AccessControl, Role, DEFAULT_ADMIN_ROLE};
use odra_modules::dapp::{DappMetadata, DappRegistryBase};

pub const CURATOR_ROLE: Role = [1u8; 32];

#[odra::module]
pub struct CuratedDappRegistry {
    access_control: SubModule<AccessControl>,
    dapp: SubModule<DappRegistryBase>
}

#[odra::module]
impl CuratedDappRegistry {
    pub fn init(&mut self, metadata: DappMetadata) {
        let admin = self.env().caller();
        self.access_control.unchecked_grant_role(&DEFAULT_ADMIN_ROLE, &admin);
        self.access_control.unchecked_grant_role(&CURATOR_ROLE, &admin);
        self.dapp.init();
        self.dapp.set_dapp_metadata(metadata);
    }

    pub fn add_dapp_contract(&mut self, dapp_contract: &Address, is_registrar: bool) {
        self.access_control.check_role(&CURATOR_ROLE, &self.env().caller());
        self.dapp.add_dapp_contract(dapp_contract, is_registrar);
    }

    pub fn remove_dapp_contract(&mut self, dapp_contract: &Address) {
        self.access_control.check_role(&CURATOR_ROLE, &self.env().caller());
        self.dapp.remove_dapp_contract(dapp_contract);
    }

    delegate! {
        to self.dapp {
            fn get_dapp_metadata(&self) -> DappMetadata;
            fn get_dapp_contracts(&self) -> Vec<Address>;
            fn is_dapp_contract(&self, dapp_contract: &Address) -> bool;
            fn is_dapp_registrar(&self, dapp_contract: &Address) -> bool;
            fn get_dapp_registry(&self) -> Address;
        }
    }
}
```

To let registrars add contracts to such a registry, call `self.dapp.assert_dapp_registrar(&caller)`
for callers without the role, as `OwnedDappRegistry` does.

## Registering contracts created through a factory

A contract that creates contracts (see `factory.md`) can add them to the dapp right away, once the
registry lists it as a registrar. `DappContractBase` has two helpers for it: `register_address()`
returns the registry address to pass to the child's `init`, and `register(address)` adds the child
to the registry (reverting with `CallerNotDappRegistrar` if the caller is not one). From
`examples/src/factory/dapp.rs`:

```rust
use odra::{prelude::*, ContractRef};
use odra_modules::dapp::DappContractBase;

#[odra::module(factory=on)]
pub struct DappCounter {
    dapp: SubModule<DappContractBase>,
    value: Var<u32>
}

#[odra::module(factory=on)]
impl DappCounter {
    pub fn init(&mut self, registry: Address) {
        self.dapp.set_dapp_registry(&registry);
    }
    pub fn increment(&mut self) { self.value.add(1); }
    pub fn value(&self) -> u32 { self.value.get_or_default() }
    delegate! { to self.dapp { fn get_dapp_registry(&self) -> Address; } }
}

#[odra::module]
pub struct DappCounterSpawner {
    dapp: SubModule<DappContractBase>,
    factory: Var<Address>,
    spawned: Var<u32>
}

#[odra::module]
impl DappCounterSpawner {
    pub fn init(&mut self, registry: Address, factory: Address) {
        self.dapp.set_dapp_registry(&registry);
        self.factory.set(factory);
    }

    delegate! { to self.dapp { fn get_dapp_registry(&self) -> Address; } }

    /// The spawner must be registered in the dapp as a registrar.
    pub fn spawn(&mut self) -> Address {
        let factory = self.factory.get().unwrap_or_revert(self);
        let n = self.spawned.get_or_default();
        let mut factory = DappCounterFactoryContractRef::new(self.env(), factory);
        // The name keys the child in the factory, so each child gets its own.
        let (address, _) =
            factory.new_contract(format!("DappCounter{}", n), self.dapp.register_address());
        self.spawned.set(n + 1);
        self.dapp.register(address);
        address
    }
}
```

```rust
let mut registry = OwnedDappRegistry::deploy(&env, NoArgs);
let factory = DappCounterFactory::deploy(&env, NoArgs);
let mut spawner = DappCounterSpawner::deploy(&env, DappCounterSpawnerInitArgs {
    registry: registry.address(),
    factory: factory.address()
});

assert_eq!(spawner.try_spawn(), Err(Error::CallerNotDappRegistrar.into())); // not a registrar yet
registry.add_dapp_contract(&spawner.address(), true);
let first = spawner.spawn();
assert_eq!(registry.get_dapp_contracts(), vec![registry.address(), spawner.address(), first]);
```

Register `DappCounter`, `DappCounterFactory` and `DappCounterSpawner` in `Odra.toml`. The test runs
on OdraVM and CasperVM alike.

## Retrofitting dapp support to deployed contracts

"Add dapp support to our contracts" usually arrives after the contracts are live. Verified recipe
(Odra 2.10, cargo-odra 0.2.0):

1. **Check that the contracts can be upgraded.** Read the deploy script: `load_or_deploy` or
   `try_deploy` without `InstallConfig::upgradable` installed a *locked* package, which cannot be
   upgraded (`A locked contract cannot be upgraded`); the only option is a redeploy under a new
   address — say so before writing any `upgrade`. Switch the script to `load_or_deploy_with_cfg`
   with `InstallConfig::upgradable::<T>()` so the next deployment is upgradable.
2. **Add the members' fields and an `upgrade`.** Append the new submodules *after* the existing
   fields (storage is addressed by position); `upgrade` bootstraps them. The upgrader is the account
   holding the upgrade rights, so it is a sound first owner:

   ```rust
   #[odra::module]
   pub struct Counter {
       value: Var<u32>,                      // existing
       ownable: SubModule<Ownable>,          // appended
       dapp: SubModule<DappContractBase>,    // appended
   }

   #[odra::module]
   impl Counter {
       pub fn init(&mut self, start: u32) {  // unchanged signature: fresh deploys still work
           self.value.set(start);
           self.ownable.init(self.env().caller());
       }

       /// Runs once, during the upgrade: `upgrade Counter --registry <hash> --gas ..`
       pub fn upgrade(&mut self, registry: Address) {
           self.ownable.init(self.env().caller());
           self.dapp.set_dapp_registry(&registry);
       }

       pub fn set_dapp_registry(&mut self, registry: &Address) {
           self.ownable.assert_owner(&self.env().caller());
           self.dapp.set_dapp_registry(registry);
       }

       delegate! {
           to self.dapp { fn get_dapp_registry(&self) -> Address; }
           to self.ownable { fn get_owner(&self) -> Address; }
       }
       // ... existing entry points ...
   }
   ```
3. **Build the registry from `odra-modules`.** `odra-modules` in `Cargo.toml`,
   `fqn = "odra_modules::dapp::OwnedDappRegistry"` in `Odra.toml`, and `use odra_modules;` in both
   `bin/build_contract.rs` and `bin/build_schema.rs`. Deploy it from the deploy script
   (`OwnedDappRegistry::load_or_deploy_with_cfg(env, None, NoArgs, InstallConfig::upgradable::<OwnedDappRegistry>(), container, cspr!(350))`)
   and register it in the CLI (`.contract::<OwnedDappRegistry>()`, named `OwnedDappRegistry`).
4. **Registration scenario.** `add_dapp_contract` can only be called after each member runs the new
   code (the registry calls the member's `get_dapp_registry`), so it cannot be part of `deploy`.
   Write an idempotent scenario: `container.contract_ref::<OwnedDappRegistry>(env)?`, set the
   metadata, then `try_add_dapp_contract(&member.address(), false)` for every member that is not yet
   `is_dapp_contract`.
5. **Test** with `deploy_with_cfg(.., InstallConfig::upgradable)` + `try_upgrade` (see `testing.md`).

Runbook for the user (binary `<project>_cli`, NCTL config selected with `ODRA_CASPER_LIVENET_ENV`):

```sh
cargo odra build                                   # new wasm for the members and the registry
cargo run --bin my_project_cli -- deploy           # loads the members, deploys OwnedDappRegistry
cargo run --bin my_project_cli -- status           # copy the OwnedDappRegistry package hash
cargo run --bin my_project_cli -- upgrade Flipper --registry hash-… --gas 400cspr
cargo run --bin my_project_cli -- upgrade Counter --registry hash-… --gas 400cspr
cargo run --bin my_project_cli -- scenario register-dapp --name "My Dapp"
cargo run --bin my_project_cli -- contract OwnedDappRegistry get_dapp_contracts
```

Run the upgrades as the account that installed the contracts. The registry hash is copied by hand
from `status` or `resources/<chain>-contracts.toml`; there is no automatic handoff into `upgrade`.
Storage of the members survives (`Counter.get` still returns the old value), their package hashes do
not change.

## Events and errors

| Event | Emitted by | Fields |
|---|---|---|
| `DappMetadataChanged` | registry | `name`, `description`, `website_url`, `icon_url` |
| `DappContractAdded` | registry | `contract`, `is_registrar`, `registrar` (the caller) |
| `DappContractRemoved` | registry | `contract`, `registrar` |
| `DappRegistryChanged` | member | `previous_registry: Option<Address>`, `new_registry` |

Errors (`odra_modules::dapp::errors::Error`):

| Error | Code | When |
|---|---|---|
| `NotAContract` | 22000 | An account address is added, or set as a registry. |
| `DappContractAlreadyRegistered` | 22001 | The contract, or the registry itself, is already in the dapp. |
| `DappContractNotRegistered` | 22002 | Removing a contract that is not in the dapp. |
| `DappRegistryMismatch` | 22003 | The contract's `get_dapp_registry` returns a different address. |
| `CallerNotDappRegistrar` | 22004 | A contract that is not a registrar tries to add a contract. |
| `DappRegistryNotSet` | 22005 | `get_dapp_registry` on a member before its registry is set. |
| `CannotRemoveDappRegistry` | 22006 | Removing the registry itself. |

## Things to know

- Removing a contract moves the last contract into its place, so the order of `get_dapp_contracts`
  changes.
- `get_dapp_contracts` reads every member from storage. For a dapp with many contracts, prefer
  `is_dapp_contract` in contract code — or an `#[odra(offchain)]` function for reports.
- The events keep their fields: an upgrade cannot change the schema of an event a contract already
  emits.
