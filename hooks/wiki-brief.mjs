#!/usr/bin/env node
// SessionStart: the read tax is the thing to avoid, so this stays <=10 lines, raw stdout,
// never a page body -- just enough to know the wiki exists and what's open right now.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { execSync } from 'node:child_process';

let input = '';
process.stdin.on('data', (d) => { input += d; });
process.stdin.on('end', () => {
  let data = {};
  try { data = JSON.parse(input); } catch { /* fall back to process.cwd() below */ }
  const cwd = data.cwd || process.cwd();
  const mmmData = join(homedir(), '.mmm');

  if (!existsSync(mmmData)) { process.stdout.write(''); return; }

  snapshot(mmmData);

  const totalPages = countMdFiles(mmmData);
  const lines = [`[mmm: ${totalPages} pages at ~/.mmm]`];

  const project = resolveProject(cwd, mmmData);
  const projectKey = project?.key ?? null;
  if (projectKey) {
    // ensure_claude_md (bin/mmm) leaves this marker instead of blocking init on a non-interactive
    // claude -p /init that has no approval channel -- this session IS the interactive one it was
    // waiting for, so surface it once
    const claudeMdPath = join(mmmData, 'projects', projectKey, 'CLAUDE.md');
    try {
      if (readFileSync(claudeMdPath, 'utf8').startsWith('<!-- mmm:placeholder -->')) {
        lines.push(`${projectKey}: CLAUDE.md is a placeholder -- run /init to generate the real one`);
      }
    } catch { /* no CLAUDE.md yet at all, nothing to flag */ }
    const tasksPath = join(mmmData, 'projects', projectKey, 'tasks.md');
    if (existsSync(tasksPath)) {
      const items = [...readFileSync(tasksPath, 'utf8').matchAll(/^- \[ \] (.+)$/gm)].map((m) => m[1]);
      lines.push(`${projectKey}: ${items.length} open task(s)`);
      for (const t of items.slice(0, 5)) lines.push(`  - ${truncate(t, 90)}`);
    }
    if (project.domains.length) {
      lines.push(`domains: ${project.domains.map((d) => `${d} -> ~/.mmm/domains/${d}/index.md`).join(', ')}`);
    }
    lines.push(`See ~/.mmm/projects/${projectKey}/index.md`);
  } else {
    lines.push('See ~/.mmm/global/index.md');
  }

  process.stdout.write(lines.slice(0, 10).join('\n'));
});

// a restore point before this session's agent touches anything -- the same commit `mmm git log`
// shows, so a page clobbered mid-session is one `mmm git checkout` away
function snapshot(mmmData) {
  if (!existsSync(join(mmmData, '.git'))) return;
  const git = (args) => execSync(`git -C "${mmmData}" -c user.name=mmm -c user.email=mmm@localhost ${args}`,
    { stdio: ['ignore', 'pipe', 'ignore'] });
  try {
    git('add -A');
    try { git('diff --cached --quiet'); } catch { git('commit -q -m "mmm: before session"'); }
  } catch { /* a locked index or broken repo must never block a session start */ }
}

function countMdFiles(dir) {
  let n = 0;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === '.git') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) n += countMdFiles(p);
    else if (e.name.endsWith('.md')) n += 1;
  }
  return n;
}

// returns { key, domains } so the brief can point at both this project's wiki and any domain
// tiers woven into it (many-to-many: a project can carry more than one)
function resolveProject(cwd, mmmData) {
  try {
    const remote = execSync('git remote get-url origin', { cwd, stdio: ['ignore', 'pipe', 'ignore'] })
      .toString().trim();
    const registry = JSON.parse(readFileSync(join(mmmData, 'registry.json'), 'utf8'));
    for (const [key, info] of Object.entries(registry.projects || {})) {
      if (info.remote === remote) return { key, domains: info.domains || [] };
    }
  } catch { /* not a git repo, or no matching registry entry */ }
  return null;
}

function truncate(s, n) {
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}
