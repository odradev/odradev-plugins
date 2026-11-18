#!/usr/bin/env node
// Check, without a browser, that the generated client can read the deployed contract: the same
// code path the page uses (reader key, RPC proxies, contract address, getters).
//
// Usage (from the Odra project root):
//   node check-reads.mjs <Contract> <getter> [<getter> ...] [--network testnet|mainnet]
//   e.g. node check-reads.mjs DailyAuction currentRound highestBid minBid
// Getters are the camelCase method names of <Contract>WasmClient that take no arguments.
// Exit code 0 if every read answered.
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const args = process.argv.slice(2);
const networkFlag = args.indexOf("--network");
const network = networkFlag >= 0 ? args.splice(networkFlag, 2)[1] : "testnet";
const [contractName, ...getters] = args;
if (!contractName || getters.length === 0) {
  console.error("Usage: node check-reads.mjs <Contract> <getter> [<getter> ...] [--network testnet|mainnet]");
  process.exit(1);
}
const NETWORKS = {
  testnet: ["casper-test", "https://testnet-rpc.odra.dev", "https://testnet-speculative-rpc.odra.dev"],
  mainnet: ["casper", "https://mainnet-rpc.odra.dev", "https://mainnet-speculative-rpc.odra.dev"],
};
if (!NETWORKS[network]) {
  console.error(`Unknown network "${network}" (expected testnet or mainnet)`);
  process.exit(1);
}
const [chainName, rpcUrl, speculativeRpcUrl] = NETWORKS[network];

// The client package: <project>_client/pkg-web next to Odra.toml.
const clientDir = readdirSync(".").find((d) => d.endsWith("_client"));
if (!clientDir) {
  console.error("No <project>_client directory here. Run build-client.sh from the Odra project root first.");
  process.exit(1);
}
const pkg = resolve(clientDir, "pkg-web");
const js = readdirSync(pkg).find((f) => f.endsWith("_wasm_client.js"));
const wasm = readdirSync(pkg).find((f) => f.endsWith("_bg.wasm"));

// The client expects a browser: give it just enough of one.
class Window {}
globalThis.Window = Window;
Object.setPrototypeOf(globalThis, Window.prototype);
globalThis.addEventListener ??= () => {};

const client = await import(pathToFileURL(join(pkg, js)).href);
await client.default({ module_or_path: readFileSync(join(pkg, wasm)) });

const contractsFile = `resources/${chainName}-contracts.toml`;
const toml = readFileSync(contractsFile, "utf8");
const entry = toml.split("[[contracts]]").find((block) => new RegExp(`name\\s*=\\s*"${contractName}"`).test(block));
const packageHash = entry && /package_hash\s*=\s*"([^"]+)"/.exec(entry)?.[1];
if (!packageHash) {
  console.error(`${contractName} is not in ${contractsFile}. Deploy it first.`);
  process.exit(1);
}
const Wrapper = client[`${contractName}WasmClient`];
if (!Wrapper) {
  console.error(`The client has no ${contractName}WasmClient. Regenerate it with build-client.sh.`);
  process.exit(1);
}
const odra = new client.OdraWasmClient(rpcUrl, speculativeRpcUrl, chainName);
const contract = new Wrapper(odra, new client.Address(packageHash));
client.setGas(5_000_000_000n);

const show = (v) => (v === undefined ? "undefined" : typeof v === "bigint" ? `${v}n` : v?.value ?? String(v));
let failed = 0;
console.log(`${contractName} ${packageHash} on ${chainName}`);
for (const getter of getters) {
  if (typeof contract[getter] !== "function") {
    console.log(`  ${getter}: no such method (names are camelCase, see the .d.ts file)`);
    failed++;
    continue;
  }
  try {
    console.log(`  ${getter}: ${show(await contract[getter]())}`);
  } catch (e) {
    console.log(`  ${getter}: FAILED - ${e?.message ?? e}`);
    failed++;
  }
}
process.exit(failed ? 1 : 0);
