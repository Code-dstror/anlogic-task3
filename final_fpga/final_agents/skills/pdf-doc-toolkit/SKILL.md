---
name: pdf-doc-toolkit
description: Locate and verify TD and vendor PDF content, including parameter tables, diagrams and exact identifiers. Use the existing helpers for related Word documents, result grids or PDF forms when needed.
---

# TD and vendor technical documents

For this repository, start with [the vendor index](../../../references/vendor/README.md). Identify the actual document edition and target device/IP before interpreting parameters. Read only the relevant pages or section.

New TD manuals are versioned under `references/vendor/安路科技_TD_技术文档/2026.2/`;
general technical notes are under `references/vendor/安路科技_总体_技术文档/`.
Codex's current default tool is TD 6.2.3.210850; resolve its actual installation
from root `ENVIRONMENT.local.md`. Start with its versioned manuals for current
tool questions. An explicitly requested historical/IP provenance lookup still
uses the actual recorded edition. Do not recursively scan the full root MLK
package; use the vendor catalog and curated MLK copy.
Use `catalog.json` to distinguish same-name editions by hash and internal version.
The 2026.08 user guide still calls itself V6.2; the installed release log reports
6.2.3.210850. Release notes physical pages 6–13 describe Release 2026.2. Do not
substitute a directory or download filename for this edition evidence.

## Choose the needed operation

| Request | Helper under `scripts/` |
|---|---|
| Find a section in a long manual | `pdf_nav.py outline --grep` then `section`; use `profile` only when structure or extraction quality is unclear |
| Read a short document or specific pages | `pdf_read.py` |
| Check a technical table, diagram or pin map | Locate in text, then `pdf_render.py --pages ...` and inspect the returned image |
| Inspect spans, coordinates or difficult identifiers | `pdf_inspect.py` and the relevant extraction notes |
| Requested integrity or hidden-text audit | `pdf_audit.py`; this is not the default for ordinary lookup |
| PDF forms, Word or fixed-precision result grids | Read the matching section of `references/operations.md`; use `pdf_forms.py`, `docx_tool.py` or `xlsx_tool.py` |

Version metadata, file inventory and pure prose do not require rendering or full-document audits. For layout-dependent facts, look at the located page and any actual continuation or needed definition; expand to adjacent pages when the answer crosses a boundary. Use `pdf_render.py` so its content-hash cache prevents stale images. Do not render the entire manual by default.

Report the document hash, internal version, physical page and whether the conclusion comes from text or visually checked layout. Keep download labels separate from PDF internal versions; preserve conflicting conditions. Text extraction can corrupt identifiers or column assignment, so verify the original before copying a parameter or command. A blank text layer with visible page content is an extraction gap, not proof the page is empty.

## Runtime and additional detail

Check imports in the interpreter being used. This project's existing Python 3.12 had PyMuPDF 1.28.2 at the 2026-10-04 check; the Codex bundled Python lacked `pymupdf`. When project Python paths disagree, inspect the target machine's `ENVIRONMENT.local.md` and interpreter imports; use workspace dependency discovery for artifact work. Do not assume a universal installed-library list or install tools for a simple lookup.

Read [operations and extraction details](references/operations.md) only for the needed mode or an observed issue. It contains helper recipes, command/identifier extraction pitfalls, forms, Office operations and audit reporting. These are available capabilities, not a requirement to run all of them.

Preserve source originals. For numeric grid or form edits, read back actual saved values using the matching verifier. For ordinary document questions, stop once the specific answer and its applicable evidence are established; no FPGA simulation or TD build follows from reading a document.
