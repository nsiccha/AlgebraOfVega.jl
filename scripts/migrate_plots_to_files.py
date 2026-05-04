#!/usr/bin/env python3
"""
One-off migration: parse the `PLOTS` literal in
`web/src/AlgebraOfVegaGallery.jl` and emit one file per entry under
`examples/aov-gallery/<section_dir>/<id>.jl`.

Each emitted file has the canonical HTMXObjects gallery shape:

    # title: <Title>
    # description: <Description>

    <code body verbatim>

The parent section directory carries a `_section.md` with the section
title (read by `HTMXObjects.Gallery` for human-readable headings).

This script parses the Julia source as text — it does not run Julia.
The PLOTS array uses a consistent format (see the source) so a
regex-based parser is sufficient. Output is reviewed by hand before the
follow-up refactor of `AlgebraOfVegaGallery.jl` to use `Gallery`.

Run:  python3 scripts/migrate_plots_to_files.py
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "web" / "src" / "AlgebraOfVegaGallery.jl"
OUT_ROOT = REPO / "examples" / "aov-gallery"


def slugify_section(title: str) -> str:
    """'AoG: Statistical Analyses' -> 'aog-statistical-analyses'"""
    s = title.lower()
    s = s.replace(":", "")
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s


def parse_plot_sections(text: str):
    """
    Return [(section_title, [id, ...]), ...] in declaration order.
    """
    m = re.search(
        r"PLOT_SECTIONS\s*=\s*\[(.+?)\n    \]",
        text,
        flags=re.DOTALL,
    )
    if not m:
        sys.exit("PLOT_SECTIONS literal not found")
    body = m.group(1)
    sections = []
    for entry in re.finditer(
        r'"([^"]+)"\s*=>\s*\[((?:\s*"[^"]+",?)+)\s*\]',
        body,
    ):
        title = entry.group(1)
        ids = re.findall(r'"([^"]+)"', entry.group(2))
        sections.append((title, ids))
    return sections


def parse_plots(text: str):
    """
    Return [(id, title, description, code_string), ...] in source order.

    Strategy: walk the PLOTS array character by character, tracking
    paren/bracket/string state to identify each top-level tuple entry,
    then within each tuple grab the four leading string literals
    (id, title, description, code-as-triple-quoted).
    """
    start = text.find("PLOTS = [")
    if start < 0:
        sys.exit("PLOTS literal not found")
    # advance past the opening [
    i = text.index("[", start) + 1
    depth_paren = 0
    depth_bracket = 1  # we just consumed `[`
    in_str = None  # None | '"' | '"""' | '#=' (block comment)
    entries = []  # list of (start_idx, end_idx) in `text`
    entry_start = None
    n = len(text)
    while i < n:
        ch = text[i]
        if in_str == '"""':
            if text.startswith('"""', i):
                in_str = None
                i += 3
                continue
            i += 1
            continue
        if in_str == '"':
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_str = None
            i += 1
            continue
        if ch == "#":
            # line comment
            nl = text.find("\n", i)
            i = nl + 1 if nl != -1 else n
            continue
        if text.startswith('"""', i):
            in_str = '"""'
            i += 3
            continue
        if ch == '"':
            in_str = '"'
            i += 1
            continue
        if ch == "(":
            if depth_paren == 0 and depth_bracket == 1 and entry_start is None:
                entry_start = i
            depth_paren += 1
            i += 1
            continue
        if ch == ")":
            depth_paren -= 1
            if depth_paren == 0 and entry_start is not None:
                entries.append((entry_start, i + 1))
                entry_start = None
            i += 1
            continue
        if ch == "[":
            depth_bracket += 1
            i += 1
            continue
        if ch == "]":
            depth_bracket -= 1
            if depth_bracket == 0:
                break
            i += 1
            continue
        i += 1

    out = []
    for s, e in entries:
        chunk = text[s + 1 : e - 1]  # strip the outer parens
        # Pull id and title (each a single quoted string).
        head = re.match(
            r'\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*',
            chunk,
        )
        if not head:
            print(f"  skip: malformed id/title at offset {s}", file=sys.stderr)
            continue
        id_, title = head.group(1), head.group(2)
        # Description may be a single string OR a `"..." * "..." * ...`
        # concatenation. Collect strings until we hit the trailing comma
        # (the comma before the triple-quoted code body).
        desc_parts = []
        idx = head.end()
        while idx < len(chunk):
            sm = re.match(r'\s*"((?:[^"\\]|\\.)*)"', chunk[idx:])
            if not sm:
                break
            desc_parts.append(sm.group(1))
            idx += sm.end()
            cont = re.match(r"\s*\*\s*", chunk[idx:])
            if cont:
                idx += cont.end()
                continue
            break
        if not desc_parts:
            print(f"  skip: no description at offset {s}", file=sys.stderr)
            continue
        # Unescape Julia string-literal escapes in the description (the
        # parser captured `\"` as two chars; turn it back into `"`).
        desc = "".join(desc_parts).replace('\\"', '"').replace("\\\\", "\\")
        # Skip the comma after description.
        m_comma = re.match(r"\s*,", chunk[idx:])
        if not m_comma:
            print(f"  skip: missing comma after description for {id_}", file=sys.stderr)
            continue
        rest = chunk[idx + m_comma.end() :]
        # Pull the first triple-quoted string from the remainder.
        body_m = re.search(r'"""(.+?)"""', rest, flags=re.DOTALL)
        if not body_m:
            print(f"  skip: no code_string for {id_}", file=sys.stderr)
            continue
        code = body_m.group(1)
        out.append((id_, title, desc, code))
    return out


def main():
    text = SRC.read_text()
    sections = parse_plot_sections(text)
    plots = parse_plots(text)

    # Build id -> section_title via PLOT_SECTIONS
    id_to_section = {}
    for sec_title, ids in sections:
        for id_ in ids:
            id_to_section[id_] = sec_title

    # Wipe + rebuild output dir
    if OUT_ROOT.exists():
        import shutil

        shutil.rmtree(OUT_ROOT)
    OUT_ROOT.mkdir(parents=True)

    # Group by section in declaration order so we can write _section.md per dir
    section_dirs = {}
    for sec_title, _ in sections:
        slug = slugify_section(sec_title)
        d = OUT_ROOT / slug
        d.mkdir(parents=True, exist_ok=True)
        (d / "_section.md").write_text(f"title: {sec_title}\n")
        section_dirs[sec_title] = d

    # Orphan section for entries in PLOTS that PLOT_SECTIONS doesn't
    # mention — these accumulated as the gallery grew.
    orphan_title = "Uncategorized"
    orphan_dir = OUT_ROOT / slugify_section(orphan_title)
    orphan_dir.mkdir(parents=True, exist_ok=True)
    (orphan_dir / "_section.md").write_text(f"title: {orphan_title}\n")
    section_dirs[orphan_title] = orphan_dir

    written = 0
    orphan = 0
    for id_, title, desc, code in plots:
        sec_title = id_to_section.get(id_)
        if sec_title is None:
            print(f"  uncategorized: {id_}", file=sys.stderr)
            sec_title = orphan_title
            orphan += 1
        d = section_dirs[sec_title]
        path = d / f"{id_}.jl"
        # The triple-quoted code is captured verbatim — but Julia's
        # source uses escape sequences (`\"`, `\\`) that survive the
        # `"""..."""` capture as literal backslash-quote pairs. Unescape
        # them so the body is valid Julia (single quote, single
        # backslash) when written out.
        code = code.replace('\\"', '"').replace("\\\\", "\\")
        # Compute common leading whitespace across non-empty
        # continuation lines and strip it. The first line follows the
        # opening `"""` with no leading newline, so we only dedent
        # continuation lines.
        lines = code.split("\n")
        if len(lines) > 1:
            cont = [ln for ln in lines[1:] if ln.strip()]
            if cont:
                ind = min(len(ln) - len(ln.lstrip(" ")) for ln in cont)
                if ind:
                    lines = [lines[0]] + [
                        (ln[ind:] if len(ln) >= ind else ln) for ln in lines[1:]
                    ]
        body = "\n".join(lines).rstrip() + "\n"
        header = f"# title: {title}\n# description: {desc}\n\n"
        path.write_text(header + body)
        written += 1

    print(f"Wrote {written} entries across {len(section_dirs)} sections")
    if orphan:
        print(f"  ({orphan} orphans skipped — listed above)")


if __name__ == "__main__":
    main()
