# mmm content rules

The rules every wiki page in `~/.mmm` follows — part of the tool, not the data, since they're
generic rules, not this user's personal content. `mmm import`, `mmm init`'s seeding step, and
`mmm doctor`'s checks all point back here rather than each carrying their own copy.

## Page format
- Bite-sized: ~150 lines, one topic per page.
- YAML frontmatter: `title`, `category`, `tags`, `updated` at minimum.
- Cross-link with `[[slug]]` (resolves by bare filename stem, globally unique across the whole
  tree — don't use `[[index]]`, every tier has one and it can't disambiguate; link to `index.md`
  files with a real `[text](path/to/index.md)` link instead).

## Before writing
- Check whether an existing page already covers the topic — update it instead of creating a new
  one. `mmm query` is the fast way to check.
- No page-count headers in any `index.md` — a hand-maintained count with no automated
  enforcement just goes stale and misleads. `mmm doctor` checks referential completeness
  (every file has an index row, every row has a file) instead.
- No wiki-editorial meta-commentary in page content ("extracted from...", "moved from...",
  "this used to say..."). Git and each tier's `log.md` already own that history — a page states
  current facts, not how it got that way.

## The two exceptions to bite-sized
- **`deep-research/<topic>/`** — an investigation too long to compress into one page. Its own
  `index.md` as a table of contents, sub-pages still bite-sized individually.
- **`plans/`** — a design document worth keeping. Distinct from Claude Code's own ephemeral
  `~/.claude/plans/*.md`; this is the subset promoted to durable knowledge.

Both are exempt from the line budget. `plans/` is additionally exempt from the `[[link]]`
resolution check, since a design doc may use `[[...]]` to illustrate the syntax itself rather
than as a real link.

## Placement rule
Would this help on a *different* project too? → global (`~/.mmm/global`). Otherwise → that
project's own wiki (`~/.mmm/projects/<key>`). `tasks.md` is always project-local, never global,
even though it needs to travel with `mmm pack` like everything else. Likewise a project's
`CLAUDE.md`: the real file lives at `projects/<key>/CLAUDE.md` and the repo only gets a
git-ignored symlink (`mmm rebalance` maintains it), so it is never committed to the work repo.

## `tasks.md`
One per project, named exactly `tasks.md` (not `<project>-tasks.md` — a real inconsistency this
rule is written down specifically to prevent from recurring). Two sections only: `## To
Implement`, `## To Test`. One line per item, `- [ ]` checkbox, link out to the detailed page
instead of inlining narrative. `(JIRA: KEY-123)` inline once a ticket exists — never fabricate a
ticket URL/key.
