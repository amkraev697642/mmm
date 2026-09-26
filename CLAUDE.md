# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`mmm` (aka meta³) is a portable, shareable, multi-project, agent-native memory layer on cruise 
control. Just make sure you plan things - i.e., use plan mode. a canonical markdown wiki store at
`~/.mmm` (private data, dotted like `~/.ssh`), symlinked into `~/.omc/wiki` (global) and each
project's `<repo>/.omc/wiki` (project-local) — the paths Claude Code's own `wiki_*` MCP tools
and Cursor's rules already read/write. `~/mmm` (no dot, this repo) is the tool itself: safe to
publish, no user data in it.

No package manager, no lockfile, no build step. Everything shells out to already-common CLI
tools (`jq`, `git`, `rsync`, `rg`, `7z`, `claude`) or language stdlib.

## Architecture

- **`bin/mmm`** — the CLI, plain bash (`set -euo pipefail`). Single dispatch at the bottom;
  each subcommand is a `cmd_*` function. Holds the project registry (`~/.mmm/registry.json`,
  keyed by git remote URL, not path — path is just a cached hint) and all symlink-adoption
  logic (`init_one`), plus `link_claude_md` (`init` and `rebalance`): a project's `CLAUDE.md`
  lives in the store, the repo gets a git-ignored symlink; and `link_auto_memory` (same two
  commands): Claude Code's machine-local auto memory dir moves to `projects/<key>/memory`, a
  symlink left in its place. Requires `jq`, `git`, `rsync`, `python3`, `rg` on `PATH`.
- **`bin/mmm-query.py`** / **`bin/mmm-doctor.py`** — stdlib-only Python 3 (no pip installs).
  `mmm-query.py` is `rg --json` with wiki-structure awareness (frontmatter hits ranked over
  body hits, results grouped by page). `mmm-doctor.py` does structural checks: broken
  `[[wikilink]]`s (checked tree-wide, since pages cross-link between tiers), dangling
  `[text](file.md)` links, oversized pages (150-line budget), unindexed pages.
- **`hooks/*.mjs`** — Claude Code hooks, plain Node ESM, no dependencies, speaking Claude
  Code's hook JSON contract (stdin JSON in, `{continue: true, ...}` JSON out on stdout).
  Symlinked by `install.sh` into `~/.claude/hooks/` and registered in `~/.claude/settings.json`.
  See `hooks/README.md` for the manual-registration JSON if `install.sh` can't merge safely.
  - `wiki-brief.mjs` (`SessionStart`) — ≤10-line session brief: page count, current project's
    open tasks, pointer to the relevant `index.md`.
  - `wiki-recall.mjs` (`PostToolUse`, matcher `Read|Edit|Write|MultiEdit`) — one-line pointer
    to a page whose `applies_to:` globs or `sources:` match the touched file, once per session.
  - `plan-tax-mark.mjs` (`PostToolUse`, matcher `ExitPlanMode`) — marks that a plan-mode task
    just got approved (knowledge debt).
  - `plan-tax-collect.mjs` (`Stop`) — nags once if nothing under `~/.mmm` changed since the
    debt was marked ("paid" = any file mtime under `~/.mmm` newer than the mark).
- **`install.sh`** — POSIX `sh` on purpose (piped through `sh`, which is `dash` on many
  systems: no `set -o pipefail`, no arrays, no `[[`, no `local`). Clones/updates this repo,
  symlinks hooks, merges hook registration into `~/.claude/settings.json` via `jq`, offers
  optional companion plugin installs (oh-my-claudecode/ponytail/caveman), adds `bin/` to `PATH`.
  Idempotent — same command installs and updates.
- **`integrations/bootstrap.mdc`** — Cursor rule (symlinked to `~/.cursor/rules/`) giving
  Cursor the same wiki-routing awareness Claude Code gets from `CLAUDE.md` + hooks, since
  Cursor has no MCP access to the wiki paths.
- **`content-rules.md`** — the actual rules every wiki page follows (page format, placement
  rule, `tasks.md` convention). `mmm import`'s prompt, `mmm init`'s index-seeding, and
  `mmm-doctor.py`'s checks all point back here rather than duplicating it. Marked draft,
  flagged for review once used a few times.

## Key design points

- **Two roots, deliberately**: `~/mmm` (tool, no data) vs `~/.mmm` (data, private). `mmm pack`
  only ever archives `~/.mmm`.
- **`~/.mmm` is a local git repo** (`snapshot()` in `bin/mmm`, `snapshot()` in
  `wiki-brief.mjs`): committed at session start and before pack/unpack, never pushed. `.git` is
  not archived by pack and is skipped by every tree walk (plan-tax "paid" check, page count).
- **Registry keyed by git remote**, not filesystem path — `resolve_path()` in `bin/mmm` walks
  `searchRoots` to relocate a project if its cached `pathHint` no longer matches. A second
  worktree/clone of an already-registered remote shares that project's wiki (one project, one
  wiki); `mmm init --merge` is required if it grew independent content, to avoid silently
  clobbering same-named files.
- **`mmm doctor` is the only enforced gate** — nothing about wiki content is enforced on
  commits; `pack` runs the full doctor battery first and refuses to write an archive if it
  fails.
- **`mmm ask`** reduces the natural-language question to an `rg` alternation pattern
  (stopword-filtered) before calling `mmm-query.py --json`, then pipes those excerpts into one
  scoped `claude -p` call — never a raw semantic search.
- **`mmm import`** hands off to an interactive `claude` session (not scripted) with
  `content-rules.md` as its instructions, since placement/normalization is a judgment call.

## Testing / verification

No test suite. `mmm doctor` (`cmd_doctor` in `bin/mmm`) is the closest thing to CI: secret
scan, git-ignore check, symlink health (`cmd_status`), structural checks (`mmm-doctor.py`),
companion-plugin check. Run it after any change touching `bin/mmm`, `bin/mmm-*.py`, or
`content-rules.md`. There's no separate lint/build command — `bash -n bin/mmm` and
`python3 -m py_compile bin/*.py` are reasonable syntax-only sanity checks before relying on
`mmm doctor` for the rest.

## Working in this repo

- Read the function you're closest to touching before adding a new one alongside it — the
  codebase is deliberately small and flat (one file per concern), not a framework.
- Don't add a dependency or package manager for what a stdlib call or an already-common CLI
  tool already does — this is a hard constraint here, not just a style preference (see `need`
  calls at the top of `bin/mmm` and the tool list in `install.sh`).
- Comments in this codebase explain *why*, never *what* — match that style in any new code
  (see existing comments in `bin/mmm` and the hooks for the tone).
