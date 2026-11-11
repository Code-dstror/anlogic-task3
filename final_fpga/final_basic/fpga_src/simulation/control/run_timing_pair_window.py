"""Compare parallel-deadline owner arithmetic against fixed R2 14df and official RAM."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


BASE = '14df01dcce'
BASE_PATH = 'refactor/dual_lane_s1/src_fpga/rtl/hdr_pair_bank_owner_dual.v'
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
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('unsafe run name')
    run = PROJECT/'tmp/pair_owner_window'/args.name
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
    for prefix in ['dut','reference']:
        connections = [f'        .{name}({name if direction=="input" else prefix+"_"+name})'
                       for direction,_,name in ports]
        bench=bench.replace('__'+prefix.upper()+'_PORTS__',',\n'.join(connections))
        bench=bench.replace('__OUTPUTS_'+prefix.upper()+'__',','.join(prefix+'_'+name for _,name in outputs))
    bench=bench.replace('__INITIALIZE__','\n'.join(f'            {name}=0;' for _,name in inputs if name!='i_clk'))
    bench=bench.replace('math_checks=math_checks+1;', '''check(dut.timestamp_ge(clock_value,origin)==(clock_value>=origin),"parallel timestamp order exact unsigned64");
            check(dut.timestamp_ge(origin,clock_value)==(origin>=clock_value),"reverse timestamp order exact unsigned64");
            math_checks=math_checks+1;''')
    bench=bench.replace('for(k=0;k<30000;k=k+1)begin', '''arithmetic_check(64'd0,64'hffffffffffffffff,32'hffffffff,1,0);
        arithmetic_check(64'hffffffffffffffff,64'hffffffff00000000,32'hffffffff,1,0);
        arithmetic_check(64'h100000000,64'd1,32'hffffffff,1,0);
        arithmetic_check(64'h100000001,64'd1,32'hffffffff,1,0);
        arithmetic_check(64'h100000000,64'h100000000,0,1,0);
        arithmetic_check(64'hffffffff00000001,64'hffffffff00000000,0,1,0);
        for(k=0;k<30000;k=k+1)begin''')
    bench=bench.replace('// Cold identity reset during an owned serial directory write.', '''// Inclusive delta=0, limit equality, full32 maximum and nonmod full64 wrap.
        clear_inputs();cold_reset();i_max_delta=0;configure();
        offer(0,1,500,i_now-2,1);offer(1,1,500,i_now-2,1);finish(0,1);finish(1,1);acquire_release(0);expect_empty();
        offer(0,2,501,i_now-2,1);offer(1,2,501,i_now-1,0);finish(0,1);expect_empty();
        clear_inputs();cold_reset();i_now=1;i_max_delta=32'hffffffff;configure();
        offer(0,1,502,1,1);i_now=64'h100000000;offer(1,1,502,i_now,1);
        finish(0,1);finish(1,1);acquire_release(0);expect_empty();
        clear_inputs();cold_reset();i_now=1;i_max_delta=32'hffffffff;configure();
        offer(0,1,503,1,1);i_now=64'h100000001;offer(1,1,503,i_now,0);finish(0,1);expect_empty();
        clear_inputs();cold_reset();i_now=64'hfffffffffffffff0;i_max_delta=32'hffffffff;configure();
        offer(0,1,504,i_now,1);i_now=0;offer(1,1,504,0,0);finish(0,1);expect_empty();
        clear_inputs();cold_reset();configure();
        // Cold identity reset during an owned serial directory write.''')
    test = run/'tb_timing_pair_owner.sv'
    test.write_text(bench, newline='\n')
    models = [args.td_root/'sim_release'/name for name in [
        'common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_phy_eram.v']]
    sources = [args.td_root/'sim_release/ph1/ph1_phy_gsr.v',
        ip/'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        rtl/'td_sdp_ram40.v',rtl/'hdr_pair_directory.v',source,reference]
    inputs = models+sources+[test,template,Path(__file__)]+headers
    identity=[{'path':str(path),'sha256':sha(path)} for path in inputs]
    result={'status':'IN_PROGRESS','baseline':{'commit':BASE,'path':BASE_PATH,
        'sha256':hashlib.sha256(baseline).hexdigest()},'inputs':identity,
        'modelsim_bin':str(args.modelsim_bin),'td_root':str(args.td_root),
        'latency_change_cycles':0,'arithmetic':'strict modulo wait window and unsigned timestamp arithmetic; nonmod pair delta exercised by directory transactions','synthesis':'NOT_RUN',
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
