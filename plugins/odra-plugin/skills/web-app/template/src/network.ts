// Everything that differs between Casper networks. Testnet by default;
// `VITE_NETWORK=mainnet npm run build` builds the mainnet site, `VITE_NETWORK=nctl npm run dev`
// reads from a local node.
export interface Network {
  /** The chain name transactions are signed for. */
  chainName: string;
  /** JSON-RPC proxies that browsers may call (CORS enabled), run by the Odra team. */
  rpcUrl: string;
  speculativeRpcUrl: string;
  /** Block explorer. */
  explorerUrl: string;
  /** Addresses of the deployed contracts, written by `sync-contracts.sh`. */
  contractsPath: string;
}

const NETWORKS: Record<string, Network> = {
  // A local NCTL node, after setup-nctl's enable-speculative.sh. Reads only: wallets do not
  // send transactions to a local network.
  nctl: {
    chainName: "casper-net-1",
    rpcUrl: "http://localhost:11101",
    speculativeRpcUrl: "http://localhost:25101",
    explorerUrl: "https://testnet.cspr.live",
    contractsPath: "./contracts.casper-net-1.json",
  },
  testnet: {
    chainName: "casper-test",
    rpcUrl: "https://testnet-rpc.odra.dev",
    speculativeRpcUrl: "https://testnet-speculative-rpc.odra.dev",
    explorerUrl: "https://testnet.cspr.live",
    contractsPath: "./contracts.casper-test.json",
  },
  mainnet: {
    chainName: "casper",
    rpcUrl: "https://mainnet-rpc.odra.dev",
    speculativeRpcUrl: "https://mainnet-speculative-rpc.odra.dev",
    explorerUrl: "https://cspr.live",
    contractsPath: "./contracts.casper.json",
  },
};

export const NETWORK_NAME: string = import.meta.env.VITE_NETWORK ?? "testnet";
export const NETWORK: Network = NETWORKS[NETWORK_NAME];
if (!NETWORK) throw new Error(`Unknown VITE_NETWORK "${NETWORK_NAME}"`);

// `csprclick-template` is a public id that works on localhost only. A site published anywhere
// else needs its own id from https://console.cspr.build (VITE_CSPR_CLICK_APP_ID).
export const CSPR_CLICK_APP_ID: string =
  import.meta.env.VITE_CSPR_CLICK_APP_ID ?? "csprclick-template";

export const transactionUrl = (hash: string) => `${NETWORK.explorerUrl}/transaction/${hash}`;
export const accountUrl = (publicKey: string) => `${NETWORK.explorerUrl}/account/${publicKey}`;
export const contractUrl = (packageHash: string) =>
  `${NETWORK.explorerUrl}/contract-package/${packageHash.replace(/^hash-/, "")}`;
/** Explorer page of an `Address` value read from a contract (`address.value`). */
export const addressUrl = (address: string) =>
  address.startsWith("hash-") || address.startsWith("contract-package-")
    ? contractUrl(address.replace(/^contract-package-/, "hash-"))
    : `${NETWORK.explorerUrl}/account/${address.replace(/^(entity-account-|account-hash-)/, "")}`;
