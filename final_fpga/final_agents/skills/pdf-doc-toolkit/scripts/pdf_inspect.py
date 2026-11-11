#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pdf_inspect.py - structured PDF inspection for the pdf-doc-toolkit skill.

Extracts text with font/size/color/position fidelity, reconstructs tables from
vector geometry, and repairs mangled CJK font names. No external binaries.

Usage:
    python pdf_inspect.py <file.pdf> [--mode spans|blocks|text|tables|images|fonts|outline|all]
                                      [--page N] [--json OUT.json]

Design notes (learned from real documents):
  * pymupdf.get_text("dict") MERGES adjacent spans. Use "rawdict" when you need
    per-character ground truth; use "dict" for a readable span inventory.
  * Word-produced PDFs write CJK font names as GBK bytes inside a Latin-1
    string, so 'ABCDEE+ËÎÌå' is really '宋体'. repair_font_name() fixes this.
  * Tables made of vector fill rectangles are reconstructed by find_tables();
    verify the row/col count against the rendered page before trusting it.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter

try:
    import pymupdf
except ImportError:  # pragma: no cover
    sys.exit("pymupdf is required: python -m pip install pymupdf")


# --------------------------------------------------------------------------
# font name repair
# --------------------------------------------------------------------------
def repair_font_name(name: str) -> str:
    """Recover a CJK font name whose bytes were written as Latin-1.

    Word/LibreOffice PDF export writes the font's GBK bytes into a string the
    PDF spec treats as Latin-1, producing mojibake such as
    'ABCDEE+ËÎÌå' for 'ABCDEE+宋体'. Round-tripping through Latin-1 and
    decoding as GBK recovers it; ASCII names pass through unchanged.
    """
    if not isinstance(name, str) or not name:
        return name
    try:
        recovered = name.encode("latin-1", "ignore").decode("gbk", "ignore")
    except Exception:
        return name
    # only accept the repair when it produced a CJK result and is non-degenerate
    if recovered.strip() and any("\u4e00" <= ch <= "\u9fff" for ch in recovered):
        return recovered
    return name


def _span_records(page, pno: int, raw: bool = False):
    """Yield span dicts for one page."""
    mode = "rawdict" if raw else "dict"
    for block in page.get_text(mode)["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block["lines"]:
            for span in line["spans"]:
                yield {
                    "page": pno,
                    "bbox": [round(v, 2) for v in span["bbox"]],
                    "origin": [round(v, 2) for v in span.get("origin", (0, 0))],
                    "font_raw": span["font"],
                    "font": repair_font_name(span["font"]),
                    "size": round(span["size"], 2),
                    "color": "#%06x" % span["color"],
                    "flags": span["flags"],
                    "text": span["text"],
                    "char_count": len(span.get("chars", [])) if raw else None,
                }


# --------------------------------------------------------------------------
# inspection modes
# --------------------------------------------------------------------------
def mode_spans(doc, page_filter=None):
    out = []
    for pno, page in enumerate(doc, 1):
        if page_filter and pno != page_filter:
            continue
        out.extend(_span_records(page, pno))
    return out


def mode_blocks(doc, page_filter=None):
    out = []
    for pno, page in enumerate(doc, 1):
        if page_filter and pno != page_filter:
            continue
        for block in page.get_text("dict")["blocks"]:
            if block.get("type") != 0:
                continue
            text = "".join(s["text"] for l in block["lines"] for s in l["spans"])
            out.append({
                "page": pno,
                "bbox": [round(v, 1) for v in block["bbox"]],
                "sizes": sorted({round(s["size"], 2) for l in block["lines"] for s in l["spans"]}),
                "fonts": sorted({repair_font_name(s["font"]) for l in block["lines"] for s in l["spans"]}),
                "text": text.strip(),
            })
    return out


def mode_tables(doc, page_filter=None):
    out = []
    for pno, page in enumerate(doc, 1):
        if page_filter and pno != page_filter:
            continue
        try:
            found = page.find_tables()
        except Exception as exc:  # keeps the report honest instead of silent
            out.append({"page": pno, "error": f"{type(exc).__name__}: {exc}"})
            continue
        for idx, table in enumerate(found.tables, 1):
            out.append({
                "page": pno,
                "index": idx,
                "bbox": [round(v, 1) for v in table.bbox],
                "rows": table.row_count,
                "cols": table.col_count,
                "cells": table.extract(),
            })
    return out


def mode_images(doc, page_filter=None):
    """Report each image ONCE, with both its XObject facts and its display rect.

    Earlier versions emitted an XObject entry and a separate
    'displayed-image-block' entry for the same picture, which double-counted
    every image. The display block is now merged into the XObject record, and a
    display block with no matching XObject is reported as inline/decorative.
    """
    out = []
    for pno, page in enumerate(doc, 1):
        if page_filter and pno != page_filter:
            continue
        xobjects = page.get_images(full=True)
        blocks = [b for b in page.get_text("dict")["blocks"] if b.get("type") == 1]
        blocks.sort(key=lambda b: (b["bbox"][1], b["bbox"][0]))
        for i, img in enumerate(xobjects):
            xref = img[0]
            rec = {"page": pno, "xref": xref, "width": img[2], "height": img[3],
                   "bpc": img[4], "colorspace": img[5], "filter": img[8],
                   "has_smask": bool(img[1])}
            try:
                rec["extract_size"] = len(doc.extract_image(xref)["image"])
            except Exception as exc:
                rec["extract_error"] = str(exc)
            if i < len(blocks):
                rec["display_bbox"] = [round(v, 1) for v in blocks[i]["bbox"]]
            out.append(rec)
        for b in blocks[len(xobjects):]:
            out.append({"page": pno, "kind": "display-block-without-xobject",
                        "bbox": [round(v, 1) for v in b["bbox"]]})
    return out


def mode_fonts(doc, page_filter=None):
    out = []
    for pno, page in enumerate(doc, 1):
        if page_filter and pno != page_filter:
            continue
        for f in page.get_fonts(full=True):
            out.append({
                "page": pno, "xref": f[0], "ext": f[1], "type": f[2],
                "basefont_raw": f[3], "basefont": repair_font_name(f[3]),
                "refname": f[4], "encoding": f[5],
            })
    return out


def mode_outline(doc, page_filter=None):
    meta = doc.metadata or {}
    return {
        "page_count": doc.page_count,
        "is_pdf": doc.is_pdf,
        "is_encrypted": doc.is_encrypted,
        "needs_pass": bool(doc.needs_pass),
        "pdf_format": meta.get("format"),
        "title": meta.get("title"),
        "author": meta.get("author"),
        "subject": meta.get("subject"),
        "creator": meta.get("creator"),
        "producer": meta.get("producer"),
        "creationDate": meta.get("creationDate"),
        "modDate": meta.get("modDate"),
        "toc": doc.get_toc(),
        "page_sizes": [
            {"page": i, "width": round(p.rect.width, 1), "height": round(p.rect.height, 1),
             "rotation": p.rotation}
            for i, p in enumerate(doc, 1)
        ],
    }


MODES = {
    "spans": mode_spans, "blocks": mode_blocks, "tables": mode_tables,
    "images": mode_images, "fonts": mode_fonts, "outline": mode_outline,
}


def mode_text(doc, page_filter=None):
    out = []
    for pno, page in enumerate(doc, 1):
        if page_filter and pno != page_filter:
            continue
        out.append({"page": pno, "text": page.get_text("text")})
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Inspect a PDF's text, fonts, tables and images.")
    ap.add_argument("pdf")
    ap.add_argument("--mode", default="all",
                    choices=["spans", "blocks", "text", "tables", "images",
                             "fonts", "outline", "all"])
    ap.add_argument("--page", type=int, default=None, help="restrict to one 1-based page")
    ap.add_argument("--json", default=None, help="write full result to this JSON path")
    args = ap.parse_args(argv)

    doc = pymupdf.open(args.pdf)
    wanted = list(MODES) + ["text"] if args.mode == "all" else [args.mode]
    result = {}
    for m in wanted:
        fn = mode_text if m == "text" else MODES[m]
        result[m] = fn(doc, args.page)
    doc.close()

    # console summary - the parts a human or model should read first
    if "outline" in result:
        o = result["outline"]
        print(f"pages={o['page_count']} encrypted={o['is_encrypted']} "
              f"producer={o['producer']!r} author={o['author']!r}")
    if "spans" in result:
        c = Counter((s["font"], s["size"]) for s in result["spans"])
        print(f"\nspans={len(result['spans'])}  distinct font/size pairs={len(c)}")
        for (font, size), n in sorted(c.items(), key=lambda kv: -kv[1]):
            print(f"  {n:5d}  {size:6.2f}pt  {font}")
        colors = Counter(s["color"] for s in result["spans"])
        print(f"  colors: {dict(colors)}")
    if "blocks" in result:
        print(f"\nblocks={len(result['blocks'])}")
        for b in result["blocks"][:20]:
            print(f"  p{b['page']} y={b['bbox'][1]:7.1f} sz={b['sizes']} "
                  f"f={b['fonts']} {b['text'][:70]!r}")
    if "fonts" in result:
        uniq = {}
        for f in result["fonts"]:
            uniq.setdefault(f["basefont"], set()).add(f["page"])
        print(f"\ndistinct fonts={len(uniq)}")
        for name, pages in sorted(uniq.items()):
            print(f"  {name:<28} pages={sorted(pages)}")
    if "text" in result:
        total = sum(len(t["text"]) for t in result["text"])
        print(f"\ntext pages={len(result['text'])} total_chars={total}")
        first = result["text"][0]["text"] if result["text"] else ""
        print("  --- first page (first 600 chars) ---")
        print("  " + first[:600].replace("\n", "\n  "))
    if "tables" in result:
        print(f"\ntables={len(result['tables'])}")
        for t in result["tables"]:
            if "error" in t:
                print(f"  page {t['page']}: ERROR {t['error']}")
            else:
                print(f"  page {t['page']} #{t['index']}: {t['rows']}x{t['cols']} bbox={t['bbox']}")
    if "images" in result:
        print(f"\nembedded images={len(result['images'])}")

    if args.json:
        # Always emit a stable shape: {"mode": ..., "file": ..., "result": ...}.
        # An earlier version wrote a bare {mode: value} mapping, so a consumer
        # could not tell "single mode" from "all modes" without guessing - which
        # is exactly how a downstream script ended up indexing a dict as a list.
        payload = {
            "file": args.pdf,
            "mode": args.mode,
            "page_filter": args.page,
            "modes_present": sorted(result),
            "result": result,
        }
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
        print(f"\nfull JSON -> {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
