# Odra Plugin Marketplace

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) for distributing plugins related to [Odra](https://github.com/odradev/odra) — a Rust-based smart contract framework for Casper Network.

## Available Plugins

### odra-plugin

Streamlines smart contract development with the Odra framework. Gives Claude Code deep knowledge of Odra's APIs, patterns, and tooling so it can help you scaffold, build, and test Odra contracts more effectively.

The bundled reference targets **Odra 2.10** and **cargo-odra 0.2.0**. Older projects still work with
every skill; the plugin points at the matching versioned docs and the migration guide when it meets one.

## Prerequisites

The plugin drives Odra's own toolchain — it does not replace it. Before installing, make sure you have:

- Rust toolchain with the `wasm32-unknown-unknown` target
- [`cargo-odra`](https://github.com/odradev/cargo-odra) 0.2.0 or newer: `cargo install cargo-odra --locked`
- `wasm-strip` ([wabt](https://github.com/WebAssembly/wabt)) and `wasm-opt`
  ([binaryen](https://github.com/WebAssembly/binaryen), **121 or newer** — distribution packages are
  usually too old)

The [Installation guide](https://odra.dev/docs/getting-started/installation) covers all of them, and
[Ubuntu / WSL setup](https://odra.dev/docs/getting-started/ubuntu-wsl-setup) has verified
copy-pasteable commands for Linux.
Once the plugin is installed, `/odra-plugin:check-env` verifies the setup for you, and
`/odra-plugin:new-project` scaffolds a project with `cargo odra new`.

## Installation

Add the marketplace and install the plugin:

```
/plugin marketplace add odradev/odradev-plugins
/plugin install odra-plugin@odradev-plugins
```

To verify it's active:

```
/plugin list
```

## Updating

Pull the latest version of the marketplace and its plugins:

```
/plugin marketplace update
```

## Project-level setup

To make the plugin available automatically for everyone working on your Odra project, add this to `.claude/settings.json` in your repository:

```json
{
  "extraKnownMarketplaces": {
    "odradev-plugins": {
      "source": {
        "source": "github",
        "repo": "odradev/odradev-plugins"
      }
    }
  },
  "enabledPlugins": {
    "odra-plugin@odradev-plugins": true
  }
}
```

Anyone who clones the repo and trusts the project folder will be prompted to install the plugin.

## Repository Structure

```
.claude-plugin/
  marketplace.json           # Marketplace catalog
plugins/
  odra-plugin/
    .claude-plugin/
      plugin.json            # Plugin manifest
    commands/
      onboard.md             # Guided walkthrough
    reference/
      docs-map.md            # Index of odra.dev/docs — where to look when knowledge is missing
    skills/
      check-env/             # Verify the toolchain is installed
      new-project/           # Scaffold a project with `cargo odra new`
      setup-nctl/            # Start and configure a local Casper node
      deploy-to-livenet/     # Deploy to nctl, testnet or mainnet
      smart-contract-writer/ # Write and fix contracts (+ reference/: contract model, CLI, testing, factory, dapp, ...)
      test-contracts/        # Run tests on OdraVM and/or CasperVM
README.md
```

## Keeping the plugin in sync with the docs

`plugins/odra-plugin/reference/docs-map.md` mirrors the structure of
[odra.dev/docs](https://odra.dev/docs) and is what the skills consult when their bundled reference
runs out. When pages are added, renamed or removed on the docs site, update it — the generated
[llms.txt](https://odra.dev/llms.txt) is the authoritative list to check against.

## Links

- [Odra Framework](https://github.com/odradev/odra) — source, project templates and examples
- [Odra Docs & Tutorials](https://odra.dev/docs) — source: [odradev/odradev.github.io](https://github.com/odradev/odradev.github.io)
- [Cargo Odra](https://github.com/odradev/cargo-odra) — the `cargo odra` project generator and build tool
- [Odra API reference](https://docs.rs/odra/latest/odra/)
- [llms.txt](https://odra.dev/llms.txt) — documentation index for agents that cannot use this plugin
- [Claude Code Plugin Docs](https://code.claude.com/docs/en/plugin-marketplaces)

## License

MIT
