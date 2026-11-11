#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""docx_tool.py - read and write .docx for pdf-doc-toolkit.

Reading is the priority: get paragraph text, run-level formatting, tables and
section geometry out of a Word file without losing structure. Writing covers the
common case of producing a report from text.

Known limitation (documented in SKILL.md): python-docx cannot round-trip a
document losslessly. Reading preserves everything; re-saving a heavily formatted
source may drop constructs python-docx does not model (some field codes,
content controls, advanced drawing objects). Prefer in-place text edits or
regenerating from source data over load-and-save for layout-critical files.

Usage:
    python docx_tool.py read    <file.docx> [--json OUT.json]
    python docx_tool.py write   <out.docx> --from-json IN.json
    python docx_tool.py write   <out.docx> --text file.txt --title "Heading"
"""
from __future__ import annotations

import argparse
import json
import os
import sys

try:
    import docx
    from docx.shared import Pt
except ImportError:  # pragma: no cover
    sys.exit("python-docx is required: python -m pip install python-docx")


def read_docx(path: str) -> dict:
    d = docx.Document(path)

    paragraphs = []
    for i, p in enumerate(d.paragraphs):
        runs = []
        for r in p.runs:
            runs.append({
                "text": r.text,
                "bold": r.bold,
                "italic": r.italic,
                "underline": bool(r.underline),
                "size_pt": r.font.size.pt if r.font.size else None,
                "font": r.font.name,
            })
        paragraphs.append({
            "index": i,
            "style": p.style.name if p.style is not None else None,
            "alignment": str(p.alignment) if p.alignment is not None else None,
            "text": p.text,
            "runs": runs,
        })

    tables = []
    for ti, t in enumerate(d.tables):
        rows = []
        for row in t.rows:
            rows.append([c.text for c in row.cells])
        tables.append({
            "index": ti,
            "rows": len(t.rows),
            "cols": len(t.columns),
            "data": rows,
        })

    # section geometry, useful for reproducing layout
    sections = []
    for s in d.sections:
        sections.append({
            "page_width_pt": s.page_width.pt if s.page_width else None,
            "page_height_pt": s.page_height.pt if s.page_height else None,
            "left_margin_pt": s.left_margin.pt if s.left_margin else None,
            "right_margin_pt": s.right_margin.pt if s.right_margin else None,
            "top_margin_pt": s.top_margin.pt if s.top_margin else None,
            "bottom_margin_pt": s.bottom_margin.pt if s.bottom_margin else None,
        })

    headers = []
    for s in d.sections:
        headers.append([p.text for p in s.header.paragraphs])

    return {
        "file": path,
        "paragraph_count": len(paragraphs),
        "table_count": len(tables),
        "paragraphs": paragraphs,
        "tables": tables,
        "sections": sections,
        "headers": headers,
        "full_text": "\n".join(p["text"] for p in paragraphs),
    }


def write_docx(path: str, spec: dict) -> dict:
    """spec: {"title": str|None, "blocks": [{"type":"heading|para|table", ...}]}"""
    d = docx.Document()
    title = spec.get("title")
    if title:
        d.add_heading(title, level=0)

    for block in spec.get("blocks", []):
        kind = block.get("type", "para")
        if kind == "heading":
            d.add_heading(block.get("text", ""), level=int(block.get("level", 1)))
        elif kind == "para":
            p = d.add_paragraph()
            run = p.add_run(block.get("text", ""))
            if block.get("bold"):
                run.bold = True
            if block.get("size_pt"):
                run.font.size = Pt(float(block["size_pt"]))
        elif kind == "table":
            data = block.get("data") or []
            if not data:
                continue
            t = d.add_table(rows=len(data), cols=len(data[0]))
            t.style = block.get("style", "Table Grid")
            for ri, row in enumerate(data):
                for ci, val in enumerate(row):
                    t.cell(ri, ci).text = "" if val is None else str(val)
    d.save(path)

    # verify by reading our own output back
    check = docx.Document(path)
    verify = {
        "file": path,
        "paragraph_count": len(check.paragraphs),
        "table_count": len(check.tables),
        "first_paragraphs": [p.text for p in check.paragraphs[:5]],
        "table_dims": [[len(t.rows), len(t.columns)] for t in check.tables],
    }
    return verify


def main(argv=None):
    ap = argparse.ArgumentParser(description="Read or write .docx files.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("read"); p.add_argument("docx"); p.add_argument("--json")
    p = sub.add_parser("write"); p.add_argument("docx")
    p.add_argument("--from-json", help="JSON spec: {title, blocks:[...]}")
    p.add_argument("--text-file", help="read paragraph lines from this text file")
    p.add_argument("--para", action="append", default=[],
                   help="add one paragraph; repeat the flag for several")
    p.add_argument("--title")

    a = ap.parse_args(argv)

    if a.cmd == "read":
        if not os.path.isfile(a.docx):
            raise SystemExit(f"not a file: {a.docx}")
        if os.path.basename(a.docx).startswith("~$"):
            raise SystemExit(f"{a.docx} is a Word lock file (~$ prefix), not a document")
        r = read_docx(a.docx)
        print(f"paragraphs={r['paragraph_count']} tables={r['table_count']} "
              f"chars={len(r['full_text'])}")
        for p in r["paragraphs"][:15]:
            sizes = sorted({run['size_pt'] for run in p['runs'] if run['size_pt']})
            print(f"  [{p['style']}] sz={sizes} {p['text'][:90]!r}")
        for t in r["tables"]:
            print(f"  TABLE {t['index']}: {t['rows']}x{t['cols']}")
        if a.json:
            with open(a.json, "w", encoding="utf-8") as fh:
                json.dump(r, fh, ensure_ascii=False, indent=1)
            print(f"JSON -> {a.json}")
    else:
        if a.from_json:
            spec = json.load(open(a.from_json, encoding="utf-8"))
        else:
            blocks = [{"type": "para", "text": t} for t in a.para]
            if a.text_file:
                with open(a.text_file, encoding="utf-8") as fh:
                    blocks += [{"type": "para", "text": ln}
                               for ln in fh.read().splitlines() if ln.strip()]
            if not blocks and not a.title:
                raise SystemExit("nothing to write: pass --from-json, --para, or --text-file")
            spec = {"title": a.title, "blocks": blocks}
        print(json.dumps(write_docx(a.docx, spec), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
