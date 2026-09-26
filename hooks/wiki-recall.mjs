#!/usr/bin/env node
// PostToolUse(Read|Edit|Write|MultiEdit): the SessionStart brief can't know which files a session
// will touch, so this points at the page covering a file at the moment it's touched -- a page
// covers the files matched by its `applies_to:` globs or cited in its `sources:`. One line, only
// a pointer (never a page body), and each page at most once per session.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname, relative } from 'node:path';
import { execSync } from 'node:child_process';

const mmmData = join(homedir(), '.mmm');
const statePath = join(homedir(), '.omc', 'state', 'mmm-recall.json');

let input = '';
process.stdin.on('data', (d) => { input += d; });
process.stdin.on('end', () => {
  try { run(JSON.parse(input)); } catch { done(); }
});

function done(context) {
  const out = { continue: true };
  if (context) out.hookSpecificOutput = { hookEventName: 'PostToolUse', additionalContext: context };
  process.stdout.write(JSON.stringify(out));
}

function run(data) {
  const file = data.tool_input?.file_path;
  if (!file || !existsSync(mmmData) || file.startsWith(mmmData)) return done();

  const root = git('rev-parse --show-toplevel', dirname(file));
  if (!root) return done();
  const rel = relative(root, file);
  const key = projectKey(git('remote get-url origin', root));

  const tiers = [join(mmmData, 'global')];
  if (key) tiers.push(join(mmmData, 'projects', key));

  const state = loadState(data.session_id);
  const hits = [];
  for (const tier of tiers) {
    for (const page of mdFiles(tier)) {
      const shown = relative(mmmData, page);
      if (state.shown.includes(shown)) continue;
      const fm = frontmatter(readFileSync(page, 'utf8'));
      const patterns = [...list(fm.applies_to), ...list(fm.sources).map((s) => s.replace(/:\d+(-\d+)?$/, ''))];
      if (patterns.some((p) => globToRegex(p).test(rel))) {
        hits.push(`~/.mmm/${shown}${fm.title ? ` (${fm.title})` : ''}`);
        state.shown.push(shown);
      }
    }
  }
  if (!hits.length) return done();
  saveState(state);
  done(`[mmm] ${rel} is covered by: ${hits.slice(0, 3).join(', ')} -- read it before relying on your own reading of the code.`);
}

function git(args, cwd) {
  try { return execSync(`git ${args}`, { cwd, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { return ''; }
}

function projectKey(remote) {
  if (!remote) return null;
  try {
    const registry = JSON.parse(readFileSync(join(mmmData, 'registry.json'), 'utf8'));
    for (const [key, info] of Object.entries(registry.projects || {})) if (info.remote === remote) return key;
  } catch { /* no registry yet */ }
  return null;
}

// memory/ is Claude Code's auto memory, which has no applies_to/sources of its own
function mdFiles(dir) {
  let out = [];
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    if (e.name === '.git' || e.name === 'memory') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) out = out.concat(mdFiles(p));
    else if (e.name.endsWith('.md')) out.push(p);
  }
  return out;
}

// same subset of YAML mmm-doctor.py reads: `k: v`, `k: [a, b]`, `k:` + `  - item` lines
function frontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\n/);
  const fields = {};
  if (!m) return fields;
  let key = null;
  for (const line of m[1].split('\n')) {
    const item = line.match(/^\s+-\s*(.*)$/);
    if (item && key) {
      if (!Array.isArray(fields[key])) fields[key] = [];
      fields[key].push(unquote(item[1]));
      continue;
    }
    const kv = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
    if (!kv) continue;
    key = kv[1];
    const val = kv[2].trim();
    fields[key] = val.startsWith('[') && val.endsWith(']')
      ? val.slice(1, -1).split(/,(?![^{]*})/).map(unquote).filter(Boolean)
      : unquote(val);
  }
  return fields;
}

function unquote(s) { return s.trim().replace(/^["']|["']$/g, ''); }
function list(v) { return Array.isArray(v) ? v : v ? [v] : []; }

// **, *, ? and {a,b} -- enough for the globs .claude/rules and Cursor rules use
function globToRegex(glob) {
  let re = '';
  let depth = 0;
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      re += glob[i + 2] === '/' ? '(?:.*/)?' : '.*';
      i += glob[i + 2] === '/' ? 2 : 1;
    } else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else if (c === '{') { re += '(?:'; depth++; }
    else if (c === '}' && depth) { re += ')'; depth--; }
    else if (c === ',' && depth) re += '|';
    else re += c.replace(/[.+^$()|[\]\\]/g, '\\$&');
  }
  try { return new RegExp(`^${re}$`); } catch { return /(?!)/; }  // one bad glob can't mute every page
}

function loadState(session) {
  try {
    const s = JSON.parse(readFileSync(statePath, 'utf8'));
    if (s.session === session) return s;
  } catch { /* first touch this session */ }
  return { session: session || null, shown: [] };
}

function saveState(state) {
  mkdirSync(dirname(statePath), { recursive: true });
  writeFileSync(statePath, JSON.stringify(state));
}
