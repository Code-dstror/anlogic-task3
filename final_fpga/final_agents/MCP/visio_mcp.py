"""Project-local Visio MCP; editable diagrams plus PDF/SVG/PNG exports."""
from __future__ import annotations

import json
import math
from contextlib import contextmanager
from pathlib import Path

import pythoncom
import win32com.client
from mcp.server.mcpserver import MCPServer

ROOT = Path(__file__).resolve().parents[2]
ALLOWED = (ROOT / "work" / "exp", ROOT / "work" / "technical_document")
mcp = MCPServer("technical-report-visio", version="1.0.0")


def workspace_path(value: str, suffix: str | None = None) -> Path:
    path = Path(value)
    path = (ROOT / path).resolve() if not path.is_absolute() else path.resolve()
    if not any(path.is_relative_to(base.resolve()) for base in ALLOWED):
        raise ValueError("Use a path under work/exp or work/technical_document.")
    if suffix and path.suffix.lower() != suffix:
        raise ValueError(f"Expected {suffix} file")
    return path


@contextmanager
def visio():
    pythoncom.CoInitialize()
    app = None
    try:
        app = win32com.client.DispatchEx("Visio.Application")
        app.Visible = False
        app.AlertResponse = 7
        yield app
    finally:
        if app is not None:
            app.Quit()
        pythoncom.CoUninitialize()


def number(value, low=0.0, high=100.0) -> float:
    result = float(value)
    if not math.isfinite(result) or not low <= result <= high:
        raise ValueError(f"Number outside {low}..{high}: {value}")
    return result


def set_cell(shape, name, value):
    shape.CellsU(name).FormulaU = str(value)


def exports(doc, page, target: Path) -> dict:
    outputs = {}
    for ext in ("svg", "png"):
        path = target.with_suffix("." + ext)
        page.Export(str(path))
        outputs[ext] = str(path)
    pdf = target.with_suffix(".pdf")
    doc.ExportAsFixedFormat(1, str(pdf), 1, 0)
    outputs["pdf"] = str(pdf)
    return outputs


@mcp.tool()
def visio_status() -> dict:
    """Check desktop Visio COM availability using a short-lived private instance."""
    with visio() as app:
        return {"version": app.Version, "workspace": str(ROOT),
                "allowed_roots": [str(p) for p in ALLOWED]}


@mcp.tool()
def create_diagram(spec_path: str, output_vsdx: str, overwrite: bool = False) -> dict:
    """Create an editable Visio diagram from a JSON spec, then export PDF/SVG/PNG.

    Spec: width/height in inches; nodes [{id,text,x,y,w,h,fill?,kind?}];
    edges [{from,to,text?}]. x/y are lower-left coordinates, Y increases upward.
    kind is rectangle, ellipse, or text. fill is '#RRGGBB'. Text is literal.
    Existing output files are refused unless overwrite is explicitly true.
    """
    spec_file = workspace_path(spec_path, ".json")
    target = workspace_path(output_vsdx, ".vsdx")
    spec = json.loads(spec_file.read_text(encoding="utf-8-sig"))
    width, height = number(spec["width"], 1, 40), number(spec["height"], 1, 40)
    nodes, edges = spec["nodes"], spec.get("edges", [])
    if not 1 <= len(nodes) <= 150 or len(edges) > 300:
        raise ValueError("Expected 1..150 nodes and at most 300 edges")
    identifiers = [n["id"] for n in nodes]
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("Duplicate node IDs")
    for n in nodes:
        for key in ("x", "y", "w", "h"):
            number(n[key])
        if n["w"] <= 0 or n["h"] <= 0 or n["x"] + n["w"] > width or n["y"] + n["h"] > height:
            raise ValueError("Node exceeds page or has nonpositive size")
        if n.get("kind", "rectangle") not in ("rectangle", "ellipse", "text"):
            raise ValueError("Unsupported node kind")
        color = n.get("fill", "#E8F1FA")
        if len(color) != 7 or not color.startswith("#"):
            raise ValueError("Expected #RRGGBB color")
        int(color[1:], 16)
    for e in edges:
        if e["from"] not in identifiers or e["to"] not in identifiers:
            raise ValueError("Edge references missing node")
    for ext in ("vsdx", "svg", "png", "pdf"):
        if target.with_suffix("." + ext).exists() and not overwrite:
            raise FileExistsError(target.with_suffix("." + ext))
    target.parent.mkdir(parents=True, exist_ok=True)
    with visio() as app:
        doc = app.Documents.Add("")
        page = doc.Pages.Item(1)
        page.Name = "报告框图"
        set_cell(page.PageSheet, "PageWidth", f"{width} in")
        set_cell(page.PageSheet, "PageHeight", f"{height} in")
        shapes = {}
        for n in nodes:
            x, y, w, h = (float(n[k]) for k in ("x", "y", "w", "h"))
            draw = page.DrawOval if n.get("kind") == "ellipse" else page.DrawRectangle
            shape = draw(x, y, x + w, y + h)
            shape.NameU = n["id"]
            shape.Text = n["text"]
            color = n.get("fill", "#E8F1FA")
            rgb = [int(color[k:k + 2], 16) for k in (1, 3, 5)]
            set_cell(shape, "FillForegnd", f"RGB({rgb[0]},{rgb[1]},{rgb[2]})")
            set_cell(shape, "LineColor", "RGB(51,65,85)")
            set_cell(shape, "LineWeight", "0.8 pt")
            set_cell(shape, "Char.Size", "11 pt")
            set_cell(shape, "Para.HorzAlign", "1")
            set_cell(shape, "VerticalAlign", "1")
            if n.get("kind") == "text":
                set_cell(shape, "LinePattern", "0")
                set_cell(shape, "FillPattern", "0")
            shapes[n["id"]] = shape
        for e in edges:
            conn = page.Drop(app.ConnectorToolDataObject, 0, 0)
            conn.CellsU("BeginX").GlueTo(shapes[e["from"]].CellsU("PinX"))
            conn.CellsU("EndX").GlueTo(shapes[e["to"]].CellsU("PinX"))
            set_cell(conn, "EndArrow", "4")
            set_cell(conn, "LineWeight", "0.8 pt")
            set_cell(conn, "Char.Size", "9 pt")
            if e.get("text"):
                conn.Text = e["text"]
        doc.SaveAs(str(target))
        result = exports(doc, page, target)
        result.update(vsdx=str(target), shape_count=page.Shapes.Count, version=app.Version)
        doc.Close()
        return result


@mcp.tool()
def inspect_diagram(vsdx_path: str) -> dict:
    """Read page names and shape text/geometry without changing a saved diagram."""
    path = workspace_path(vsdx_path, ".vsdx")
    with visio() as app:
        doc = app.Documents.OpenEx(str(path), 2 + 64 + 128)
        pages = []
        for page in doc.Pages:
            pages.append({"name": page.Name, "shapes": [
                {"id": s.ID, "name": s.NameU, "text": s.Text,
                 "x": s.CellsU("PinX").ResultIU, "y": s.CellsU("PinY").ResultIU}
                for s in page.Shapes]})
        doc.Close()
        return {"path": str(path), "pages": pages}


if __name__ == "__main__":
    mcp.run(transport="stdio")
