# Setting up mmm

## Got an archive (`.7z` / `.zip`)?

The one prerequisite is [Homebrew](https://brew.sh). The installer refuses without it rather
than half-install.

```
curl -fsSL https://raw.githubusercontent.com/amkraev697642/mmm/main/install.sh | sh -s -- ~/Downloads/mmm-2026-09.7z
```

(Or run it without the path — it asks for one first; dragging the file in from Finder works.)

1. **Setup screen.** Missing required tools (`jq`, `node`, …) come pre-ticked; `7z` is
   ticked for you because you gave an archive. `↑↓`/`jk` move, `space` toggles, `enter`
   installs everything ticked with one `brew install`, `q` skips. A mouse click toggles too.
   Claude Code plugins stay greyed out until `node`, `jq` and `claude` are ticked or installed.
2. **Clone** into `~/mmm`, put `~/mmm/bin` on your `PATH`, register the hooks.
3. **Unpack** — type the archive's password. This lays the wiki into `~/.mmm`, then links:
   - the global wiki at `~/.omc/wiki`,
   - every project in the archive that's already cloned on this machine,
   - and prints a `git clone …` line for each one that isn't.

For a project that wasn't here yet: clone it, then `mmm init <path>`. Check everything with
`mmm doctor`, try `mmm q "some term"`.

Already installed? `mmm unpack <archive>` does step 3 on its own. Anything it changed in
`~/.mmm` is one `mmm git diff` / `mmm git checkout -- <file>` away; your own registered
projects are kept, the archive's are added.

## No archive

Same command without the path. Then `mmm init .` in each project you want in it.

## Contribute

`~/mmm` is already the full source — an https clone, so no GitHub account was needed to
install. `mmm` runs straight from it, so an edit is live on the next command. To send one
back, turn the clone into your fork:

```
brew install gh && gh auth login
cd ~/mmm && gh repo fork --remote   # your fork becomes origin, this repo upstream
```

Then see [CONTRIBUTING.md](../CONTRIBUTING.md). Re-running the installer still updates in place.
