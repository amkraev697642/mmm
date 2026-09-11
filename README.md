# mmm aka meta³ - a portable, agent-native memory

## Install

```
curl -fsSL https://raw.githubusercontent.com/amkraev697642/mmm/main/install.sh | sh
```

Clones (or updates) into `~/mmm` and adds it to your `PATH`. Same command for install and update.

## What it is

A knowledge base for you and your AI coding agent (Claude Code, Cursor) — a global wiki
(things true across every project) plus each project's own (its tasks, architecture,
incident history). Symlinked into the `~/.omc/wiki` / `<repo>/.omc/wiki` paths your agent
already reads and writes — `mmm` changes where the bytes live, not how you touch them.

Plain markdown with a small YAML header. No vector database, no server, no account, no
lock-in — if `mmm` disappeared tomorrow, you'd still have a folder of readable `.md` files.

Two roots, deliberately: **`~/mmm`** (no dot) is the tool — safe to publish or fork, no data
in it. **`~/.mmm`** (dotted, like `~/.ssh`) is your actual wiki content — private, never
shared as-is. `mmm pack` only ever archives `~/.mmm`.

## Using (meta)

The common starting point: someone (a teammate, or you on another machine) handed you an
archive.

```
mmm unpack mmm-2026-09.7z   # extract it (password prompt)
mmm init .                  # link this project into the store (repeat per project you're in)
mmm query "some term"       # instant, free, no model call
mmm ask "a real question"   # one cheap model call, scoped only to query's hits
```

That's the whole loop for reading: unpack once, then `query`/`ask` whenever something comes up.

**Most of that loop isn't even something you run by hand.** Your agent starts the same way:
on Claude Code, a `SessionStart` hook briefs it with the open tasks and a pointer to
`index.md` before you've typed anything; on Cursor, `bootstrap.mdc` tells it to read
`index.md` before acting on any multi-project or architecture question. Either way, the
agent's own research pass consults the same memory you'd `query` by hand — you're not the
only reader, and usually not even the first one in a given session.

## Contributing (meta²)

Adding to it, not just reading it:

```
mmm import some-notes.md   # interactive claude session: reads it, places it, normalizes it
mmm doctor                 # links resolve, nothing leaked into git, no secrets
mmm pack --project <key>   # runs doctor first, then one encrypted file to hand off
```

Rules: bite-sized pages (~150 lines), one topic each, cross-linked with `[[wikilinks]]`.
Update an existing page before creating a new one. Two exceptions: `deep-research/` for an
investigation too long to compress, `plans/` for a design doc worth keeping. Put it in the
global wiki if it'd help a *different* project too; otherwise it's that project's own.

Nothing here is required or enforced on your commits — `mmm doctor` clean is the only ask
before you send anything.

## Contributing to the tool itself (meta³)

`bin/mmm` is bash; `mmm-query.py`/`mmm-doctor.py` are stdlib-only Python 3 (no pip installs);
the hooks are plain Node `.mjs`, no dependencies, speaking Claude Code's own hook JSON
contract. `install.sh` is POSIX `sh` on purpose — it's piped through `sh`, which is `dash` on
plenty of systems, not bash. No package manager, no lockfile, no build step: everything it
shells out to (`jq`, `git`, `rsync`, `rg`, `7z`, and `claude` itself) is either a language
stdlib call or an already-common CLI tool you likely have. Small and readable end to end, not
a framework — send a PR the way you'd send a wiki page: `mmm doctor` clean, and read the
function you're closest to touching before adding a new one alongside it.

## Why you'd want this

- **Your agent stops re-deriving the same facts every session.** A finding gets written down
  once and is there again next time, instead of getting re-discovered later.
- **"What does mmm say about X" answers instantly**, for free — `rg` with a bit of wiki
  awareness on top, not a new search engine you have to trust.
- **It can't leak into your project's git history.** `mmm` never runs git commands inside a
  project repo beyond checking it's ignored — the wiki only lives in a symlinked, gitignored
  folder.

## If you've used any of these, this will feel familiar

- **Obsidian / Logseq / Foam** — same content model: plain markdown, `[[wikilinks]]`, a
  graph of notes you fully own.
- **chezmoi / dotfiles managers** — same mechanism: one canonical store, symlinked out to
  wherever it's used, packed into an encrypted archive to move machines.
- **Cline / Roo-Code's "Memory Bank"** — same motivation: agent memory that survives a
  context reset, generalized here across every project and machine.
- **Grep-based RAG** — `mmm ask` is genuinely just `rg` piped into one `claude -p` call.

## Editors

Claude Code is the primary target — skills, hooks, the `wiki_*` MCP tools for project wikis.
Cursor works too, since `mmm` is just a shell tool either way, but reads/writes `.omc/wiki`
as plain files rather than through any MCP integration.
