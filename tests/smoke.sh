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

echo "smoke: all $pass checks passed"
