# Odra gotchas

Traps that cost time when writing Odra 2.10 code. Every item here was hit and reproduced against a
real project, or is a behaviour change documented in the 2.10 changelog — these are not hypotheticals.

Read this file before writing any non-trivial contract, and again when a compile error does not make
obvious sense.

## Project setup

- **Never hand-create a project — scaffold it.** `cargo odra new --name <snake_case> -t <template>`.
  A project has interlocking parts (`Odra.toml`, `build.rs`, three `[[bin]]` targets, a pinned
  `rust-toolchain.toml`, a `cfg(not(target_arch = "wasm32"))` dependency section); writing them by
  hand produces something that looks right and fails later in ways that read as contract bugs.
- **`cargo odra new` takes the Odra version from the latest GitHub release**, which can lag crates.io
  for a few days after a release. Check `odra = ` in the generated `Cargo.toml`; pin with
  `-s 2.10.0` if it is older. With cargo-odra 0.2.0 a `workspace` project on Odra 2.9 cannot find its
  wasm (0.2.0 writes it only to the root `wasm/`, where 2.9 does not look).
- **The project pins a nightly toolchain** in `rust-toolchain.toml` (older projects: a bare
  `rust-toolchain` file). rustup installs it on first build, so the first `cargo odra test` is slow.
  `rustup target add wasm32-unknown-unknown` must apply to *that* toolchain — run it from inside the
  project directory.
- **The folder name is taken verbatim from `--name`; the package name is normalized.**
  `cargo odra new --name my-project` gives a `my-project/` directory containing a package called
  `my_project`. Pass an underscore name to keep them identical.
- **A new module is not picked up until it is declared.** Adding `src/foo.rs` does nothing until
  `pub mod foo;` is in `src/lib.rs`. For a contract you also want to build to wasm, add a
  `[[contracts]]` entry to `Odra.toml`. OdraVM tests pass without the `Odra.toml` entry, so this
  failure only surfaces later, at `cargo odra build`.
- **`fqn` is a Rust path, not a package path.** Single-crate: `fqn = "flipper::Flipper"`
  (`<module>::<Struct>`). Workspace: `fqn = "flipper::flipper::Flipper"` (`<crate>::<module>::<Struct>`).
  Since 2.10 the first segment may be a dependency crate (`fqn = "odra_modules::erc20::Erc20"`,
  needs cargo-odra 0.2.0). The crate must be linked into `bin/build_contract.rs` and
  `bin/build_schema.rs`: on 2.10 with a `use odra_modules;` in both, as the comment there says; from
  2.11 the `odra::link_contract_crates!();` line of a generated project does it.
- **The wasm file is named after the struct, case included** — `Flipper.wasm`, not `flipper.wasm`.
- **`cargo odra build` has no `-b`/`--backend` flag.** Only `cargo odra test` does. `-c` selects
  contracts and takes **space**-separated names: `cargo odra build -c Foo Bar`.
- **`wasm/` does not exist after a plain `cargo odra test`** — only after `cargo odra build` or
  `cargo odra test -b casper`. In a workspace it is at the workspace root only.
- **`cargo odra schema` writes one file per contract**, `resources/casper_contract_schemas/<name>_schema.json`.
  There is no `resources/legacy` any more; delete a stale one. `bin/build_schema.rs` of a 2.10
  project calls `odra_build::contract_schema`; an older project's `odra_build::schema(..)` still
  compiles.
- **Templates are `full`, `blank`, `workspace`, `cep18`, `cep95`.** There is no `cep78` template.
  `cargo odra list-templates` is authoritative.

## Storage

- **`get_or_default()` requires `T: Default`.** `Address` does not implement it, so
  `Var<Address>::get_or_default()` does not compile. Use `get().unwrap()` or
  `get_or_revert_with(Error::X)`. Same for your own `#[odra::odra_type]` types unless they derive
  `Default` — and a unit-only enum needs `#[derive(Default)]` plus `#[default]` on a variant.
- **`Var::get_or_revert_with(err)` takes one argument.** The similarly named `unwrap_or_revert_with`
  comes from the `UnwrapOrRevert` trait on `Option`/`Result` and takes **two**
  (`.unwrap_or_revert_with(self, err)`). Reach for `get_or_revert_with` on a `Var`.
- **`Sequence::next_value()` returns `0` on its first call**, then `1`, `2`… It is a zero-based
  counter, not a pre-increment. `get_current_value()` also returns `0` for an untouched sequence, so
  it cannot tell you whether the sequence has been used.
- **Nested mappings go through `Mapping::module(&key)`**, which yields a `SubModule<V>` with storage
  isolated per key. A `Mapping<K, List<T>>` goes through `Mapping::list(&key)`, which yields a bare
  `List<T>` (never declare `SubModule<List<T>>`). A `List` can be a mapping value, never a key.
  `Mapping` also has `add()`/`subtract()` for numeric values.
- **Field indices start at 1**, not 0. The compact key encoding only holds while every index in the
  path is ≤ 15; nesting deeper than 8 levels reverts with `PathIndexOutOfBounds`.
- **`U256::from(..)` is not `const`.** For a constant use `u256(..)`/`u512(..)` from the prelude
  (`const ONE: U256 = u256(1_000_000_000_000_000_000);`), and `odra_cli::cspr!(500)` for CSPR
  amounts.
- **Reading a value as the wrong type reverts with the concrete `bytesrepr` error**
  (`LeftOverBytes`, `EarlyEndOfStream`), not `Formatting` — usually a field whose type changed
  across an upgrade. An argument that exists with the wrong type is `InvalidArg`, a missing one
  `MissingArg`.

## Modules, attributes, calls

- **`#[odra::module]` goes on the struct *and* on the impl block.** Without it on the impl, no entry
  points are generated and the type never implements `OdraContract`/`Deployer` — the error surfaces
  far away, at `Foo::deploy(...)`, as an unsatisfied trait bound.
- **Module arguments belong on the struct.** `events`, `errors`, `name`, `version` and `layout` on
  an impl block are a compile error since 2.10 (they used to be silently ignored, so events never
  reached the schema). Only `factory = on` goes on an impl block too.
- **`#[odra(..)]` accepts exactly `payable`, `non_reentrant` and `offchain`.** A typo
  (`#[odra(paybale)]`), a repeat (`#[odra(payable, payable)]`) or a value (`payable = true`) is a
  compile error since 2.10; before, it compiled and did nothing.
- **`#[odra(payable)]` or `non_reentrant` on `init` or `upgrade` is a compile error** (2.10). A
  constructor can never receive attached tokens; fund the contract through a separate payable entry
  point after deploy.
- **Reserved names.** An entry point cannot be called `new`, `env`, `address`, `new_contract`,
  `upgrade_child_contract` or `batch_upgrade_child_contract`, and its arguments cannot be `gas` or
  `attached_value`. Private helpers may use any name. Everything else — arguments named `contract`,
  `result`, a field named `env` — compiles since 2.10 (the generated locals are `__odra_` prefixed;
  the hidden env field is `__odra_env`, was `__env` — use `self.env()`).
- **A second, un-annotated `impl` block holds internal helpers.** Do not annotate two impl blocks for
  the same struct — that is a duplicate-impl error.
- **`#[odra(offchain)]` functions** take `&self`, live in a plain impl block (not a trait impl),
  cannot be `payable`/`non_reentrant`, are not on the `ContractRef` (other contracts cannot call
  them) and are not in the wasm. They may call the contract's own functions and non-mutating entry
  points of other contracts.
- **`ContractEnv::attached_value()` returns `U512`**, not `U256`.
- **`self.env()` is a method, not a field.** `self.env.revert(...)` fails with E0615.
- **`#[odra::external_contract]` keeps the trait** (2.10). A second hand-written copy of the trait,
  a common 2.9 workaround, now fails with *the name is defined multiple times* — delete it. Both
  `XxxContractRef` and `XxxHostRef` implement the trait, so it works as a bound.
- **The cross-call type is `{Module}ContractRef`**, and `new()` comes from the `ContractRef` trait —
  `use odra::ContractRef;` must be in scope wherever you construct one by hand.
- **`ContractRef::new` takes `Rc<ContractEnv>`, never `&HostEnv`.** From a host-side test:
  `FooContractRef::new(Rc::new(env.contract_env()), address)`.
- **Helpers shared by `ContractRef` and `HostRef` go in `#[odra::ref_helpers] impl Foo { .. }`**,
  an inherent impl named after the module or external trait. Inside, only entry points and
  `self.contract_address()` are available; a helper calling a `&mut self` entry point takes `&mut self`.
- **`Deployer::deploy` is implemented on the module struct, not on the `ContractRef`.** Use
  `Foo::deploy(&env, args)`, which returns a `FooHostRef`.
- **`.address()` comes from `Addressable`,** not `HostRef` — import `odra::prelude::Addressable`.
  Inside a `ContractRef` it is `contract_address()` (`ContractAddress` in the prelude).
- **Contract-to-contract CSPR goes through `ContractRef::with_tokens(amount)`**, taken from the
  calling contract's balance; the target entry point must be `#[odra(payable)]`.
- **`#[odra::module(name = "..")]` also names the package key** since 2.10 (`<name>_package_hash`).
  A contract installed with 2.9 keeps its old key; the "already installed" guard checks the new one,
  so rely on `load_or_deploy`/the contracts file, not on the revert.

## Events

- **Event fields need a concrete `CLType`.** An `#[odra::odra_type]` struct or data-carrying enum
  (also inside `Option`, `Vec`, a map, a tuple) has `CLType::Any`, which the event standard rejects.
  Since 2.10 such a contract is refused at deploy, upgrade and `cargo odra schema`, with a message
  naming the event and field; before, it deployed and every `emit_event` reverted with `Formatting`.
  Flatten the struct into the event; a unit enum is fine.
- **An upgrade cannot change the schema of an event the contract already emits.** Add a new event
  instead.
- **Native events on livenet are visible only for the transactions this environment sent.** Casper
  keeps a message's payload only in its transaction's execution result. Use CES events (`emit_event`)
  when anyone must be able to read the history.

## Host / testing

- **`HostEnv::emitted_event` takes the event by value**, not by reference: `emitted_event(&contract, Ev { .. })`.
- **`HostEnv::transfer(to, amount) -> OdraResult<()>`** is the host-side transfer (works on CasperVM
  since 2.10; it used to panic). There is no `HostEnv::transfer_tokens`; that name only exists on
  `ContractEnv` (and returns `()`, reverting on failure).
- **To assert a revert, use the `try_` variant.** `contract.foo()` panics the test on revert; only
  `contract.try_foo()` returns a comparable `Result`.
- **A contract with a constructor gets `{Module}InitArgs`; one without gets nothing** — use
  `odra::host::NoArgs`.
- **`HostRef::new(address, env)` takes the `HostEnv` by value** — `env.clone()` if you keep using it.
  Since 2.10 it registers the contract like `load`, so a contract known only by its address (a
  factory child) has working getters, events and offchain functions on every backend.
- **OdraVM rolls back a reverted call completely** (2.10): storage, balances, events (also of nested
  calls), deployed children, the code of a failed upgrade. A test that counted the events of a
  reverted call sees fewer than on 2.9 — and the same as on CasperVM.
- **Arithmetic overflow is a raw Rust panic, not a clean revert.** Odra does not add Solidity-style
  checked arithmetic. It surfaces as `Err(VmError(Panic))`; since 2.10 OdraVM also prints the panic
  message. Guard subtractions explicitly.
- **`advance_block_time(1000)` is milliseconds.** Pass a `core::time::Duration` to state the unit
  (`Duration::from_secs(60)`); both compile.
- **Snapshots keep neither the caller nor the gas report.** `restore_snapshot()` after
  `set_caller(bob)` leaves bob as the caller. Only the last snapshot is kept.
- **`odra_test::env()` follows `-b casper`.** A test of a module that is not in `Odra.toml` fails
  there (no wasm); pin it with `odra_test::odra_env()`.
- **`self.env().debug(..)` is silent on CasperVM** unless the contract crate has
  `odra = { .., features = ["test-support"] }`; and silent everywhere without `-- --nocapture`.

## odra-modules

- The security module is spelled **`Pauseable`** (`odra_modules::security::Pauseable`), with the
  extra `e`. There is no `Pausable` alias.
- **`Erc20::mint` and `Erc20::burn` are no longer entry points** (2.10; a bare `Erc20` let anyone
  mint). They exist as Rust methods for a wrapping module to call behind its own check
  (`self.ownable.assert_owner(&self.env().caller()); self.erc20.mint(..)`). `Erc20HostRef::mint`
  is gone. Same for `Ownable::unchecked_transfer_ownership`.
- **`Cep18::init` takes four arguments**: `init(symbol, name, decimals, initial_supply)`. `Cep18` has
  no `assert_caller` — compare `self.env().caller()` yourself and revert. Its `mint`/`burn` are
  entry points guarded by modalities and badges; `raw_mint`/`raw_burn` are unguarded.
- **`Cep95` has no `mint`** — the public minting function is `raw_mint(to, token_id, metadata)`, and
  it is deliberately unguarded. Add your own access control around it.
- **`AccessControl` needs bootstrapping.** Nothing grants the first role, so a standalone deployment
  can never pass its own admin checks. The wrapping contract's `init` must call
  `unchecked_grant_role(&DEFAULT_ADMIN_ROLE, &self.env().caller())`.
- **`DappRegistryBase`/`DappContractBase` check no caller.** Their mutating functions are plain Rust
  methods; the composing contract guards them. The ready-made `OwnedDappRegistry` uses `Ownable`.

## Upgrades

- **`deploy`, `try_deploy` and odra-cli's `load_or_deploy` install a locked package.** It can never
  be upgraded (`A locked contract cannot be upgraded`), only redeployed. Only
  `InstallConfig::upgradable::<T>()` — via `deploy_with_cfg` in tests and `load_or_deploy_with_cfg`
  in a deploy script — makes a contract upgradable. Before writing an `upgrade` for a deployed
  contract, read how it was installed and tell the user if it is locked.
- **OdraVM does not model the lock**, so an upgrade test passes on OdraVM and fails on CasperVM.
- **Storage is addressed by field position: append new fields, never reorder or remove.** A new
  `SubModule` or `Var` goes after the existing fields; `upgrade` initialises it.
- **`Contract::upgrade(&env, ..)` is not the host-side upgrade** — with an `upgrade` entry point in
  the module it resolves to that method (`expected &mut Contract, found &HostEnv`). The host call is
  `Contract::try_upgrade(&env, address, ContractUpgradeArgs { .. })`.
- **Order of a retrofit:** deploy anything new (a registry) → `upgrade` the existing contracts →
  then register/wire them. A registry verifies `get_dapp_registry` on the member, which the old code
  does not have (`No such method`).

## Livenet / deployment

- **A generated project needs no `livenet` feature.** `odra-cli` (a dependency of the template)
  brings the livenet backend; `cargo run --bin <project>_cli -- deploy` is all. Only a hand-written
  livenet binary outside odra-cli adds `odra-casper-livenet-env` itself.
- **Binaries live in `bin/`, not `src/bin/`,** and are registered with `[[bin]]` (double brackets).
  The CLI binary is `<project>_cli`, not `cli`.
- **Build the wasm before running a livenet binary**, or it fails with `Failed to find wasm file`.
- **Every deploy and every mutating call needs `env.set_gas(...)`.** No gas set is rejected locally
  with `Gas not set`; too little gas *is* sent and comes back as `OutOfGas`. Gas budgets are per
  contract — expect to tune them. Getters and offchain functions send no transaction and need none.
- **Configuration files:** `.env`, plus `<name>.env` selected with `ODRA_CASPER_LIVENET_ENV=<name>`.
  The templates git-ignore `.env`, `*.env` and `secret_key*.pem`.
- **Extra livenet accounts are numbered from 1** (`ODRA_CASPER_LIVENET_KEY_1`); account 0 is
  `ODRA_CASPER_LIVENET_SECRET_KEY_PATH`.
- **Livenet getters run your local code.** A `&self` entry point is executed on your machine against
  the chain state, so it works even if the chain still runs the old version — after a failed upgrade
  a new getter answers `DappRegistryNotSet`, not `No such method`. Mutating calls run on the node and
  fail honestly. Trust the upgrade transaction's result, not a getter, for "is the new code live".
- **Errors come back named only if the schemas are current.** Livenet decodes a user error against
  `resources/casper_contract_schemas/` (the called contract's schema first); an unknown code is
  `VmError::Other`. Run `cargo odra schema` after changing errors.
- **`ODRA_CASPER_LIVENET_STATE_ROOT_HASH` (or `--state-root-hash`) refuses transactions** — it is a
  read-only view of the past; unset it to deploy.
- **`ODRA_LOG_LEVEL=debug`** prints the full transaction JSON before it is sent — the fastest way to
  see what was actually signed — and every retried read.

## Building wasm

**Always build through `cargo odra build` or `cargo odra test -b casper`.** They run the whole wasm
pipeline for you. Never invoke `wasm-opt`/`wasm-strip` by hand to "fix" a build — doing so hides the
real problem and gets the order wrong (stripping first removes the sections `wasm-opt` needs, which
fails with thousands of validation errors).

A failure in those commands is almost always a missing tool, not a code problem. Read the message and
install what it names, rather than working around it:

| Message | Missing |
| --- | --- |
| `wasm32-unknown-unknown target is not present` | `rustup target add wasm32-unknown-unknown` — run it inside the project so it applies to the pinned nightly |
| `wasm-opt` missing or too old (`--llvm-memory-copy-fill-lowering` rejected) | binaryen **121 or newer** (`brew install binaryen`; on Linux a GitHub release, distro packages are too old) |
| `There was an error while running wasm-strip - is it installed?` | wabt (`brew install wabt`, `apt install wabt`) |
| `wasm-pack is not installed` | wasm-pack, needed only by `cargo odra generate-client` |

Driving `cargo` directly is a deliberate escape hatch for controlling feature flags, not a
troubleshooting step; if you genuinely need it, follow the "Building contracts manually" page in the
Odra docs rather than improvising.

## Odra CLI

- The name in `CommandArg::new("number", ...)` and the key in `args.get_single::<u64>("number")` are
  matched at runtime, not compile time. A mismatch compiles fine and fails only when the scenario
  runs, with `Arg error: Unexpected arg: <name>`. Grep any scenario you write to confirm every
  registered name has an exactly matching lookup key.
- `--json` only formats the final report of a *successful* command. Errors and transaction-progress
  lines are always plain text, so parse the last JSON object in stdout rather than the whole stream.
- **Do not write an upgrade scenario** — `upgrade <Contract> --gas .. [--args]` and
  `upgrade-children <Factory>` are built in since 2.10.
- **A scenario sees no events unless it overrides `captures_events()` to `true`.**
