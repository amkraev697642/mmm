#!/usr/bin/env node
// Stop(*): collects the debt plan-tax-mark.mjs left, if any. Paid = some file under ~/.mmm
// changed since the plan was approved. Unpaid = nag once (not every Stop), then stay quiet
// until either it's paid or a new debt replaces it.
import { readFileSync, writeFileSync, existsSync, unlinkSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const debtPath = join(homedir(), '.omc', 'state', 'knowledge-debt.json');

function newerFileExists(dir, thresholdMs) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return false; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      if (newerFileExists(p, thresholdMs)) return true;
    } else {
      try { if (statSync(p).mtimeMs > thresholdMs) return true; } catch { /* race, skip */ }
    }
  }
  return false;
}

function done(extra) {
  process.stdout.write(JSON.stringify({ continue: true, ...extra }));
}

if (!existsSync(debtPath)) { done(); process.exit(0); }

let debt;
try { debt = JSON.parse(readFileSync(debtPath, 'utf8')); } catch { done(); process.exit(0); }

const mmmData = join(homedir(), '.mmm');
const markedAtMs = new Date(debt.markedAt).getTime();
const paid = newerFileExists(mmmData, markedAtMs);

if (paid) {
  unlinkSync(debtPath);
  done();
  process.exit(0);
}

if (debt.nagged) { done(); process.exit(0); }

debt.nagged = true;
writeFileSync(debtPath, JSON.stringify(debt, null, 2));

const context = `[mmm] A plan-mode task just finished (${debt.planTitle || 'untitled plan'}) and nothing in ~/.mmm has changed since. If it produced a durable finding or decision, apply the placement rule and update the page that already covers it -- create one only if nothing does -- budget roughly 13% of the task's tokens. If there's genuinely nothing worth keeping, ignore this.`;

done({ hookSpecificOutput: { hookEventName: 'Stop', additionalContext: context } });
