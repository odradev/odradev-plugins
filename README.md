# Odra Plugin Marketplace

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) for distributing plugins related to [Odra](https://odra.dev) — a Rust-based smart contract framework for Casper Network.

## Available Plugins

### odra-plugin

Streamlines smart contract development with the Odra framework. Gives Claude Code deep knowledge of Odra's APIs, patterns, and tooling so it can help you scaffold, build, and test Odra contracts more effectively.

## Installation

Add the marketplace and install the plugin:

```
/plugin marketplace add odradev/plugin-marketplace
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
        "repo": "odradev/plugin-marketplace"
      }
    }
  }
  "enabledPlugins": {
    "odra-plugin@plugin-marketplace": true
  }
}
```

Anyone who clones the repo and trusts the project folder will be prompted to install the plugin.

## Repository Structure

```
.claude-plugin/
  marketplace.json       # Marketplace catalog
plugins/
  odra-plugin/           # The Odra development plugin
README.md
```

## Links

- [Odra Framework](https://github.com/odradev/odra)
- [Odra Docs & Tutorials](https://odra.dev/docs)
- [Cargo Odra](https://github.com/odradev/cargo-odra)
- [Claude Code Plugin Docs](https://code.claude.com/docs/en/plugin-marketplaces)

## License

MIT
