#!/usr/bin/env node
// MCP server over stdio, plain Node, no SDK: gives agents without file access to ~/.mmm (Cursor,
// Codex, any MCP client) the same query/read/write reach Claude Code gets from plain file tools.
// Newline-delimited JSON-RPC 2.0 is the whole stdio transport, so an SDK would buy nothing here.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve, dirname, relative, sep } from 'node:path';
import { execFileSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

const MMM_HOME = process.env.MMM_HOME || join(homedir(), '.mmm');
const MMM_CLI = join(dirname(realpathSync(fileURLToPath(import.meta.url))), '..', 'bin', 'mmm');

const TOOLS = [
  {
    name: 'mmm_query',
    description: 'Search the mmm wiki (global + project pages) for a literal term. Instant, no LLM. Returns pages ranked by title/tag hits, with snippets. Use before re-deriving anything.',
    inputSchema: { type: 'object', properties: { term: { type: 'string' }, project: { type: 'string', description: 'project key to search besides global' } }, required: ['term'] },
  },
  {
    name: 'mmm_list',
    description: 'List wiki pages, as paths relative to ~/.mmm. Optionally only under one tier, e.g. "global" or "projects/<key>".',
    inputSchema: { type: 'object', properties: { under: { type: 'string' } } },
  },
  {
    name: 'mmm_read',
    description: 'Read one wiki page by its path relative to ~/.mmm (e.g. "global/index.md").',
    inputSchema: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] },
  },
  {
    name: 'mmm_write',
    description: 'Create or replace one wiki page (path relative to ~/.mmm, must end in .md). Follow ~/mmm/content-rules.md: update an existing page before creating one, YAML frontmatter with title/category/tags/updated, one topic, under 150 lines, add new pages to the tier\'s index.md.',
    inputSchema: { type: 'object', properties: { path: { type: 'string' }, content: { type: 'string' } }, required: ['path', 'content'] },
  },
];

// every path an agent hands us must stay inside the store, symlinks included
function inStore(p) {
  const abs = resolve(MMM_HOME, p);
  let probe = abs;
  while (!existsSync(probe)) probe = dirname(probe);
  const real = join(realpathSync(probe), relative(probe, abs));
  const root = realpathSync(MMM_HOME);
  if (real !== root && !real.startsWith(root + sep)) throw new Error(`path escapes ~/.mmm: ${p}`);
  if (relative(root, real).split(sep).includes('.git')) throw new Error('the store\'s .git is off limits');
  return abs;
}

// Cursor/Codex sessions never run the SessionStart hook that snapshots the store, so the first
// write of each server lifetime takes that restore point instead
let snapshotted = false;
function snapshot() {
  if (snapshotted || !existsSync(join(MMM_HOME, '.git'))) return;
  snapshotted = true;
  const git = (...a) => execFileSync('git', ['-C', MMM_HOME, '-c', 'user.name=mmm', '-c', 'user.email=mmm@localhost', ...a], { stdio: 'ignore' });
  try {
    git('add', '-A');
    try { git('diff', '--cached', '--quiet'); } catch { git('commit', '-q', '-m', 'mmm: before MCP writes'); }
  } catch { /* history is a nicety; never block the write over it */ }
}

function mdFiles(dir) {
  let out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === '.git') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) out = out.concat(mdFiles(p));
    else if (e.name.endsWith('.md')) out.push(relative(MMM_HOME, p));
  }
  return out;
}

function call(name, args) {
  switch (name) {
    case 'mmm_query': {
      const cli = ['query', '--json', args.term];
      if (args.project) cli.push('--project', args.project);
      try {
        return execFileSync(MMM_CLI, cli, { stdio: ['ignore', 'pipe', 'pipe'] }).toString();
      } catch (e) {
        if (e.status === 1) return `no matches for ${JSON.stringify(args.term)}`;
        throw e;
      }
    }
    case 'mmm_list':
      return mdFiles(inStore(args.under || '.')).join('\n');
    case 'mmm_read':
      return readFileSync(inStore(args.path), 'utf8');
    case 'mmm_write': {
      if (!args.path.endsWith('.md')) throw new Error('pages are .md files');
      const abs = inStore(args.path);
      snapshot();
      mkdirSync(dirname(abs), { recursive: true });
      writeFileSync(abs, args.content);
      return `wrote ${args.path} -- run 'mmm doctor' (or ask the user to) before relying on it`;
    }
    default:
      throw new Error(`unknown tool: ${name}`);
  }
}

function send(msg) { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', ...msg }) + '\n'); }

createInterface({ input: process.stdin }).on('line', async (line) => {
  let req;
  try { req = JSON.parse(line); } catch { return; }
  const { id, method, params = {} } = req;
  if (id === undefined) return;  // notifications (initialized, cancelled) need no answer
  try {
    if (method === 'initialize') {
      send({ id, result: { protocolVersion: params.protocolVersion || '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'mmm', version: '0.1.0' } } });
    } else if (method === 'tools/list') {
      send({ id, result: { tools: TOOLS } });
    } else if (method === 'tools/call') {
      try {
        const text = await call(params.name, params.arguments || {});
        send({ id, result: { content: [{ type: 'text', text }] } });
      } catch (e) {
        // a tool failure is a result the model should see, not a protocol error
        send({ id, result: { content: [{ type: 'text', text: String(e.message || e) }], isError: true } });
      }
    } else if (method === 'ping') {
      send({ id, result: {} });
    } else {
      send({ id, error: { code: -32601, message: `method not found: ${method}` } });
    }
  } catch (e) {
    send({ id, error: { code: -32603, message: String(e.message || e) } });
  }
});
