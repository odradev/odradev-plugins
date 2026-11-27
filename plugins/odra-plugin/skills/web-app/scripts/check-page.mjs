#!/usr/bin/env node
// Open the page in a headless browser and fail if it does not start: an uncaught error, an error
// in the console, or an expected text that never appears. This is what a user sees first, and
// `npm run build` and `check-reads.mjs` cannot see it.
//
// Usage (from web/, with the dev or preview server running):
//   node check-page.mjs <url> [--expect <text>]... [--wait <seconds>] [--screenshot <file>]
//   e.g. node check-page.mjs http://localhost:5173 --expect "Total supply" --expect "Send"
// Needs Playwright in web/ (not saved to package.json):
//   npm install --no-save playwright@1.49.1 && npx playwright install chromium
// Exit code 0 if the page loaded, logged no error and showed every expected text.
import { createRequire } from "node:module";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const take = (flag) => {
  const values = [];
  for (let i = args.indexOf(flag); i >= 0; i = args.indexOf(flag)) values.push(args.splice(i, 2)[1]);
  return values;
};
const expected = take("--expect");
const wait = Number(take("--wait")[0] ?? 5);
const screenshot = take("--screenshot")[0] ?? "/tmp/check-page.png";
const [url] = args;
if (!url) {
  console.error("Usage: node check-page.mjs <url> [--expect <text>]... [--wait <seconds>] [--screenshot <file>]");
  process.exit(1);
}

let chromium;
try {
  ({ chromium } = createRequire(resolve("package.json"))("playwright"));
} catch {
  console.error("Playwright is not installed here. From web/: npm install --no-save playwright@1.49.1 && npx playwright install chromium");
  process.exit(1);
}

const browser = await chromium.launch();
const page = await browser.newPage();
const problems = [];
page.on("pageerror", (e) => problems.push(`uncaught: ${e.message}`));
// A missing favicon is noise, not a broken page.
const noise = (where) => /favicon\.ico/.test(where ?? "");
page.on("console", (m) => m.type() === "error" && !noise(m.location()?.url) && problems.push(`console: ${m.text()}`));
page.on("requestfailed", (r) => !noise(r.url()) && problems.push(`request failed: ${r.url()} (${r.failure()?.errorText})`));

try {
  await page.goto(url, { waitUntil: "load", timeout: 30_000 });
} catch (e) {
  console.log(`FAILED to open ${url}: ${e.message}`);
  await browser.close();
  process.exit(1);
}
// Reads go to the node after the page loads; give them time to land.
await page.waitForTimeout(wait * 1000);
const text = await page.locator("body").innerText();
for (const t of expected) if (!text.includes(t)) problems.push(`missing text: "${t}"`);
await page.screenshot({ path: screenshot, fullPage: true });
await browser.close();

console.log(`${url}: ${problems.length ? `${problems.length} problem(s)` : "ok"} (screenshot: ${screenshot})`);
for (const p of problems) console.log(`  ${p}`);
process.exit(problems.length ? 1 : 0);
