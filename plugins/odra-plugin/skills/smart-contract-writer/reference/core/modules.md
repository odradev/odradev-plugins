# Odra Modules

Odra strongly recommends composing contracts from reusable modules rather than
reimplementing logic. Every `#[odra::module]` struct is simultaneously a
deployable contract and a reusable building block. Before writing new logic,
check whether an existing module (from the project or from `odra-modules`)
already provides the functionality you need.

## Import odra-modules

The `odra-modules` crate provides battle-tested implementations of common patterns and standards. Add it to your `Cargo.toml`:

```toml
[dependencies]
odra-modules = { version = "2.10.0", default-features = false }
```

## Composing modules with `SubModule<T>`

Use the `SubModule` wrapper to nest one module inside another:

```rust
#[odra::module]
pub struct ModulesContract {
    pub math_engine: SubModule<MathEngine>,
}

#[odra::module]
impl ModulesContract {
    pub fn add_using_module(&self) -> u32 {
        self.math_engine.add(3, 5)
    }
}
```

`SubModule` does two things:

| Responsibility | Detail |
|---|---|
| **Keyspace isolation** | Each nested module gets its own storage namespace, preventing key collisions (see `reference/contract-model.md`) |
| **Method access** | The parent calls the child's public methods directly via `self.field_name.method()` |

You can nest as many modules as needed — there is no depth limit. A module's events are collected
recursively, so the parent does not list the events of its submodules in `events = [..]`.

## Why prefer modules over reimplementation

- **Correctness** — battle-tested modules reduce the surface area for bugs.
- **Consistency** — shared modules ensure uniform behavior across contracts.
- **Upgradability** — fixing a module fixes every contract that embeds it.
- **Readability** — a contract that composes `SubModule<Ownable>` and
  `SubModule<Cep18>` communicates intent immediately.

Always look for an existing module first. Rewriting access-control, token, or
ownership logic from scratch is an anti-pattern in Odra.

## Entry points vs plain methods of a module

A module exposes two kinds of functions: the `pub fn`s of its `#[odra::module]` impl block, which
become entry points of every contract that embeds it (or deploys it directly), and `pub fn`s of
plain impl blocks, which exist only in Rust. Since 2.10 `odra-modules` keeps unguarded mutations
in the second group — `Erc20::mint`, `Erc20::burn`, `Ownable::unchecked_transfer_ownership`,
`AccessControl::unchecked_grant_role`, `Cep18::raw_mint`, `Cep95::raw_mint`, the mutating functions
of the `dapp` modules — so a wrapping contract must expose them behind its own check:

```rust
#[odra::module]
impl OwnedToken {
    pub fn mint(&mut self, address: &Address, amount: &U256) {
        self.ownable.assert_owner(&self.env().caller());
        self.erc20.mint(address, amount);
    }
}
```

Follow the same rule in your own modules: unguarded helpers go in a plain impl block.

## Available modules in `odra-modules`

The `odra-modules` crate ships ready-to-use modules. Embed them via
`SubModule<T>` instead of writing your own.

### Access Control (`odra_modules::access`)

| Module | Description |
|---|---|
| `Ownable` | Single-owner access control: `get_owner()`, `transfer_ownership()`, `renounce_ownership()`, and `assert_owner(&addr)` as the guard. `unchecked_transfer_ownership` is a plain method. |
| `Ownable2Step` | Two-step ownership transfer. |
| `AccessControl` | Role-based access control: `has_role`, `grant_role`, `revoke_role`, `check_role(&role, &addr)` as the guard. Bootstrap the first admin with `unchecked_grant_role(&DEFAULT_ADMIN_ROLE, ..)` in `init`. |

### Security (`odra_modules::security`)

| Module | Description |
|---|---|
| `Pauseable` | Pause/unpause contract functionality (`pause`, `unpause`, `require_not_paused`). Use to implement emergency stops. |

### Token Standards — Casper CEPs

| Module | Description |
|---|---|
| `Cep18` (`odra_modules::cep18_token`) | CEP-18 fungible token (the Casper native fungible token standard). `init(symbol, name, decimals, initial_supply)`. |
| `Cep2612` | CEP-18 extension: `permit` — an allowance granted by an off-chain EIP-712 signature (adaptation of ERC-2612). |
| `Cep3009` | CEP-18 extension: `transfer_with_authorization` / `receive_with_authorization` / `cancel_authorization` — gasless transfers by EIP-712 signature (adaptation of ERC-3009). |
| `Cep95` (`odra_modules::cep95`) | CEP-95 NFT standard; see `cep95.md`. |
| `Cep96` | CEP-96 standard. |

### Token Standards — ERC-compatible

| Module | Description |
|---|---|
| `Erc20` | ERC-20 fungible token. `mint`/`burn` are plain methods (not entry points) since 2.10. |
| `Erc721` | ERC-721 NFT — base implementation plus extensions and `OwnedErc721WithMetadata`. |
| `Erc721Receiver` | Receiver hook interface for safe ERC-721 transfers. |
| `Erc1155` | ERC-1155 multi-token — base implementation plus extensions and `OwnedErc1155`. |
| `Erc1155Receiver` | Receiver hook interface for safe ERC-1155 transfers. |

### Dapp (`odra_modules::dapp`, 2.10)

| Item | Description |
|---|---|
| `DappRegistryBase` | Module: stores the dapp metadata and the list of member contracts; verifies each member points back at the registry. |
| `DappContractBase` | Module: stores the registry a contract belongs to; `register_address()`/`register(..)` for a registrar that creates contracts. |
| `OwnedDappRegistry` | Contract, ready to deploy: `DappRegistryBase` guarded by `Ownable`. |
| `DappRegistry`, `DappContract` | External contract traits to call a registry / a member by address. |
| `DappMetadata` | Name, description, website URL, icon URL. |

Neither base module checks the caller; compose with `Ownable` or `AccessControl`. Details and a
full example in `dapp.md`.

### Other

| Module | Description |
|---|---|
| `WrappedNative` | Wrapped native token (WCSPR pattern — wraps the chain's native token into a CEP-18-compatible contract). |

### Composition example

```rust
use odra_modules::access::Ownable;
use odra_modules::cep18_token::Cep18;

#[odra::module]
pub struct OwnedToken {
    ownable: SubModule<Ownable>,
    token: SubModule<Cep18>,
}
```

## Building a module's wasm from your project (2.10)

A contract from `odra-modules` (or any dependency crate) can be built and deployed from your project
without a wrapper, with cargo-odra 0.2.0:

```toml
[[contracts]]
fqn = "odra_modules::erc20::Erc20"
```

The dependency has to be linked into both build binaries, or the wasm has no entry points:

- **Odra 2.11+:** `bin/build_contract.rs` and `bin/build_schema.rs` of a generated project contain
  `odra::link_contract_crates!();`, which links every dependency `Odra.toml` lists a contract of.
  Nothing to edit. Add that line to a project generated for an older Odra. An optional or
  `[target.*]` dependency still needs its own `use`.
- **Odra 2.10:** add `use odra_modules;` to both files, next to the existing `use` line.

`cargo odra build -c Erc20` then writes `wasm/Erc20.wasm` and the schema next to your own contracts.
With cargo-odra 0.2.1 the build fails with an error naming the crate if it was not linked; 0.2.0
only searches the sources for the crate's name, so a mention in a comment passes and the wasm is
saved without entry points.

## Testing modules

Modules are tested the same way as contracts — no special setup required:

```rust
#[test]
fn test_modules() {
    let test_env = odra_test::env();
    let modules_contract = ModulesContract::deploy(&test_env, NoArgs);
    assert_eq!(modules_contract.add_using_module(), 8);
}
```

A module that is not registered in `Odra.toml` has no wasm, so a test deploying it standalone fails
under `cargo odra test -b casper`. Pin such tests to OdraVM with `odra_test::odra_env()`.

Because `SubModule` calls are internal (not cross-contract), they do not
require addresses and are cheaper to execute than `External<T>` calls.
