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
architecture question, and to fall back to plain file read/write on `.omc/wiki/*.md`. OMC's
`wiki_*` MCP tools are Claude Code only; mmm's own MCP server (below) gives Cursor query/read/write
tools for both tiers instead.

Every `mmm` subcommand except `ask`/`import` (which need the `claude` CLI) works with no
Claude Code installation on the machine at all — `init`'s optional `/init` doc-seed step
skips itself with a warning instead of failing if `claude` isn't on PATH.

## What's NOT required

Neither editor's own AI features, nor oh-my-claudecode/ponytail/caveman, are dependencies of
`mmm`. `install.sh` only ever *offers* them; every offer is skippable and re-run-safe.

## Any MCP client (Cursor, Codex, others)

`integrations/mcp-server.mjs` is a dependency-free stdio MCP server exposing four tools:
`mmm_query`, `mmm_list`, `mmm_read`, `mmm_write`. Every path is confined to `~/.mmm` (its `.git`
excluded), and the first write of each server run snapshots the store into its git history, the
same restore point Claude Code's `SessionStart` hook takes. `install.sh` registers it for Cursor
in `~/.cursor/mcp.json`. For any other client, point it at:

```json
{"mcpServers": {"mmm": {"command": "node", "args": ["~/mmm/integrations/mcp-server.mjs"]}}}
```

(expand `~` yourself if the client doesn't). Codex: `codex mcp add mmm -- node ~/mmm/integrations/mcp-server.mjs`.
Claude Code doesn't need it, since it already reads and writes the files directly.
