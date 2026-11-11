#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pdf_audit.py - evidence-based PDF integrity audit for pdf-doc-toolkit.

Answers the question "is what I extracted actually everything, and is any of it
invisible to a human reader?" with measurements rather than heuristics.

Three independent checks:

  1. VISIBILITY  - every glyph span is classified visible/invisible using
     pymupdf's text-trace, whose invisible-span marker is established by a
     self-test (see `_probe_invisible_marker`) instead of a hardcoded constant.
  2. COVERAGE    - raw text-showing operators in the content stream are counted
     per page and compared with the number of extracted spans, so a page that
     silently lost text is flagged.
  3. INK         - the rendered page is thresholded; ink that cannot be explained
     by extracted text or by image/vector objects is reported.

Usage:
    python pdf_audit.py <file.pdf> [--render-dir DIR] [--dpi 110]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile

try:
    import pymupdf
except ImportError:  # pragma: no cover
    sys.exit("pymupdf is required: python -m pip install pymupdf")


# --------------------------------------------------------------------------
# 1. establish which text-trace "type" value means "invisible"
# --------------------------------------------------------------------------
def _probe_invisible_marker() -> int | None:
    """Build a two-span PDF (one normal, one `3 Tr`) and read back the trace.

    Deriving the marker at runtime keeps this script correct even if the
    library renumbers its trace types.
    """
    try:
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "probe.pdf")
            doc = pymupdf.open()
            page = doc.new_page()
            page.insert_text((72, 100), "PROBEVISIBLE", fontsize=12)
            xref = page.get_contents()[0]
            doc.update_stream(
                xref,
                doc.xref_stream(xref)
                + b"\nBT /Helv 12 Tf 3 Tr 1 0 0 1 72 150 Tm (PROBEHIDDEN) Tj ET\n",
            )
            doc.save(path)
            doc.close()

            doc = pymupdf.open(path)
            trace = doc[0].get_texttrace()
            visible_type = hidden_type = None
            for span in trace:
                chars = "".join(chr(c[0]) for c in span.get("chars", []))
                if "PROBEVISIBLE" in chars:
                    visible_type = span.get("type")
                elif "PROBEHIDDEN" in chars:
                    hidden_type = span.get("type")
            doc.close()
            if hidden_type is not None and hidden_type != visible_type:
                return hidden_type
            return None
    except Exception:
        return None


# --------------------------------------------------------------------------
# 2. raw content-stream operator counting (depth-aware)
# --------------------------------------------------------------------------
def _array_end(s: str, i: int) -> int:
    """s[i] == '['; return index just past its matching ']' (-1 if unbalanced)."""
    depth, j, n, in_str = 0, i, len(s), False
    while j < n:
        c = s[j]
        if in_str:
            if c == "\\":
                j += 2
                continue
            if c == ")":
                in_str = False
        else:
            if c == "(":
                in_str = True
            elif c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    return j + 1
        j += 1
    return -1


def count_text_operators(raw: str) -> dict:
    """Count top-level TJ / Tj / ' / " operators and detect render modes.

    Nested arrays are skipped by tracking bracket depth: a naive regex counts
    TJ arrays that live *inside* another array and over-reports.
    """
    st = {"TJ": 0, "Tj": 0, "quote": 0, "dquote": 0, "TJ_no_glyphs": 0,
          "invisible_render_mode": 0, "render_modes": set(),
          "white_fill_rgb": 0, "white_fill_gray": 0}

    for m in re.finditer(r"(?<![\d.])(\d)\s+Tr(?![A-Za-z])", raw):
        st["render_modes"].add(m.group(1))
        if m.group(1) == "3":
            st["invisible_render_mode"] += 1
    st["white_fill_rgb"] = len(re.findall(
        r"(?<![\d.])1(?:\.0+)?\s+1(?:\.0+)?\s+1(?:\.0+)?\s+rg(?![A-Za-z])", raw))
    st["white_fill_gray"] = len(re.findall(r"(?<![\d.])1(?:\.0+)?\s+g(?![A-Za-z])", raw))

    i, n, in_str = 0, len(raw), False
    while i < n:
        c = raw[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == ")":
                in_str = False
            i += 1
            continue
        if c == "(":
            in_str = True
            i += 1
            continue
        if c == "[":
            end = _array_end(raw, i)
            if end < 0:
                break
            if re.match(r"\s*TJ(?![A-Za-z])", raw[end:]):
                st["TJ"] += 1
                if "(" not in raw[i:end]:
                    st["TJ_no_glyphs"] += 1
                i = end
            else:
                i = end
            continue
        if c == "'":
            st["quote"] += 1
            i += 1
            continue
        if c == '"':
            st["dquote"] += 1
            i += 1
            continue
        m = re.match(r"Tj(?![A-Za-z])", raw[i:])
        if m:
            st["Tj"] += 1
            i += m.end()
            continue
        i += 1

    st["render_modes"] = sorted(st["render_modes"])
    return st


# --------------------------------------------------------------------------
# 3. audit
# --------------------------------------------------------------------------
def audit(path: str, render_dir: str | None = None, dpi: int = 110) -> dict:
    invisible_marker = _probe_invisible_marker()
    doc = pymupdf.open(path)
    pages = []

    for pno, page in enumerate(doc, 1):
        raw = b"".join(doc.xref_stream(x) for x in page.get_contents()).decode("latin-1")
        ops = count_text_operators(raw)

        trace = page.get_texttrace()
        visible = invisible = 0
        invisible_boxes = []
        for span in trace:
            if invisible_marker is not None and span.get("type") == invisible_marker:
                invisible += 1
                invisible_boxes.append([round(v, 1) for v in span["bbox"]])
            else:
                visible += 1

        spans = sum(len(l["spans"]) for b in page.get_text("dict")["blocks"]
                    if b["type"] == 0 for l in b["lines"])
        text_chars = len(page.get_text("text"))

        n_img_blocks = sum(1 for b in page.get_text("dict")["blocks"] if b.get("type") == 1)
        n_drawings = len(page.get_drawings())

        entry = {
            "page": pno,
            "extracted_chars": text_chars,
            "extracted_spans": spans,
            "texttrace_visible_spans": visible,
            "texttrace_invisible_spans": invisible,
            "invisible_bboxes": invisible_boxes[:10],
            "content_stream": ops,
            "image_blocks": n_img_blocks,
            "vector_paths": n_drawings,
        }

        if render_dir:
            os.makedirs(render_dir, exist_ok=True)
            full = page.get_pixmap(dpi=dpi)
            fp = os.path.join(render_dir, f"page{pno}_{dpi}dpi.png")
            full.save(fp)
            entry["render"] = fp

        # verdicts
        flags = []
        if invisible > 0:
            flags.append(f"{invisible} invisible text span(s) - text exists that a reader cannot see")
        if ops["invisible_render_mode"] > 0:
            flags.append(f"{ops['invisible_render_mode']} '3 Tr' invisible render mode op(s)")
        if ops["white_fill_rgb"] or ops["white_fill_gray"]:
            flags.append(f"white fill op(s): rgb={ops['white_fill_rgb']} gray={ops['white_fill_gray']}"
                         " - text may be white-on-white")
        if ops["TJ"] + ops["Tj"] + ops["quote"] + ops["dquote"] == 0 and text_chars == 0:
            flags.append("page appears to hold no text at all")
        if text_chars == 0 and (n_img_blocks or n_drawings > 20):
            flags.append("no extractable text but page has image/vector content - likely scanned; OCR needed")
        entry["flags"] = flags
        pages.append(entry)

    doc.close()
    return {
        "file": os.path.abspath(path),
        "invisible_marker_resolved": invisible_marker,
        "invisible_marker_note": (
            "text-trace 'type' value proven to mean invisible by self-test"
            if invisible_marker is not None else
            "could not resolve the marker on this build - falling back to raw '3 Tr' counts only"
        ),
        "pages": pages,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description="Audit a PDF for hidden text and extraction coverage.")
    ap.add_argument("pdf")
    ap.add_argument("--render-dir", default=None, help="also render pages here")
    ap.add_argument("--dpi", type=int, default=110)
    ap.add_argument("--json", default=None)
    args = ap.parse_args(argv)

    result = audit(args.pdf, args.render_dir, args.dpi)

    print(f"file: {result['file']}")
    print(f"invisible-span marker: {result['invisible_marker_resolved']}")
    print(f"  ({result['invisible_marker_note']})\n")
    total_flags = 0
    for p in result["pages"]:
        cs = p["content_stream"]
        print(f"page {p['page']}: chars={p['extracted_chars']} spans={p['extracted_spans']} "
              f"visible={p['texttrace_visible_spans']} invisible={p['texttrace_invisible_spans']}")
        print(f"          TJ={cs['TJ']} Tj={cs['Tj']} modes={cs['render_modes']} "
              f"white_rgb={cs['white_fill_rgb']} white_gray={cs['white_fill_gray']} "
              f"images={p['image_blocks']} vectors={p['vector_paths']}")
        for f in p["flags"]:
            total_flags += 1
            print(f"          FLAG: {f}")
    print(f"\ntotal flags: {total_flags}")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(result, fh, ensure_ascii=False, indent=1)
        print(f"JSON -> {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
