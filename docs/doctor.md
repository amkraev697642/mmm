# What `mmm doctor` actually checks

**The goal, stated once:** doctor answers *"is the store structurally sound and safe to hand
off?"* — never *"is the knowledge any good?"* It's a structural and safety linter, not an
editor. It auto-repairs exactly one thing (a missing git-ignore entry); everything else is
read-only reporting. `mmm pack` runs it first and refuses to produce an archive if it fails.

| Does | Does **not** |
|---|---|
| `[[slug]]` links resolve tree-wide; `[text](file.md)` targets exist | Judge whether a page's content is *right* — only whether it's dated, sourced and current by the rules below |
| Frontmatter has `title`/`category`/`tags`/`updated` (`WARN`, not a failure) | Validate frontmatter values beyond presence and the `updated` date |
| Pages whose `updated` is older than `MMM_STALE_DAYS` (default 180) — `WARN` | Decide a page is wrong just because it's old |
| Links into a page marked `superseded_by` — `WARN` | Rewrite those links for you |
| A project page's `sources:` files still exist and have no commits newer than its `updated` — `WARN` | Read the code to see whether the page is actually wrong now |
| Page budget (150 lines), exempting `plans/` and `deep-research/` | Judge content: duplication, contradictions, factual accuracy (that's `mmm tidy`) |
| `.omc` is git-ignored per registered project — **auto-repairs** via `.git/info/exclude` | Touch project git in any other way |
| Symlink health per project (linked / dangling / unexpected target / not-yet-initialized) — **dangling or unexpected now fails doctor**, not just prints a note | Verify the archive itself, its encryption, or a real round-trip |
| Greps `*.json` for the keywords `ticket=`, `token=`, `secret`, `password`, and `*.md`/`*.json` for credential *shapes*: AWS/GitHub/GitLab/Google/Slack/Anthropic/OpenAI key prefixes, PEM private-key headers, JWTs | **Detect every secret.** No entropy check, so a bare random string with no known prefix still slips through |
| Index completeness for **top-level** pages in each tier's `index.md` | Check pages inside subdirectories (`tech/`, `decisions/`, …) — an orphaned page one level deep prints a `WARN`, not a failure, and doesn't fail the run either |
| Confirms `ponytail`/`caveman` are `true` in a staged `claude/settings.json` | Confirm anything about a `claude/` subset that hasn't been staged yet (prints `SKIP`) |

## Exit codes

`ALL CLEAR` → 0. `ISSUES FOUND` → 1 (and `mmm pack` stops before archiving). A project
reported "absent on this machine" is informational only and never fails the run — that's the
normal state for a registered project you simply haven't cloned here.

## The known false-positive

The keyword grep is intentionally broad and *will* flag a JSON file that merely mentions
secrets. It no longer runs over `*.md`, because prose *about* passwords tripped it on every
design page. Pages are covered by the shape patterns instead, which only match the fixed
prefixes real credentials carry. Treat a doctor `FAIL` on either scan as "go read the line,"
not "go patch the regex."

## If you want more

A real secret scanner (entropy-based, like `gitleaks`) would catch what the keyword grep
misses, and is deliberately out of scope for now — it's a new dependency, against the
no-new-deps stance the rest of the tool holds to. If that changes, this file changes with it.
