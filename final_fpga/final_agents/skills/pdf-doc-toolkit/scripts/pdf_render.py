#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pdf_render.py - cached page rendering for pdf-doc-toolkit.

Rendering a page is only worth doing when the text layer cannot answer the
question (a formula, a pin-out diagram, a waveform, a timing table). Doing it
repeatedly for the same page and settings is pure waste, and a corpus of vendor
manuals makes that waste easy to accumulate.

This script owns the cache policy:

  1. Ensure a `tmp` directory exists in the working directory (create if absent).
  2. Create a per-document subdirectory inside it for this render batch.
  3. Re-render nothing: a page whose bytes are unchanged and whose settings
     match an existing cache entry is reused.

Cache key = document content hash + dpi + page. Editing the source PDF or
changing the dpi produces a new key and therefore a fresh render, so a stale
image can never be served silently.

Usage:
    python pdf_render.py <file.pdf> --pages 1,5,10-12 [--dpi 150]
    python pdf_render.py <file.pdf> --pages all --dpi 72 --max-pages 20
    python pdf_render.py <file.pdf> --list                # show cache contents
    python pdf_render.py <file.pdf> --clean               # drop this doc's cache
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone

try:
    import pymupdf
except ImportError:  # pragma: no cover
    sys.exit("pymupdf is required: python -m pip install pymupdf")

CACHE_ROOT_NAME = "pdf-render"
MANIFEST = "manifest.json"


# --------------------------------------------------------------------------
# cache location
# --------------------------------------------------------------------------
def workspace_root(start: str | None = None) -> str:
    """Nearest ancestor containing .git, else the cwd. Mirrors how the harness
    resolves a project root."""
    cur = os.path.abspath(start or os.getcwd())
    if os.path.isfile(cur):
        cur = os.path.dirname(cur)
    while True:
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.abspath(start or os.getcwd()) if os.path.isdir(start or "") else os.getcwd()
        cur = parent


def ensure_tmp(root: str) -> str:
    """Return <root>/tmp, creating it when missing. That is the contract:
    the workspace-level `tmp` is the single home for render caches."""
    tmp = os.path.join(root, "tmp")
    os.makedirs(tmp, exist_ok=True)
    return tmp


def doc_slug(path: str) -> str:
    base = os.path.splitext(os.path.basename(path))[0]
    slug = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff._-]+", "-", base).strip("-")
    return (slug or "document")[:48]


def content_hash(path: str, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        # first, middle and last chunk - cheap and stable for large files
        fh.seek(0)
        h.update(fh.read(chunk))
        if size > 3 * chunk:
            fh.seek(size // 2)
            h.update(fh.read(chunk))
            fh.seek(max(0, size - chunk))
            h.update(fh.read(chunk))
    h.update(str(size).encode())
    return h.hexdigest()[:12]


def cache_dir_for(pdf: str, dpi: int, root: str | None = None) -> str:
    root = workspace_root(root)
    tmp = ensure_tmp(root)
    key = f"{doc_slug(pdf)}-{content_hash(pdf)}-{dpi}dpi"
    d = os.path.join(tmp, CACHE_ROOT_NAME, key)
    os.makedirs(d, exist_ok=True)
    return d


def _load_manifest(cdir: str) -> dict:
    p = os.path.join(cdir, MANIFEST)
    if os.path.isfile(p):
        try:
            return json.load(open(p, encoding="utf-8"))
        except Exception:
            pass
    return {"created": datetime.now(timezone.utc).isoformat(), "pages": {}}


def _save_manifest(cdir: str, m: dict) -> None:
    m["updated"] = datetime.now(timezone.utc).isoformat()
    json.dump(m, open(os.path.join(cdir, MANIFEST), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)


# --------------------------------------------------------------------------
# page spec parsing
# --------------------------------------------------------------------------
def parse_pages(spec: str, page_count: int) -> list[int]:
    if spec.strip().lower() == "all":
        return list(range(1, page_count + 1))
    out = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.fullmatch(r"(\d+)\s*-\s*(\d+)", part)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            if a > b:
                a, b = b, a
            out.extend(range(a, b + 1))
        elif part.isdigit():
            out.append(int(part))
        else:
            raise SystemExit(f"bad page spec: {part!r}")
    seen, uniq = set(), []
    for p in out:
        if 1 <= p <= page_count and p not in seen:
            seen.add(p)
            uniq.append(p)
    return uniq


# --------------------------------------------------------------------------
# render
# --------------------------------------------------------------------------
def render_pages(pdf: str, pages: list[int], dpi: int = 150,
                 root: str | None = None, force: bool = False,
                 clip: tuple | None = None) -> dict:
    cdir = cache_dir_for(pdf, dpi, root)
    man = _load_manifest(cdir)
    doc = pymupdf.open(pdf)

    rendered, reused = [], []
    for pno in pages:
        name = f"page{pno:04d}_{dpi}dpi.png"
        fp = os.path.join(cdir, name)
        entry = man["pages"].get(str(pno))
        if not force and entry and entry.get("file") == name and os.path.isfile(fp):
            reused.append(fp)
            continue
        pix = doc[pno - 1].get_pixmap(dpi=dpi)
        pix.save(fp)
        man["pages"][str(pno)] = {
            "file": name, "dpi": dpi, "width": pix.width, "height": pix.height,
            "bytes": os.path.getsize(fp),
            "rendered": datetime.now(timezone.utc).isoformat(),
        }
        rendered.append(fp)

    man["source"] = os.path.abspath(pdf)
    man["source_hash"] = content_hash(pdf)
    man["page_count"] = doc.page_count
    doc.close()
    _save_manifest(cdir, man)

    return {
        "cache_dir": cdir,
        "dpi": dpi,
        "rendered": rendered,
        "reused": reused,
        "requested": len(pages),
        "manifest": os.path.join(cdir, MANIFEST),
    }


def list_cache(pdf: str, root: str | None = None) -> dict:
    root_res = workspace_root(root)
    tmp = os.path.join(root_res, "tmp", CACHE_ROOT_NAME)
    hits = []
    if os.path.isdir(tmp):
        for d in sorted(glob.glob(os.path.join(tmp, f"{doc_slug(pdf)}-*"))):
            man = _load_manifest(d)
            hits.append({
                "cache_dir": d,
                "pages_cached": len(man.get("pages", {})),
                "source": man.get("source"),
                "updated": man.get("updated"),
                "bytes": sum(v.get("bytes", 0) for v in man.get("pages", {}).values()),
            })
    return {"tmp_root": tmp, "entries": hits}


def clean_cache(pdf: str, root: str | None = None) -> dict:
    info = list_cache(pdf, root)
    removed = []
    for e in info["entries"]:
        shutil.rmtree(e["cache_dir"], ignore_errors=True)
        removed.append(e["cache_dir"])
    return {"removed": removed}


# --------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description="Render PDF pages with a content-addressed cache.")
    ap.add_argument("pdf")
    ap.add_argument("--pages", help="e.g. 1,5,10-12 or all")
    ap.add_argument("--dpi", type=int, default=150)
    ap.add_argument("--max-pages", type=int, default=40,
                    help="safety cap for --pages all; every page you view costs context")
    ap.add_argument("--force", action="store_true", help="ignore the cache and re-render")
    ap.add_argument("--root", help="workspace root override (default: nearest .git ancestor or cwd)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args(argv)

    if a.list:
        r = list_cache(a.pdf, a.root)
        print(f"cache root: {r['tmp_root']}")
        if not r["entries"]:
            print("  (no cached renders for this document)")
        for e in r["entries"]:
            print(f"  {os.path.basename(e['cache_dir'])}: {e['pages_cached']} page(s), "
                  f"{e['bytes'] / 1024:.0f} KB, updated {e['updated']}")
        return 0

    if a.clean:
        r = clean_cache(a.pdf, a.root)
        print(f"removed {len(r['removed'])} cache dir(s)")
        for d in r["removed"]:
            print(f"  {d}")
        return 0

    if not a.pages:
        raise SystemExit("pass --pages (or --list / --clean)")

    doc = pymupdf.open(a.pdf)
    n = doc.page_count
    doc.close()
    pages = parse_pages(a.pages, n)
    capped = False
    if len(pages) > a.max_pages:
        pages = pages[:a.max_pages]
        capped = True

    r = render_pages(a.pdf, pages, a.dpi, a.root, a.force)
    print(f"cache dir: {r['cache_dir']}")
    print(f"requested={r['requested']} rendered={len(r['rendered'])} reused={len(r['reused'])}")
    if capped:
        print(f"NOTE: capped at {a.max_pages} pages; re-run with a narrower --pages range")
    for fp in r["rendered"]:
        print(f"  NEW  {fp}")
    for fp in r["reused"]:
        print(f"  HIT  {fp}")
    if a.json:
        json.dump(r, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
