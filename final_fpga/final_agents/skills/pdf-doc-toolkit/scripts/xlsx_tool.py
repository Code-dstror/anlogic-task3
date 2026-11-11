#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""xlsx_tool.py - read, write and verify spreadsheets for pdf-doc-toolkit.

Designed around a recurring requirement in numeric work: produce a grid of
results at a fixed decimal precision, keep a header row/column, and be able to
prove afterwards that what landed in the file is what was computed.

Usage:
    python xlsx_tool.py read    <file.xlsx> [--sheet NAME] [--json OUT.json]
    python xlsx_tool.py dump    <file.xlsx>
    python xlsx_tool.py matrix  <out.xlsx> --from-csv IN.csv --sheet NAME \
                                [--decimals 4] [--header-row]
    python xlsx_tool.py verify  <file.xlsx> --from-csv IN.csv [--sheet NAME] \
                                [--decimals 4] [--tolerance 5e-5]

`matrix` writes a 2-D array; `verify` re-opens the written file and compares it
against the source array so a precision or rounding mistake cannot pass silently.

Note on loading: openpyxl load_workbook(data_only=False) preserves formulas and
formatting. data_only=True returns the last cached values instead, which are
absent for files never opened in Excel - choose deliberately.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys

try:
    import openpyxl
except ImportError:  # pragma: no cover
    sys.exit("openpyxl is required: python -m pip install openpyxl")


# --------------------------------------------------------------------------
def _cell_value(v):
    if v is None:
        return None
    if isinstance(v, float):
        if math.isnan(v):
            return None
        return v
    return v


def read_sheet(path: str, sheet: str | None = None, data_only: bool = False) -> dict:
    wb = openpyxl.load_workbook(path, data_only=data_only)
    names = wb.sheetnames
    ws = wb[sheet] if sheet else wb[names[0]]

    rows = []
    for row in ws.iter_rows():
        rows.append([_cell_value(c.value) for c in row])

    formulas = []
    for row in ws.iter_rows():
        for c in row:
            if isinstance(c.value, str) and c.value.startswith("="):
                formulas.append({"cell": c.coordinate, "formula": c.value})

    wb.close()
    return {
        "file": path,
        "sheets": names,
        "sheet": ws.title,
        "max_row": ws.max_row,
        "max_column": ws.max_column,
        "rows": rows,
        "formulas": formulas,
    }


def dump_workbook(path: str) -> dict:
    wb = openpyxl.load_workbook(path, data_only=False)
    out = []
    for ws in wb.worksheets:
        merged = [str(r) for r in ws.merged_cells.ranges]
        out.append({
            "sheet": ws.title,
            "dims": f"{ws.max_row}x{ws.max_column}",
            "merged": merged,
            "charts": len(getattr(ws, "_charts", [])),
            "images": len(getattr(ws, "_images", [])),
            "freeze_panes": ws.freeze_panes,
        })
    wb.close()
    return {"file": path, "sheets": out}


# --------------------------------------------------------------------------
def _load_csv(path: str):
    grid = []
    with open(path, newline="", encoding="utf-8-sig") as fh:
        for row in csv.reader(fh):
            out = []
            for cell in row:
                cell = cell.strip()
                if cell == "":
                    out.append(None)
                    continue
                try:
                    out.append(int(cell))
                except ValueError:
                    try:
                        out.append(float(cell))
                    except ValueError:
                        out.append(cell)
            grid.append(out)
    return grid


def write_matrix(out_path: str, grid, sheet: str = "Sheet1",
                 decimals: int | None = None, bold_header: bool = True) -> dict:
    from openpyxl.styles import Font

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = sheet

    fmt = None if decimals is None else "0." + "0" * int(decimals)

    for ri, row in enumerate(grid, start=1):
        for ci, val in enumerate(row, start=1):
            cell = ws.cell(row=ri, column=ci)
            if isinstance(val, float) and decimals is not None:
                cell.value = round(val, int(decimals))
                cell.number_format = fmt
            else:
                cell.value = val
            if ri == 1 and bold_header:
                cell.font = Font(bold=True)

    wb.save(out_path)
    wb.close()
    return {"file": out_path, "sheet": sheet, "rows": len(grid),
            "cols": max((len(r) for r in grid), default=0),
            "decimals": decimals}


# --------------------------------------------------------------------------
def _num_equal(a, b, tol: float) -> bool:
    if a is None and b is None:
        return True
    if a is None or b is None:
        return False
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= tol
    return str(a) == str(b)


def verify_matrix(path: str, grid, sheet: str | None = None,
                  decimals: int | None = None, tolerance: float = 5e-5) -> dict:
    """Compare a written workbook against the intended grid, cell by cell."""
    got = read_sheet(path, sheet)
    rows = got["rows"]

    # truncate the workbook view to the intended grid size (trailing blanks are noise)
    n_rows = len(grid)
    n_cols = max((len(r) for r in grid), default=0)
    if decimals is not None:
        grid = [[round(v, int(decimals)) if isinstance(v, float) else v for v in row]
                for row in grid]

    mismatches = []
    for ri in range(n_rows):
        for ci in range(n_cols):
            want = grid[ri][ci] if ci < len(grid[ri]) else None
            have = rows[ri][ci] if ri < len(rows) and ci < len(rows[ri]) else None
            if not _num_equal(want, have, tolerance):
                mismatches.append({
                    "cell": f"r{ri + 1}c{ci + 1}",
                    "expected": want, "found": have,
                })

    return {
        "file": path,
        "sheet": got["sheet"],
        "compared_rows": n_rows,
        "compared_cols": n_cols,
        "mismatch_count": len(mismatches),
        "mismatches": mismatches[:40],
        "ok": not mismatches,
    }


# --------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description="Read, write and verify .xlsx files.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("read"); p.add_argument("xlsx"); p.add_argument("--sheet"); p.add_argument("--json")
    p = sub.add_parser("dump"); p.add_argument("xlsx")
    p = sub.add_parser("matrix"); p.add_argument("xlsx"); p.add_argument("--from-csv", required=True)
    p.add_argument("--sheet", default="Sheet1"); p.add_argument("--decimals", type=int)
    p = sub.add_parser("verify"); p.add_argument("xlsx"); p.add_argument("--from-csv", required=True)
    p.add_argument("--sheet"); p.add_argument("--decimals", type=int)
    p.add_argument("--tolerance", type=float, default=5e-5)

    a = ap.parse_args(argv)

    if a.cmd == "read":
        r = read_sheet(a.xlsx, a.sheet)
        print(f"sheets={r['sheets']} active={r['sheet']!r} dims={r['max_row']}x{r['max_column']}")
        for row in r["rows"][:12]:
            print("  ", row[:10])
        if r["formulas"]:
            print(f"  formulas: {r['formulas'][:10]}")
        if a.json:
            with open(a.json, "w", encoding="utf-8") as fh:
                json.dump(r, fh, ensure_ascii=False, indent=1, default=str)
            print(f"JSON -> {a.json}")
    elif a.cmd == "dump":
        print(json.dumps(dump_workbook(a.xlsx), ensure_ascii=False, indent=1))
    elif a.cmd == "matrix":
        grid = _load_csv(a.from_csv)
        print(json.dumps(write_matrix(a.xlsx, grid, a.sheet, a.decimals),
                         ensure_ascii=False, indent=1))
    elif a.cmd == "verify":
        grid = _load_csv(a.from_csv)
        r = verify_matrix(a.xlsx, grid, a.sheet, a.decimals, a.tolerance)
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return 0 if r["ok"] else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
