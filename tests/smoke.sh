#!/usr/bin/env bash
# Smoke test: init, doctor and query against a throwaway HOME. No framework, no network, never
# touches the real ~/.mmm. Run it from anywhere: `bash tests/smoke.sh`.
set -euo pipefail

MMM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/mmm"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# init refuses to register a repo under $TMPDIR (looks ephemeral), so the fake HOME must sit
# outside the TMPDIR mmm sees, even though both live under the real tmp dir
export HOME="$T/home" TMPDIR="$T/tmp"
unset MMM_HOME
mkdir -p "$HOME" "$TMPDIR"
export GIT_CONFIG_NOSYSTEM=1

# a PATH with rsync, 7z and claude hidden: proves the commands that don't use them no longer
# require them, and guarantees nothing here ever reaches a real claude call
NODEPS="$T/nodeps-bin"
mkdir -p "$NODEPS"
IFS=: read -ra path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    name=$(basename "$f")
    case "$name" in rsync|7z|claude) continue ;; esac
    [ -x "$f" ] && [ ! -e "$NODEPS/$name" ] && ln -s "$f" "$NODEPS/$name"
  done
done

pass=0
ok() { pass=$((pass + 1)); echo "ok $pass - $*"; }
fail() { echo "FAIL - $*" >&2; exit 1; }
nodeps() { PATH="$NODEPS" "$MMM" "$@"; }

nodeps status >/dev/null || fail "status without rsync/7z/claude"
[ -f "$HOME/.mmm/registry.json" ] || fail "first run did not create the registry"
ok "status runs without rsync/7z/claude and bootstraps the registry"

if PATH="$NODEPS" "$MMM" init --global 2>"$T/err"; then
  fail "init should refuse to run without rsync"
fi
grep -q "requires 'rsync'" "$T/err" || fail "init without rsync gave no install hint: $(cat "$T/err")"
ok "init without rsync fails with an install hint"

if command -v rsync >/dev/null 2>&1; then
  "$MMM" init --global >/dev/null
  [ -L "$HOME/.omc/wiki" ] || fail "global wiki not linked"
  ok "init --global links ~/.omc/wiki"

  proj="$HOME/src/demo"
  mkdir -p "$proj/.omc/wiki"
  git -C "$proj" init -q
  git -C "$proj" remote add origin https://example.invalid/demo.git
  # a CLAUDE.md up front keeps init from shelling out to 'claude /init'
  printf '# demo\n' > "$proj/CLAUDE.md"
  printf -- '---\ntitle: Old note\ncategory: misc\ntags: [demo]\nupdated: 2026-01-01\n---\npre-existing\n' \
    > "$proj/.omc/wiki/old-note.md"
  "$MMM" init "$proj" >/dev/null
  store="$HOME/.mmm/projects/demo"
  [ -L "$proj/.omc/wiki" ] || fail "project wiki not linked"
  [ -f "$store/old-note.md" ] || fail "existing wiki content not adopted into the store"
  [ -L "$proj/CLAUDE.md" ] && [ -f "$store/CLAUDE.md" ] || fail "CLAUDE.md not moved into the store"
  { git -C "$proj" check-ignore -q .omc && git -C "$proj" check-ignore -q CLAUDE.md; } || fail ".omc/CLAUDE.md not git-ignored"
  ok "init <repo> adopts the existing wiki and CLAUDE.md, git-ignores both"
  printf '# Wiki Index\n\n- [[old-note]]\n' >> "$store/index.md"
else
  # without rsync the global store is created by hand, so doctor/query below still run
  echo "skip - init happy path (rsync not on PATH)"
  mkdir -p "$HOME/.mmm/global" "$HOME/.omc"
  ln -s "$HOME/.mmm/global" "$HOME/.omc/wiki"
fi

global="$HOME/.mmm/global"
printf -- '---\ntitle: Smoke page\ncategory: test\ntags: [smoke]\nupdated: 2026-01-01\n---\nThe zebracorn lives here.\n' \
  > "$global/smoke-page.md"
printf '# Wiki Index\n\n- [[smoke-page]]\n' > "$global/index.md"

nodeps doctor >"$T/doctor.out" || { cat "$T/doctor.out"; fail "doctor on a clean store"; }
grep -q "ALL CLEAR" "$T/doctor.out" || fail "doctor did not say ALL CLEAR"
ok "doctor passes on a clean store"

printf 'see [[no-such-page]]\n' >> "$global/smoke-page.md"
if nodeps doctor >"$T/doctor.out"; then fail "doctor missed a broken [[link]]"; fi
grep -q "no-such-page" "$T/doctor.out" || fail "doctor failed without naming the broken link"
ok "doctor fails on a broken [[link]]"
sed -i.bak '/no-such-page/d' "$global/smoke-page.md" && rm -f "$global/smoke-page.md.bak"

nodeps q zebracorn >"$T/q.out" || fail "query exited non-zero"
grep -q "smoke-page" "$T/q.out" || fail "query did not find the page: $(cat "$T/q.out")"
ok "q finds a page without rsync/7z/claude on PATH"

nodeps q zebracorn --json | python3 -c 'import json,sys; json.load(sys.stdin)' \
  || fail "q --json is not valid JSON"
ok "q --json emits valid JSON"

# built by concatenation so this file never itself looks like a leaked token
printf 'leaked %s\n' "ghp_$(printf 'a%.0s' $(seq 36))" >> "$global/smoke-page.md"
if nodeps doctor >"$T/doctor.out"; then fail "doctor missed a credential-shaped string in a page"; fi
grep -q "credential-shaped" "$T/doctor.out" || fail "doctor failed without naming the secret scan"
ok "doctor fails on a credential-shaped string in a .md page"
sed -i.bak '/^leaked /d' "$global/smoke-page.md" && rm -f "$global/smoke-page.md.bak"

nodeps git log --oneline >"$T/git.out" || fail "~/.mmm is not a git repo"
grep -q "mmm: start history" "$T/git.out" || fail "no initial snapshot in ~/.mmm history"
ok "~/.mmm keeps its own git history"

printf -- '---\ntitle: Linker\ncategory: test\ntags: [smoke]\nupdated: 2026-01-01\n---\nsee [[smoke-page]]\n' \
  > "$global/linker.md"
nodeps links smoke-page >"$T/links.out" || fail "links exited non-zero"
grep -q "global/linker.md" "$T/links.out" || fail "links missed a backlink: $(cat "$T/links.out")"
ok "links lists backlinks"

if command -v node >/dev/null 2>&1; then
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mmm_read","arguments":{"path":"global/linker.md"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"mmm_read","arguments":{"path":"../escape.md"}}}' \
    | node "$(dirname "$MMM")/../integrations/mcp-server.mjs" >"$T/mcp.out"
  grep '"id":1' "$T/mcp.out" | grep -q "Linker" || fail "MCP mmm_read did not return the page"
  grep '"id":2' "$T/mcp.out" | grep -q "escapes" || fail "MCP server let a path escape ~/.mmm"
  ok "MCP server reads pages and refuses paths outside ~/.mmm"
fi

echo "smoke: all $pass checks passed"
