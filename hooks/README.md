# mmm hooks

Four Claude Code hooks that make the wiki self-maintaining. `install.sh` symlinks these into
`~/.claude/hooks/` and registers them in `~/.claude/settings.json` automatically; this page is
for manual setup (no `jq`, or a settings.json install.sh couldn't safely merge into).

- **`plan-tax-mark.mjs`** (`PostToolUse`, matcher `ExitPlanMode`) — marks a debt: plan mode was
  used, so a real finding or decision probably needs writing down somewhere.
- **`plan-tax-collect.mjs`** (`Stop`, matcher `*`) — if a debt exists and nothing under `~/.mmm`
  has changed since it was marked, nags once with a filing instruction. Clears itself silently
  once something *has* changed.
- **`wiki-brief.mjs`** (`SessionStart`, matcher `*`) — a ≤10-line brief at session start: page
  count, the current project's open tasks, a pointer to the right `index.md`. Also snapshots
  `~/.mmm` into its local git repo first, so every session starts from a restore point.
- **`wiki-recall.mjs`** (`PostToolUse`, matcher `Read|Edit|Write|MultiEdit`) — when a touched
  file matches a page's `applies_to:` globs or is cited in its `sources:`, injects a one-line
  pointer to that page. Each page at most once per session.

Manual registration — add to `~/.claude/settings.json`'s `hooks` key:

```json
{
  "hooks": {
    "PostToolUse": [
      {"matcher": "ExitPlanMode", "hooks": [{"type": "command", "command": "node ~/.claude/hooks/plan-tax-mark.mjs"}]},
      {"matcher": "Read|Edit|Write|MultiEdit", "hooks": [{"type": "command", "command": "node ~/.claude/hooks/wiki-recall.mjs"}]}
    ],
    "Stop": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "node ~/.claude/hooks/plan-tax-collect.mjs"}]}
    ],
    "SessionStart": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "node ~/.claude/hooks/wiki-brief.mjs"}]}
    ]
  }
}
```

If `settings.json` already has hooks under any of these events, merge the arrays — don't
replace the whole `hooks` key.
