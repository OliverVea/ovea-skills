// Confusion-matrix summary for a `claude plugin eval` run of the triggering suite.
// Usage: node score.mjs <result.json>
// Each run is one trial: "load" cases count as positives, "no-load" as negatives.
import fs from "node:fs";
import path from "node:path";

const file = process.argv[2];
if (!file) { console.error("usage: node score.mjs <result.json>"); process.exit(2); }
const result = JSON.parse(fs.readFileSync(file, "utf8"));
const casesDir = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, "$1")), "..");

const expected = (name) => {
  const yaml = fs.readFileSync(path.join(casesDir, name, "case.yaml"), "utf8");
  return /^tags: \[load,/m.test(yaml) ? "load" : "no-load";
};

let tp = 0, fn = 0, tn = 0, fp = 0, errors = 0, cost = 0;
const rows = [];
for (const c of result.cases) {
  if (!fs.existsSync(path.join(casesDir, c.name, "case.yaml"))) continue; // case since removed
  const exp = expected(c.name);
  let loaded = 0, scored = 0;
  for (const run of c.arms.with) {
    cost += run.costUsd ?? 0;
    if (run.error) { errors++; continue; }
    scored++;
    const didLoad = exp === "load" ? run.passed : !run.passed;
    if (didLoad) loaded++;
    if (exp === "load") didLoad ? tp++ : fn++; else didLoad ? fp++ : tn++;
  }
  rows.push({ case: c.name, expected: exp, loaded: `${loaded}/${scored}` });
}

const pct = (a, b) => (b ? `${(100 * a / b).toFixed(0)}%` : "n/a");
console.table(rows);
console.log(`recall      ${pct(tp, tp + fn)}  (${tp}/${tp + fn} should-load runs loaded)`);
console.log(`specificity ${pct(tn, tn + fp)}  (${tn}/${tn + fp} should-not-load runs stayed quiet)`);
console.log(`precision   ${pct(tp, tp + fp)}  (${tp}/${tp + fp} loads were wanted)`);
console.log(`errors ${errors}, cost $${cost.toFixed(2)}, duration ${result.durationSeconds}s`);
