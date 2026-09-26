# mmm

*aka meta³ — a portable, shareable, multi-project, agent-native memory layer on cruise
control. Just make sure you plan things — i.e., use plan mode.*

## Install

```
curl -fsSL https://raw.githubusercontent.com/amkraev697642/mmm/main/install.sh | sh
```

Clones (or updates) into `~/mmm`, adds it to your `PATH`, offers a `~/.claude/CLAUDE.md`
directive so your agent uses it without being asked. Same command for install and update.

## What it is

A knowledge base for you and your AI coding agent (Claude Code, Cursor) — a global wiki
(things true across every project) plus each project's own (its tasks, architecture,
incident history). Symlinked into the `~/.omc/wiki` / `<repo>/.omc/wiki` paths your agent
already reads and writes (an oh-my-claudecode convention — mmm works standalone, without it).

Plain markdown with a small YAML header. No vector database, no server, no account, no
lock-in. Two roots, deliberately: **`~/mmm`** (no dot) is the tool — safe to publish or fork,
no data in it. **`~/.mmm`** (dotted) is your actual content — `mmm pack` only ever archives it.

## Using it

```
mmm unpack mmm-2026-09.7z   # got handed one? extract it (password prompt)
mmm init .                  # link this project into the store (repeat per project)
mmm rebalance               # keep every project's CLAUDE.md and auto memory in the store (pack runs it)
mmm q "some term"           # instant, free, no model call
mmm a "a real question"     # one cheap model call, scoped only to query's hits
mmm a --save "..."          # same, and append the answer to this project's log.md
mmm links some-page         # what links here, what it links to (--orphans: nothing links here)
mmm tidy                    # a claude session that merges duplicates and drops stale facts
mmm git log --stat          # ~/.mmm is a local git repo: history, diff, undo
```

What's actually automatic vs. what you (or your agent) still have to do:

- **Automatic:** a `SessionStart` hook briefs your agent with open tasks and a pointer to
  `index.md`, before anyone's typed anything.
- **Automatic:** `~/.mmm` is snapshotted into its own local git repo (no remote) at every
  session start and before `pack`/`unpack`, so a page an agent clobbered is one
  `mmm git checkout -- <file>` away.
- **Prompted, not enforced:** finish a plan-mode task and a `Stop` hook reminds the agent,
  once, to file what it learned — a nudge it can ignore, not a quota.
- **Automatic:** Claude Code's own auto memory (`~/.claude/projects/<dir>/memory`, normally
  stuck on one machine) is moved into `~/.mmm/projects/<key>/memory` by `init`/`rebalance`
  and symlinked back, so it travels with `pack` like everything else.
- **Deterministic:** `mmm import some-notes.md` (reads, places, normalizes it) or just asking
  your agent to write a page — these are what actually grow the wiki.

`mmm doctor` before you pack or send anything — see [docs/doctor.md](docs/doctor.md) for
exactly what it does and doesn't check. Content rules (bite-sized, cross-linked, one topic
per page) live in [content-rules.md](content-rules.md).

## Why you'd want this

- **Your agent stops re-deriving the same facts every session.**
- **"What does mmm say about X" answers instantly**, for free — `rg` with wiki awareness on
  top, not a new search engine to trust.
- **It can't leak into your project's git history** — `mmm` never touches project git beyond
  confirming `.omc` is ignored.
- **It travels.** `mmm pack --project <key>` hands a teammate (or another machine) one
  encrypted file instead of a Notion space that's 40% stale.

If you've used Obsidian/Logseq/Foam (same content model), a dotfiles manager like chezmoi
(same symlink-and-archive mechanism), or Cline's Memory Bank (same motivation), this will
feel familiar — `mmm ask` is genuinely just `rg` piped into one `claude -p` call.

## More

[CONTRIBUTING.md](CONTRIBUTING.md) · [docs/editors.md](docs/editors.md) (Claude Code vs.
Cursor) · [docs/doctor.md](docs/doctor.md)
