// The page of the dapp. Everything specific to the contracts lives in this file; casper.ts and
// network.ts stay as they are.
import { AccountInfo, TransactionResult, __CONTRACT__WasmClient } from "contract-client";
import { Casper, currentAccount, prepareRead, short, startCasper } from "./casper";
import { NETWORK_NAME, accountUrl, contractUrl, transactionUrl } from "./network";

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

let casper: Casper;
let contract: __CONTRACT__WasmClient;

function setStatus(text: string, kind: "" | "ok" | "err" = "", link?: string) {
  const status = $("status");
  status.className = kind;
  status.textContent = text;
  if (link) {
    const a = document.createElement("a");
    a.href = link;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    a.textContent = " View in the explorer";
    status.append(a);
  }
}

/** Reads the contract and draws it. Called at start and after every successful transaction. */
async function refresh() {
  prepareRead();
  // Read entry points here, one `await contract.<getter>()` each, and put the values on the page.
  // Lookups that may find nothing go through readOr() from ./casper:
  //   const owner = await readOr(undefined, () => contract.ownerOf(id));
  $("summary").textContent = "Connected to the contract.";
}

function onAccount(account: AccountInfo | null) {
  const link = $<HTMLAnchorElement>("account");
  link.textContent = account ? short(account.publicKey) : "";
  if (account) link.href = accountUrl(account.publicKey);
  $("connect").hidden = !!account;
  $("disconnect").hidden = !account;
}

/** Turns a failed transaction into a sentence. Map the contract's error codes here. */
function describeError(result: TransactionResult): string {
  // switch (result.errorCode) { case __CONTRACT__Errors.Something: return "…"; }
  return result.error ?? "The transaction failed.";
}

function onTransaction(state: "sent" | "done" | "failed", result: TransactionResult) {
  const link = result.txHash ? transactionUrl(result.txHash) : undefined;
  if (state === "sent") setStatus("Transaction sent, waiting for the network…", "", link);
  if (state === "failed") setStatus(describeError(result), "err", link);
  if (state === "done") {
    setStatus("Done.", "ok", link);
    refresh().catch(console.error);
  }
}

/**
 * Runs a state-changing call, e.g. `transact(() => send(10, () => contract.doSomething(arg)))`.
 * Asks the user to connect first; the wallet then shows the transaction for approval.
 */
export async function transact(call: () => Promise<TransactionResult>) {
  if (!currentAccount()) {
    await casper.client.signIn();
    return;
  }
  try {
    setStatus("Confirm the transaction in your wallet…");
    const result = await call();
    if (result.isCancelled) setStatus("Cancelled.");
  } catch (e) {
    setStatus(String(e), "err");
  }
}

async function main() {
  $("network").textContent = NETWORK_NAME;
  casper = await startCasper("__TITLE__", { onAccount, onTransaction });
  const info = casper.contracts.get("__CONTRACT__");
  contract = new __CONTRACT__WasmClient(casper.client, info.address);

  const link = $<HTMLAnchorElement>("contract-link");
  link.textContent = short(info.package_hash);
  link.href = contractUrl(info.package_hash);

  $("connect").addEventListener("click", () => casper.client.signIn());
  $("disconnect").addEventListener("click", () => casper.client.signOut());
  // Wire the buttons and forms of the page to `transact(...)` here.

  await refresh();
}

main().catch((e) => {
  console.error(e);
  setStatus(`Could not start: ${e}`, "err");
});
