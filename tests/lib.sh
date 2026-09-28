#!/usr/bin/env bash
# Shared scaffolding for tests/smoke.sh and tests/install.sh: source this after `set -euo
# pipefail`. Gives you a throwaway $T (mktemp -d, cleaned up on exit), GIT_CONFIG_NOSYSTEM=1, and
# mkbin() -- the "run mmm/install.sh as if some tool isn't installed" trick both files need.
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_NOSYSTEM=1

# mkbin <dirname> <hidden-cmd>...: builds $T/<dirname>, a PATH dir symlinking every real command
# already on PATH except the ones named -- proves the caller's invocation doesn't secretly need
# them (or lets a later stub, e.g. stub_brew, stand in for one without the real one shadowing it).
mkbin() {
  local d="$T/$1" p f n h skip; shift
  mkdir -p "$d"
  IFS=: read -ra dirs <<< "$PATH"
  for p in "${dirs[@]}"; do
    [ -d "$p" ] || continue
    for f in "$p"/*; do
      n=$(basename "$f"); skip=0
      for h in "$@"; do [ "$n" = "$h" ] && skip=1; done
      [ "$skip" = 0 ] && [ -x "$f" ] && [ ! -e "$d/$n" ] && ln -s "$f" "$d/$n"
    done
  done
}

# stub_brew <dirname>: adds a fake `brew` to an mkbin'd dir that only logs its args to
# $HOME/brew.log. Pass "brew" in mkbin's hidden list first so the real one never shadows it.
stub_brew() {
  local d="$T/$1"
  printf '#!/bin/sh\necho "brew $*" >> "$HOME/brew.log"\n' > "$d/brew"
  chmod +x "$d/brew"
}
