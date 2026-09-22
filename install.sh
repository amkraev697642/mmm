#!/bin/sh
# mmm installer — clones/updates the tool into an install dir and puts it on PATH.
# Usage: curl -fsSL <raw-url>/install.sh | sh
# POSIX sh, deliberately — piped to `sh`, which is dash (not bash) on plenty of systems.
# No pipefail (dash doesn't have it), no arrays, no [[, no local.
set -eu

REPO_URL="${MMM_REPO:-git@github.com:amkraev697642/mmm.git}"
TARGET="${MMM_INSTALL_DIR:-$HOME/mmm}"

# command:brew-formula pairs -- command name and Homebrew formula name diverge for rg (ripgrep)
# and 7z (p7zip; the "sevenzip" formula only installs a "7zz" binary, not "7z").
MMM_DEPS="jq:jq git:git rsync:rsync python3:python3 rg:ripgrep 7z:p7zip"
for pair in $MMM_DEPS; do
  cmd=${pair%%:*}
  formula=${pair##*:}
  command -v "$cmd" >/dev/null 2>&1 || echo "mmm: WARN — '$cmd' not found on PATH — install it with: brew install $formula"
done

if [ -d "$TARGET/.git" ]; then
  echo "mmm: $TARGET is already a git checkout — pulling latest"
  git -C "$TARGET" pull --ff-only
else
  echo "mmm: cloning into $TARGET"
  git clone "$REPO_URL" "$TARGET"
fi

chmod +x "$TARGET"/bin/mmm "$TARGET"/bin/*.py

# Hooks are source-controlled here, not authored directly in ~/.claude/hooks/ (that's a
# machine-local runtime location, not something a clone of this repo brings with it).
mkdir -p "$HOME/.claude/hooks"
for f in "$TARGET"/hooks/*.mjs; do
  ln -sf "$f" "$HOME/.claude/hooks/$(basename "$f")"
  echo "mmm: hook -> ~/.claude/hooks/$(basename "$f")"
done

# The CLAUDE.md directive is the actual mechanism that makes an agent use mmm without being
# asked -- the SessionStart brief alone is read-only. Append-only, idempotent via the marker.
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SNIPPET="$TARGET/integrations/claude-snippet.md"
if [ -f "$CLAUDE_MD" ] && grep -q '^# >>> mmm >>>$' "$CLAUDE_MD" 2>/dev/null; then
  echo "mmm: CLAUDE.md directive already present in $CLAUDE_MD"
elif [ -r /dev/tty ]; then
  printf 'mmm: add the mmm directive to %s so your agent uses it automatically? [Y/n] ' "$CLAUDE_MD"
  ANSWER=""
  read -r ANSWER < /dev/tty || ANSWER=""
  case "$ANSWER" in
    n|N|no|No)
      echo "mmm: skipped — paste $SNIPPET into $CLAUDE_MD yourself anytime"
      ;;
    *)
      [ -s "$CLAUDE_MD" ] && printf '\n' >> "$CLAUDE_MD"
      cat "$SNIPPET" >> "$CLAUDE_MD"
      echo "mmm: appended the mmm directive to $CLAUDE_MD"
      ;;
  esac
else
  echo "mmm: non-interactive install — paste $SNIPPET into $CLAUDE_MD yourself"
fi

SETTINGS="$HOME/.claude/settings.json"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  TMP=$(mktemp)
  jq '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher":"ExitPlanMode","hooks":[{"type":"command","command":"node ~/.claude/hooks/plan-tax-mark.mjs"}]}] | unique_by(.matcher))
    | .hooks.Stop = ((.hooks.Stop // []) + [{"matcher":"*","hooks":[{"type":"command","command":"node ~/.claude/hooks/plan-tax-collect.mjs"}]}] | unique_by(.matcher))
    | .hooks.SessionStart = ((.hooks.SessionStart // []) + [{"matcher":"*","hooks":[{"type":"command","command":"node ~/.claude/hooks/wiki-brief.mjs"}]}] | unique_by(.matcher))' \
    "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
  echo "mmm: registered hooks in $SETTINGS -- see $TARGET/hooks/README.md for what each does"
else
  echo "mmm: WARN — jq or $SETTINGS not found, register the hooks manually (see $TARGET/hooks/README.md)"
fi

# Cursor integration, only if Cursor is actually present on this machine.
if [ -d "$HOME/.cursor" ]; then
  mkdir -p "$HOME/.cursor/rules"
  ln -sf "$TARGET/integrations/bootstrap.mdc" "$HOME/.cursor/rules/bootstrap.mdc"
  echo "mmm: Cursor found -> ~/.cursor/rules/bootstrap.mdc"
fi

# Optional: the oh-my-claudecode/ponytail/caveman plugins this tool's own conventions lean on
# stylistically (bite-sized content-rules.md, the hooks). Not a dependency -- mmm works without
# them -- purely a recommended-experience offer, and Claude Code only (Cursor has no plugin
# marketplace equivalent). Skipped entirely if claude isn't installed or they're already enabled.
OMC_PRESENT=0
if command -v claude >/dev/null 2>&1; then
  ALREADY=1
  if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
    ALREADY=$(jq -r '[(.enabledPlugins // {}) | keys[] | select(startswith("oh-my-claudecode@") or startswith("ponytail@") or startswith("caveman@"))] | length > 0' "$SETTINGS" 2>/dev/null || echo false)
    case "$ALREADY" in true) ALREADY=1 ;; *) ALREADY=0 ;; esac
  else
    ALREADY=0
  fi
  OMC_PRESENT="$ALREADY"
  if [ "$ALREADY" = "0" ] && [ -r /dev/tty ]; then
    printf 'mmm: also install the oh-my-claudecode/ponytail/caveman plugins? (optional, recommended) [y/N] '
    ANSWER=""
    read -r ANSWER < /dev/tty || ANSWER=""
    case "$ANSWER" in
      y|Y|yes|Yes)
        for pair in "Yeachan-Heo/oh-my-claudecode:oh-my-claudecode@omc" \
                    "DietrichGebert/ponytail:ponytail@ponytail" \
                    "alirezarezvani/claude-skills:caveman@claude-code-skills"; do
          repo=${pair%%:*}
          plugin=${pair##*:}
          claude plugin marketplace add "$repo" 2>&1 || true
          if claude plugin install "$plugin" --scope user 2>&1; then
            echo "mmm: installed $plugin"
            case "$plugin" in oh-my-claudecode@*) OMC_PRESENT=1 ;; esac
          else
            echo "mmm: WARN — failed to install $plugin, install it yourself later: claude plugin install $plugin --scope user"
          fi
        done
        ;;
      *)
        echo "mmm: skipped — install anytime with 'claude plugin install <name> --scope user' (see README)"
        ;;
    esac
  fi
fi

# Without this, OMC's own SessionEnd hook keeps auto-generating empty session-log stub pages
# into the wiki forever — every one of them dead weight, never promoted, never cleaned up. Only
# relevant, and only written, when oh-my-claudecode is actually present (including one just
# installed above) — mmm itself never reads or needs this file.
if [ "$OMC_PRESENT" = "1" ]; then
  OMC_CONFIG="$HOME/.claude/.omc-config.json"
  if command -v jq >/dev/null 2>&1; then
    if [ -f "$OMC_CONFIG" ]; then
      TMP=$(mktemp)
      jq '.wiki.autoCapture = false' "$OMC_CONFIG" > "$TMP" && mv "$TMP" "$OMC_CONFIG"
    else
      printf '{\n  "wiki": {\n    "autoCapture": false\n  }\n}\n' > "$OMC_CONFIG"
    fi
    echo "mmm: disabled OMC's session-log auto-capture in $OMC_CONFIG"
  else
    echo "mmm: WARN — jq not found, disable OMC session-log auto-capture manually: {\"wiki\":{\"autoCapture\":false}} in $OMC_CONFIG"
  fi
fi

RC="$HOME/.zshrc"
[ "${SHELL:-}" = "/bin/bash" ] && RC="$HOME/.bash_profile"
LINE="export PATH=\"$TARGET/bin:\$PATH\""
if ! grep -qxF "$LINE" "$RC" 2>/dev/null; then
  printf '\n%s\n' "$LINE" >> "$RC"
  echo "mmm: added to PATH in $RC — restart your terminal, or run: source $RC"
else
  echo "mmm: already on PATH via $RC"
fi

echo "mmm: installed at $TARGET. Run 'mmm' to get started (see $TARGET/README.md)."
