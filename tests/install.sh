#!/usr/bin/env bash
# Installer test: drives install.sh's setup screen through a pty (script(1)) against a throwaway
# HOME, with a stub brew that only logs. No network, never touches the real ~/.mmm or ~/.zshrc.
# Keystrokes are fed with sleeps between screens -- slow (~40s), but it's the real terminal path.
# Run it from anywhere: `bash tests/install.sh`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # $T, mkbin(), stub_brew()
command -v 7z >/dev/null || { echo "SKIP: needs 7z for the seed case"; exit 0; }

fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

# install.sh clones MMM_REPO -- a snapshot of the working tree, so uncommitted changes are tested
rsync -a --exclude .git "$ROOT"/ "$T/src/"
git -C "$T/src" init -q && git -C "$T/src" add -A
git -C "$T/src" -c user.name=t -c user.email=t@t commit -qm test

mkbin nodeps brew jq node claude; stub_brew nodeps
mkbin withdeps brew claude; stub_brew withdeps
mkdir -p "$T/nobrew"; for f in sh git; do ln -s "$(command -v $f)" "$T/nobrew/$f"; done

# run <home> <bindir> <feeder-fn> [VAR=val ...]: install.sh in a pty, keystrokes from the feeder
run() {
  local home="$T/$1" bin="$T/$2" feed="$3"; shift 3
  mkdir -p "$home"
  local cmd=(env -i HOME="$home" PATH="$bin" TERM=xterm SHELL=/bin/zsh MMM_REPO="$T/src" "$@" sh "$T/src/install.sh")
  if script -q /dev/null true 2>/dev/null; then  # BSD/macOS: script [-q] file cmd...
    "$feed" | script -q "$home/typescript" "${cmd[@]}" >/dev/null 2>&1 || true
  else                                          # util-linux: script -qec "cmd" file
    "$feed" | script -qec "$(printf '%q ' "${cmd[@]}")" "$home/typescript" >/dev/null 2>&1 || true
  fi
  tr -d '\r' < "$home/typescript" > "$home/out"
}
S() { sleep "$1"; }

echo "-- no brew: refuses before touching anything --"
mkdir -p "$T/h0"
if env -i HOME="$T/h0" PATH="$T/nobrew" sh "$T/src/install.sh" > "$T/h0/out" 2>&1; then rc=0; else rc=$?; fi
check "exits non-zero" '[ "$rc" != 0 ]'
check "says Homebrew is required" 'grep -q "Homebrew required" "$T/h0/out"'
check "nothing cloned" '[ ! -e "$T/h0/mmm" ]'

echo "-- keyboard: Required rows stay ticked; a plugin whose dep is unticked is skipped --"
# rows: 1 git 2 jq 3 node 4 python3 5 rsync 6 rg 7 7z 8 claude 9 oh-my-claudecode 10 ponytail 11 caveman
feed_keys() { S 1; printf '\n'; S 1; printf 'j '; S .5; printf 'j '; S .5; printf 'jjjjj '; S .5; printf 'j '; S .5; printf 'k '; S .5; printf '\n'; S 3; printf 'n\n'; S 3; }
run h1 nodeps feed_keys
check "space on jq/node can't untick them" 'grep -qx "brew install jq node" "$T/h1/brew.log"'
check "unticked claude not installed" '! grep -q "cask" "$T/h1/brew.log"'
check "plugin skipped while claude is unticked" '! grep -q "claude plugin install\|failed to install" "$T/h1/out"'
check "plugins drawn dim before deps are chosen" 'grep -aqF "$(printf "\033[2m") [ ] oh-my-claudecode" "$T/h1/out"'
check "cloned" '[ -x "$T/h1/mmm/bin/mmm" ]'

echo "-- mouse: click a dim plugin (no-op), claude, the plugin; keys for another --"
# screen lines: title 1, Required 3, rows 4-9, Optional 11, 7z 12, claude 13, Plugins 15, omc 16
feed_mouse() { S 1; printf '\n'; S 1; printf '\033[<0;5;16M\033[<0;5;16m'; S .5; printf '\033[<0;5;13M\033[<0;5;13m'; S .5; printf '\033[<0;5;16M\033[<0;5;16m'; S .5; printf 'jj '; S .5; printf '\n'; S 3; printf 'n\n'; S 3; }
run h2 nodeps feed_mouse
check "brew gets missing jq + node in one call" 'grep -qx "brew install jq node" "$T/h2/brew.log"'
check "click selected claude" 'grep -qx "brew install --cask claude-code" "$T/h2/brew.log"'
check "click selected oh-my-claudecode" 'grep -q "install oh-my-claudecode@omc" "$T/h2/out"'
check "keys selected caveman" 'grep -q "install caveman@claude-code-skills" "$T/h2/out"'
check "ponytail left alone" '! grep -q "install ponytail@" "$T/h2/out"'

echo "-- non-interactive: warnings only, no brew, no plugins --"
feed_none() { S 1; }
run h3 nodeps feed_none MMM_NONINTERACTIVE=1
check "warns about jq and node" 'grep -q "'"'"'jq'"'"' not found" "$T/h3/out" && grep -q "'"'"'node'"'"' not found" "$T/h3/out"'
check "no brew calls" '[ ! -s "$T/h3/brew.log" ]'
check "still installs" '[ -x "$T/h3/mmm/bin/mmm" ]'

echo "-- seed archive: unpack + link global, present project, hint for absent one --"
H="$T/h4"; mkdir -p "$H/code/proj" "$T/store/global" "$T/store/projects/proj" "$T/store/projects/gone"
git -C "$H/code/proj" init -q && git -C "$H/code/proj" remote add origin https://example.com/proj.git
echo .omc > "$H/code/proj/.gitignore"
for d in global projects/proj projects/gone; do printf -- '---\ntitle: Index\n---\n# %s\n' "$d" > "$T/store/$d/index.md"; done
printf '{"searchRoots":[],"projects":{"proj":{"remote":"https://example.com/proj.git","pathHint":"%s"},"gone":{"remote":"git@github.com:x/gone.git","pathHint":"/nowhere/gone"}}}\n' \
  "$H/code/proj" > "$T/store/registry.json"
(cd "$T/store" && 7z a -ptest -mhe=on "$H/seed.7z" registry.json global projects >/dev/null)
# typed as ~/..., the way a person would; 7z's password prompt comes after the CLAUDE.md one
feed_seed() { S 1; printf '~/seed.7z\n'; S 1; printf '\n'; S 3; printf 'n\n'; S 4; printf 'test\n'; S 6; }
run h4 withdeps feed_seed
check "no 7z overwrite prompt over the first-run registry" '! grep -q "replace the existing file" "$H/out"'
check "global wiki linked" '[ -L "$H/.omc/wiki" ] && [ -f "$H/.omc/wiki/index.md" ]'
check "present project linked" '[ -L "$H/code/proj/.omc/wiki" ] && [ -f "$H/code/proj/.omc/wiki/index.md" ]'
check "absent project gets a clone hint" 'grep -q "gone: not on this machine — git clone git@github.com:x/gone.git" "$H/out"'
check "registry has both projects" '[ "$(jq -r ".projects | keys | join(\",\")" "$H/.mmm/registry.json")" = "gone,proj" ]'
check "hooks registered in a fresh settings.json" 'jq -e ".hooks.SessionStart" "$H/.claude/settings.json" >/dev/null'
check "doctor clear" 'PATH="$T/withdeps" HOME="$H" "$H/mmm/bin/mmm" doctor 2>&1 | grep -q "ALL CLEAR"'

echo "-- unpack merges into an existing registry instead of replacing it --"
M="$T/h5"; mkdir -p "$M/.mmm"
printf '{"searchRoots":["~/code"],"projects":{"mine":{"remote":"https://example.com/mine.git","pathHint":"/nowhere/mine"}}}\n' > "$M/.mmm/registry.json"
printf 'test\n' | HOME="$M" PATH="$T/withdeps" "$ROOT/bin/mmm" unpack "$H/seed.7z" > "$M/out" 2>&1 || true
check "local project kept" 'jq -e ".projects.mine" "$M/.mmm/registry.json" >/dev/null'
check "archive projects added" 'jq -e ".projects.proj and .projects.gone" "$M/.mmm/registry.json" >/dev/null'
check "searchRoots kept" '[ "$(jq -r ".searchRoots[0]" "$M/.mmm/registry.json")" = "~/code" ]'

echo "-- domain delivery: a real 'mmm pack --domain' archive, unpacked through the installer --"
# hand-built store (like the seed archive above), but shaped as a delivery: a rootless domain
# (the common "hand this to a colleague" case -- see developer-advocate in the real rollout) with
# one member project and one project deliberately left OUT, to prove --domain really excludes it
S2="$T/store2"; mkdir -p "$S2/global" "$S2/domains/delivery-test" "$S2/projects/member" "$S2/projects/outsider"
printf '# Wiki Index\n\n' > "$S2/global/index.md"
printf '# Wiki Index\n\n- [[note]]\n' > "$S2/domains/delivery-test/index.md"
printf -- '---\ntitle: Note\ncategory: test\ntags: [delivery]\nupdated: 2026-09-28\n---\ndelivery-test only\n' \
  > "$S2/domains/delivery-test/note.md"
printf '# Wiki Index\n\n' > "$S2/projects/member/index.md"
printf '# Wiki Index\n\n' > "$S2/projects/outsider/index.md"
printf '{"searchRoots":[],"domains":{"delivery-test":{"sources":[]}},"projects":{"member":{"remote":"https://example.com/member.git","pathHint":"/nowhere/member","domains":["delivery-test"]},"outsider":{"remote":"https://example.com/outsider.git","pathHint":"/nowhere/outsider"}}}\n' \
  > "$S2/registry.json"

H6="$T/h6"; mkdir -p "$H6"
# a throwaway HOME for the pack step itself: cmd_status's global check compares against the real
# $HOME/.omc/wiki, not MMM_HOME-relative, so packing from the ambient dev HOME would pick up
# whatever's really linked there instead of this hand-built store
HOME="$T/store2home" MMM_HOME="$S2" "$ROOT/bin/mmm" pack --domain delivery-test --out "$H6/domain-seed.7z" < /dev/null \
  > "$S2/pack.out" 2>&1 || { cat "$S2/pack.out"; echo "FAIL: mmm pack --domain (setup)"; fail=1; }
check "pack wrote a real archive" '[ -s "$H6/domain-seed.7z" ]'

# same feeder shape as feed_seed above, empty password instead of 'test' (packed with none)
feed_domain_seed() { S 1; printf '~/domain-seed.7z\n'; S 1; printf '\n'; S 3; printf 'n\n'; S 4; printf '\n'; S 6; }
run h6 withdeps feed_domain_seed
check "domain page landed in the store" '[ -f "$H6/.mmm/domains/delivery-test/note.md" ]'
check "member project registered" 'jq -e ".projects.member" "$H6/.mmm/registry.json" >/dev/null'
check "member project (not checked out here) gets a clone hint" \
  'grep -q "member: not on this machine" "$H6/out"'
check "project outside the domain never shipped" '! jq -e ".projects.outsider" "$H6/.mmm/registry.json" >/dev/null 2>&1'
check "doctor clear on the delivered store" 'PATH="$T/withdeps" HOME="$H6" "$H6/mmm/bin/mmm" doctor 2>&1 | grep -q "ALL CLEAR"'

[ "$fail" = 0 ] && echo "install test: ALL PASS" || { echo "install test: FAILURES"; exit 1; }
