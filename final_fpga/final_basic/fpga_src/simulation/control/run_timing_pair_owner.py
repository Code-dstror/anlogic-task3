"""Compare DFI owner timing arithmetic against fixed f3 RTL and official RAM."""
import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path


BASE = 'f3fc9adb5462ea91b50886be6dfa23449eec4d74'
BASE_PATH = 'refactor/hdr_jpeg/src_fpga/rtl/hdr_pair_bank_owner_dual.v'
HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--slot-order', action='store_true',
                        help='compare the isolated two-bank ordering candidate to this project')
    parser.add_argument('--camera-id', type=int, choices=(0, 1), default=0)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('unsafe run name')
    run = PROJECT/'tmp/pair_owner'/args.name
    run.mkdir(parents=True, exist_ok=False)
    rtl, ip = PROJECT/'src_fpga/rtl', PROJECT/'src_fpga/ip'
    source = rtl/'hdr_pair_bank_owner_dual.v'
    template = HERE/'tb_timing_pair_owner.sv'
    manifest = json.loads((PROJECT/'SOURCE_MANIFEST.json').read_text())
    includes = [PROJECT/item for item in manifest['include_dirs']]
    headers = [directory/'pcie_protocol_v1.vh' for directory in includes
               if (directory/'pcie_protocol_v1.vh').is_file()]
    if len(headers) != 1:
        raise RuntimeError('expected one production protocol header')
    base_identity = {'commit': BASE, 'path': BASE_PATH}
    extra_inputs = []
    if args.slot_order:
        relative = source.relative_to(PROJECT)
        frozen = PROJECT/'verification_reference/raw_85fb8a2c'/source.name
        integrated_slot_order = PROJECT/'experiments/hdr_pair_time/baseline_owner.v'
        baseline = frozen.read_bytes()
        base_identity = {'commit': '85fb8a2c', 'path': relative.as_posix(), 'camera': args.camera_id}
        patch = PROJECT / 'experiments/hdr_slot_order/owner.patch'
        extra_inputs = [frozen, integrated_slot_order, patch]
        source = run / relative
        source.parent.mkdir(parents=True)
        source.write_bytes(baseline.replace(b'\r\n', b'\n'))
        # Do not let Git discover and edit the containing production checkout.
        subprocess.run(['git', 'apply', '--no-index', str(patch)], cwd=run, check=True,
                       env={**os.environ, 'GIT_CEILING_DIRECTORIES': str(run.parent)})
        if source.read_text() != integrated_slot_order.read_text():
            raise RuntimeError('slot-order candidate differs from its frozen integrated owner')
    else:
        if args.camera_id:
            parser.error('--camera-id 1 requires --slot-order')
        baseline = subprocess.check_output(['git','show',f'{BASE}:{BASE_PATH}'], cwd=REPO)
    reference = run/'timing_pair_owner_reference.v'
    reference.write_bytes(baseline.replace(b'module hdr_pair_bank_owner_dual #(',
                                          b'module timing_pair_owner_reference #(', 1))
    header = re.sub(r'//[^\n]*', '', baseline.decode().split('    localparam',1)[0])
    ports = []
    for match in re.finditer(r'\b(input|output)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*([^\n]*?)(?=\binput\b|\boutput\b|$)', header, re.M):
        direction, width, names = match.groups()
        for name in re.findall(r'\b[ismo]_\w+', names):
            ports.append((direction,width or '',name))
    if len(ports)!=55 or len(set(name for _,_,name in ports))!=len(ports):
        raise RuntimeError('unexpected baseline interface '+str(ports))
    inputs = [(width,name) for direction,width,name in ports if direction=='input']
    outputs = [(width,name) for direction,width,name in ports if direction=='output']
    declarations = [f'    reg {width} {name};' for width,name in inputs if name!='i_clk']
    declarations += [f'    wire {width} {prefix}_{name};' for width,name in outputs
                     for prefix in ['dut','reference']]
    bench = template.read_text().replace('__DECLARATIONS__','\n'.join(declarations))
    if args.slot_order:
        bench = bench.replace('.WIDTH(24),.HEIGHT(3)', f'.WIDTH(24),.HEIGHT(3),.CAMERA_ID({args.camera_id})')
        bench = bench.replace('s_frame=0;i_begin_member=member;',
                              f"s_frame=0;s_frame[4]=1'b{args.camera_id};i_begin_member=member;")
    for prefix in ['dut','reference']:
        connections = [f'        .{name}({name if direction=="input" else prefix+"_"+name})'
                       for direction,_,name in ports]
        bench=bench.replace('__'+prefix.upper()+'_PORTS__',',\n'.join(connections))
        bench=bench.replace('__OUTPUTS_'+prefix.upper()+'__',','.join(prefix+'_'+name for _,name in outputs))
    bench=bench.replace('__INITIALIZE__','\n'.join(f'            {name}=0;' for _,name in inputs if name!='i_clk'))
    test = run/'tb_timing_pair_owner.sv'
    test.write_text(bench, newline='\n')
    models = [args.td_root/'sim_release'/name for name in [
        'common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_phy_eram.v']]
    sources = [args.td_root/'sim_release/ph1/ph1_phy_gsr.v',
        ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        rtl/'td_sdp_ram40.v',rtl/'hdr_pair_directory.v',source,reference]
    inputs = models+sources+[test,template,Path(__file__)]+headers+extra_inputs
    identity=[{'path':str(path),'sha256':sha(path)} for path in inputs]
    result={'status':'IN_PROGRESS','baseline':{**base_identity,
        'sha256':hashlib.sha256(baseline).hexdigest()},'inputs':identity,
        'modelsim_bin':str(args.modelsim_bin),'td_root':str(args.td_root),
        'latency_change_cycles':0,'new_state_bits':int(args.slot_order),'synthesis':'NOT_RUN',
        'place_route':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN'}

    def command(name, exe, words):
        argv=[str(args.modelsim_bin/exe)]+list(map(str,words))
        completed=subprocess.run(argv,cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                                 text=True,errors='replace')
        (run/(name+'.console.log')).write_text(completed.stdout)
        if completed.returncode:
            raise RuntimeError(exe+' failed: '+completed.stdout[-12000:])

    try:
        command('vmap','vmap.exe',['-c'])
        command('work','vlib.exe',['work'])
        command('ph1','vlib.exe',['ph1'])
        command('models','vlog.exe',['-quiet','-work','ph1','-l','models.log']+models)
        inc=['+incdir+'+str(path) for path in includes]
        command('rtl','vlog.exe',['-quiet','+define+PH1','-l','rtl.log']+inc+sources)
        command('bench','vlog.exe',['-quiet','-sv','-l','bench.log']+inc+[test])
        command('run','vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl',
            'work.tb_timing_pair_owner','-l','run.log','-do','onerror {quit -code 1}; run -all; quit -f'])
        log=(run/'run.log').read_text(errors='replace')
        metrics=[line.strip('# ') for line in log.splitlines() if 'RESULT: PASS timing_pair_owner' in line]
        if len(metrics)!=1:
            raise RuntimeError('missing PASS: '+log[-12000:])
        warnings=[]
        for path in run.glob('*.log'):
            if path.name.endswith('.console.log'):
                continue
            lines=path.read_text(errors='replace').splitlines()
            for index,line in enumerate(lines):
                if re.search(r'\*\* (Error|Fatal):',line):
                    raise RuntimeError(path.name+': '+line)
                if '** Warning:' not in line:
                    continue
                ecc_compile=re.search(r'ram40_sdp_fixed.v\(69\).*ecc_[sd]biterrinj',line)
                ecc_runtime=(re.search(r"\(vsim-3015\).*port 'ecc_[sd]biterrinj'.*ph1_logic_eram.v\(52\)",line)
                    and index+1<len(lines) and '/src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v Line: 69'
                    in lines[index+1].replace('\\','/'))
                init_bound=re.search(r'ph1_logic_eram.v\(1287\).*INIT_FILE.*out of bounds',line)
                if not (ecc_compile or ecc_runtime or init_bound):
                    raise RuntimeError('unclassified warning '+path.name+': '+line)
                warnings.append({'log':path.name,'line':index+1,'message':line})
        for item in identity:
            if sha(Path(item['path']))!=item['sha256']:
                raise RuntimeError('source drift: '+item['path'])
        result.update(status='PASS',metrics=metrics,accepted_vendor_warnings=warnings)
        print(metrics[0])
    except Exception as error:
        result.update(status='FAIL',error=str(error))
        raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Results:',run/'RESULTS.json')


if __name__=='__main__':
    main()
