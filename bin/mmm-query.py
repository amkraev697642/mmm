#!/usr/bin/env python3
"""mmm query — rg with wiki-structure awareness: rank frontmatter hits over body hits,
group by page, surface tags/[[links]] for free, walk global first."""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
LINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
TITLE_RE = re.compile(r'^title:\s*"?(.*?)"?\s*$', re.MULTILINE)
TAGS_RE = re.compile(r"^tags:\s*(\[.*\])\s*$", re.MULTILINE)


def parse_frontmatter(text: str):
    m = FRONTMATTER_RE.match(text)
    if not m:
        return "", []
    fm = m.group(1)
    title_m = TITLE_RE.search(fm)
    tags_m = TAGS_RE.search(fm)
    title = title_m.group(1) if title_m else ""
    tags = []
    if tags_m:
        try:
            tags = json.loads(tags_m.group(1).replace("'", '"'))
        except json.JSONDecodeError:
            tags = [t.strip(' "\'') for t in tags_m.group(1).strip("[]").split(",") if t.strip()]
    return title, tags


def rg_matches(term: str, dirs: list[Path]) -> dict[str, list[tuple[int, str]]]:
    existing = [str(d) for d in dirs if d.is_dir()]
    if not existing:
        return {}
    proc = subprocess.run(
        ["rg", "--json", "-i", "--glob", "*.md", "--", term, *existing],
        capture_output=True, text=True,
    )
    hits: dict[str, list[tuple[int, str]]] = {}
    for line in proc.stdout.splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") != "match":
            continue
        path = obj["data"]["path"]["text"]
        line_number = obj["data"]["line_number"]
        snippet = obj["data"]["lines"]["text"].strip()
        hits.setdefault(path, []).append((line_number, snippet))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mmm_home")
    ap.add_argument("terms", nargs="+", help="one term, or several bare words = must all appear (AND)")
    ap.add_argument("--project")
    ap.add_argument("--global-only", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    root = Path(args.mmm_home)
    global_dir = root / "global"
    if args.global_only:
        dirs = [global_dir]
    elif args.project:
        dirs = [global_dir, root / "projects" / args.project]
    else:
        dirs = [global_dir]
        proj_root = root / "projects"
        if proj_root.is_dir():
            dirs += sorted(p for p in proj_root.iterdir() if p.is_dir())

    per_term_hits = [rg_matches(t, dirs) for t in args.terms]
    # multiple bare words = AND: only pages every term matched somewhere in
    common_files = set(per_term_hits[0]) if per_term_hits else set()
    for h in per_term_hits[1:]:
        common_files &= set(h)
    if not common_files:
        print(f"mmm query: no matches for all of {args.terms!r}", file=sys.stderr)
        return 1

    terms_l = [t.lower() for t in args.terms]
    results = []
    for path in common_files:
        line_hits = [lh for h in per_term_hits for lh in h.get(path, [])]
        text = Path(path).read_text(errors="replace")
        title, tags = parse_frontmatter(text)
        links = sorted(set(LINK_RE.findall(text)))
        fm_match = FRONTMATTER_RE.match(text)
        fm_line_count = text[: fm_match.end()].count("\n") if fm_match else 0
        frontmatter_hit = any(
            t in title.lower() or any(t in tag.lower() for tag in tags) for t in terms_l
        )
        score = 2 if frontmatter_hit else 1
        # a hit inside the YAML header just re-shows title:/tags: already printed above —
        # only surface body snippets, so a frontmatter-only hit still scores 2 but shows nothing redundant
        body_snippets = sorted({(ln, s) for ln, s in line_hits if ln > fm_line_count})
        results.append({
            "file": path,
            "title": title,
            "tags": tags,
            "links": links,
            "score": score,
            "snippets": [s for _, s in body_snippets[:3]],
        })

    results.sort(key=lambda r: (-r["score"], 0 if str(global_dir) in r["file"] else 1, r["file"]))

    if args.json:
        print(json.dumps(results, indent=2))
        return 0

    TAG_DISPLAY_CAP = 7
    for r in results:
        print(f"\n{r['file']}")
        if r["title"]:
            print(f"  title: {r['title']}")
        if r["tags"]:
            shown = r["tags"][:TAG_DISPLAY_CAP]
            rest = len(r["tags"]) - len(shown)
            suffix = f" (+{rest} more)" if rest > 0 else ""
            print(f"  tags: {', '.join(shown)}{suffix}")
        if r["links"]:
            print(f"  links: {', '.join(r['links'])}")
        for s in r["snippets"]:
            print(f"  > {s}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
