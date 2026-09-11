#!/usr/bin/env node
// PostToolUse(ExitPlanMode): plan mode used = a big task just got approved = knowledge debt.
// Marks it; plan-tax-collect.mjs checks later whether the wiki actually got updated.
import { writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

let input = '';
process.stdin.on('data', (d) => { input += d; });
process.stdin.on('end', () => {
  let data = {};
  try { data = JSON.parse(input); } catch { /* no stdin JSON, proceed with empty */ }

  const stateDir = join(homedir(), '.omc', 'state');
  mkdirSync(stateDir, { recursive: true });

  // ExitPlanMode doesn't carry the plan text in its own tool call -- best-effort: the most
  // recently touched file in ~/.claude/plans/ is almost certainly the plan just approved.
  let planTitle = null;
  try {
    const plansDir = join(homedir(), '.claude', 'plans');
    let newest = null, newestTime = 0;
    for (const f of readdirSync(plansDir)) {
      if (!f.endsWith('.md')) continue;
      const t = statSync(join(plansDir, f)).mtimeMs;
      if (t > newestTime) { newestTime = t; newest = f; }
    }
    planTitle = newest;
  } catch { /* no plans dir yet */ }

  writeFileSync(
    join(stateDir, 'knowledge-debt.json'),
    JSON.stringify({ session: data.session_id || null, markedAt: new Date().toISOString(), planTitle, nagged: false }, null, 2)
  );

  process.stdout.write(JSON.stringify({ continue: true }));
});
