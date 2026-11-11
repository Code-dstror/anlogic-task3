# PDF operations and extraction details

Specialized TD/vendor-document work for Codex. Everything here runs on libraries that are
already installed — no external binaries, no network, no `pdftoppm`, no
`pdfplumber`, no `pypdf`, no `reportlab`.

## Text finds it. Vision confirms it.

**The default workflow for any non-trivial document question is two-phase:**

```
1. LOCATE    text, cheaply        profile -> outline --grep -> section
                                  (page counts, bookmark search, section text)
2. LOOK      render those pages   pdf_render.py --pages <the pages just found>
                                  then read the PNG(s) with the image tool
3. RECONCILE compare the render against the extracted text;
             fix, or note, the difference
```

Text-first is correct and stays the default: it covers 400 pages for a few
hundred tokens, and it is how you *find* anything. The failure mode is stopping
after phase 1. Text tells you **which pages matter**; looking tells you **what is
actually on them**.

Phase 1 almost always ends with an explicit page number or range — from
`outline --grep`, from `profile`, or from a `section` result. **That page number
is the input to phase 2.** Having a page number and not having looked at it means
the read is not finished.

### What looking gets you that text cannot

Verified on a 4-column parameter table in an Anlogic TCL manual:

| | text extraction | looking at the page |
|---|---|---|
| cell contents | yes | yes |
| column assignment | approximately | yes |
| **merged cells (a `step` spanning 4 rows)** | **no** | **yes** |
| whether a value is one cell or two | guesswork | obvious |
| whether the table continues past the page | infer from proximity | obvious |

That table took six iterations of x-coordinate heuristics to approximate; one
look settled the structure. Conversely, looking at 400 pages to answer a question
about one register is not affordable — which is why phase 1 exists.

### Skip phase 2 only when

- the question is about **bulk text** (summarise, search, cross-reference) with
  no table, diagram or layout involved, or
- the same pages were already visually confirmed earlier in this session, or
- the pages are pure running prose.

### How many pages to look at

**Read the page, plus one page either side.** The neighbours are not padding:
definitions, tables and code examples routinely continue across a page break, and
a single-page look silently truncates them. Concretely, `create_clock` in the
Anlogic TCL guide starts on p44 and its parameter definitions run onto p45 — a
p44-only look would have missed the five worked examples entirely.

```
outline --grep  ->  p44
render          ->  --pages 43,44,45      (one either side)
```

So a located page `N` means rendering `N-1, N, N+1`. Skip a neighbour only when
you already know the content ends before it (e.g. the next bookmark starts on
`N`). Render through `pdf_render.py` so a repeat look costs nothing.

Prefer this over rendering a whole section: 3 pages covers the boundaries, 34
pages does not fit in a useful context.

## Interpreter and dependencies

Check the interpreter actually running the scripts. The project Python 3.12 has
PyMuPDF available; the Codex bundled Python did not have it at the 2026-10-04 check.
Use the workspace dependency discovery tool for artifact tasks and the existing
`fpga-windows-toolchain` skill for this project's interpreter. Confirm imports
before use; do not assume every interpreter has the same packages or install a
new runtime as part of document lookup. Scripts remain under this skill's `scripts/`.

## Scripts

All paths below are relative to this skill's `scripts/` directory.

| Script | Purpose | Cost |
|---|---|---|
| `pdf_nav.py` | **Long manuals**: profile, bookmark outline, section extract | cheap — start here for a manual |
| `pdf_read.py` | **ONE-CALL read**: text + tables + anomaly detection | cheap — start here for a short doc |
| `pdf_inspect.py` | Per-span detail: spans, blocks, tables, images, fonts, outline | moderate |
| `pdf_audit.py` | Integrity proof: hidden text, coverage, render | expensive |
| `pdf_render.py` | Cached page rendering (writes to the workspace `tmp/`) | cheap after first render |
| `pdf_forms.py` | AcroForm list / create / fill / verify / flatten | moderate |
| `docx_tool.py` | Read and write Word documents | cheap |
| `xlsx_tool.py` | Read, write and numerically verify spreadsheets | cheap |

Run them with `python <script> --help` for the full argument list.

---

## Pick the light path first

**Most document questions need a few cheap calls, then one look — not twelve calls
and no look.**

| The user wants | Phase 1 (locate) | Phase 2 (look) |
|---|---|---|
| What a short document says | `pdf_read.py` | the pages carrying the answer |
| What a 100+ page manual says | `pdf_nav.py profile → outline → section` | 1-3 key pages |
| One command/register/parameter | `outline --grep` → `section --tables` | the page the table is on |
| Proof nothing was missed | `pdf_audit.py` | render-dir inspection |
| Font, size, colour, exact coordinates | `pdf_inspect.py --mode spans` | — (machine-only data) |
| Bulk text / search / cross-reference | `pdf_read.py`, `section` | not needed |

Phase 2 is skipped only for pure prose or machine-only data — see *Skip phase 2
only when* above. Otherwise: locate, then look.

### Long manuals: navigate, do not read

Vendor manuals are reference works with a real bookmark tree. A 400-page register
guide is ~700k characters; nobody needs that in context to answer a question
about one register.

```bash
python pdf_nav.py profile manual.pdf          # size, density, image map, furniture
python pdf_nav.py outline manual.pdf --grep "TX_CLK|LANE_PROTOCOL"
python pdf_nav.py section manual.pdf --title TX_CLK_CTRL_0
python pdf_nav.py clean manual.pdf --start 30 --end 32     # no bookmarks? page range
```

`profile` first: it tells you the page count, whether a bookmark tree exists, how
dense the text is, where the images are, and what the running header/footer is.
That single call usually decides the whole approach.

**No bookmarks? The outline is inferred.** When `get_toc()` is empty, `outline`
and `section` fall back to reconstructing headings from font sizes: the size
carrying the most characters is body text, larger sizes rank as heading levels.
Validated against manuals that DO have bookmarks — 90% and 98% recall on two
documents. Force it with `--rebuild` if the embedded bookmarks are wrong.
Detected running headers are excluded, otherwise a heading-sized page header
would appear once per page (measured: 14 phantom entries out of 134).

`section` strips the detected running header/footer and page numbers, so the
output is content only. Header/footer bands are derived per document from its own
layout (`_furniture_bands`), never from a fixed margin constant — measured on a
37-manual corpus the header band ranged 61.9–71.4pt and a fixed 95pt margin
swallowed a register table's column headers.

### Page images: always through the cache

**Reading a page as an image must go through `pdf_render.py`.** It owns the
cache policy so the same page is never rendered twice:

1. ensure a `tmp` directory exists in the workspace (created when missing)
2. create a per-document subdirectory inside it for this render batch
3. serve an existing PNG when the document bytes and dpi are unchanged

```bash
python pdf_render.py manual.pdf --pages 10,42-44 --dpi 150
python pdf_render.py manual.pdf --list          # what is cached
python pdf_render.py manual.pdf --clean         # drop this document's cache
```

Layout: `<workspace>/tmp/pdf-render/<doc-slug>-<content-hash>-<dpi>dpi/`
with `pageNNNN_<dpi>dpi.png` and a `manifest.json`.

The cache key includes a content hash of the source, so **editing the PDF or
changing the dpi re-renders and a stale image can never be served silently.**
Do not render with ad-hoc scripts; if a task needs a page image, call this.

Rendering is the expensive step in context terms too — every page you look at
costs tokens. Render the pages whose layout actually matters.

### JSON contract

`pdf_inspect.py --json` always writes a stable envelope, so consumers never
have to guess the shape:

```json
{ "file": ..., "mode": "spans", "page_filter": null,
  "modes_present": ["spans"], "result": { "spans": [ ... ] } }
```

Access data as `payload["result"]["<mode>"]`. An earlier version wrote a bare
`{mode: value}` mapping, which made `--mode spans` and `--mode all`
indistinguishable to a caller and caused a real downstream crash.

## Workflow: answering a question from a manual

The two-phase loop, end to end. This is the default path.

```bash
# ---- PHASE 1: LOCATE (text, cheap) ----
python pdf_nav.py profile manual.pdf
python pdf_nav.py outline manual.pdf --grep "Syn/Phy|set_param"
#   -> 4.2 Syn/Phy Properties设置  ... p28          <-- the page number you need
python pdf_nav.py section manual.pdf --title "Syn/Phy Properties" --tables

# ---- PHASE 2: LOOK (vision, on those pages only) ----
python pdf_render.py manual.pdf --pages 28,29 --dpi 150
#   -> tmp/pdf-render/.../page0028_150dpi.png
#   then open the PNG with the image tool and READ it

# ---- PHASE 3: RECONCILE ----
#   does the page show anything the text got wrong or omitted?
#   merged cells, spanning headers, footnotes, a table continuing overleaf
```

Worked example — a question about configuring an IP core over Tcl:

| phase | action | result |
|---|---|---|
| 1 | `outline --grep` | `4.2 Syn/Phy Properties设置 ... p28` |
| 1 | `section --tables` | `set_param [-run <r>] <step> <param> <value>`, 表4-1, `syn_ip_flow off/ip` |
| 2 | render p28-29, look | **the render revealed 4 merged `step` cells the text had flattened** |
| 3 | reconcile | text content correct; merge structure only obtainable from the render |

Cost: three cheap text calls plus two page images. Without phase 2 the answer
would have been missing the structure that makes the table readable.

## Workflow: reading a PDF (per-span detail, only when needed)

1. **Orient.** `pdf_inspect.py <file> --mode outline` — page count, encryption,
   producer, geometry. A `Microsoft Office Word` producer means the mojibake
   font trap below applies.

2. **Inventory fonts and sizes.** `--mode spans` — the font/size histogram and
   colour set. This is where you learn the document's typographic system.

3. **Extract what you need.** `--mode text` prose, `--mode tables` grids,
   `--mode blocks` layout-ordered text with coordinates.

4. **Audit before claiming completeness.** `pdf_audit.py <file>` — see below.

5. **Look at the pages you extracted from.** `pdf_render.py --pages ...`, then
   open the PNG. Per-span data is for machine consumption; the render is the
   check that the machine's answer matches the page.

## Workflow: proving an extraction is trustworthy

`pdf_audit.py` answers three independent questions per page:

| Check | Question | How |
|---|---|---|
| Visibility | Is any text present that a human cannot see? | text-trace span classification; the invisible marker is **resolved by a self-test at runtime**, not hardcoded |
| Coverage | Did the extraction silently lose text? | raw content-stream `TJ`/`Tj` counting vs extracted span count |
| Ink | Is there content the text layer does not explain? | image-block and vector-path counts, plus render |

Report flags to the user rather than swallowing them. A page with
`text_chars == 0` and substantial vector or image content is a **scanned page**
and needs OCR — say that instead of returning an empty string.

## Workflow: AcroForm PDFs

The rule that matters: **a rendered page is not proof a form was filled.** A
widget can paint a value from its appearance stream while the canonical field
value is missing or stale. Always read the value back from the written file.

```bash
# see what is there, through two paths (widgets and raw field objects)
python pdf_forms.py list form.pdf

# fill — refuses to write if any requested field is absent
python pdf_forms.py fill form.pdf out.pdf --set name="Zhang Wei" --set agree=true

# flatten (burns annotations into page content, removes widgets)
python pdf_forms.py fill form.pdf flat.pdf --set name="Li Na" --flatten

# independent verification at any later time
python pdf_forms.py verify out.pdf --expect "name=Zhang Wei"
```

`fill` verifies automatically and **exits non-zero** if the written file does not
match. Do not report success from the exit code alone — quote the
`values_read_back` block.

Toggle fields (checkbox/radio) report their on-state as `Yes`/`Off`, not
`true`/`false`, and after flattening they leave **no extractable text** (the mark
is an appearance glyph). `verify` accounts for this; do not "fix" a missing
checkbox by searching the page text for it.

## Workflow: spreadsheets

```bash
# write a numeric grid at fixed precision, bold header
python xlsx_tool.py matrix out.xlsx --from-csv grid.csv --sheet 温度 --decimals 4

# prove the file matches the intended numbers
python xlsx_tool.py verify out.xlsx --from-csv grid.csv --sheet 温度 --decimals 4

# inspect structure without loading values
python xlsx_tool.py dump out.xlsx

# read values (formulas preserved) or cached values (data_only)
python xlsx_tool.py read out.xlsx --sheet 温度 --json sheet.json
```

`verify` exits non-zero on any mismatch and names the offending cell. Use it
whenever the deliverable is a numeric grid — it catches rounding and
precision mistakes that a visual check will not.

`read` uses `data_only=False` so formulas survive. `data_only=True` returns the
**last cached** value, which is `None` for a workbook never opened in Excel.
Choose deliberately.

---

## Pitfalls this skill exists to prevent

These were each hit and confirmed on a real document, not theorised.

### 1. CJK font names arrive as mojibake

Word writes the font's GBK bytes into a Latin-1 string, so `pymupdf` reports
`ABCDEE+ËÎÌå` where the real name is `宋体` (SimSun). Recognise it by a
producer of `Microsoft Office Word` plus font names containing `Ã`-range
letters. `pdf_inspect.py` repairs this automatically via `repair_font_name()`
and returns both `font_raw` and `font`.

### 2. `get_text("dict")` merges spans

Span counts from `"dict"` are lower than the true glyph-run count. Use
`get_text("rawdict")` for per-character ground truth, and
`page.get_texttrace()` when you need per-run font, colour, opacity and
visibility. In one real case the same page reported 190 dict-spans but 237
text-trace runs.

### 3. A regex cannot count text operators

`re.findall(r"\[(.*?)\]\s*TJ")` also matches arrays **nested inside** another
array, badly over-reporting. `pdf_audit.py` walks the stream tracking bracket
depth and string state instead. If you write your own scanner, do the same:
track `[`/`]` depth and skip over `(...)` literals including `\` escapes.

Related trap: `pymupdf` normalises `Tj` into `[] TJ` when it rewrites a content
stream, so an "empty TJ" count derived from a rewritten stream is an artefact of
the library, **not** evidence of lost text. Never report it as a finding.

### 4. Do not hardcode library-internal constants

Whether text-trace `type == 3` means "invisible" is an implementation detail.
`pdf_audit.py` settles it by building a two-span probe PDF (one normal, one
`3 Tr`), reading the trace back, and comparing — then reports the resolved value.
Copy that pattern for any similar internal marker.

### 5. Vector tables are not images

A Word-exported table is usually vector fill rectangles, so
`--mode images` returns 0 while the page is full of "graphics". Use
`--mode tables` (geometry reconstruction) for those. Verify the returned
row/column count against the rendered page before trusting it — reconstruction
can merge or split cells.

### 6. `python-docx` cannot round-trip losslessly

Reading a `.docx` is faithful. **Re-saving** a heavily formatted source may drop
constructs python-docx does not model (some field codes, content controls,
advanced drawing objects). For layout-critical files prefer in-place text edits
or regenerating from source data over load-and-save. State this to the user when
they ask you to "edit" a formatted document.

### 7. Word lock files look like documents

`~$name.docx` files are lock artefacts, not documents. `docx_tool.py read`
rejects them explicitly; do not treat the error as a corrupt file.

### 8. Text extraction is not evidence of layout

For a formula, a fraction, or a nested subscript, the extracted string may be
ambiguous. In one document the difference between `e^{-0.45/C}` and
`e^{-0.45·C}` was only decidable from glyph bounding boxes plus a 600 dpi
render. When structure matters, use coordinates **and** the rendered image, and
say which evidence supports the conclusion.

### 9. Do not double-count images

`page.get_images(full=True)` returns the XObject records; `get_text("dict")`
separately reports displayed image blocks. Reporting both as "images" doubles
the count for every picture. Merge them into one record per image, and report a
display block with no matching XObject separately as inline/decorative.

### 10. Anomaly checks must not fire on normal documents

A check that trips on an ordinary Word export trains the reader to ignore the
whole list. A "coloured empty span" check once produced 237 hits on a clean
document, because the body text colour was not pure black — while the genuinely
odd case was **2** red empty spans. Compare against the document's own text
palette instead of an assumed "normal" colour.

### 11. PowerShell surfaces stderr as an error

Under `pwsh`, anything a script writes to stderr appears as a
`NativeCommandError` and can set a non-zero exit code even when the script
succeeded. Write status messages to **stdout**, and when a command's exit code
matters, check it explicitly rather than inferring failure from the presence of
red text.

### 12. A repeated line is not automatically noise

Detecting a running header by "appears on most pages" deletes a register table's
column header row (`Bit`, `Label`, `R/W`, `Default_value`), which repeats on
every page and is the document's core content. Require BOTH a repeating line AND
a stable position inside the outer margin band, and derive that band from the
document rather than assuming it. Verified on 37 manuals: zero content leaks.

### 13. Group before you filter

A footer such as `UG1318_1.1   www.anlogic.com   22` appears on every page, but
each variant is a unique string because the page number changes. Applying a
per-string frequency threshold first discards every variant, and any later
"family" logic then has nothing to group. Mask the trailing digits into a family
key and compute coverage per family, then filter.

### 14. Check classification order for interacting rules

A line-number classifier ran in the wrong order once: `2025.03` matched the
"trailing digits" mask, became `#`, and could then never be recognised as a
date. When two rules can both match, decide which one owns the input first and
make that explicit in the code and its comment.

### 15. Do not rewrite UTF-8 source with PowerShell string operators

`Get-Content -Raw` + `-replace` + `Set-Content` mangled CJK punctuation in a
script (`"。", "；", "，"` became `"銆?, "锛?`), producing a syntax error that
only surfaced on the next run. Use the dedicated file-edit tool for source
edits, and after any bulk rewrite, verify with `py_compile` plus a scan for
U+FFFD.

### 16. `find_tables().extract()` corrupts identifiers

On a Tcl command reference, the parameter named `qor_monitor` comes out of
`table.extract()` as `'qor monitor\n_'` — the underscore is split onto its own
line and the name is silently wrong. For a command or signal reference that is a
correctness bug, not a cosmetic one. `find_tables()` is right about the
**geometry**; take the **text** from `rawdict` characters inside each cell bbox.
`extract_table_text()` in `pdf_nav.py` does exactly this.

Also note: both that helper and the whitespace rebuilder are *worse* than the
raw text layer at preserving names, so do not "clean up" cell text with a
generic whitespace collapse before checking it against the source.

### 17. Re-check a claim before building on it

A "find_tables() reports 0 tables for this document" claim was made from memory
of a *different* file and then drove six iterations of unnecessary heuristics.
The function had actually detected the tables correctly all along. Verify the
premise with a one-line command before designing around it.

### 18. Symbol fonts arrive as private-use characters

Anlogic's bulleted parameter lists use Wingdings: the bullet extracts as
`U+F09F`, which renders as nothing useful and is invisible in a read. Five list
markers vanished from a `create_clock` parameter list this way. Map known symbol
glyphs to real Unicode and strip any remaining private-use characters —
`normalise_symbols()` does this inside `strip_furniture()`.

### 19. A wrapped source line silently breaks code

A long command wraps mid-token in the text layer:

```
create_clock -name clk_25m -period 40.000 ... [get_ports {clk_25
m}]
```

`clk_25m` is now split, and nothing marks it — a reader who copies the command
gets a syntax error. Indentation is unavailable as a signal (extracted text has
no x-coordinates) but **delimiter balance** identifies it reliably: a short line
that closes what the previous line left open is a wrap, joined with no
separator. `rejoin_wrapped_code()` implements this and is applied by
`strip_furniture()`; verified to join the broken example while leaving complete
commands alone.

---

## Reporting rules

- **Finish the two-phase loop.** Locating content in text and never looking at
  the page is an incomplete read. If phase 1 produced a page number, phase 2 is
  a render of that page.
- **Match the depth of the work to the ask.** A "what does this say" request
  gets a read, not an audit. A "find command X in a 400-page manual" request
  gets an outline grep, one section, and one look — not a full extraction.
- When you state a fact about a document, name the evidence: extraction, audit
  counts, coordinates, or the rendered image.
- Never claim a document was read in full unless `pdf_audit.py` reports zero
  flags **and** you inspected the pages that carry the content in question.
- Report audit flags to the user even when they do not change the answer.
- Numeric deliverables: run the `verify` subcommand and show its output.
- If a tool of your own throws or returns a nonsense number, fix the tool and
  say so — do not quietly work around it and leave the defect in place.
- Never render a page image outside `pdf_render.py`; bypassing it breaks the
  cache and can serve a stale render.
