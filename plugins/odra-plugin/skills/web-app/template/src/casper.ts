// The Casper plumbing every page needs: start the contract client, connect a wallet through
// CSPR.click, send transactions and report what happened to them. Nothing here depends on the
// contracts of the project - main.ts does.
import init, {
  AccountInfo,
  Contracts,
  CsprClickCallbacks,
  OdraWasmClient,
  TransactionResult,
  TransactionStatus,
  U512,
  setGas,
} from "contract-client";
import { CSPR_CLICK_APP_ID, NETWORK } from "./network";

const CSPR_CLICK_VERSION = "2.1.0";
export const MOTES_PER_CSPR = 1_000_000_000n;

export interface Casper {
  client: OdraWasmClient;
  contracts: Contracts;
}

export interface Handlers {
  /** The connected account changed; `null` after sign out. */
  onAccount(account: AccountInfo | null): void;
  /** A transaction was sent (no result yet), or finished (`result.error` is set if it failed). */
  onTransaction(state: "sent" | "done" | "failed", result: TransactionResult): void;
}

let account: AccountInfo | null = null;

/** The connected account, if any. */
export const currentAccount = () => account;

/**
 * Starts the contract client, then CSPR.click. The order matters: the client subscribes to
 * CSPR.click's `csprclick:loaded` event, so it has to be running before the script is added.
 */
export async function startCasper(appName: string, handlers: Handlers): Promise<Casper> {
  await init();
  const client = new OdraWasmClient(NETWORK.rpcUrl, NETWORK.speculativeRpcUrl, NETWORK.chainName);
  const contracts = await Contracts.fromPath(NETWORK.contractsPath);

  const setAccount = (next: AccountInfo | null) => {
    account = next;
    handlers.onAccount(next);
  };
  CsprClickCallbacks.onSignedIn(setAccount);
  CsprClickCallbacks.onSwitchedAccount(setAccount);
  CsprClickCallbacks.onSignedOut(() => setAccount(null));
  CsprClickCallbacks.onDisconnected(() => setAccount(null));
  CsprClickCallbacks.onTransactionStatusUpdate(
    (status: TransactionStatus, result: TransactionResult) => {
      if (status === TransactionStatus.SENT) handlers.onTransaction("sent", result);
      else if (status === TransactionStatus.PROCESSED)
        handlers.onTransaction(result.error ? "failed" : "done", result);
      else if (status === TransactionStatus.ERROR) handlers.onTransaction("failed", result);
    },
  );

  loadCsprClick(appName);
  return { client, contracts };
}

function loadCsprClick(appName: string) {
  const w = window as any;
  // Both objects must exist before the script runs.
  w.clickUIOptions = { uiContainer: "csprclick-ui", rootAppElement: "#root", showTopBar: false };
  w.clickSDKOptions = {
    appName,
    appId: CSPR_CLICK_APP_ID,
    contentMode: "iframe",
    providers: ["casper-wallet", "ledger", "metamask-snap"],
    chainName: NETWORK.chainName,
  };
  const script = document.createElement("script");
  script.id = "csprclick-client";
  script.async = true;
  script.src = `https://cdn.cspr.click/ui/v${CSPR_CLICK_VERSION}/csprclick-client-${CSPR_CLICK_VERSION}.js`;
  document.head.appendChild(script);
}

/**
 * Sends a transaction: `gasCspr` is the most it may spend on fees (part of what is not used comes
 * back). Opens the wallet prompt; resolves when the transaction is processed or cancelled.
 * Progress arrives through `Handlers.onTransaction`.
 */
export async function send(
  gasCspr: number,
  call: () => Promise<TransactionResult>,
): Promise<TransactionResult> {
  setGas(BigInt(gasCspr) * MOTES_PER_CSPR);
  return call();
}

/** Reads need a gas limit too, although nothing is paid: they are simulated, not sent. */
export function prepareRead(gasCspr = 5) {
  setGas(BigInt(gasCspr) * MOTES_PER_CSPR);
}

/**
 * Runs a read that may have nothing to return, and gives `fallback` instead of failing.
 * Use it for getters that revert when the thing looked up does not exist. It hides every other
 * failure of that read too, so not for getters that always answer.
 */
export function readOr<T>(fallback: T, call: () => Promise<T>): Promise<T> {
  return call().catch(() => fallback);
}

/** "12.5" -> 12_500_000_000 motes, without going through floating point. `null` if not a number. */
export function parseCspr(text: string): U512 | null {
  const match = /^(\d+)(?:[.,](\d{1,9}))?$/.exec(text.trim());
  if (!match) return null;
  const motes = BigInt(match[1]) * MOTES_PER_CSPR + BigInt((match[2] ?? "").padEnd(9, "0"));
  return U512.fromBigInt(motes);
}

/** Motes -> "12.50 CSPR". */
export const formatCspr = (motes: U512, precision = 2) =>
  `${motes.formatter(9).fmtWithPrecision(precision)} CSPR`;

/** Shortens a public key or hash for display. */
export const short = (text: string) =>
  text.length > 20 ? `${text.slice(0, 10)}…${text.slice(-6)}` : text;
