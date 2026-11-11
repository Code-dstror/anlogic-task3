"""Materialize the candidate-local TOP cold/mono/dual short fixture once."""
from pathlib import Path
import hashlib
import json

EXT = Path(__file__).resolve().parent
HERE = EXT.parent
CASE = EXT / 'short'
CASE.mkdir(exist_ok=False)
rows = []


def adapted(name, body):
    source = HERE / name
    target = CASE / name.replace('run_main.py', 'run.py')
    target.write_text(body, encoding='utf-8', newline='\n')
    rows.append(dict(donor_path=source.as_posix(), donor_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                     path=target.relative_to(EXT).as_posix(), sha256=hashlib.sha256(target.read_bytes()).hexdigest()))


runner = (HERE / 'run_main.py').read_text(encoding='utf-8-sig')
runner = runner.replace('HERE = Path(__file__).resolve().parent', 'CASE = Path(__file__).resolve().parent\nHERE = CASE.parents[1]')
runner = runner.replace("ROOT / 'tmp' / 'main' / a.name", "ROOT / 'tmp' / 'merge_short_20261101' / a.name")
needle = '        for p in group:\n'
assert runner.count(needle) == 1
runner = runner.replace(needle, "        group = [CASE/'tb_dual_imx415.sv' if p.name=='tb_dual_imx415.sv' else p for p in group]\n        if key=='compile.args' and ROOT/'src_fpga/rtl/hdr_csi_boundary_adapter.v' not in group:\n            group.append(ROOT/'src_fpga/rtl/hdr_csi_boundary_adapter.v')\n" + needle)
runner = runner.replace('stderr=subprocess.STDOUT, text=True, errors=\'replace\')', "stderr=subprocess.STDOUT, text=True, errors='replace', creationflags=subprocess.CREATE_NO_WINDOW)")
adapted('run_main.py', runner)
tb = (HERE / 'tb_dual_imx415.sv').read_text(encoding='utf-8-sig')
tb = tb.replace('    defparam dut.u_camera.u_config.WAIT_CYCLES=4;', '    defparam dut.u_camera.u_config.WAIT_CYCLES=4;\n    defparam dut.u_camera.SDR_WAKE_CYCLES=4;\n    defparam dut.u_camera1.SDR_WAKE_CYCLES=4;')
adapted('tb_dual_imx415.sv', tb)
(CASE / 'PROVENANCE.json').write_text(json.dumps(dict(files=rows, changes=['Explicit new HDR adapter source', 'Run-local TB and accelerated SDR wake delay only', 'Hidden ModelSim children']), indent=2)+'\n', encoding='utf-8')
print('PREPARED_CURRENT_TOP_SHORT')
