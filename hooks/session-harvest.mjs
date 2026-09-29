#!/usr/bin/env node
// SessionEnd: one haiku call per session pulls durable findings (-> tier log.md) and reusable
// shell tricks (-> global/terminal-fu/log.md) out of the transcript. Promotion to real pages
// stays with `mmm tidy` -- placement is a judgment call, this is just the inbox.
//
// Runs the actual work in a detached child (`--harvest`) so a slow/hung `claude -p` call never
// blocks session exit. That nested `claude -p` is itself a real session and fires its own
// SessionEnd -- MMM_HARVESTING=1 on its env is how the resulting hook invocation recognizes
// itself and no-ops instead of recursing forever.
import { readFileSync, appendFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SELF = fileURLToPath(import.meta.url);
const MMM_DATA = join(homedir(), '.mmm');
const MIN_TURNS = 20;
const TAIL_BYTES = 30 * 1024;
const MAX_TRICKS = 8;

const [, , mode, ...rest] = process.argv;

if (mode === '--harvest') {
  runHarvest(rest[0], rest[1] || null);
} else {
  hookMode();
}

function hookMode() {
  let input = '';
  process.stdin.on('data', (d) => { input += d; });
  process.stdin.on('end', () => {
    const done = () => process.stdout.write(JSON.stringify({ continue: true }));
    let data = {};
    try { data = JSON.parse(input); } catch { return done(); }

    if (process.env.MMM_HARVESTING === '1') return done(); // this SessionEnd is the nested claude -p's own
    if (!existsSync(MMM_DATA)) return done();
    if (!data.transcript_path || !existsSync(data.transcript_path)) return done();
    if (countTurns(data.transcript_path) < MIN_TURNS) return done();

    const child = spawn(process.execPath, [SELF, '--harvest', data.transcript_path, data.cwd || ''],
      { detached: true, stdio: 'ignore' });
    child.unref();
    done();
  });
}

function countTurns(transcriptPath) {
  let n = 0;
  try {
    for (const line of readFileSync(transcriptPath, 'utf8').split('\n')) {
      if (/"type"\s*:\s*"(user|assistant)"/.test(line)) n++;
    }
  } catch { /* unreadable, treat as empty */ }
  return n;
}

function runHarvest(transcriptPath, cwd) {
  if (!transcriptPath || !existsSync(transcriptPath)) return;
  const { text, bashCandidates } = parseTranscript(transcriptPath);
  if (!text && bashCandidates.length === 0) return;

  const firstPrompt = truncate(text.split('\n').find((l) => l.trim()) || 'session', 90);
  const prompt = buildPrompt(text, bashCandidates);

  let output;
  try {
    output = execFileSync('claude', ['-p', '--model', 'haiku', prompt],
      { encoding: 'utf8', env: { ...process.env, MMM_HARVESTING: '1' }, maxBuffer: 10 * 1024 * 1024 }).trim();
  } catch {
    return; // a detached background harvest failing must never surface anywhere
  }
  if (!output) return;

  const findings = section(output, 'SESSION FINDINGS');
  const tricks = section(output, 'TERMINAL-FU');

  if (findings) {
    const log = join(resolveTier(cwd), 'log.md');
    mkdirSync(dirname(log), { recursive: true });
    appendFileSync(log, `\n## [${today()}] session | ${firstPrompt}\n\n${findings}\n`);
  }
  if (tricks) {
    const log = join(MMM_DATA, 'global', 'terminal-fu', 'log.md');
    mkdirSync(dirname(log), { recursive: true });
    appendFileSync(log, `\n${tricks}\n`);
  }
}

// keep only user prompts + assistant text (drop tool payloads) for the findings prompt; Bash
// tool_use calls and fenced shell blocks in assistant text are pulled separately for terminal-fu
function parseTranscript(transcriptPath) {
  const lines = readFileSync(transcriptPath, 'utf8').split('\n');
  const textParts = [];
  const bashCandidates = [];
  const seen = new Set();

  const addCandidate = (command, description) => {
    const key = command.trim().replace(/\s+/g, ' ');
    if (!key || seen.has(key) || isTrivial(key)) return;
    seen.add(key);
    bashCandidates.push({ command: command.trim(), description: description || '' });
  };

  for (const line of lines) {
    if (!line.trim()) continue;
    let entry;
    try { entry = JSON.parse(line); } catch { continue; }
    const role = entry.type;
    if (role !== 'user' && role !== 'assistant') continue;
    const content = entry.message?.content;
    const blocks = Array.isArray(content) ? content : (typeof content === 'string' ? [{ type: 'text', text: content }] : []);
    for (const block of blocks) {
      if (block.type === 'text' && block.text) {
        textParts.push(block.text);
        if (role === 'assistant') {
          for (const m of block.text.matchAll(/```(?:bash|sh|zsh)\n([\s\S]*?)```/g)) addCandidate(m[1], '');
        }
      } else if (role === 'assistant' && block.type === 'tool_use' && block.name === 'Bash' && block.input?.command) {
        addCandidate(block.input.command, block.input.description);
      }
    }
  }

  let text = textParts.join('\n').replace(/<private>[\s\S]*?<\/private>/g, '');
  const buf = Buffer.from(text, 'utf8');
  if (buf.length > TAIL_BYTES) text = buf.subarray(buf.length - TAIL_BYTES).toString('utf8');
  return { text, bashCandidates };
}

// bare no-arg commands and status-only git reads aren't tricks -- everything else (including
// multi-line scripts and heredocs) passes through untouched
function isTrivial(cmd) {
  if (['ls', 'cat', 'cd', 'pwd'].includes(cmd)) return true;
  if (/^git (status|diff|log)$/.test(cmd)) return true;
  if (!/[\s|]/.test(cmd)) return true; // single word, no pipe or flags
  return false;
}

function buildPrompt(text, bashCandidates) {
  const candidateBlock = bashCandidates.slice(0, 40).map((c, i) =>
    `${i + 1}. ${c.description ? `(${c.description}) ` : ''}\n\`\`\`\n${c.command}\n\`\`\``).join('\n');

  return `You're harvesting one Claude Code session for a personal knowledge base. Respond in exactly this shape, omitting a whole heading (including its "##" line) if it has nothing to add. If both are empty, respond with nothing at all.

## SESSION FINDINGS
At most 5 bullets: durable findings, decisions, or bug root causes from this session that are worth remembering later. Skip anything trivial or already obvious from the code.

## TERMINAL-FU
At most ${MAX_TRICKS} reusable shell tricks (this project + any others), picked from the candidate commands below. A trick is NOT limited to one line -- keep multi-line scripts, pipelines and heredocs exactly as multi-line, never collapse them. For each: a "### <category>: <what it does>" heading, the command as a fenced code block with placeholders instead of any local path/secret/username, and one line on why it works or when to reach for it.

--- session transcript (user + assistant text only) ---
${text}

--- candidate commands ---
${candidateBlock || '(none)'}`;
}

function section(output, heading) {
  const re = new RegExp(`##\\s*${heading}\\s*\\n([\\s\\S]*?)(?=\\n##\\s|$)`, 'i');
  const m = output.match(re);
  return m ? m[1].trim() : '';
}

// mirrors current_tier() in bin/mmm: this checkout's project if registered, else global
function resolveTier(cwd) {
  if (cwd) {
    try {
      const remote = execFileSync('git', ['remote', 'get-url', 'origin'], { cwd, stdio: ['ignore', 'pipe', 'ignore'] })
        .toString().trim();
      const registry = JSON.parse(readFileSync(join(MMM_DATA, 'registry.json'), 'utf8'));
      for (const [key, info] of Object.entries(registry.projects || {})) {
        if (info.remote === remote) return join(MMM_DATA, 'projects', key);
      }
    } catch { /* not a git repo, or no matching registry entry */ }
  }
  return join(MMM_DATA, 'global');
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function truncate(s, n) {
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}
