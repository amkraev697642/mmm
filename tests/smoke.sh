#!/usr/bin/env bash
# Smoke test: init, doctor and query against a throwaway HOME. No framework, no network, never
# touches the real ~/.mmm. Run it from anywhere: `bash tests/smoke.sh`.
set -euo pipefail

MMM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/mmm"
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # $T, mkbin()

# init refuses to register a repo under $TMPDIR (looks ephemeral), so the fake HOME must sit
# outside the TMPDIR mmm sees, even though both live under the real tmp dir
export HOME="$T/home" TMPDIR="$T/tmp"
unset MMM_HOME
mkdir -p "$HOME" "$TMPDIR"

# a PATH with rsync, 7z and claude hidden: proves the commands that don't use them no longer
# require them, and guarantees nothing here ever reaches a real claude call
mkbin nodeps rsync 7z claude

pass=0
ok() { pass=$((pass + 1)); echo "ok $pass - $*"; }
fail() { echo "FAIL - $*" >&2; exit 1; }
nodeps() { PATH="$T/nodeps" "$MMM" "$@"; }

# status works with rsync/7z/claude hidden from PATH and creates the registry on first run
nodeps status >/dev/null || fail "status without rsync/7z/claude"
[ -f "$HOME/.mmm/registry.json" ] || fail "first run did not create the registry"
ok "status runs without rsync/7z/claude and bootstraps the registry"

# init without rsync refuses and tells you what to install
if PATH="$T/nodeps" "$MMM" init --global 2>"$T/err"; then
  fail "init should refuse to run without rsync"
fi
grep -q "requires 'rsync'" "$T/err" || fail "init without rsync gave no install hint: $(cat "$T/err")"
ok "init without rsync fails with an install hint"

if command -v rsync >/dev/null 2>&1; then
  # init --global links ~/.omc/wiki into the store
  "$MMM" init --global >/dev/null
  [ -L "$HOME/.omc/wiki" ] || fail "global wiki not linked"
  ok "init --global links ~/.omc/wiki"

  # init on a repo with an existing wiki and CLAUDE.md adopts both into the store and git-ignores them
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

# doctor passes on a clean store
nodeps doctor >"$T/doctor.out" || { cat "$T/doctor.out"; fail "doctor on a clean store"; }
grep -q "ALL CLEAR" "$T/doctor.out" || fail "doctor did not say ALL CLEAR"
ok "doctor passes on a clean store"

# doctor fails on a [[link]] to a missing page and names it
printf 'see [[no-such-page]]\n' >> "$global/smoke-page.md"
if nodeps doctor >"$T/doctor.out"; then fail "doctor missed a broken [[link]]"; fi
grep -q "no-such-page" "$T/doctor.out" || fail "doctor failed without naming the broken link"
ok "doctor fails on a broken [[link]]"
sed -i.bak '/no-such-page/d' "$global/smoke-page.md" && rm -f "$global/smoke-page.md.bak"

# q finds a page by a word in its body
nodeps q zebracorn >"$T/q.out" || fail "query exited non-zero"
grep -q "smoke-page" "$T/q.out" || fail "query did not find the page: $(cat "$T/q.out")"
ok "q finds a page without rsync/7z/claude on PATH"

# q --json prints valid JSON
nodeps q zebracorn --json | python3 -c 'import json,sys; json.load(sys.stdin)' \
  || fail "q --json is not valid JSON"
ok "q --json emits valid JSON"

# doctor fails on a credential-shaped string in a page
# built by concatenation so this file never itself looks like a leaked token
printf 'leaked %s\n' "ghp_$(printf 'a%.0s' $(seq 36))" >> "$global/smoke-page.md"
if nodeps doctor >"$T/doctor.out"; then fail "doctor missed a credential-shaped string in a page"; fi
grep -q "credential-shaped" "$T/doctor.out" || fail "doctor failed without naming the secret scan"
ok "doctor fails on a credential-shaped string in a .md page"
sed -i.bak '/^leaked /d' "$global/smoke-page.md" && rm -f "$global/smoke-page.md.bak"

# the store keeps its own git history
nodeps git log --oneline >"$T/git.out" || fail "~/.mmm is not a git repo"
grep -q "mmm: start history" "$T/git.out" || fail "no initial snapshot in ~/.mmm history"
ok "~/.mmm keeps its own git history"

# links lists the pages that link to a page
printf -- '---\ntitle: Linker\ncategory: test\ntags: [smoke]\nupdated: 2026-01-01\n---\nsee [[smoke-page]]\n' \
  > "$global/linker.md"
nodeps links smoke-page >"$T/links.out" || fail "links exited non-zero"
grep -q "global/linker.md" "$T/links.out" || fail "links missed a backlink: $(cat "$T/links.out")"
ok "links lists backlinks"

# the MCP server reads a page and refuses a path that escapes the store
if command -v node >/dev/null 2>&1; then
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mmm_read","arguments":{"path":"global/linker.md"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"mmm_read","arguments":{"path":"../escape.md"}}}' \
    | node "$(dirname "$MMM")/../integrations/mcp-server.mjs" >"$T/mcp.out"
  grep '"id":1' "$T/mcp.out" | grep -q "Linker" || fail "MCP mmm_read did not return the page"
  grep '"id":2' "$T/mcp.out" | grep -q "escapes" || fail "MCP server let a path escape ~/.mmm"
  ok "MCP server reads pages and refuses paths outside ~/.mmm"
fi

if command -v rsync >/dev/null 2>&1 && command -v 7z >/dev/null 2>&1; then
  # a second project that stays OUT of the domain -- proves --domain doesn't ship everything
  other="$HOME/src/other"; mkdir -p "$other"
  git -C "$other" init -q
  git -C "$other" remote add origin https://example.invalid/other.git
  printf '# other\n' > "$other/CLAUDE.md"
  "$MMM" init "$other" >/dev/null
  "$MMM" init --domain zzz "$HOME/other-root" >/dev/null   # domain root, no --from: nothing auto-adopted
  "$MMM" init "$proj" --domain zzz >/dev/null               # $proj ("demo") explicitly joins zzz
  printf -- '---\ntitle: Domain note\ncategory: test\ntags: [smoke]\nupdated: 2026-01-01\n---\nzzz-only fact\n' \
    > "$HOME/.mmm/domains/zzz/note.md"
  printf '\n- [[note]]\n' >> "$HOME/.mmm/domains/zzz/index.md"

  # pack --domain writes an archive that opens with an empty password
  packout="$T/domain.7z"
  "$MMM" pack --domain zzz --out "$packout" < /dev/null >"$T/pack.out" 2>&1 \
    || { cat "$T/pack.out"; fail "mmm pack --domain zzz"; }
  ok "pack --domain zzz (empty password) writes an archive"

  # a domain pack holds only that domain, its members and global, with the registry trimmed to match
  extract="$T/domain-extract"; mkdir -p "$extract"
  7z x -p"" "$packout" -o"$extract" >/dev/null 2>&1 || fail "packed archive did not open with an empty password"
  [ -f "$extract/domains/zzz/note.md" ] || fail "packed archive missing the domain's own page"
  [ -f "$extract/global/index.md" ] || fail "packed archive should ship global by default"
  [ -d "$extract/projects/demo" ] || fail "packed archive missing the domain's member project"
  [ ! -e "$extract/projects/other" ] || fail "packed archive leaked a project outside the domain"
  jq -e '(.domains | keys) == ["zzz"]' "$extract/registry.json" >/dev/null \
    || fail "packed registry should list only the zzz domain: $(cat "$extract/registry.json")"
  jq -e '(.projects | keys) == ["demo"]' "$extract/registry.json" >/dev/null \
    || fail "packed registry leaked a project outside the domain: $(cat "$extract/registry.json")"
  ok "pack --domain zzz ships only that domain's wiki + members + global, registry trimmed to match"
else
  echo "skip - pack --domain (needs rsync + 7z)"
fi

if command -v rsync >/dev/null 2>&1 && command -v 7z >/dev/null 2>&1 && command -v rg >/dev/null 2>&1; then
  # two machines syncing through a bare repo: push/pull merges instead of overwriting
  remote="$T/remote.git"; git init -q --bare "$remote"
  mA() { HOME="$T/a" MMM_SYNC_DIR="$T/a-sync" MMM_PASSWORD=pw "$MMM" "$@"; }
  mB() { HOME="$T/b" MMM_SYNC_DIR="$T/b-sync" MMM_PASSWORD=pw "$MMM" "$@"; }
  mkdir -p "$T/a" "$T/b"
  page() { printf -- '---\ntitle: %s\ncategory: test\ntags: [sync]\nupdated: 2026-01-01\n---\n# %s\n\n%s\n' "$1" "$1" "$2"; }
  mA init --global >/dev/null
  { page one "l1
l2
l3
l4
l5
l6
l7"; printf '\n- [[one]]\n'; } > "$T/a/.mmm/global/one.md"
  printf '\n- [[one]]\n' >> "$T/a/.mmm/global/index.md"
  jq '.identity = {name: "Sync User", email: "sync@example.com"}' "$T/a/.mmm/registry.json" > "$T/reg.tmp" && mv "$T/reg.tmp" "$T/a/.mmm/registry.json"
  # push then pull on a fresh machine carries the page and the registry identity
  MMM_SYNC_URL="$remote" mA push >"$T/sync.out" 2>&1 || { cat "$T/sync.out"; fail "A push"; }
  MMM_SYNC_URL="$remote" mB pull >"$T/sync.out" 2>&1 || { cat "$T/sync.out"; fail "B first pull"; }
  [ -f "$T/b/.mmm/global/one.md" ] || fail "B did not receive A's page"
  jq -e '.identity.email == "sync@example.com"' "$T/b/.mmm/registry.json" >/dev/null || fail "the registry identity did not travel to B"
  ok "push then pull on a fresh machine carries the page"

  # edits to different lines and new pages on two machines merge without loss, and a stale push is refused
  sed -i.bak 's/^l1$/l1-from-a/' "$T/a/.mmm/global/one.md"; rm "$T/a/.mmm/global/one.md.bak"
  page anew a > "$T/a/.mmm/global/a-new.md"; printf '\n- [[a-new]]\n' >> "$T/a/.mmm/global/index.md"
  sed -i.bak 's/^l7$/l7-from-b/' "$T/b/.mmm/global/one.md"; rm "$T/b/.mmm/global/one.md.bak"
  page bnew b > "$T/b/.mmm/global/b-new.md"; printf '\n- [[b-new]]\n' >> "$T/b/.mmm/global/index.md"
  mA push >"$T/sync.out" 2>&1 || { cat "$T/sync.out"; fail "A second push"; }
  if mB push >"$T/sync.out" 2>&1; then fail "B push should refuse while the remote is ahead"; fi
  grep -q "pull" "$T/sync.out" || fail "B's refused push did not say to pull"
  mB pull >"$T/sync.out" 2>&1 || { cat "$T/sync.out"; fail "B merge pull"; }
  [ "$(grep -c -- '-- linking --' "$T/sync.out")" = 1 ] && grep -q "mmm: pulled" "$T/sync.out" \
    || fail "pull should print one linking header and end with 'mmm: pulled'"
  grep -q "l1-from-a" "$T/b/.mmm/global/one.md" && grep -q "l7-from-b" "$T/b/.mmm/global/one.md" \
    || fail "merge lost one side's edit"
  [ -f "$T/b/.mmm/global/a-new.md" ] && [ -f "$T/b/.mmm/global/b-new.md" ] || fail "merge lost a new page"
  mB push >"$T/sync.out" 2>&1 || { cat "$T/sync.out"; fail "B push after merge"; }
  mA pull >"$T/sync.out" 2>&1 || { cat "$T/sync.out"; fail "A pull"; }
  [ -f "$T/a/.mmm/global/b-new.md" ] || fail "A did not receive B's page"
  ok "edits to different lines and new pages on two machines merge without loss"

  # pull initialises a domain-adopted project once, not again in the project loop
  vroot="$T/b/vroot"; mkdir -p "$vroot/proj"
  git -C "$vroot/proj" init -q; git -C "$vroot/proj" remote add origin https://example.invalid/vid/proj.git
  printf '# proj\n' > "$vroot/proj/CLAUDE.md"
  mB init --domain vid "$vroot" --from example.invalid/vid --no-clone >/dev/null 2>&1
  mB pull >"$T/sync.out" 2>&1 || { cat "$T/sync.out"; fail "B pull with a domain"; }
  [ "$(grep -c "'proj' already registered" "$T/sync.out")" = 1 ] || { cat "$T/sync.out"; fail "a domain-adopted project should be initialised once per pull"; }
  ok "pull initialises a domain-adopted project once, not again in the project loop"

  # a same-line conflict leaves markers, fails doctor and blocks push
  sed -i.bak 's/^l4$/l4-from-a/' "$T/a/.mmm/global/one.md"; rm "$T/a/.mmm/global/one.md.bak"
  sed -i.bak 's/^l4$/l4-from-b/' "$T/b/.mmm/global/one.md"; rm "$T/b/.mmm/global/one.md.bak"
  mA push >/dev/null 2>&1 || fail "A push before conflict"
  if mB pull >"$T/sync.out" 2>&1; then fail "conflicting pull should exit non-zero"; fi
  grep -q '^<<<<<<<' "$T/b/.mmm/global/one.md" || fail "conflict markers missing"
  if mB doctor >/dev/null 2>&1; then fail "doctor should fail on conflict markers"; fi
  if mB push >/dev/null 2>&1; then fail "push should refuse with an unresolved merge"; fi
  ok "a same-line conflict leaves markers, fails doctor and blocks push"
else
  echo "skip - push/pull (needs rsync + 7z + rg)"
fi

if command -v rsync >/dev/null 2>&1; then
  mI() { HOME="$T/id" "$MMM" "$@"; }
  mkdir -p "$T/id"
  mI init --global >/dev/null
  mkrepo() { mkdir -p "$1"; git -C "$1" init -q; git -C "$1" remote add origin "$2"; printf '# x\n' > "$1/CLAUDE.md"; }
  mkrepo "$T/id/src/in-dom" https://example.invalid/vid/in-dom.git
  mkrepo "$T/id/src/two" https://example.invalid/vid/two.git
  mkrepo "$T/id/other/plain" https://example.invalid/oth/plain.git
  mI init --domain vid "$T/id/src" --from example.invalid/vid --no-clone >/dev/null 2>&1
  mI init "$T/id/other/plain" >/dev/null 2>&1
  idreg="$T/id/.mmm/registry.json"
  jq '.identity = {name: "Test User", email: "default@example.com"} | .domains.vid.identity = {email: "vid@example.com"}' "$idreg" > "$T/reg.tmp" && mv "$T/reg.tmp" "$idreg"
  # init applies the domain identity to a member and the default identity to a project outside any domain
  mI init "$T/id/src/in-dom" >/dev/null 2>&1; mI init "$T/id/other/plain" >/dev/null 2>&1
  [ "$(git -C "$T/id/src/in-dom" config user.email)" = vid@example.com ] && [ "$(git -C "$T/id/src/in-dom" config user.name)" = "Test User" ] \
    || fail "a domain member should get the domain email and the default name"
  [ "$(git -C "$T/id/other/plain" config user.email)" = default@example.com ] || fail "a project in no domain should get the default identity"
  ok "init applies the domain identity, and the default to a project outside any domain"

  # init replaces a repo-local email and name that already have several values
  git -C "$T/id/src/in-dom" config --local --add user.email extra1@example.com; git -C "$T/id/src/in-dom" config --local --add user.email extra2@example.com
  git -C "$T/id/src/in-dom" config --local --add user.name Extra1; git -C "$T/id/src/in-dom" config --local --add user.name Extra2
  mI init "$T/id/src/in-dom" >/dev/null 2>&1
  [ "$(git -C "$T/id/src/in-dom" config --local --get-all user.email)" = vid@example.com ] && [ "$(git -C "$T/id/src/in-dom" config --local --get-all user.name)" = "Test User" ] \
    || fail "init should collapse multi-valued user.email/user.name to the registry identity"
  ok "init collapses a multi-valued repo-local identity to one value"

  # mmm identity says why it did not check: an unregistered repo, and a repo outside git
  mkrepo "$T/id/other/unreg" https://example.invalid/none/unreg.git
  ( cd "$T/id/other/unreg" && mI identity ) | grep -q "not a registered project" || fail "mmm identity should say an unregistered repo is not checked"
  ( cd "$T/id" && mI identity ) | grep -q "not in a git repo" || fail "mmm identity should say it is outside a git repo"
  ok "mmm identity explains when it cannot check"

  # doctor repairs a drifted git email
  git -C "$T/id/src/in-dom" config --local user.email wrong@example.com
  mI doctor >"$T/id.out" 2>&1 || true
  grep -q "REPAIR: in-dom" "$T/id.out" || { cat "$T/id.out"; fail "doctor did not notice the drifted email"; }
  [ "$(git -C "$T/id/src/in-dom" config user.email)" = vid@example.com ] || fail "doctor did not repair the drifted email"
  ok "doctor repairs a drifted git email"

  # the pre-commit hook refuses a wrong email and passes a correct one
  git -C "$T/id/src/in-dom" config --local user.email wrong@example.com
  printf 'x\n' > "$T/id/src/in-dom/f.txt"; git -C "$T/id/src/in-dom" add f.txt
  if HOME="$T/id" git -C "$T/id/src/in-dom" commit -q -m x 2>"$T/id.err"; then fail "the pre-commit hook should refuse a wrong email"; fi
  grep -q "vid@example.com" "$T/id.err" || fail "the refused commit did not say which email was expected"
  mI init "$T/id/src/in-dom" >/dev/null 2>&1
  HOME="$T/id" git -C "$T/id/src/in-dom" commit -q -m x || fail "the commit should pass once the identity is applied"
  ok "the pre-commit hook refuses a wrong email and passes a correct one"

  # the same repo spelled as ssh and https is one project
  mkrepo "$T/id/other/plain-ssh" git@example.invalid:oth/plain.git
  mI init "$T/id/other/plain-ssh" >"$T/id.out" 2>&1 || true
  grep -q "'plain' already registered" "$T/id.out" || { cat "$T/id.out"; fail "an ssh-form origin should match the https-registered project"; }
  ok "the same repo spelled as ssh and https is one project"

  # mmm identity prints where to edit
  ( cd "$T/id/src/in-dom" && mI identity ) | grep -q "To edit, see" || fail "mmm identity should print where to edit"

  # a scoped pack carries no identity
  if command -v 7z >/dev/null 2>&1; then
    mI pack --domain vid --out "$T/id.7z" </dev/null >"$T/id.out" 2>&1 || { cat "$T/id.out"; fail "pack --domain vid"; }
    mkdir -p "$T/id-x"; 7z x -p"" "$T/id.7z" -o"$T/id-x" >/dev/null 2>&1 || fail "could not open the scoped pack"
    jq -e '(has("identity") | not) and ([.domains[] | has("identity")] | any | not)' "$T/id-x/registry.json" >/dev/null \
      || fail "a scoped pack must not carry identity"
    ok "a scoped pack carries no identity"

    # pack --project ships only that project, and its registry has no identity or searchRoots
    mI pack --project plain --out "$T/id-p.7z" </dev/null >"$T/id.out" 2>&1 || { cat "$T/id.out"; fail "pack --project plain"; }
    mkdir -p "$T/id-px"; 7z x -p"" "$T/id-p.7z" -o"$T/id-px" >/dev/null 2>&1 || fail "could not open the project pack"
    [ -d "$T/id-px/projects/plain" ] && [ ! -e "$T/id-px/projects/in-dom" ] || fail "a project pack should hold only that project"
    jq -e '(.projects | keys) == ["plain"] and (has("identity") | not) and (has("searchRoots") | not)' "$T/id-px/registry.json" >/dev/null \
      || fail "a project pack's registry should list only that project and carry no identity or searchRoots: $(cat "$T/id-px/registry.json")"
    ok "a project pack ships only that project, with no identity or searchRoots in its registry"
  fi

  # doctor fails when a project's domains disagree on the email
  jq '.domains.vid2 = {sources: [], identity: {email: "v2@example.com"}} | .projects.two.domains += ["vid2"]' "$idreg" > "$T/reg.tmp" && mv "$T/reg.tmp" "$idreg"
  if mI doctor >"$T/id.out" 2>&1; then fail "doctor should fail when two domains disagree on the email"; fi
  grep -q "FAIL: two domains disagree" "$T/id.out" || { cat "$T/id.out"; fail "doctor did not report the conflicting emails"; }
  ok "doctor fails when a project's domains disagree on the email"
else
  echo "skip - identity (needs rsync)"
fi

echo "smoke: all $pass checks passed"
