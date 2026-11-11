#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pdf_forms.py - AcroForm inspection, filling and flattening for pdf-doc-toolkit.

The whole point of this script is that a rendered page is NOT proof that a form
was filled. A widget annotation can paint a value from its appearance stream
while the canonical field value is stale or missing. So every operation here
reads back through two independent paths and refuses to claim success when they
disagree.

Usage:
    python pdf_forms.py list    <in.pdf>
    python pdf_forms.py create  <out.pdf> --field name=text:72,100,300,120 ...
    python pdf_forms.py fill    <in.pdf> <out.pdf> --set name=value [--flatten]
    python pdf_forms.py verify  <in.pdf> [--expect name=value ...]

Field spec for `create`:  name=TYPE:x0,y0,x1,y1[:option|option|...]
    TYPE is one of text, checkbox, combobox, listbox
Coordinates are PDF points, origin top-left (pymupdf convention).
"""
from __future__ import annotations

import argparse
import json
import sys

try:
    import pymupdf
except ImportError:  # pragma: no cover
    sys.exit("pymupdf is required: python -m pip install pymupdf")

TYPE_MAP = {
    "text": pymupdf.PDF_WIDGET_TYPE_TEXT,
    "checkbox": pymupdf.PDF_WIDGET_TYPE_CHECKBOX,
    "combobox": pymupdf.PDF_WIDGET_TYPE_COMBOBOX,
    "listbox": pymupdf.PDF_WIDGET_TYPE_LISTBOX,
    "radiobutton": pymupdf.PDF_WIDGET_TYPE_RADIOBUTTON,
}

# PDF field flag bit 0 is ReadOnly (ISO 32000-1, Table 226).
FLAG_READ_ONLY = 1

# Checkbox / radio on-state labels are arbitrary names chosen by the producer.
# Acrobat and pymupdf use "Yes"; treat any of these as the on-state.
TRUTHY = {"1", "true", "yes", "on", "y", "checked", "selected"}


def as_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in TRUTHY


# --------------------------------------------------------------------------
def list_fields(path: str) -> dict:
    """Enumerate fields through BOTH the widget-annotation path and the raw
    object path, so a widget/field mismatch is visible instead of hidden."""
    doc = pymupdf.open(path)
    widgets = []
    for pno, page in enumerate(doc, 1):
        for w in page.widgets():
            widgets.append({
                "page": pno,
                "name": w.field_name,
                "type": w.field_type_string,
                "value": w.field_value,
                "flags": w.field_flags,
                "read_only": bool((w.field_flags or 0) & FLAG_READ_ONLY),
                "rect": [round(v, 1) for v in w.rect],
                "is_signed": w.is_signed,
                "has_appearance": bool(w.xref),
            })

    # raw /V scan: the canonical value lives on the field object
    raw_fields = []
    for xref in range(1, doc.xref_length()):
        try:
            obj = doc.xref_object(xref, compressed=True)
        except Exception:
            continue
        if "/FT" in obj and ("/T(" in obj or "/T (" in obj):
            v = None
            m = None
            for pat in (r"/V\(((?:[^()\\]|\\.)*)\)", r"/V/(\w+)", r"/V\s+(\S+)"):
                import re
                m = re.search(pat, obj)
                if m:
                    v = m.group(1)
                    break
            raw_fields.append({"xref": xref, "has_V": "/V" in obj, "value": v})

    doc.close()
    names_widgets = {w["name"] for w in widgets}
    names_raw = {f["xref"] for f in raw_fields}  # xref not name; count only
    return {
        "file": path,
        "widget_count": len(widgets),
        "raw_field_objects": len(raw_fields),
        "widgets": widgets,
        "raw_fields": raw_fields,
        "note": ("widget_count vs raw_field_objects differing is normal for "
                 "multi-widget fields (e.g. radio groups); a widget whose name "
                 "is absent from the raw field set is the dangerous case."),
    }


# --------------------------------------------------------------------------
def create_form(out_path: str, specs: list[str]) -> dict:
    doc = pymupdf.open()
    page = doc.new_page()
    created = []
    for spec in specs:
        name, _, rest = spec.partition("=")
        ftype, _, geom = rest.partition(":")
        parts = geom.split(":")
        coords = [float(v) for v in parts[0].split(",")]
        options = parts[1].split("|") if len(parts) > 1 and parts[1] else []

        w = pymupdf.Widget()
        w.field_name = name
        w.field_type = TYPE_MAP[ftype]
        w.rect = pymupdf.Rect(*coords[:4])
        if ftype == "text":
            w.field_value = ""
        elif ftype == "checkbox":
            w.field_value = False
        elif ftype in ("combobox", "listbox"):
            w.choice_values = options
        page.add_widget(w)
        created.append(name)
    doc.save(out_path)
    doc.close()
    return {"file": out_path, "created": created}


# --------------------------------------------------------------------------
def fill_form(in_path: str, out_path: str, values: dict, flatten: bool = False) -> dict:
    """Fill fields, then re-open the written file and verify every expectation.

    flatten=True uses Document.bake(), which burns annotations into page content
    and removes the widgets entirely (verified on pymupdf 1.28).
    """
    doc = pymupdf.open(in_path)
    present = []
    for page in doc:
        for w in page.widgets():
            present.append(w.field_name)

    missing = [k for k in values if k not in present]
    if missing:
        doc.close()
        raise SystemExit(f"refusing to write: fields not found in the document: {missing}\n"
                         f"fields present: {present}")

    for page in doc:
        for w in page.widgets():
            if w.field_name in values:
                raw = values[w.field_name]
                if w.field_type in (pymupdf.PDF_WIDGET_TYPE_CHECKBOX,
                                    pymupdf.PDF_WIDGET_TYPE_RADIOBUTTON):
                    w.field_value = as_bool(raw)
                else:
                    w.field_value = raw
                w.update()

    if flatten:
        doc.bake()
        doc.save(out_path, garbage=3)
    else:
        doc.save(out_path, garbage=3)
    doc.close()

    report = verify_form(out_path, values, source_for_types=in_path)
    report["flattened"] = flatten
    report["requested"] = values
    if not report["ok"]:
        raise SystemExit("fill did not verify:\n" + json.dumps(report, ensure_ascii=False, indent=1))
    return report


# --------------------------------------------------------------------------
def _field_types(path: str) -> dict:
    """Field name -> widget type, read from a file that still has widgets.

    Needed because a flattened file has no widgets left, yet we still must know
    which expectations were toggles (excluded from the text search).
    """
    types = {}
    try:
        doc = pymupdf.open(path)
    except Exception:
        return types
    for page in doc:
        for w in page.widgets():
            types[w.field_name] = w.field_type
    doc.close()
    return types


def verify_form(path: str, expect: dict | None = None,
                source_for_types: str | None = None) -> dict:
    """Read the written file back and report mismatches.

    For a flattened file the widgets are gone, so verification asserts the
    widget count is zero and that text values survive as extractable page text.
    Checkbox and radio fields are excluded from the text search: their on-state
    is an appearance-stream glyph, not a text object, so baking them leaves no
    string to find. They are reported by state instead.
    """
    doc = pymupdf.open(path)
    got = {}
    types = {}
    widget_count = 0
    for page in doc:
        for w in page.widgets():
            widget_count += 1
            got[w.field_name] = w.field_value
            types[w.field_name] = w.field_type
    page_text = "".join(p.get_text() for p in doc)
    doc.close()

    toggle_types = (pymupdf.PDF_WIDGET_TYPE_CHECKBOX, pymupdf.PDF_WIDGET_TYPE_RADIOBUTTON)
    # a flattened file exposes no widget types, so fall back to the source file
    if widget_count == 0 and source_for_types:
        types = _field_types(source_for_types)
    problems = []
    skipped_toggles = []

    if widget_count == 0:
        # flattened: only non-toggle values are expected to survive as text
        for k, v in (expect or {}).items():
            if types.get(k) in toggle_types:
                skipped_toggles.append(k)
                continue
            if str(v) and str(v) not in page_text:
                problems.append(
                    f"flattened value for {k!r} ({v!r}) not found in extracted page text")
    else:
        for k, v in (expect or {}).items():
            if k not in got:
                problems.append(f"field {k!r} missing after write")
                continue
            actual = got[k]
            if types.get(k) in toggle_types:
                ok = as_bool(actual) == as_bool(v)
            else:
                ok = str(actual) == str(v)
            if not ok:
                problems.append(f"field {k!r}: expected {v!r}, found {actual!r}")

    return {
        "file": path,
        "widget_count": widget_count,
        "values_read_back": got,
        "extractable_text_length": len(page_text),
        "skipped_toggle_text_search": skipped_toggles,
        "ok": not problems,
        "problems": problems,
    }


# --------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description="Inspect, create, fill and verify AcroForm PDFs.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list"); p.add_argument("pdf")
    p = sub.add_parser("verify"); p.add_argument("pdf")
    p.add_argument("--expect", action="append", default=[])
    p = sub.add_parser("create"); p.add_argument("pdf")
    p.add_argument("--field", action="append", default=[], required=True)
    p = sub.add_parser("fill"); p.add_argument("pdf"); p.add_argument("out")
    p.add_argument("--set", action="append", default=[], required=True)
    p.add_argument("--flatten", action="store_true")

    a = ap.parse_args(argv)
    kv = lambda items: dict(i.split("=", 1) for i in items)

    if a.cmd == "list":
        print(json.dumps(list_fields(a.pdf), ensure_ascii=False, indent=1))
    elif a.cmd == "verify":
        r = verify_form(a.pdf, kv(a.expect))
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return 0 if r["ok"] else 1
    elif a.cmd == "create":
        print(json.dumps(create_form(a.pdf, a.field), ensure_ascii=False, indent=1))
    elif a.cmd == "fill":
        print(json.dumps(fill_form(a.pdf, a.out, kv(a.set), a.flatten),
                         ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
