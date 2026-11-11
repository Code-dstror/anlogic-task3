#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pdf_read.py - ONE-CALL document read for pdf-doc-toolkit.

Answers "what does this document say" in a single invocation: reading-order
markdown plus automatically detected anomalies. Use this FIRST. Reach for
pdf_inspect.py / pdf_audit.py only when this reports something it cannot
resolve, or when the task genuinely needs per-span detail.

Design intent: the expensive path (span inventory, full content-stream audit,
page rendering, visual inspection) is for proving things, not for reading.
Applying it to a plain prose document wastes a dozen tool calls.

Usage:
    python pdf_read.py <file.pdf> [--max-chars N] [--json OUT.json] [--tables-only]
"""
from __future__ import annotations

import argparse
import json
import re
import sys

try:
    import pymupdf
except ImportError:  # pragma: no cover
    sys.exit("pymupdf is required: python -m pip install pymupdf")

# Word emits this string into a TOC when a heading bookmark was never created.
WORD_FIELD_ERROR = re.compile(r"错误!\s*未定义书签。|Error!\s*Bookmark not defined\.")


def _norm_bbox(b):
    return [round(v, 1) for v in b]


def join_split_tables(tables: list[dict], page_height: float) -> list[dict]:
    """Merge tables that continue across a page break.

    Two signatures, in decreasing confidence:

    CONFIDENT  - the first fragment ends near the page bottom (small gap), the
                 next starts near the next page's top (small top margin), and
                 the two share the same x-origin and width. The continuation has
                 no repeated header.
    AMBIGUOUS  - same x/width and the continuation REPEATS the header row.
                 This is also what two genuinely separate same-shaped tables
                 look like, so it is reported, not silently merged.
    """
    joined = []
    i = 0
    while i < len(tables):
        cur = dict(tables[i])
        cur["continued_from"] = None
        cur["merge_confidence"] = None
        if i + 1 < len(tables):
            nxt = tables[i + 1]
            same_x = abs(nxt["bbox"][0] - cur["bbox"][0]) < 1.5
            same_w = abs((nxt["bbox"][2] - nxt["bbox"][0])
                         - (cur["bbox"][2] - cur["bbox"][0])) < 1.5
            cur_gap = page_height - cur["bbox"][3]
            nxt_top = nxt["bbox"][1]
            header_repeated = (nxt.get("header") and cur.get("header")
                               and [str(c) for c in nxt["header"]] == [str(c) for c in cur["header"]])
            if same_x and same_w and cur_gap < 120 and nxt_top < 120:
                if not header_repeated:
                    cur["data"] = list(cur["data"]) + list(nxt["data"])
                    cur["rows"] = len(cur["data"])
                    cur["merged_pages"] = [cur["page"], nxt["page"]]
                    cur["merge_confidence"] = "confident"
                    joined.append(cur)
                    i += 2
                    continue
                cur["merge_confidence"] = "ambiguous-header-repeated"
                cur["possible_continuation_page"] = nxt["page"]
        joined.append(cur)
        i += 1
    return joined


def collect_tables(doc) -> list[dict]:
    out = []
    for pno, page in enumerate(doc, 1):
        try:
            found = page.find_tables()
        except Exception:
            continue
        for t in found.tables:
            data = t.extract()
            out.append({
                "page": pno, "bbox": _norm_bbox(t.bbox),
                "rows": t.row_count, "cols": t.col_count,
                "header": data[0] if data else [],
                "data": data,
            })
    return out


def find_anomalies(doc, tables) -> list[str]:
    """Cheap, high-signal checks - no rendering involved.

    Every check here must be specific enough that a normal document does not
    trip it. An earlier version flagged every coloured empty span, which fired
    237 times on an ordinary Word export because the body text colour itself is
    not pure black. Noise like that trains the reader to ignore the whole list.
    """
    notes = []

    # 1. Word TOC field errors
    for pno, page in enumerate(doc, 1):
        txt = page.get_text("text")
        for m in WORD_FIELD_ERROR.finditer(txt):
            ctx = txt[max(0, m.start() - 60):m.end()].replace("\n", " ").strip()
            notes.append(f"p{pno}: Word field error in text -> ...{ctx}")

    # 2. empty spans - only report colours that are NOT part of the document's
    #    own text palette, since a coloured empty span in the body colour is
    #    just Word leaving formatting artefacts behind.
    def hexc(c):
        return "#%06x" % c

    palette, empty = {}, {}
    for page in doc:
        for b in page.get_text("dict")["blocks"]:
            if b.get("type") != 0:
                continue
            for ln in b["lines"]:
                for s in ln["spans"]:
                    if s["text"].strip():
                        palette[hexc(s["color"])] = palette.get(hexc(s["color"]), 0) + 1
                    else:
                        empty[hexc(s["color"])] = empty.get(hexc(s["color"]), 0) + 1
    odd = {c: n for c, n in empty.items() if c not in palette}
    if odd:
        notes.append(f"{sum(odd.values())} empty span(s) in colour(s) absent from the text "
                     f"palette {odd} - formatting artefacts (harmless, listed for completeness)")
    total_empty = sum(empty.values())
    if total_empty:
        notes.append(f"{total_empty} empty span(s) total - Word formatting residue, not content")

    # 3. tables that touch a page edge (split candidates)
    ph = doc[0].rect.height
    for t in tables:
        bottom_gap = ph - t["bbox"][3]
        top_gap = t["bbox"][1]
        if bottom_gap < 120:
            notes.append(f"table on p{t['page']} ends {bottom_gap:.0f}pt from the page bottom - may continue")
        if top_gap < 120 and t["bbox"][1] > 0:
            notes.append(f"table on p{t['page']} starts {top_gap:.0f}pt from the page top - may be a continuation")

    # 4. header/footer detection (same text on many pages)
    first_lines = {}
    for pno, page in enumerate(doc, 1):
        for ln in page.get_text("text").splitlines():
            ln = ln.strip()
            if ln:
                first_lines.setdefault(ln, []).append(pno)
                break
    repeated = {k: v for k, v in first_lines.items() if len(v) > 3}
    if repeated:
        notes.append(f"repeated running header/footer on {len(repeated)} distinct string(s): "
                     f"{list(repeated)[:2]}")

    return notes


def read_document(path: str, max_chars: int | None = None) -> dict:
    doc = pymupdf.open(path)
    meta = doc.metadata or {}
    n_pages = doc.page_count

    pages, per_page_chars = [], []
    for pno, page in enumerate(doc, 1):
        txt = page.get_text("text")
        per_page_chars.append(len(txt))
        if max_chars is not None and pno > max_chars:
            break
        # collapse blank-line padding that Word exports produce
        lines, out, prev_blank = txt.splitlines(), [], False
        for ln in lines:
            blank = ln.strip() == ""
            if blank and prev_blank:
                continue
            out.append(ln.rstrip())
            prev_blank = blank
        body = "\n".join(out).strip()
        if body:
            pages.append({"page": pno, "text": body})

    tables = collect_tables(doc)
    joined = join_split_tables(tables, doc[0].rect.height)
    notes = find_anomalies(doc, tables)

    n_images = sum(len(page.get_images(full=True)) for page in doc)

    doc.close()
    return {
        "file": path,
        "page_count": n_pages,
        "producer": meta.get("producer"),
        "author": meta.get("author"),
        "total_chars": sum(per_page_chars),
        "chars_per_page": per_page_chars,
        "embedded_images": n_images,
        "pages": pages,
        "tables": joined,
        "notes": notes,
    }


def render_markdown(r: dict, include_text: bool = True) -> str:
    L = []
    L.append(f"# {r['file'].split(chr(92))[-1].split('/')[-1]}")
    L.append("")
    L.append(f"- pages: {r['page_count']}  chars: {r['total_chars']}  "
             f"images: {r['embedded_images']}  tables: {len(r['tables'])}")
    L.append(f"- producer: {r['producer']!r}  author: {r['author']!r}")
    if r["notes"]:
        L.append("")
        L.append("**Anomalies detected:**")
        for n in r["notes"]:
            L.append(f"- {n}")
    if r["tables"]:
        L.append("")
        L.append("## Tables")
        for t in r["tables"]:
            tag = ""
            if t.get("merged_pages"):
                tag = f"  [merged from pages {t['merged_pages']}]"
            elif t.get("merge_confidence") == "ambiguous-header-repeated":
                tag = (f"  [AMBIGUOUS: page {t['possible_continuation_page']} repeats this "
                       f"header - verify before treating as separate]")
            L.append("")
            L.append(f"### p{t['page']} ({t['rows']}x{t['cols']}){tag}")
            L.append("")
            for row in t["data"]:
                L.append("| " + " | ".join("" if c is None else str(c) for c in row) + " |")
    if include_text:
        L.append("")
        L.append("## Text")
        for p in r["pages"]:
            L.append("")
            L.append(f"### page {p['page']}")
            L.append("")
            L.append(p["text"])
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="One-call read of a PDF: text + tables + anomaly detection.")
    ap.add_argument("pdf")
    ap.add_argument("--json", help="also write the structured result here")
    ap.add_argument("--max-chars", type=int, default=None,
                    help="stop after this many pages (safety valve for huge files)")
    ap.add_argument("--no-text", action="store_true",
                    help="print metadata/tables/notes only")
    ap.add_argument("--markdown", help="write the full markdown read to this path")
    args = ap.parse_args(argv)

    r = read_document(args.pdf, args.max_chars)
    md = render_markdown(r, include_text=not args.no_text)
    print(md)

    if args.markdown:
        with open(args.markdown, "w", encoding="utf-8") as fh:
            fh.write(md)
        # stdout, not stderr: PowerShell surfaces stderr as a NativeCommandError
        print(f"[markdown written to {args.markdown}]")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(r, fh, ensure_ascii=False, indent=1)
        print(f"[json written to {args.json}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
