"""Copy proven fixture bytes into this candidate, recording every adaptation."""
from pathlib import Path
import hashlib
import json

EXT = Path(__file__).resolve().parent
PROJECT = EXT.parents[2]
REPO = PROJECT.parents[1]
SDR = REPO / 'refactor/dual_sdr_lane_r1/src_fpga/simulation/extended_sdr_20261101'
MONO = REPO / 'refactor/dual_lane_s1/src_fpga/simulation/extended_mono'
BASE = '6f9c72762bd88abdc13e3a0ee31fd7dc97e4ccb7'
rows = []
if (EXT / 'PROVENANCE.json').exists():
    raise RuntimeError('Prepared and adapted fixture already exists; do not overwrite retained test inputs')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, relative):
    target = EXT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(source.read_bytes())
    rows.append(dict(path=relative, donor_path=source.relative_to(REPO).as_posix(),
                     donor_sha256=sha(source)))


def change(relative, old, new, count=1):
    path = EXT / relative
    body = path.read_text(encoding='utf-8-sig')
    if body.count(old) != count:
        raise RuntimeError(f'{relative}: expected {count} occurrences of {old!r}, got {body.count(old)}')
    path.write_text(body.replace(old, new), encoding='utf-8', newline='\n')


for relative in ['c1_reference_frozen.py', 'PROTOCOL_REFERENCE.json',
                 'sdr_he/run.py', 'sdr_he/tb.sv', 'sdr_he/oracle.py',
                 'sdr_he/extended_uart_decode.vh', 'sdr_he/runtime_recovery/top_runtime.vh',
                 'sdr_recover/oracle.py']:
    copy(SDR / relative, relative)
for source in sorted((SDR / 'protocol_reference').rglob('*.py')):
    copy(source, 'protocol_reference/' + source.relative_to(SDR / 'protocol_reference').as_posix())
for relative in ['run.py', 'tb.sv', 'oracle.py']:
    copy(MONO / 'hdr_startup' / relative, 'hdr_startup/' + relative)
copy(SDR / 'sdr_he/extended_uart_decode.vh', 'hdr_startup/extended_uart_decode.vh')
copy(SDR / 'sdr_he/runtime_recovery/top_runtime.vh', 'hdr_startup/runtime_recovery/top_runtime.vh')
copy(MONO / 'word_phy_extended.sv', 'word_phy_extended.sv')

for relative in ['sdr_he/run.py', 'hdr_startup/run.py']:
    change(relative, 'ROOT = HERE.parents[1]', "ROOT = HERE.parents[1]\nsys.path.insert(0, str(EXTENDED))\nfrom binding import begin_binding, finish_binding")
    if relative.startswith('hdr'):
        change(relative, "    run = ROOT / 'tmp' / 'extended_20261031' / a.name",
               "    run = ROOT / 'tmp' / 'extended_20261101' / a.name")
    if relative.startswith('sdr'):
        old = "    seal = json.loads((ROOT/'docs/SOURCE_SEAL_20261101.json').read_text())\n    if len(seal['production_inputs'])!=380:raise RuntimeError('Expected380 production inputs')\n    for relative,digest in seal['production_inputs'].items():\n        if sha(ROOT/relative)!=digest:raise RuntimeError('Production6f9c drift '+relative)"
    else:
        old = "    seal = json.loads((ROOT/'docs/SOURCE_SEAL_TIMING_R2_20261031.json').read_text())\n    for relative,digest in seal['production_inputs'].items():\n        if sha(ROOT/relative)!=digest:raise RuntimeError('Production14df drift '+relative)"
    change(relative, old, "    bound = begin_binding(run)\n    seal = bound['seal']")
    if relative.startswith('sdr'):
        change(relative, "ROOT/'docs/SOURCE_SEAL_20261101.json'", "bound['seal_path']")
        change(relative, "        for relative,digest in seal['production_inputs'].items():\n            if sha(ROOT/relative)!=digest:raise RuntimeError('Production6f9c end drift '+relative)\n", '')
    else:
        change(relative, "    paths.update(ROOT / relative for relative in fixture['oracle_inputs'])", "    paths.update(ROOT / relative for relative in fixture['oracle_inputs'])\n    paths.update(ROOT/k for k in seal['production_inputs'])\n    paths.add(bound['seal_path'])")
        change(relative, "'fixed_source_commit':'14df01dcce'", "'fixed_source_commit':'LOCAL_SEALED_TREE_NOT_PUSHED'", 2)
        change(relative, "'expected_hdr_sequence':9", "'expected_hdr_sequence':10", 2)
        change(relative, "'extended_case':'hdr_startup_lane8'", "'extended_case':'hdr_startup_lane8_one_overlap'", 2)
        change(relative, "        if key==\"compile.args\":group.append(ROOT/\"src_fpga/rtl/csi_clock_watchdog.v\")", "        if key==\"compile.args\" and ROOT/\"src_fpga/rtl/csi_clock_watchdog.v\" not in group:group.append(ROOT/\"src_fpga/rtl/csi_clock_watchdog.v\")")
    change(relative, "        'schema': 1, 'mode': a.mode, 'td_root': td.as_posix(),", "        'schema': 1, 'mode': a.mode, 'td_root': td.as_posix(),\n        'production_lock':'LOCAL_SEALED_TREE_NOT_PUSHED',\n        'source_seal_sha256':bound['source_seal_sha256'], 'test_lock_sha256':bound['test_lock_sha256'],\n        'production_inputs':[{'path':(ROOT/k).resolve().as_posix(),'sha256':v} for k,v in seal['production_inputs'].items()],")
    if relative.startswith('sdr'):
        change(relative, "        'production_lock':'"+BASE+"', 'production_inputs':[{'path':(ROOT/k).resolve().as_posix(),'sha256':v} for k,v in seal['production_inputs'].items()],\n", '')
        change(relative, "'fixed_source_commit':'"+BASE+"'", "'fixed_source_commit':'LOCAL_SEALED_TREE_NOT_PUSHED'", 2)
    change(relative, "    finally:\n        q['elapsed_seconds']", "    finally:\n        try:finish_binding(bound, run)\n        except Exception as drift:q.update(status='SOURCE_DRIFT', source_binding_error=str(drift))\n        q['elapsed_seconds']")
    # All fixture and reference inputs are pinned separately from the production seal.
    change(relative, "    paths = {Path(__file__), HERE / 'MAIN_FIXTURE.json', ROOT / 'BASELINE_INPUTS.json'}", "    paths = {Path(__file__), HERE / 'MAIN_FIXTURE.json', ROOT / 'BASELINE_INPUTS.json'}\n    paths.update(ROOT / k for k in bound['lock']['test_inputs'])")

# Both actual oracles validate the same externally pinned lock before accepting traces.
for relative in ['sdr_recover/oracle.py', 'hdr_startup/oracle.py']:
    change(relative, 'ROOT = PROJECT / "verification_reference"', 'ROOT = PROJECT / "verification_reference"\nsys.path.insert(0, str(EXTENDED))\nfrom binding import assert_snapshot_binding')
    old = "    need(sid.get('production_lock')=='"+BASE+"' and len(sid.get('production_inputs',[]))==380,'current380 production seal')\n    for row in sid['production_inputs']:need(sha(row['path'])==row['sha256'],'production seal drift '+row['path'])\n"
    if relative.startswith('sdr'):
        change(relative, old, '    assert_snapshot_binding(sid)\n')
    else:
        change(relative, '    need(q["status"] == expected_status, f"MAIN status {q[\'status\']} != {expected_status}")', '    need(q["status"] == expected_status, f"MAIN status {q[\'status\']} != {expected_status}")\n    assert_snapshot_binding(sid)')

change('sdr_he/oracle.py', "source_commit='"+BASE+"'", "source_commit='LOCAL_SEALED_TREE_NOT_PUSHED'")
change('hdr_startup/tb.sv', '    defparam dut.u_camera.u_config.WAIT_CYCLES=4;', '    defparam dut.u_camera.u_config.WAIT_CYCLES=4;\n    defparam dut.u_camera.SDR_WAKE_CYCLES=4;')
change('hdr_startup/oracle.py', '9 if hdr_startup_recovery else 2', '10 if hdr_startup_recovery else 2', 2)

for row in rows:
    row['sha256'] = sha(EXT / row['path'])
(EXT / 'PROVENANCE.json').write_text(json.dumps(dict(
    baseline_commit=BASE, source_kind='LOCAL_SEALED_TREE_NOT_PUSHED',
    donor_qualification_inherited=False, files=rows), indent=2) + '\n', encoding='utf-8')
print(json.dumps(dict(status='PREPARED', files=len(rows), root=str(EXT))))
