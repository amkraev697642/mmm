#!/usr/bin/env python3
"""Structural checks over an ~/mmm tree: broken [[links]], unindexed pages, oversized pages,
frontmatter completeness, page age, links into superseded pages.

Referential completeness is checked per-tier (global's own index.md, each project's own
index.md) but [[slug]] links are checked against the WHOLE tree, since pages legitimately
cross-link between tiers (a project page linking to a global decision page, etc).
"""
import json
import os
import re
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

LINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
MD_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+\.md)\)")
# environment.md is OMC's own reserved/auto-generated file — excluded from its index by design
SKIP_NAMES = {"index.md", "log.md", "README.md", "environment.md"}
# a project's CLAUDE.md lives in the store but is the repo's file, not a wiki page -- its relative links resolve against the repo
NOT_PAGES = {"CLAUDE.md"}
PAGE_BUDGET = 150
# plans/: design-doc prose that may illustrate [[link]] syntax without meaning a real link, and
# is explicitly not bite-sized by design. deep-research/: allowed to be long, but its [[links]]
# between real sub-pages should still be checked normally.
EXEMPT_FROM_BUDGET = {"plans", "deep-research"}
EXEMPT_FROM_LINK_CHECK = {"plans"}
# memory/: Claude Code's own auto memory, adopted into the store by `mmm init` -- its files use
# Claude Code's frontmatter (name/description/type) and link to memories that may not exist yet
# on purpose, so none of the wiki-page rules apply to it
NOT_WIKI_DIRS = {"memory"}
REQUIRED_FIELDS = ("title", "category", "tags", "updated")
# tasks.md has its own two-section format in content-rules.md, no frontmatter
NO_FRONTMATTER_NAMES = SKIP_NAMES | {"tasks.md"}
STALE_DAYS = int(os.environ.get("MMM_STALE_DAYS", "180"))
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")
LINE_SUFFIX_RE = re.compile(r":\d+(-\d+)?$")
# key -> checkout path, resolved by bin/mmm (registry + searchRoots) since only it knows how
PROJECT_PATHS = json.loads(os.environ.get("MMM_PROJECT_PATHS") or "{}")


def check_sources(tier_name: str, fm, updated: str):
    """Copilot-style citation check: a page lists the repo files it describes in `sources:`,
    and it's suspect once one is gone or has commits newer than the page's `updated`."""
    repo = PROJECT_PATHS.get(tier_name)
    sources = fm.get("sources") if fm else None
    if not repo or not sources:
        return []
    if isinstance(sources, str):
        sources = [sources]
    problems = []
    for src in sources:
        rel = LINE_SUFFIX_RE.sub("", src)
        if not (Path(repo) / rel).exists():
            problems.append(f"{src} no longer exists")
            continue
        if not updated:
            continue
        last = subprocess.run(["git", "-C", repo, "log", "-1", "--format=%cs", "--", rel],
                              capture_output=True, text=True).stdout.strip()
        if last and last > updated:
            problems.append(f"{src} changed {last}, page updated {updated}")
    return problems


def frontmatter(text: str):
    """Just enough YAML for the flat keys content-rules.md asks for: `k: v`, `k: [a, b]`,
    and `k:` followed by `  - item` lines. None when the page has no header at all."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None
    fields: dict[str, object] = {}
    key = None
    for line in m.group(1).splitlines():
        item = re.match(r"^\s+-\s*(.*)$", line)
        if item and key is not None:
            if not isinstance(fields.get(key), list):
                fields[key] = []
            fields[key].append(item.group(1).strip(" \"'"))
            continue
        kv = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if not kv:
            continue
        key, val = kv.group(1), kv.group(2).strip()
        if val.startswith("[") and val.endswith("]"):
            fields[key] = [v.strip(" \"'") for v in val[1:-1].split(",") if v.strip()]
        else:
            fields[key] = val.strip("\"'")
    return fields


def is_under(path: Path, dirname: str) -> bool:
    return dirname in path.parts


def tiers(root: Path):
    yield "global", root / "global"
    projects = root / "projects"
    if projects.is_dir():
        for d in sorted(projects.iterdir()):
            if d.is_dir():
                yield d.name, d


def main() -> int:
    root = Path(sys.argv[1])
    fail = False

    slug_to_path: dict[str, Path] = {}
    all_pages: list[tuple[str, Path]] = []
    for tier_name, tier_dir in tiers(root):
        if not tier_dir.is_dir():
            continue
        for f in tier_dir.rglob("*.md"):
            if f.name in NOT_PAGES or any(is_under(f, d) for d in NOT_WIKI_DIRS):
                continue
            slug_to_path[f.stem] = f
            all_pages.append((tier_name, f))

    texts = {f: f.read_text(errors="replace") for _, f in all_pages}
    meta = {f: frontmatter(t) for f, t in texts.items()}
    superseded = {f.stem: meta[f]["superseded_by"] for f in meta
                  if meta[f] and meta[f].get("superseded_by")}

    broken = []
    dangling_md_links = []
    oversized = []
    to_superseded = []
    missing_fields = []
    stale = []
    unsourced = []
    stale_before = date.today() - timedelta(days=STALE_DAYS)
    for tier_name, f in all_pages:
        text = texts[f]
        # log.md is a historical record (like plans/) -- a link inside it was true when written,
        # not a claim the target still exists now
        if f.name != "log.md" and not any(is_under(f, d) for d in EXEMPT_FROM_LINK_CHECK):
            for m in LINK_RE.finditer(text):
                slug = m.group(1).strip()
                if slug not in slug_to_path:
                    broken.append((f, slug))
                elif slug in superseded and f.name not in SKIP_NAMES:
                    to_superseded.append((f, slug, superseded[slug]))
            for target in MD_LINK_RE.findall(text):
                if target.startswith(("http://", "https://")):
                    continue
                if not (f.parent / target).exists():
                    dangling_md_links.append((f, target))
        if f.name not in SKIP_NAMES and not any(is_under(f, d) for d in EXEMPT_FROM_BUDGET):
            n = text.count("\n") + 1
            if n > PAGE_BUDGET:
                oversized.append((f, n))
        if f.name not in NO_FRONTMATTER_NAMES:
            fm = meta[f]
            missing = [k for k in REQUIRED_FIELDS if not fm or not fm.get(k)]
            if missing:
                missing_fields.append((f, missing))
            m = DATE_RE.search(str(fm.get("updated", ""))) if fm else None
            if m and date.fromisoformat(m.group(1)) < stale_before and f.stem not in superseded:
                stale.append((f, m.group(1)))
            for problem in check_sources(tier_name, fm, m.group(1) if m else ""):
                unsourced.append((f, problem))

    if broken:
        fail = True
        print("FAIL: broken [[links]]:")
        for f, slug in broken:
            print(f"  {f}: [[{slug}]] has no matching page")
    else:
        print(f"PASS: all [[links]] resolve ({len(all_pages)} pages checked)")

    if dangling_md_links:
        fail = True
        print("FAIL: [text](file.md) link to a file that doesn't exist:")
        for f, target in dangling_md_links:
            print(f"  {f}: ({target})")
    else:
        print("PASS: every [text](file.md) link resolves to a real file")

    if oversized:
        fail = True
        print(f"FAIL: pages over the {PAGE_BUDGET}-line budget:")
        for f, n in oversized:
            print(f"  {f}: {n} lines")
    else:
        print(f"PASS: no page exceeds {PAGE_BUDGET} lines")

    # WARN, not FAIL: these judge upkeep rather than structure, and a store written before the
    # checks existed shouldn't suddenly block pack
    if missing_fields:
        print("WARN: pages missing required frontmatter (content-rules.md):")
        for f, missing in missing_fields:
            print(f"  {f}: {', '.join(missing)}")
    else:
        print("PASS: every page has title/category/tags/updated")

    if stale:
        print(f"WARN: pages not updated in {STALE_DAYS}+ days (MMM_STALE_DAYS) -- still true?")
        for f, d in sorted(stale, key=lambda x: x[1]):
            print(f"  {f}: updated {d}")
    else:
        print(f"PASS: no page older than {STALE_DAYS} days")

    if unsourced:
        print("WARN: pages whose cited sources moved on (re-check them against the code):")
        for f, problem in unsourced:
            print(f"  {f}: {problem}")
    else:
        print("PASS: every cited source still exists and predates its page's update")

    if to_superseded:
        print("WARN: links into superseded pages:")
        for f, slug, repl in to_superseded:
            print(f"  {f}: [[{slug}]] is superseded by {repl}")

    unindexed = []
    for tier_name, tier_dir in tiers(root):
        idx = tier_dir / "index.md"
        idx_text = idx.read_text(errors="replace") if idx.is_file() else ""
        for f in tier_dir.glob("*.md"):
            if f.name in SKIP_NAMES or f.name in NOT_PAGES:
                continue
            if f.stem not in idx_text:
                unindexed.append(f)
    if unindexed:
        print("WARN: top-level pages not mentioned in their tier's index.md:")
        for f in unindexed:
            print(f"  {f}")
    else:
        print("PASS: every top-level page has an index.md mention")

    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
