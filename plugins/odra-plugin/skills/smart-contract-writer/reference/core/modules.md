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
odra-modules = "2.6.0"
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

You can nest as many modules as needed — there is no depth limit.

## Why prefer modules over reimplementation

- **Correctness** — battle-tested modules reduce the surface area for bugs.
- **Consistency** — shared modules ensure uniform behavior across contracts.
- **Upgradability** — fixing a module fixes every contract that embeds it.
- **Readability** — a contract that composes `SubModule<Ownable>` and
  `SubModule<Cep18>` communicates intent immediately.

Always look for an existing module first. Rewriting access-control, token, or
ownership logic from scratch is an anti-pattern in Odra.

## Available modules in `odra-modules`

The `odra-modules` crate ships ready-to-use modules. Embed them via
`SubModule<T>` instead of writing your own.

### Access Control

| Module | Description |
|---|---|
| `Ownable` | Single-owner access control. Provides `owner()`, `transfer_ownership()`, and an `only_owner` guard. |
| `AccessControl` | Role-based access control. Define roles and gate entry points by role membership. |

### Security

| Module | Description |
|---|---|
| `Pauseable` | Pause/unpause contract functionality. Use to implement emergency stops. |

### Token Standards — Casper CEPs

| Module | Description |
|---|---|
| `Cep18` | CEP-18 fungible token (the Casper native fungible token standard). |
| `Cep95` | CEP-95 standard. |
| `Cep96` | CEP-96 standard. |

### Token Standards — ERC-compatible

| Module | Description |
|---|---|
| `Erc20` | ERC-20 fungible token. |
| `Erc721` | ERC-721 NFT — base implementation plus extensions and `OwnedErc721WithMetadata`. |
| `Erc721Receiver` | Receiver hook interface for safe ERC-721 transfers. |
| `Erc1155` | ERC-1155 multi-token — base implementation plus extensions and `OwnedErc1155`. |
| `Erc1155Receiver` | Receiver hook interface for safe ERC-1155 transfers. |

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

Because `SubModule` calls are internal (not cross-contract), they do not
require addresses and are cheaper to execute than `External<T>` calls.
