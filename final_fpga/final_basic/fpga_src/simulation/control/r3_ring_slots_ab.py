"""Exact R2 ring miter using the existing real write/query/read/retire bench."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = '14df01dcce'
REL = 'refactor/dual_lane_s1/src_fpga/rtl/jpeg_frame_ring.v'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    a = ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name):
        ap.error('unsafe name')
    run = PROJECT/'tmp/r3_ring_slots_ab'/a.name
    run.mkdir(parents=True, exist_ok=False)
    old = subprocess.check_output(['git', 'show', f'{BASE}:{REL}'], cwd=REPO)
    reference = run/'r3_ring_reference.v'
    reference.write_bytes(old.replace(b'module jpeg_frame_ring #(', b'module r3_ring_reference #(', 1))
    header = re.sub(r'//[^\n]*', '', old.decode().split('    localparam', 1)[0])
    ports = []
    for m in re.finditer(r'\b(input|output)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*(.*?)(?=\binput\b|\boutput\b|$)', header, re.S):
        direction, width, names = m.groups()
        for name in re.findall(r'\b[io]_\w+', names):
            ports.append((direction, width or '', name))
    template = REPO/'src_fpga/simulation/tb_jpeg_frame_ring.v'
    body = template.read_text()
    begin = body.index('    jpeg_frame_ring #(')
    end = body.index(');', begin)+2
    instance = body[begin:end]
    # The legacy independent bench omits this later output. Connect it
    # explicitly without driving it; the miter still compares its real value.
    instance = instance[:-2]+', .o_write_quiescent());'
    body = body[:begin]+instance+body[end:]
    end = begin+len(instance)
    mapping = dict(re.findall(r'\.(\w+)\(([^()]*)\)', instance.split(' dut (', 1)[1]))
    declarations = []
    connections = []
    outputs = []
    for direction, width, name in ports:
        if direction == 'input':
            if name in mapping:
                connections.append(f'.{name}({mapping[name]})')
        else:
            declarations.append(f'    wire {width} reference_{name};')
            connections.append(f'.{name}(reference_{name})')
            outputs.append(name)
    parameter_text = instance.split(' dut (', 1)[0].replace('jpeg_frame_ring', 'r3_ring_reference', 1)
    ref_instance = parameter_text+' reference(\n        '+',\n        '.join(connections)+'\n    );\n'
    # Hierarchical DUT outputs include ports intentionally unconnected in the
    # independent bench. Compare those too, without changing its oracle.
    check = '''
    integer r3_ab_checks=0;
    always @(posedge i_clk) begin
        #1;
        r3_ab_checks=r3_ab_checks+1;
        if ({DUT_OUTPUTS} !== {REF_OUTPUTS})
            $fatal(1,"R3 ring R2 output mismatch cycle=%0d ws=%0d rs=%0d req=%0d",r3_ab_checks,dut.ws,dut.rs,dut.request_state);
    end
'''.replace('DUT_OUTPUTS', ','.join('dut.'+n for n in outputs)).replace('REF_OUTPUTS', ','.join('reference_'+n for n in outputs))
    body = body[:end]+'\n'+'\n'.join(declarations)+'\n'+ref_instance+check+body[end:]
    body = body.replace('$display("RESULT: PASS JPEG two-camera ring official FIFO tails/stalls/ownership/errors/reset");',
        '$display("RESULT: PASS R3 ring slots R2 miter cycles=%0d and independent tails/stalls/query/pin/retire oracle",r3_ab_checks);')
    bench = run/'tb_jpeg_frame_ring.v'
    bench.write_text(body, newline='\n')
    oracle = REPO/'src_fpga/simulation/jpeg_ring_oracle.py'
    subprocess.run([sys.executable, '-B', str(oracle), str(run)], check=True, capture_output=True)
    rtl = PROJECT/'src_fpga/rtl'
    models = [a.td_root/'sim_release/ph1/ph1_logic_dram.v']
    sources = [rtl/'td_sdp_ram.v', rtl/'jpeg_ring_cold_bank.v', rtl/'jpeg_frame_ring.v', reference,
        REPO/'src_fpga/simulation/axi128_stall_memory.v']
    identity = [{'path': str(p), 'sha256': sha(p)} for p in models+sources+[template, oracle, bench, Path(__file__)]]
    result = {'status': 'IN_PROGRESS', 'baseline': BASE, 'ports_compared': len(outputs), 'inputs': identity,
        'modelsim_bin': str(a.modelsim_bin), 'td_root': str(a.td_root),
        'physical': 'NOT_RUN', 'timing': 'NOT_RUN', 'board': 'NOT_RUN'}

    def execute(exe, words, name):
        p = subprocess.run([str(a.modelsim_bin/exe)]+list(map(str, words)), cwd=run,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (run/(name+'.console.log')).write_text(p.stdout)
        if p.returncode:
            raise RuntimeError(p.stdout[-12000:])

    try:
        execute('vmap.exe', ['-c'], 'vmap')
        execute('vlib.exe', ['work'], 'vlib')
        execute('vlog.exe', ['-quiet', '-sv', '-l', 'rtl.log']+models+sources+[bench], 'compile')
        execute('vsim.exe', ['-c', 'work.tb_jpeg_frame_ring', '-l', 'run.log', '-do',
            'onerror {quit -code 1}; run -all; quit -f'], 'run')
        log = (run/'run.log').read_text()
        if 'RESULT: PASS R3 ring slots R2 miter' not in log:
            raise RuntimeError(log[-12000:])
        warnings = []
        for name in ['rtl.log', 'run.log']:
            for number, line in enumerate((run/name).read_text().splitlines(), 1):
                if re.search(r'\*\*\s+(Error|Fatal):', line):
                    raise RuntimeError(name+': '+line)
                if re.search(r'\*\*\s+Warning:', line):
                    allowed = re.search(r'ph1_logic_dram\.v\(221\): \(vopt-2697\).*part-select into .INIT_FILE. is out of bounds', line)
                    if not allowed:
                        raise RuntimeError('unclassified '+name+': '+line)
                    warnings.append({'log': name, 'line': number, 'message': line})
        for item in identity:
            if sha(Path(item['path'])) != item['sha256']:
                raise RuntimeError('source drift '+item['path'])
        result.update(status='PASS', warnings=warnings,
            metrics=[x.strip('# ') for x in log.splitlines() if 'RESULT: PASS' in x])
        print('\n'.join(result['metrics']))
    except Exception as error:
        result.update(status='FAIL', error=str(error))
        raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result, indent=2)+'\n')
    print(run/'RESULTS.json')


if __name__ == '__main__':
    main()
