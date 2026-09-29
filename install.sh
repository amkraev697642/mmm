#!/bin/sh
# mmm installer — clones/updates the tool into an install dir and puts it on PATH.
# Usage: curl -fsSL <raw-url>/install.sh | sh [-s -- <packed-wiki.7z|.zip>]
# POSIX sh, deliberately — piped to `sh`, which is dash (not bash) on plenty of systems.
# No pipefail (dash doesn't have it), no arrays, no [[, no local.
set -eu

# https, not ssh: installing must not require a GitHub account or key -- the clone is still the
# full source (see docs/setup.md#contribute for turning it into a fork you can push from)
REPO_URL="${MMM_REPO:-https://github.com/amkraev697642/mmm.git}"
TARGET="${MMM_INSTALL_DIR:-$HOME/mmm}"
SETTINGS="$HOME/.claude/settings.json"
SEED="${MMM_SEED:-${1:-}}"
ESC=$(printf '\033')

# every dependency below is installed through brew; half-installing without it would leave a
# fresh machine in a state that's harder to debug than not installing at all
if ! command -v brew >/dev/null 2>&1; then
  echo "mmm: Homebrew required — install it from https://brew.sh, then re-run" >&2
  exit 1
fi

# `[ -r /dev/tty ]` is true in CI too, where opening it then fails -- actually open it
INTERACTIVE=0
if [ -z "${MMM_NONINTERACTIVE:-}" ] && (exec </dev/tty) 2>/dev/null; then INTERACTIVE=1; fi

# asked first, not last: a seed archive needs 7z, which the setup screen then pre-selects
if [ -z "$SEED" ] && [ "$INTERACTIVE" = 1 ]; then
  printf 'mmm: got a packed wiki archive (.7z/.zip) to seed from? path, or Enter to skip: '
  # no -r: a path dragged in from Finder arrives with backslash-escaped spaces
  read SEED < /dev/tty || SEED=""
fi
case "$SEED" in "~/"*) SEED="$HOME/${SEED#"~/"}" ;; esac
if [ -n "$SEED" ] && [ ! -f "$SEED" ]; then
  echo "mmm: WARN — seed archive '$SEED' not found, skipping it"
  SEED=""
fi

# --- setup screen ------------------------------------------------------------
# Rows are numbered vars (R<n>_name ...), since POSIX sh has no arrays. kind: req|opt|plugin.
# state: i (already installed, not toggleable) | 1 (selected) | 0.
N=0
row() {  # name formula kind note [marketplace-repo plugin-id]
  N=$((N + 1))
  eval "R${N}_name=\$1 R${N}_formula=\$2 R${N}_kind=\$3 R${N}_note=\$4 R${N}_repo=\${5:-} R${N}_id=\${6:-}"
  case "$1" in *-*) ;; *) eval "I_$1=$N" ;; esac
}
# command name and brew formula diverge for rg (ripgrep), 7z (p7zip; the "sevenzip" formula
# only installs "7zz") and claude (a cask)
row git git req ""
row jq jq req "settings.json merges"
row node node req "every hook runs on node"
row python3 python3 req ""
row rsync rsync req ""
row rg ripgrep req ""
row 7z p7zip opt "mmm pack/unpack"
row claude "--cask claude-code" opt "Claude Code"
# Optional: the plugins this tool's own conventions lean on stylistically. Not a dependency --
# mmm works without them -- and Claude Code only (Cursor has no marketplace equivalent).
row oh-my-claudecode "" plugin "the wiki mmm sits on" Yeachan-Heo/oh-my-claudecode oh-my-claudecode@omc
row ponytail "" plugin "YAGNI coding mode" DietrichGebert/ponytail ponytail@ponytail
row caveman "" plugin "terse replies" alirezarezvani/claude-skills caveman@claude-code-skills

plugin_enabled() {
  command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ] \
    && jq -e --arg p "${1%%@*}@" '(.enabledPlugins // {}) | keys | any(startswith($p))' "$SETTINGS" >/dev/null 2>&1
}
OMC_PRESENT=0
i=1
while [ "$i" -le "$N" ]; do
  eval "k=\$R${i}_kind n=\$R${i}_name id=\$R${i}_id"
  s=0
  if [ "$k" = plugin ]; then
    if plugin_enabled "$id"; then
      s=i
      case "$id" in oh-my-claudecode@*) OMC_PRESENT=1 ;; esac
    fi
  elif command -v "$n" >/dev/null 2>&1; then s=i
  elif [ "$k" = req ]; then s=1
  elif [ "$n" = 7z ] && [ -n "$SEED" ]; then s=1
  fi
  eval "R${i}_state=\$s"
  i=$((i + 1))
done

# a plugin is only installable through the claude CLI, and its hooks need node and jq
plugins_ok() {
  # _-prefixed: sh has no locals, and toggle() is holding its own $s across this call
  for _d in node jq claude; do
    eval "_j=\$I_$_d"
    eval "_s=\$R${_j}_state"
    if [ "$_s" = 0 ]; then return 1; fi
  done
}
toggle() {
  eval "k=\$R${1}_kind s=\$R${1}_state"
  # a Required row is only ever ticked or installed -- unticking it would "succeed" into an mmm
  # that dies on its first command
  if [ "$s" = i ] || [ "$k" = req ]; then return 0; fi
  if [ "$k" = plugin ] && ! plugins_ok; then return 0; fi
  if [ "$s" = 1 ]; then eval "R${1}_state=0"; else eval "R${1}_state=1"; fi
}
move() {
  cur=$((cur + $1))
  if [ "$cur" -lt 1 ]; then cur=1; fi
  if [ "$cur" -gt "$N" ]; then cur=$N; fi
}
draw() {
  {
    printf '%s[H%s[2J%s[1mmmm setup%s — ↑↓/jk move · space toggle · enter install · q skip · click toggles\n' "$ESC" "$ESC" "$ESC" "$ESC[0m"
    line=1; last=""; pok=0
    if plugins_ok; then pok=1; fi
    i=1
    while [ "$i" -le "$N" ]; do
      eval "k=\$R${i}_kind n=\$R${i}_name f=\$R${i}_formula note=\$R${i}_note s=\$R${i}_state id=\$R${i}_id"
      if [ "$k" != "$last" ]; then
        case "$k" in
          req) h="Required" ;;
          opt) h="Optional" ;;
          plugin) h="Claude Code plugins (need node + jq + claude)" ;;
        esac
        printf '\n%s[1m%s%s[0m\n' "$ESC" "$h" "$ESC"
        line=$((line + 2)); last=$k
      fi
      line=$((line + 1))
      eval "L_$line=$i"
      how="brew install $f"
      if [ "$k" = plugin ]; then how=$id; fi
      case "$s" in
        i) box="$ESC[32m ✓ $ESC[0m"; how="installed" ;;
        1) box="[x]" ;;
        *) box="[ ]" ;;
      esac
      pre=""
      # a ticked plugin whose deps got unticked keeps its tick, shown and installed as unticked
      if [ "$k" = plugin ] && [ "$pok" = 0 ] && [ "$s" != i ]; then pre="$ESC[2m"; box="[ ]"; fi
      if [ "$i" = "$cur" ]; then pre="$pre$ESC[7m"; fi
      printf '%s %s %-18s %-34s %s%s[0m\n' "$pre" "$box" "$n" "$how" "$note" "$ESC"
      i=$((i + 1))
    done
  } > /dev/tty
}
key() { dd bs=1 count=1 2>/dev/null < /dev/tty; }
# SGR mouse report: ESC [ < button ; x ; y (M press | m release)
mouse() {
  m=""
  while :; do
    c=$(key)
    case "$c" in M|m) break ;; '') return 0 ;; esac
    m="$m$c"
  done
  if [ "$c" != M ]; then return 0; fi
  b=${m%%;*}; y=${m##*;}
  case "$y" in ''|*[!0-9]*) return 0 ;; esac
  case "$b" in
    0) eval "r=\${L_$y:-}"
       if [ -n "$r" ]; then cur=$r; toggle "$r"; fi ;;
  esac
}
restore() {
  printf '%s[?1000l%s[?1006l%s[?25h' "$ESC" "$ESC" "$ESC" > /dev/tty
  stty "$SAVED_STTY" < /dev/tty
}

QUIT=0
if [ "$INTERACTIVE" = 1 ]; then
  SAVED_STTY=$(stty -g < /dev/tty)
  trap restore EXIT
  trap 'restore; exit 130' INT TERM
  stty -icanon -echo min 1 time 0 < /dev/tty
  printf '%s[?25l%s[?1000h%s[?1006h' "$ESC" "$ESC" "$ESC" > /dev/tty
  cur=1
  while :; do
    draw
    c=$(key)
    case "$c" in
      '') break ;;  # Enter: icrnl turns it into \n, which $(...) strips
      ' ') toggle "$cur" ;;
      j) move 1 ;;
      k) move -1 ;;
      q) QUIT=1; break ;;
      "$ESC")
        if [ "$(key)" = "[" ]; then
          case "$(key)" in A) move -1 ;; B) move 1 ;; '<') mouse ;; esac
        fi ;;
    esac
  done
  restore
  trap - EXIT INT TERM
  printf '%s[H%s[2J' "$ESC" "$ESC"
fi

FORMULAS=""; CASK=0; PLUGINS=""
i=1
while [ "$i" -le "$N" ]; do
  eval "k=\$R${i}_kind n=\$R${i}_name f=\$R${i}_formula s=\$R${i}_state r=\$R${i}_repo id=\$R${i}_id"
  if [ "$INTERACTIVE" = 0 ]; then
    if [ "$s" != i ] && [ "$k" != plugin ]; then echo "mmm: WARN — '$n' not found on PATH — install it with: brew install $f"; fi
  elif [ "$QUIT" = 0 ] && [ "$s" = 1 ]; then
    case "$k:$n" in
      plugin:*) if plugins_ok; then PLUGINS="$PLUGINS $r:$id"; fi ;;
      *:claude) CASK=1 ;;
      *) FORMULAS="$FORMULAS $f" ;;
    esac
  fi
  i=$((i + 1))
done
if [ "$QUIT" = 1 ]; then echo "mmm: setup screen skipped — nothing installed through brew"; fi
if [ -n "$FORMULAS" ]; then
  echo "mmm: brew install$FORMULAS"
  # word splitting on $FORMULAS is the point: one formula per word
  # shellcheck disable=SC2086
  brew install $FORMULAS || echo "mmm: WARN — brew install failed, re-run it yourself: brew install$FORMULAS"
fi
if [ "$CASK" = 1 ]; then
  echo "mmm: brew install --cask claude-code"
  brew install --cask claude-code || echo "mmm: WARN — brew install --cask claude-code failed"
fi
if ! command -v git >/dev/null 2>&1; then
  echo "mmm: git is required to install — brew install git, then re-run" >&2
  exit 1
fi

if [ -d "$TARGET/.git" ]; then
  echo "mmm: $TARGET is already a git checkout — pulling latest"
  git -C "$TARGET" pull --ff-only
else
  echo "mmm: cloning into $TARGET"
  git clone "$REPO_URL" "$TARGET"
fi

chmod +x "$TARGET"/bin/mmm "$TARGET"/bin/*.py "$TARGET"/integrations/mcp-server.mjs
# bin/mmm's version string is stamped at commit time by .githooks/pre-commit -- wire it for
# every checkout of the tool repo itself, not just this machine's first clone
git -C "$TARGET" config core.hooksPath .githooks

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
elif [ "$INTERACTIVE" = 1 ]; then
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

# a fresh machine has no settings.json until Claude Code first writes one -- start it empty
# rather than leave the hooks unregistered
if command -v jq >/dev/null 2>&1 && [ ! -f "$SETTINGS" ]; then printf '{}\n' > "$SETTINGS"; fi
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  TMP=$(mktemp)
  jq '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher":"ExitPlanMode","hooks":[{"type":"command","command":"node ~/.claude/hooks/plan-tax-mark.mjs"}]},{"matcher":"Read|Edit|Write|MultiEdit","hooks":[{"type":"command","command":"node ~/.claude/hooks/wiki-recall.mjs"}]}] | unique_by(.matcher))
    | .hooks.Stop = ((.hooks.Stop // []) + [{"matcher":"*","hooks":[{"type":"command","command":"node ~/.claude/hooks/plan-tax-collect.mjs"}]}] | unique_by(.matcher))
    | .hooks.SessionStart = ((.hooks.SessionStart // []) + [{"matcher":"*","hooks":[{"type":"command","command":"node ~/.claude/hooks/wiki-brief.mjs"}]}] | unique_by(.matcher))
    | .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [{"matcher":"*","hooks":[{"type":"command","command":"node ~/.claude/hooks/session-harvest.mjs"}]}] | unique_by(.matcher))' \
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
  # the rule tells Cursor where the wiki is; the MCP server gives it tools to query/read/write it
  CURSOR_MCP="$HOME/.cursor/mcp.json"
  if command -v jq >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    [ -f "$CURSOR_MCP" ] || printf '{}\n' > "$CURSOR_MCP"
    TMP=$(mktemp)
    jq --arg p "$TARGET/integrations/mcp-server.mjs" '.mcpServers.mmm = {"command":"node","args":[$p]}' \
      "$CURSOR_MCP" > "$TMP" && mv "$TMP" "$CURSOR_MCP"
    echo "mmm: registered the mmm MCP server in $CURSOR_MCP"
  else
    echo "mmm: WARN — jq or node not found, add the mmm MCP server to $CURSOR_MCP yourself (see docs/editors.md)"
  fi
fi

# plugins picked on the setup screen; installed only now so claude (maybe just brewed) exists
for pair in $PLUGINS; do
  repo=${pair%%:*}
  plugin=${pair#*:}
  claude plugin marketplace add "$repo" 2>&1 || true
  if claude plugin install "$plugin" --scope user 2>&1; then
    echo "mmm: installed $plugin"
    case "$plugin" in oh-my-claudecode@*) OMC_PRESENT=1 ;; esac
  else
    echo "mmm: WARN — failed to install $plugin, install it yourself later: claude plugin install $plugin --scope user"
  fi
done

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

# last, once mmm itself is in place: unpack also links the global wiki and every project it finds
if [ -n "$SEED" ]; then
  if ! command -v 7z >/dev/null 2>&1; then
    echo "mmm: WARN — 7z not found, can't unpack $SEED — brew install p7zip, then: mmm unpack \"$SEED\""
  else
    # piped through curl, stdin is this script -- 7z's password prompt needs the terminal
    IN=/dev/stdin; if [ "$INTERACTIVE" = 1 ]; then IN=/dev/tty; fi
    "$TARGET/bin/mmm" unpack "$SEED" < "$IN" || echo "mmm: WARN — unpack failed, retry with: mmm unpack \"$SEED\""
  fi
fi

echo "mmm: installed at $TARGET. Run 'mmm' to get started (see $TARGET/README.md)."
echo "mmm: $TARGET is the full source — to contribute, see $TARGET/docs/setup.md#contribute"
