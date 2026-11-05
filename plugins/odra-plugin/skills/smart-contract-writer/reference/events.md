# Odra Events

## Defining an Event

Apply `#[odra::event]` to a public struct. All fields must implement `CLTyped`:

```rust
#[odra::event]
pub struct Transfer {
    pub from: Address,
    pub to: Address,
    pub amount: U256,
}

#[odra::event]
pub struct Approval {
    pub owner: Address,
    pub spender: Address,
    pub amount: U256,
}
```

## Registering Events on the Module

List emitted events in the module attribute for schema generation:

```rust
#[odra::module(events = [Transfer, Approval])]
pub struct Token { ... }
```

## Emitting Events

Inside an entry point, use `self.env().emit_event(...)`:

```rust
pub fn transfer(&mut self, to: Address, amount: U256) {
    // ... update balances ...
    self.env().emit_event(Transfer {
        from: self.env().caller(),
        to,
        amount,
    });
}
```

## Field types

The fields of an event must have a concrete `CLType`: numbers, `bool`, `String`, `Address`, `U256`
and the like, a unit enum (an `#[odra::odra_type]` enum without data, serialized as `u8`), and
`Option`, `Vec`, maps, `Result` and tuples of those. An `#[odra::odra_type]` struct or an enum with
data has the `CLType` `Any`, which the Casper Event Standard rejects — also inside an `Option`, a
`Vec` or a tuple. Since 2.10 Odra refuses such a contract early: deploying or upgrading it (any
backend) and `cargo odra schema` panic with a message naming the event and the field. Flatten the
struct into the event:

```rust
#[odra::odra_type]
pub enum Side { Buy, Sell } // a unit enum is fine

#[odra::event]
pub struct Traded {
    pub side: Side,
    // not `pub price: Price` with `#[odra::odra_type] struct Price { amount, currency }`
    pub price_amount: U256,
    pub price_currency: String,
}
```

An upgrade cannot change the schema of an event the contract already emits; add a new event.

## Native Events (Casper 2.0 messages)

`emit_event` writes a Casper Event Standard (CES) event into the contract's state, where any
client can read event number N at any time. `emit_native_event` emits a Casper native message
instead:

```rust
self.env().emit_native_event(Transfer { from, to, amount });
```

A native message's payload travels only in the execution result of the transaction that emitted it;
the chain keeps no readable list of past messages. On livenet the environment records the native
events of the transactions it sends, so `native_events_count`, `get_native_event`,
`emitted_native_event` and `last_call().emitted_native_events` answer from that record — events
emitted before the environment was created, or by someone else, are not visible. Most contracts use
`emit_event`; use native events when an indexer or the sidecar is the consumer.

## Asserting Events in Tests

Use `env.emitted_event(&contract_ref, event_value)` to assert a specific event
was emitted. Struct fields can be partially matched:

```rust
assert!(env.emitted_event(
    &token,
    Transfer {
        from: env.get_account(0),
        to: env.get_account(1),
        amount: 100.into(),
    }
));
```

Check if any event with a given name was emitted (without checking fields):

```rust
assert!(env.emitted(&token, "Transfer"));
```

Count total events emitted by a contract since last check:

```rust
assert_eq!(env.events_count(&token), 1);
```

For native events:

```rust
assert!(env.emitted_native_event(&token, Transfer { ... }));
assert!(env.emitted_native(&token, "Transfer"));
assert_eq!(env.native_events_count(&token), 1);
```

Native event counts carry on across an upgrade of the contract (also of a factory child).

Events of the **last call only**, through the `HostRef`:

```rust
token.transfer(&bob, &amount);
assert!(token.last_call().emitted("Transfer"));
assert!(token.last_call().emitted_event(Transfer { .. }));
```

The events of a reverted call are gone on every backend (OdraVM rolls them back since 2.10), and
`last_call()` of the first call after `deploy` no longer includes the events of `init`.

In an odra-cli scenario `last_call()` has no events unless the scenario overrides
`captures_events()` to return `true` (see `core/cli.md`).

## Complete Example

```rust
#[odra::event]
pub struct NameChanged {
    pub old_name: String,
    pub new_name: String,
}

#[odra::module(events = [NameChanged])]
pub struct Registry {
    name: Var<String>,
}

#[odra::module]
impl Registry {
    pub fn init(&mut self, name: String) {
        self.name.set(name);
    }

    pub fn rename(&mut self, new_name: String) {
        let old_name = self.name.get_or_default();
        self.name.set(new_name.clone());
        self.env().emit_event(NameChanged { old_name, new_name });
    }
}

#[cfg(test)]
mod tests {
    use super::{NameChanged, Registry, RegistryInitArgs};
    use odra::host::Deployer;

    #[test]
    fn test_rename_emits_event() {
        let env = odra_test::env();
        let mut registry = Registry::deploy(&env, RegistryInitArgs {
            name: "Alice".to_string(),
        });
        registry.rename("Bob".to_string());
        assert!(env.emitted_event(&registry, NameChanged {
            old_name: "Alice".to_string(),
            new_name: "Bob".to_string(),
        }));
    }
}
```
