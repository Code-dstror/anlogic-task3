"""Short direct verification of the four actual configured IPs, using the chosen TD model set."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
NAMES = ("camera_packet_fifo_147x512", "camera_control_fifo_40x512",
         "camera_event_fifo_47x512", "camera_event_fifo_47x8192")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', required=True)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    a = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,40}', a.name): parser.error('invalid run name')
    out = ROOT / 'tmp/catalog_fifos' / a.name
    out.mkdir(parents=True,exist_ok=False)
    sources=[a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
    for name in NAMES:
        d = ROOT/'src_fpga/ip'/name
        sources += [d/'RTL'/(name+'_soft_fifo_core.v'), d/'RTL'/(name+'_soft_fifo.v'), d/(name+'.v')]
    sources.append(HERE/'tb_catalog_fifos.sv')
    models = [a.td_root/'sim_release'/f for f in (
        'common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v',
        'ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v')]
    scope = models + sources + [Path(__file__)]
    def hashes():return {str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in scope}
    before=hashes()
    def command(exe, args, log):
        cmd=[str(a.modelsim_bin/(exe+'.exe')), *map(str,args)]
        q=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=90)
        (out/log).write_text(q.stdout)
        if q.returncode or re.search(r'\*\* (?:Error|Fatal):',q.stdout):raise RuntimeError(q.stdout[-2400:])
        return q.stdout
    result={'status':'FAIL','scope':'four generated Soft_FIFO configurations; independent clocks, full/empty, pointer wrap, rejected accesses, reset'}
    try:
        command('vlib',['ph1'],'lib_ph1.log');command('vlib',['work'],'lib_work.log')
        command('vlog',['-work','ph1',*models],'models.log')
        command('vlog',['-sv','-work','work','+define+PH1',*sources],'compile.log')
        log=command('vsim',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_catalog_fifos','-do','run -all; quit -f'],'sim.log')
        if 'RESULT: PASS FOUR_CATALOG_FIFOS' not in log:raise RuntimeError('missing four-way PASS')
        if before!=hashes():raise RuntimeError('source drift')
        result.update(status='PASS',cases=[r.strip('# ') for r in log.splitlines() if 'CATALOG_FIFO_CASE ' in r],
                      warnings=[r for r in log.splitlines() if '** Warning:' in r])
    finally:
        result.update(inputs=before,td_root=str(a.td_root),modelsim_bin=str(a.modelsim_bin))
        (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(result['status'],result['cases'])
if __name__=='__main__':main()
