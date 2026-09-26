#!/usr/bin/env python3
"""mmm links — the [[link]] graph doctor already resolves, turned into lookups: what links to a
page (backlinks), what it links to, and which pages nothing links to at all (orphans)."""
import argparse
import re
import sys
from pathlib import Path

LINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
# same exclusions as mmm-doctor.py: indexes/logs aren't pages, memory/ is Claude Code's own
NOT_PAGES = {"index.md", "log.md", "README.md", "environment.md", "CLAUDE.md", "AGENTS.md", "tasks.md"}
NOT_WIKI_DIRS = {"memory", ".git"}


def pages(root: Path):
    for f in sorted(root.rglob("*.md")):
        if not NOT_WIKI_DIRS & set(f.relative_to(root).parts):
            yield f


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mmm_home")
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--orphans", action="store_true")
    args = ap.parse_args()
    root = Path(args.mmm_home)

    outgoing: dict[Path, set[str]] = {}
    by_slug: dict[str, Path] = {}
    for f in pages(root):
        outgoing[f] = {s.strip() for s in LINK_RE.findall(f.read_text(errors="replace"))}
        if f.name not in NOT_PAGES:
            by_slug[f.stem] = f

    if args.orphans:
        # an index row is a mention, not a link someone followed from context -- it doesn't count
        linked = {s for f, out in outgoing.items() if f.name not in {"index.md", "log.md"} for s in out}
        orphans = [p for s, p in sorted(by_slug.items()) if s not in linked and "plans" not in p.parts]
        for p in orphans:
            print(p.relative_to(root))
        print(f"mmm links: {len(orphans)} page(s) with no inbound [[link]] from another page", file=sys.stderr)
        return 0

    if not args.slug:
        ap.error("give a page slug, or --orphans")
    slug = Path(args.slug).stem
    page = by_slug.get(slug)
    if page is None:
        print(f"mmm links: no page named {slug}", file=sys.stderr)
        return 1
    back = [f for f, out in outgoing.items() if slug in out and f != page]
    print(page.relative_to(root))
    print(f"  links to ({len(outgoing[page])}): {', '.join(sorted(outgoing[page])) or '-'}")
    print(f"  linked from ({len(back)}):")
    for f in back:
        print(f"    {f.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
