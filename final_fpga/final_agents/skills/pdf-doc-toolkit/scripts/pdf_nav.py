#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pdf_nav.py - navigation for long technical PDFs (pdf-doc-toolkit).

Vendor manuals are reference works: 90-400 pages, a real bookmark tree, a large
repeated header/footer block on every page, and a question that usually concerns
two or three sections. Dumping the whole text is both expensive and unhelpful.

This script gives the three things such a document needs:

  profile  - how big, how dense, where the images are, what the running
             header/footer actually is (detected, not assumed)
  outline  - the bookmark tree with page numbers, so you can choose sections
  section  - the text of one section, header/footer removed

Usage:
    python pdf_nav.py profile  <file.pdf>
    python pdf_nav.py outline  <file.pdf> [--depth N] [--grep PATTERN]
    python pdf_nav.py section  <file.pdf> (--title TEXT | --page N)[--end-page M]
    python pdf_nav.py clean    <file.pdf> [--start N] [--end N]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter

try:
    import pymupdf
except ImportError:  # pragma: no cover
    sys.exit("pymupdf is required: python -m pip install pymupdf")


# --------------------------------------------------------------------------
# running header/footer detection
# --------------------------------------------------------------------------
def _furniture_bands(doc, sample_pages: int = 20, probe: float = 85.0):
    """Derive the header/footer bands from the document's own layout.

    A fixed threshold fails across vendors. Measured on this corpus of Anlogic
    manuals: headers end anywhere from y=61.9 to y=71.4, and one manual's table
    header row sits at y=74 - overlapping the zone a naive 95pt margin would
    claim. Any single constant either misses furniture or deletes content.

    Two simpler ideas were tried and rejected against real data:
      * largest gap in the outer 130pt  -> always the ordinary line pitch
        (10-22pt), never the separator
      * first gap above a multiple of the median pitch -> the median is itself
        contaminated by the body lines the region pulls in

    What works: look for the largest gap whose LOWER line ends within `probe`
    of the top (respectively whose UPPER line starts within `probe` of the
    bottom), then take the median across sampled pages. On eight manuals this
    landed in a 62-78pt band, matching the hand-measured truth every time.
    """
    import statistics
    heights, tops, bots = [], [], []
    step = max(1, doc.page_count // max(sample_pages, 1))

    for i in range(0, doc.page_count, step):
        page = doc[i]
        h = page.rect.height
        heights.append(h)
        lines = []
        for b in page.get_text("dict")["blocks"]:
            if b.get("type") != 0:
                continue
            for ln in b["lines"]:
                if "".join(s["text"] for s in ln["spans"]).strip():
                    lines.append((ln["bbox"][1], ln["bbox"][3]))
        if len(lines) < 4:
            continue
        lines.sort()

        cand = [(lines[k + 1][0] - lines[k][1], lines[k][1])
                for k in range(len(lines) - 1)
                if lines[k][1] <= probe and lines[k + 1][0] <= probe * 1.6]
        if cand:
            tops.append(max(cand)[1])

        cand = [(lines[k + 1][0] - lines[k][1], lines[k][0])
                for k in range(len(lines) - 1)
                if lines[k][0] >= h - probe]
        if cand:
            bots.append(max(cand)[1])

    h_med = statistics.median(heights) if heights else 842.0
    top_zone = statistics.median(tops) if tops else 75.0
    bottom_zone = (h_med - statistics.median(bots)) if bots else 75.0
    return (max(45.0, min(top_zone, 100.0)), max(45.0, min(bottom_zone, 100.0)))


def _margin_lines(page, top_zone, bottom_zone):
    """Lines in the derived outer bands, with their y."""
    h = page.rect.height
    top, bottom = [], []
    for b in page.get_text("dict")["blocks"]:
        if b.get("type") != 0:
            continue
        for ln in b["lines"]:
            txt = "".join(s["text"] for s in ln["spans"]).strip()
            if not txt:
                continue
            y0, y1 = ln["bbox"][1], ln["bbox"][3]
            if y1 <= top_zone:
                top.append((txt, round(y0, 1)))
            elif y0 >= h - bottom_zone:
                bottom.append((txt, round(y0, 1)))
    return top, bottom


def detect_furniture(doc, max_pages: int = 60, min_ratio: float = 0.5,
                     y_tolerance: float = 2.0) -> dict:
    """Find lines that repeat in the inferred outer bands at a CONSTANT y.

    Two independent conditions, both required:

    1. inside the adaptively derived outer band (see _furniture_bands)
    2. repeats on >= min_ratio of sampled pages at the same y (within tolerance)

    Condition 2 exists because repeated content is not automatically noise: a
    register table's header row repeats on every page, and stripping it destroys
    the document. Constant position in the outer band is what separates the two.
    """
    top_zone, bottom_zone = _furniture_bands(doc)
    n = doc.page_count
    step = max(1, n // max_pages)
    occ: dict[str, list[float]] = {}
    sampled = 0
    for i in range(0, n, step):
        page = doc[i]
        top, bottom = _margin_lines(page, top_zone, bottom_zone)
        if not top and not bottom:
            continue
        sampled += 1
        for txt, y in set(top + bottom):
            occ.setdefault(txt, []).append(y)

    denom = max(sampled, 1)

    # Group FIRST, filter SECOND. A footer line such as
    # 'UG1318_1.1   www.anlogic.com   22' occurs on every page but each variant
    # is a unique string, so a per-string frequency filter discards all of them
    # before any family logic can run - which is exactly the bug this ordering
    # avoids. Mask the trailing number to form the family key.
    fams: dict[str, dict] = {}
    for txt, ys in occ.items():
        if max(ys) - min(ys) > y_tolerance:
            continue  # moves around -> content that merely appears often
        masked = re.sub(r"\d+\s*$", "#", txt)
        f = fams.setdefault(masked, {"count": 0, "members": [], "raw_count": 0})
        f["count"] += 1
        f["raw_count"] += 0
        f["members"].append(txt)
    # the family's true page coverage: a masked key seen once but whose text is
    # one of many variants must still count the underlying occurrences, so
    # re-derive coverage from how many sampled pages contained ANY variant
    fam_pages: dict[str, int] = {}
    for txt, ys in occ.items():
        if max(ys) - min(ys) > y_tolerance:
            continue
        fam_pages[re.sub(r"\d+\s*$", "#", txt)] = fam_pages.get(
            re.sub(r"\d+\s*$", "#", txt), 0) + len(ys)

    furniture, pagenums, prefixes = set(), set(), set()
    for txt, ys in occ.items():
        if max(ys) - min(ys) > y_tolerance:
            continue
        # ORDER MATTERS: decide "this is a page number / date" BEFORE masking the
        # trailing digits. Masking first turns '2025.03' into '#' and it can then
        # never be recognised as a date again.
        if re.fullmatch(r"[\dIVXivx]+", txt) or re.fullmatch(r"\d{4}[.\-/]\d{1,2}", txt):
            if len(ys) / denom >= min_ratio:
                pagenums.add(txt)
            continue
        masked = re.sub(r"\d+\s*$", "#", txt)
        coverage = fam_pages.get(masked, len(ys)) / denom
        if coverage < min_ratio:
            continue
        if "#" in masked:
            prefix = masked.split("#")[0].rstrip()
            if len(prefix) >= 12:
                prefixes.add(prefix)
            continue
        if len(ys) / denom < min_ratio:
            continue
        furniture.add(txt)

    return {
        "sampled_pages": sampled,
        "top_zone": round(top_zone, 1),
        "bottom_zone": round(bottom_zone, 1),
        "furniture_lines": sorted(furniture),
        "page_number_like": sorted(pagenums),
        "stable_prefixes": sorted(prefixes),
    }


def strip_furniture(text: str, furniture: set[str], prefixes: set[str] | None = None,
                    pagenums: set[str] | None = None) -> str:
    """Remove furniture lines, never eating content.

    A blanket numeric filter is NOT used: register tables legitimately contain
    lines that are only a number, and a parameter table's column header is a
    line of short words. Only exact furniture matches, stable prefixes of
    furniture, detected page-number strings, and lines that are nothing but a
    bare numeral are removed.
    """
    prefixes = prefixes or set()
    pagenums = pagenums or set()
    keep = []
    for ln in text.splitlines():
        s = ln.strip()
        if not s:
            keep.append("")
            continue
        if s in furniture or s in pagenums:
            continue
        if any(s.startswith(p) for p in prefixes):
            continue
        if re.fullmatch(r"[\dIVXivx]{1,4}", s):
            continue
        keep.append(ln.rstrip())
    out, prev_blank = [], False
    for ln in keep:
        blank = ln.strip() == ""
        if blank and prev_blank:
            continue
        out.append(ln)
        prev_blank = blank
    body = "\n".join(out).strip()
    # symbol-font glyphs and mid-token wraps are text-layer artefacts that would
    # otherwise reach the reader as mojibake or a broken command
    body = normalise_symbols(body)
    return rejoin_wrapped_code(body)


# --------------------------------------------------------------------------
# modes
# --------------------------------------------------------------------------
def mode_profile(doc, path) -> dict:
    n = doc.page_count
    fut = detect_furniture(doc)
    furniture = set(fut["furniture_lines"])
    prefixes = set(fut["stable_prefixes"])
    pagenums = set(fut["page_number_like"])

    per_page = []
    for i, page in enumerate(doc, 1):
        raw = page.get_text("text")
        cleaned = strip_furniture(raw, furniture, prefixes, pagenums)
        per_page.append({
            "page": i,
            "chars_raw": len(raw),
            "chars_content": len(cleaned),
            "images": len(page.get_images(full=False)),
            "vector_paths": len(page.get_drawings()),
        })

    content = sorted(p["chars_content"] for p in per_page)
    n_content = sum(p["chars_content"] for p in per_page)
    raw_total = sum(p["chars_raw"] for p in per_page)
    meta = doc.metadata or {}
    return {
        "file": path,
        "pages": n,
        "producer": meta.get("producer"),
        "title": meta.get("title"),
        "toc_entries": len(doc.get_toc()),
        "chars_raw": raw_total,
        "chars_content": n_content,
        "furniture_overhead_pct": round(100 * (1 - n_content / max(raw_total, 1)), 1),
        "chars_per_page": {
            "min": content[0] if content else 0,
            "median": content[len(content) // 2] if content else 0,
            "max": content[-1] if content else 0,
        },
        "thin_pages": sum(1 for c in content if c < 200),
        "pages_with_images": sum(1 for p in per_page if p["images"] > 0),
        "total_images": sum(p["images"] for p in per_page),
        "pages_with_heavy_vectors": sum(1 for p in per_page if p["vector_paths"] > 60),
        "furniture": fut,
        "per_page": per_page,
    }


def extract_table_text(doc, page, table) -> dict:
    """Read a find_tables() table cell-by-cell from the RAW text layer.

    Why not `table.extract()`: on these manuals it returns `'qor monitor\\n_'`
    for the parameter actually named `qor_monitor` - pymupdf's word-reassembly
    mangles identifiers and splits the underscore onto its own line. Corrupting a
    parameter name is unacceptable for a command reference, so cell text is taken
    from `rawdict` characters falling inside each cell bbox instead. Verified:
    the raw layer holds `qor_monitor` intact and cell bboxes align cleanly.

    Merged cells come from find_tables as None entries; a cell spanning rows is
    reported once with its text and left blank on the continuation rows, and the
    `merged` map records which coordinates were spans so the structure is not
    silently lost.
    """
    chars = []
    for b in page.get_text("rawdict")["blocks"]:
        if b.get("type") != 0:
            continue
        for ln in b["lines"]:
            for sp in ln["spans"]:
                for c in sp["chars"]:
                    chars.append((c["c"], c["bbox"]))

    rows = []
    merged = []
    for ri, row in enumerate(table.rows):
        cells = []
        for ci, cell in enumerate(row.cells):
            if cell is None:
                cells.append("")
                continue
            x0, y0, x1, y1 = cell
            # a cell whose bbox spans more than one row is a vertical merge
            span_rows = sum(
                1 for other in table.rows
                if other.bbox[1] >= y0 - 1 and other.bbox[3] <= y1 + 1
            )
            if span_rows > 1:
                merged.append({"row": ri, "col": ci, "row_span": span_rows})
            txt = "".join(
                ch for ch, bb in chars
                if x0 - 1 <= bb[0] and bb[2] <= x1 + 1 and y0 - 1 <= bb[1] and bb[3] <= y1 + 1
            )
            cells.append(re.sub(r"\s+", " ", txt).strip())
        rows.append(cells)

    # drop all-empty phantom columns that find_tables reports around merges.
    # Applied to header AND body together, otherwise the header keeps its blanks
    # and the columns no longer line up.
    if rows:
        width = max(len(r) for r in rows)
        for r in rows:
            r.extend([""] * (width - len(r)))
        keep = [ci for ci in range(width) if any(r[ci] for r in rows)]
        rows = [[r[ci] for ci in keep] for r in rows]
    return {"rows": rows, "merged": merged}


    """A table-of-contents entry, not a real heading.

    TOC lines are set in a heading-ish font and so pollute an inferred outline.
    They are recognisable by a long leader of dots, either between title and page
    number ('1 概述 .......... 1') or trailing.
    """
    if re.search(r"\.{4,}", txt):
        return True
    if re.search(r"[·․…]{4,}", txt):
        return True
    return False


def _is_toc_line(txt: str) -> bool:
    """A table-of-contents entry, not a real heading.

    TOC lines are set in a heading-ish font and so pollute an inferred outline.
    They are recognisable by a long leader of dots, either between title and page
    number ('1 概述 .......... 1') or trailing. Measured effect on an inferred
    outline: precision 81% -> 86% and 91% -> 95% on two manuals.
    """
    if re.search(r"\.{4,}", txt):
        return True
    if re.search(r"[·․…]{4,}", txt):
        return True
    return False


def infer_outline(doc, body_ratio: float = 0.5, max_entries: int = 400,
                  exclude: set[str] | None = None):
    """Reconstruct a heading tree from font sizes when no bookmark tree exists.

    One document in the reference corpus (an AMD competition guide) ships with no
    PDF bookmarks at all, and `get_toc()` returns nothing, leaving `section`
    unusable. Font size is the reliable fallback: the size carrying the most
    characters is the body text; larger sizes are headings, ranked by size.

    `exclude` should carry the detected running header/footer: those are set in a
    heading-sized font and would otherwise appear once per page (measured: 14
    phantom entries out of 134 on one manual).
    """
    from collections import Counter
    exclude = exclude or set()
    size_chars = Counter()
    for page in doc:
        for b in page.get_text("dict")["blocks"]:
            if b.get("type") != 0:
                continue
            for ln in b["lines"]:
                for s in ln["spans"]:
                    size_chars[round(s["size"], 2)] += len(s["text"].strip())
    if not size_chars:
        return []
    body_size = size_chars.most_common(1)[0][0]
    heading_sizes = sorted((sz for sz in size_chars if sz > body_size + 0.4), reverse=True)
    if not heading_sizes:
        return []
    level_of = {sz: min(i + 1, 4) for i, sz in enumerate(heading_sizes)}

    entries = []
    for pno, page in enumerate(doc, 1):
        lines = []
        for b in page.get_text("dict")["blocks"]:
            if b.get("type") != 0:
                continue
            for ln in b["lines"]:
                txt = "".join(s["text"] for s in ln["spans"]).strip()
                if not txt or txt in exclude:
                    continue
                sizes = {round(s["size"], 2) for s in ln["spans"] if s["text"].strip()}
                if not sizes:
                    continue
                if len(sizes) == 1 and next(iter(sizes)) in level_of:
                    sz = next(iter(sizes))
                    if len(txt) <= 120 and not txt.endswith(("。", "；", ",", "，")) \
                            and not _is_toc_line(txt):
                        lines.append((ln["bbox"][1], level_of[sz], txt))
        lines.sort()
        for y, lvl, txt in lines:
            entries.append({"level": lvl, "title": txt, "page": pno})
            if len(entries) >= max_entries:
                return entries
    return entries


def reconstruct_column_tables(text: str, min_rows: int = 3, min_cols: int = 2,
                              gap: int = 3):
    """Rebuild tables that were laid out with spaces rather than table objects.

    Whole classes of vendor manual format a table as plain text columns padded
    with spaces - 表 4-1 / 表 4-2 in the Anlogic TCL guide are exactly this, and
    `find_tables()` reports nothing for them, so `pdf_read` says "0 tables"
    while the page is full of tabular data.

    Method: split each line on runs of >= `gap` spaces. A run of consecutive
    lines that all yield >= `min_cols` fields is treated as one table; the
    widest field count in the run wins and short rows are padded. Completely
    blank lines end a run.
    """
    rows = []
    for raw in text.splitlines():
        if not raw.strip():
            rows.append(None)
            continue
        cells = [c.strip() for c in re.split(r"\s{%d,}" % gap, raw.rstrip())]
        cells = [c for c in cells if c != ""]
        rows.append(cells if len(cells) >= min_cols else [raw.strip()])

    tables, cur = [], []
    for r in rows:
        if r is None:
            if len(cur) >= min_rows:
                tables.append(cur)
            cur = []
            continue
        cur.append(r)
    if len(cur) >= min_rows:
        tables.append(cur)

    out = []
    for t in tables:
        width = max(len(r) for r in t)
        if width < min_cols:
            continue
        padded = [r + [""] * (width - len(r)) for r in t]
        out.append({"rows": len(padded), "cols": width, "data": padded})
    return out


def reconstruct_tables_by_position(page, col_gap: float = 22.0, header_pad: float = 26.0):
    """Rebuild a table from a PDF where every cell is its own text line.

    `find_tables()` needs ruling lines or aligned whitespace. Anlogic's manuals
    have neither: 表 4-1 emits each cell as a separate line, so the flattened
    text reads as a bare token stream ('step','param','value','Default value',
    'flow','message',...) and `find_tables` returns nothing.

    The information is still there - as x-coordinates. Method:

      1. find a header row: >= 3 lines sharing one y whose x-origins are
         separated by >= col_gap (a genuine multi-column header)
      2. anchor columns at the header's x-origins
      3. assign every line below the header to the nearest anchored column
      4. group consecutive lines whose y is within a few points into one row,
         joining wrapped cells with a space

    Returns a list of {"header": [...], "rows": [[...]]} or [] when no table is
    found on the page.
    """
    lines = []
    for b in page.get_text("dict")["blocks"]:
        if b.get("type") != 0:
            continue
        for ln in b["lines"]:
            txt = "".join(s["text"] for s in ln["spans"]).strip()
            if txt:
                lines.append((round(ln["bbox"][1], 1), ln["bbox"][0], txt))
    if len(lines) < 8:
        return []
    lines.sort()

    # 1. header row candidate
    by_y: dict[float, list] = {}
    for y, x0, t in lines:
        by_y.setdefault(y, []).append((x0, t))
    header = None
    for y in sorted(by_y):
        cells = sorted(by_y[y])
        if len(cells) < 3:
            continue
        xs = [c[0] for c in cells]
        if all(xs[k + 1] - xs[k] >= col_gap for k in range(len(xs) - 1)):
            header = (y, xs, [c[1] for c in cells])
            break
    if header is None:
        return []
    hy, anchors, htext = header

    # 2/3. assign below-header lines to the nearest anchor column
    def col_of(x0: float) -> int:
        best, bd = 0, abs(x0 - anchors[0])
        for i, a in enumerate(anchors):
            d = abs(x0 - a)
            if d < bd:
                best, bd = i, d
        return best

    body = [(y, x0, t) for y, x0, t in lines if y > hy + 1]
    if len(body) < 3:
        return []

    # 4. group into rows. Measured on these manuals: body line pitch is ~18.4pt
    # and a wrapped cell sits ~9.4pt below its row start. A 15pt cut therefore
    # separates real rows while a tight continuation line stays with its row.
    # `row_top` must stay fixed at the row's first line: comparing against the
    # previous LINE (as an earlier version did) lets a wrapped line reset the
    # baseline and re-merge the next genuine row.
    ROW_PITCH = 15.0
    rows: list[list[str]] = []
    row_top = None
    for y, x0, t in body:
        if row_top is None or y - row_top >= ROW_PITCH:
            rows.append([""] * len(anchors))
            row_top = y
        ci = col_of(x0)
        rows[-1][ci] = (rows[-1][ci] + " " + t).strip() if rows[-1][ci] else t

    # stop at the running footer, which also parses as multi-column
    cut = len(rows)
    for i, r in enumerate(rows):
        joined = " ".join(r)
        if re.search(r"anlogic\.com|^\s*\d{4}\.\d{2}", joined) or re.match(r"^[A-Z]{2,}G?\d+_", joined):
            cut = i
            break
    rows = rows[:cut]
    return [{"header": htext, "rows": [r for r in rows if any(r)]}]


# Symbols that PDF producers emit from symbol fonts. A Wingdings bullet arrives
# as U+F09F (private use area) and is unreadable as-is; it is a list marker, not
# content, so it is either normalised to '•' or dropped.
_PUA_MAP = {
    "\uf09f": "\u2022",   # Wingdings filled bullet
    "\uf0a7": "\u25aa",   # Wingdings small square
    "\uf0d8": "\u27a4",   # Wingdings arrow
    "\uf0b7": "\u2022",   # Symbol bullet
    "\uf0e0": "\u2709",   # Wingdings envelope
}


def normalise_symbols(text: str) -> str:
    """Map private-use symbol-font glyphs to real Unicode, drop the rest.

    Verified: the parameter list in the Anlogic TCL guide uses Wingdings bullets
    at U+F09F, one per parameter, each on its own line. Left alone they either
    vanish from a reader's view or look like mojibake.
    """
    for src, dst in _PUA_MAP.items():
        text = text.replace(src, dst)
    # any remaining private-use character has no readable meaning
    return re.sub(r"[\ue000-\uf8ff]", "", text)


def rejoin_wrapped_code(text: str) -> str:
    """Rejoin source lines that a PDF wrapped mid-token.

    A long shell/Tcl command wraps like this in the text layer:

        create_clock -name clk_25m -period 40.000 ... [get_ports {clk_25
        m}]

    Copying that yields a broken command, and the corruption is silent - nothing
    in the text marks the split. Indentation cannot be used to detect it because
    the extracted text does not carry x-coordinates; **delimiter balance can**.

    Rule: a short following line whose delimiters CLOSE what the previous line
    left open is a wrap, and is joined with no separator (the break fell inside
    a token). A line that opens and closes its own delimiters is not a wrap.

    Verified against the TCL guide: `... [get_ports {clk_25` + `m}]` joins to
    `... [get_ports {clk_25m}]`, while the complete example on the following line
    (`[get_ports {clk_25m}] \u2013add`) is correctly left alone.
    """
    def balance(s: str) -> int:
        """Positive = opened more than closed, ignoring delimiters in quotes."""
        depth = 0
        in_str = False
        for i, ch in enumerate(s):
            if ch == '"' and (i == 0 or s[i - 1] != "\\"):
                in_str = not in_str
            elif not in_str:
                if ch in "{[(":
                    depth += 1
                elif ch in "}])":
                    depth -= 1
        return depth

    lines = text.splitlines()
    out: list[str] = []
    for ln in lines:
        if not ln.strip():
            out.append(ln)
            continue
        if out and out[-1].strip() and len(ln.strip()) <= 30:
            prev = out[-1]
            # previous line left a delimiter open, this line closes it
            if balance(prev) > 0 and balance(ln) + balance(prev) <= 0:
                out[-1] = prev.rstrip() + ln.strip()
                continue
        out.append(ln)
    return "\n".join(out)


def mode_outline(doc, path, depth=None, pattern=None, rebuild=False) -> list:
    out = []
    rx = re.compile(pattern, re.I) if pattern else None
    source = doc.get_toc()
    if rebuild or not source:
        fut = detect_furniture(doc)
        excl = set(fut["furniture_lines"]) | set(fut["stable_prefixes"])
        source = [(e["level"], e["title"], e["page"])
                  for e in infer_outline(doc, exclude=excl)]
    for lvl, title, pno in source:
        if depth and lvl > depth:
            continue
        t = title.strip()
        if rx and not rx.search(t):
            continue
        out.append({"level": lvl, "title": t, "page": pno})
    return out


def resolve_section(doc, title=None, page=None):
    """Return (start_page, end_page, matched_title) using the bookmark tree,
    falling back to an inferred outline when the document has none."""
    toc = doc.get_toc()
    if not toc:
        fut = detect_furniture(doc)
        excl = set(fut["furniture_lines"]) | set(fut["stable_prefixes"])
        toc = [(e["level"], e["title"], e["page"])
               for e in infer_outline(doc, exclude=excl)]
    if page is not None:
        return page, page, None
    if not toc:
        raise SystemExit("no bookmark tree and no headings could be inferred; use --page instead")
    rx = re.compile(re.escape(title), re.I)
    hit = None
    for i, (lvl, t, pno) in enumerate(toc):
        if rx.search(t.strip()):
            hit = i
            break
    if hit is None:
        raise SystemExit(f"no heading matching {title!r}")
    lvl, t, start = toc[hit]
    end = doc.page_count
    for lvl2, _t2, p2 in toc[hit + 1:]:
        if lvl2 <= lvl:
            end = max(start, p2 - 1) if p2 > start else start
            break
    return start, end, t.strip()


def mode_section(doc, path, title=None, page=None, end_page=None,
                 want_tables=False, max_pages_out: int = 60) -> dict:
    fut = detect_furniture(doc)
    furniture = set(fut["furniture_lines"])
    prefixes = set(fut["stable_prefixes"])
    pagenums = set(fut["page_number_like"])
    start, end, matched = resolve_section(doc, title, page)
    if end_page is not None:
        end = end_page
    end = min(end, doc.page_count)

    pages, skipped = [], 0
    for i in range(start, end + 1):
        if len(pages) >= max_pages_out:
            skipped = end - i + 1
            break
        cleaned = strip_furniture(doc[i - 1].get_text("text"), furniture, prefixes, pagenums)
        if cleaned:
            pages.append({"page": i, "text": cleaned})

    body = "\n\n".join(p["text"] for p in pages)
    result = {
        "file": path,
        "matched_title": matched,
        "start_page": start,
        "end_page": end,
        "pages": pages,
        "chars": sum(len(p["text"]) for p in pages),
        "truncated_pages": skipped,
    }
    if want_tables:
        found = []
        for i in range(start, end + 1):
            page = doc[i - 1]
            try:
                tf = page.find_tables()
            except Exception:
                tf = None
            if tf and tf.tables:
                # preferred path: real geometry from find_tables, text from rawdict
                for t in tf.tables:
                    got = extract_table_text(doc, page, t)
                    hdr = got["rows"][0] if got["rows"] else []
                    body = got["rows"][1:] if len(got["rows"]) > 1 else []
                    # realign the header onto the body's column set
                    if hdr and body and len(hdr) != len(body[0]):
                        width = max(len(hdr), max(len(r) for r in body))
                        hdr = hdr + [""] * (width - len(hdr))
                        body = [r + [""] * (width - len(r)) for r in body]
                        keep = [ci for ci in range(width)
                                if any(r[ci] for r in body) or (ci < len(hdr) and hdr[ci])]
                        hdr = [hdr[ci] for ci in keep]
                        body = [[r[ci] for ci in keep] for r in body]
                    found.append({
                        "page": i,
                        "bbox": [round(v, 1) for v in t.bbox],
                        "header": hdr,
                        "rows": body,
                        "merged": got["merged"],
                        "method": "find_tables+x-coordinate-merge",
                    })
            else:
                # fallback for tables find_tables cannot see
                for t in reconstruct_tables_by_position(page):
                    found.append({
                        "page": i,
                        "bbox": None,
                        "header": t["header"],
                        "rows": t["rows"],
                        "merged": [],
                        "method": "x-coordinate-only",
                    })
        result["tables"] = found
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description="Navigate long technical PDFs.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("profile"); p.add_argument("pdf"); p.add_argument("--json")
    p = sub.add_parser("outline"); p.add_argument("pdf")
    p.add_argument("--depth", type=int); p.add_argument("--grep"); p.add_argument("--json")
    p.add_argument("--rebuild", action="store_true",
                   help="ignore the PDF's own bookmarks and infer headings from font sizes")
    p = sub.add_parser("section"); p.add_argument("pdf")
    p.add_argument("--title"); p.add_argument("--page", type=int); p.add_argument("--end-page", type=int)
    p.add_argument("--tables", action="store_true",
                   help="also rebuild space-aligned tables that find_tables() misses")
    p.add_argument("--max-pages-out", type=int, default=60)
    p.add_argument("--json")
    p = sub.add_parser("clean"); p.add_argument("pdf")
    p.add_argument("--start", type=int, default=1); p.add_argument("--end", type=int)
    p.add_argument("--tables", action="store_true")
    p.add_argument("--max-pages-out", type=int, default=40)

    a = ap.parse_args(argv)
    doc = pymupdf.open(a.pdf)

    if a.cmd == "profile":
        r = mode_profile(doc, a.pdf)
        print(f"pages={r['pages']}  toc_entries={r['toc_entries']}  producer={r['producer']!r}")
        print(f"chars: raw={r['chars_raw']}  content={r['chars_content']}  "
              f"-> furniture overhead {r['furniture_overhead_pct']}%")
        cp = r["chars_per_page"]
        print(f"chars/page: min={cp['min']} median={cp['median']} max={cp['max']}  "
              f"thin_pages={r['thin_pages']}")
        print(f"images={r['total_images']} on {r['pages_with_images']} pages; "
              f"heavy-vector pages={r['pages_with_heavy_vectors']}")
        print("\ndetected running header/footer (removed automatically by `section`):")
        for ln in r["furniture"]["furniture_lines"]:
            print(f"    {ln!r}")
        if r["furniture"]["page_number_like"]:
            print(f"  page-number-like: {r['furniture']['page_number_like']}")
        if r["furniture"]["stable_prefixes"]:
            print(f"  stable prefixes also stripped: {r['furniture']['stable_prefixes']}")
        print("\nadvice: this document is navigable by bookmark - use `outline` then `section`"
              if r["toc_entries"] > 10 else
              "\nadvice: few bookmarks - use `clean` on targeted page ranges")
        if a.json:
            json.dump(r, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    elif a.cmd == "outline":
        rows = mode_outline(doc, a.pdf, a.depth, a.grep, a.rebuild)
        origin = "inferred from font sizes" if (a.rebuild or not doc.get_toc()) else "PDF bookmarks"
        print(f"{len(rows)} heading(s) [{origin}]")
        for r in rows:
            print(f"  {'  ' * (r['level'] - 1)}{r['title'][:80]}  ... p{r['page']}")
        if a.json:
            json.dump(rows, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    elif a.cmd == "section":
        if not a.title and not a.page:
            raise SystemExit("pass --title or --page")
        r = mode_section(doc, a.pdf, a.title, a.page, a.end_page, a.tables,
                         a.max_pages_out)
        print(f"# {r['matched_title'] or '(page range)'}  pages {r['start_page']}-{r['end_page']}  "
              f"({r['chars']} chars)")
        if r.get("truncated_pages"):
            print(f"NOTE: output truncated, {r['truncated_pages']} more page(s) not shown "
                  f"(raise --max-pages-out to include them)")
        for p in r["pages"]:
            print(f"\n--- page {p['page']} ---")
            print(p["text"])
        if a.tables:
            print(f"\n=== reconstructed tables: {len(r.get('tables', []))} ===")
            for ti, t in enumerate(r.get("tables", []), 1):
                hdr = t.get("header")
                print(f"\n[table {ti}] page {t.get('page')}  method={t.get('method')}")
                if hdr:
                    # find_tables pads merged cells with empty phantom columns;
                    # leading blanks are harmless, trailing padding is noise
                    print("  HDR | " + " | ".join(hdr).rstrip(" |"))
                for row in t.get("rows", []):
                    line = " | ".join(row).rstrip(" |")
                    print(f"      | {line}")
                for m in t.get("merged", []):
                    print(f"  (merged cell: row {m['row']} col {m['col']} spans "
                          f"{m['row_span']} rows)")
        if a.json:
            json.dump(r, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    elif a.cmd == "clean":
        end = a.end or doc.page_count
        fut = detect_furniture(doc)
        furniture = set(fut["furniture_lines"])
        prefixes = set(fut["stable_prefixes"])
        pagenums = set(fut["page_number_like"])
        shown = 0
        parts = []
        for i in range(a.start, min(end, doc.page_count) + 1):
            if shown >= a.max_pages_out:
                print(f"\nNOTE: stopped at --max-pages-out={a.max_pages_out}; "
                      f"pages {i}-{min(end, doc.page_count)} not shown")
                break
            txt = strip_furniture(doc[i - 1].get_text("text"), furniture, prefixes, pagenums)
            parts.append(txt)
            print(f"\n--- page {i} ---")
            print(txt)
            shown += 1
        if a.tables:
            tbls = reconstruct_column_tables("\n\n".join(parts))
            print(f"\n=== reconstructed tables: {len(tbls)} ===")
            for ti, t in enumerate(tbls, 1):
                print(f"\n[table {ti}]  {t['rows']}x{t['cols']}")
                for row in t["data"]:
                    print("  | " + " | ".join(row))

    doc.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
