# What `mmm doctor` actually checks

**The goal, stated once:** doctor answers *"is the store structurally sound and safe to hand
off?"* — never *"is the knowledge any good?"* It's a structural and safety linter, not an
editor. It auto-repairs exactly one thing (a missing git-ignore entry); everything else is
read-only reporting. `mmm pack` runs it first and refuses to produce an archive if it fails.

| Does | Does **not** |
|---|---|
| `[[slug]]` links resolve tree-wide; `[text](file.md)` targets exist | Validate frontmatter (`title`/`category`/`tags`/`updated`) — required by [content-rules.md](../content-rules.md), never checked |
| Page budget (150 lines), exempting `plans/` and `deep-research/` | Judge content: staleness, duplication, contradictions, factual accuracy |
| `.omc` is git-ignored per registered project — **auto-repairs** via `.git/info/exclude` | Touch project git in any other way |
| Symlink health per project (linked / dangling / unexpected target / not-yet-initialized) — **dangling or unexpected now fails doctor**, not just prints a note | Verify the archive itself, its encryption, or a real round-trip |
| Greps `*.md`/`*.json` for the literal strings `ticket=`, `token=`, `secret`, `password` | **Detect actual secrets.** Four keywords, no entropy check, no key-format matching — false-positives on prose *about* security, and misses a bare API key, a PEM block, or a JWT |
| Index completeness for **top-level** pages in each tier's `index.md` | Check pages inside subdirectories (`tech/`, `decisions/`, …) — an orphaned page one level deep prints a `WARN`, not a failure, and doesn't fail the run either |
| Confirms `ponytail`/`caveman` are `true` in a staged `claude/settings.json` | Confirm anything about a `claude/` subset that hasn't been staged yet (prints `SKIP`) |

## Exit codes

`ALL CLEAR` → 0. `ISSUES FOUND` → 1 (and `mmm pack` stops before archiving). A project
reported "absent on this machine" is informational only and never fails the run — that's the
normal state for a registered project you simply haven't cloned here.

## The known false-positive

The secret grep is intentionally broad and *will* flag a page that merely discusses secrets
(a design doc using the word "password" in a sentence about encryption, say). That's not a
bug to silence — loosening the pattern to dodge it would also loosen it for a real leak.
Treat a doctor `FAIL` on the secret scan as "go read the line," not "go patch the regex."

## If you want more

A real secret scanner (entropy-based, like `gitleaks`) would catch what the keyword grep
misses, and is deliberately out of scope for now — it's a new dependency, against the
no-new-deps stance the rest of the tool holds to. If that changes, this file changes with it.
