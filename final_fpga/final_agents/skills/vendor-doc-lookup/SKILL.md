---
name: vendor-doc-lookup
description: Locate and verify PH1A90SEG324, TD, IP, board or IMX415 parameters against indexed vendor references. Do not use for general document editing.
---

# Focused vendor lookup

Start with the exact question and target. This repository defaults to PH1A90SEG324-2; also identify the board revision and TD/IP version when they affect the answer.

Read [the vendor index](../../../references/vendor/README.md), then search `../../../references/vendor/catalog.json` for the relevant topic, document ID or filename. Open only the matching manual or source section. Prefer the curated `references/vendor/03_MLK_AFH03_AFC03/` copy; the root MLK package has a navigation README and otherwise remains an intact local original. Do not recursively inventory or search the full package. If the curated copy is absent, report the specific reference gap; reviewed build snapshots remain under `src_fpga/ip/vendor/`.

Distinguish chip capability, package pins, generated IP configuration and actual board wiring. Family manuals still need PH1A90/package/speed conditions checked. A similar package or another development board cannot supply this board's pins, jumpers, voltages or clock limits. Use the board schematic and actual project constraints for connections.

Keep the download label separate from the version printed inside the file. The catalog records known DS901 and UG921 label conflicts, duplicate DS900 sources and the two UG915 editions. Match an IP manual to the generator/configuration in use; the newest document alone does not establish compatibility. Resolve historical source paths through `legacy_path_prefixes` and document `aliases` rather than editing vendor provenance.

TD Release 2026.2 references are under `references/vendor/安路科技_TD_技术文档/2026.2/`;
Codex defaults new tool tasks to TD 6.2.3.210850 at the installation verified in
root `ENVIRONMENT.local.md`, explicitly selected when running TD or its models;
the older root-level manuals still describe the previous installation. Search
catalog `tool_release`, `internal_version`, `source_paths` and SHA256 to choose
an edition. This release also ships SWUG107/SWUG113 labeled TD6.2.2 and unchanged
older PH1A manuals; the install directory name is not their internal version.
The general-note subset under `references/vendor/安路科技_总体_技术文档/` retains
only TN014's PH1 simulation guidance and TN016's PH1A90SEG324 marking section.
Do not import unrelated family/programmer documents or AJE/HXT utilities.
Generic TD manuals may contain other-family chapters; select the PH1A conditions.

Distinguish nominal parameters from measured behavior. For camera rate or exposure, record the
actual MCLK/lane/RAW mode, HMAX/VMAX/SHR units and applicable timing conditions; a table-derived FPS
is not a measured product rate. Public interface/parameter information can be supplied to a black-box
test author without exposing the vendor or DUT implementation.

Locate content in text first. Use `pdf-doc-toolkit` for technical PDFs when extraction or layout needs checking; render the table, timing diagram or pin map and its actual continuation as needed. Pure prose, version metadata and file inventory do not require a full audit.

Report title, file hash, internal version, physical PDF page, applicable conditions and remaining uncertainty. Keep conflicts visible. Never guess pins, reset cycles, register values or ratings from a similar device.

Original references and protected IP stay byte-for-byte. Add only stable, cited conclusions to the directly affected module spec; project process records belong in `docs/`. Document lookup does not authorize builds, programming, deletion or decoding protected IP.
