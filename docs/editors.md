# Editors

`mmm` itself is editor-agnostic — a plain shell tool (`ln -s`/`7z`/`rsync`), equally usable
from a Cursor terminal as from Claude Code's. `mmm ask`/`mmm import` shell out to the
standalone `claude` CLI, which behaves the same regardless of which editor's terminal
invokes it.

## Claude Code

Primary target. Gets three things Cursor doesn't:
- **Hooks** (`hooks/`) — `SessionStart` brief, the plan-mode capture nudge.
- **`wiki_*` MCP tools** for project-local wikis — an **oh-my-claudecode** feature, not part
  of mmm itself; mmm's own commands (`query`/`ask`/`doctor`/`init`) work identically with or
  without OMC installed.
- The optional `ponytail`/`caveman` plugin offer during install (stylistic fit, not a
  dependency).

## Cursor

Works fully, without OMC or its MCP tools: `~/.cursor/rules/bootstrap.mdc` tells Cursor to
read `~/.claude/CLAUDE.md` and `~/.omc/wiki/index.md` before acting on any multi-project or
architecture question, and to fall back to plain file read/write on `.omc/wiki/*.md` — Cursor
never had MCP access to either wiki tier regardless.

Every `mmm` subcommand except `ask`/`import` (which need the `claude` CLI) works with no
Claude Code installation on the machine at all — `init`'s optional `/init` doc-seed step
skips itself with a warning instead of failing if `claude` isn't on PATH.

## What's NOT required

Neither editor's own AI features, nor oh-my-claudecode/ponytail/caveman, are dependencies of
`mmm`. `install.sh` only ever *offers* them; every offer is skippable and re-run-safe.
