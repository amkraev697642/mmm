#!/usr/bin/env python3
"""Structural checks over an ~/mmm tree: broken [[links]], unindexed pages, oversized pages.

Referential completeness is checked per-tier (global's own index.md, each project's own
index.md) but [[slug]] links are checked against the WHOLE tree, since pages legitimately
cross-link between tiers (a project page linking to a global decision page, etc).
"""
import re
import sys
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
            if f.name in NOT_PAGES:
                continue
            slug_to_path[f.stem] = f
            all_pages.append((tier_name, f))

    broken = []
    dangling_md_links = []
    oversized = []
    for tier_name, f in all_pages:
        text = f.read_text(errors="replace")
        # log.md is a historical record (like plans/) -- a link inside it was true when written,
        # not a claim the target still exists now
        if f.name != "log.md" and not any(is_under(f, d) for d in EXEMPT_FROM_LINK_CHECK):
            for m in LINK_RE.finditer(text):
                slug = m.group(1).strip()
                if slug not in slug_to_path:
                    broken.append((f, slug))
            for target in MD_LINK_RE.findall(text):
                if target.startswith(("http://", "https://")):
                    continue
                if not (f.parent / target).exists():
                    dangling_md_links.append((f, target))
        if f.name not in SKIP_NAMES and not any(is_under(f, d) for d in EXEMPT_FROM_BUDGET):
            n = text.count("\n") + 1
            if n > PAGE_BUDGET:
                oversized.append((f, n))

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
