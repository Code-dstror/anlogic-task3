"""Bounded actual-candidate deserialized-byte alignment adversarial matrix."""
from pathlib import Path
import hashlib
import argparse
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
SOURCE_ROOT = HERE.parents[3]
ROOT = SOURCE_ROOT.parents[1]
COMMIT = 'candidate-worktree'
PREFIX = 'src_fpga/'
MODELSIM = Path('D:/App/modelsim/win64')
STEPS = 240
WORDS = 17

def sha(data): return hashlib.sha256(data).hexdigest()

def ecc(h):
    masks=[0xf12cb7,0xf2555b,0x749a6d,0xb8e38e,0xdf03f0,0xeffc00]
    return sum(((h&m).bit_count()&1)<<i for i,m in enumerate(masks))

def crc(data):
    v=0xffff
    for b in data:
        v ^= b
        for _ in range(8): v=(v>>1)^0x8408 if v&1 else v>>1
    return v

def packet(mode):
    if mode=='zero': payload=bytes(60)
    elif mode=='b8': payload=bytes([0xb8])*60
    elif mode=='sot_runs': payload=bytes([0]*16+[0xb8]*16+[0]*16+[0xb8,0,0,0]*3)
    elif mode=='lane_sot':
        data=bytearray((31+i*37)%256 for i in range(60))
        for lane in range(4):
            for t in range(3+lane,12+lane):data[4*t+lane]=0 if t<7+lane else 0xb8
        payload=bytes(data)
    else: payload=bytes((31+i*37)%256 for i in range(60))
    h=(60<<8)|0x2b
    b=h.to_bytes(3,'little')+bytes([ecc(h)])+payload+crc(payload).to_bytes(2,'little')+b'\xff\xff'
    return [int.from_bytes(b[i:i+4],'little') for i in range(0,len(b),4)]

def add(cases,name,kind,shifts=None,skews=None,early_lane=-1,lead=0,false_shift=None,payload='pattern'):
    cases.append(dict(id=len(cases),name=name,kind=kind,shifts=shifts or [0]*4,skews=skews or [0]*4,
                      early_lane=early_lane,lead=lead,false_shift=false_shift,payload=payload,
                      legal_control=kind.startswith('legal') or kind.startswith('payload')))

def generate_cases():
    cases=[]
    add(cases,'baseline','legal_baseline')
    for s in range(1,8):add(cases,f'all_lanes_shift{s}','legal_bits',shifts=[s]*4)
    for lane in range(4):
        for s in range(1,8):
            shifts=[0]*4;shifts[lane]=s
            add(cases,f'lane{lane}_shift{s}','legal_bits',shifts=shifts)
    for rotation in range(8):add(cases,f'mixed_shift_{rotation}','legal_bits',shifts=[(rotation+i*3)%8 for i in range(4)])
    for lane in range(4):
        for skew in [1,2,3,4,5,6,7,15,16]:
            skews=[0]*4;skews[lane]=skew
            add(cases,f'lane{lane}_late{skew}', 'legal_skew' if skew<=5 else 'overrange_skew',skews=skews)
    for early in range(4):
        skews=[5]*4;skews[early]=0
        add(cases,f'lane{early}_early5','legal_skew',skews=skews,shifts=[1,3,5,7])
    for lane in range(4):
        for lead in [1,2,3,5,6,7,13,14,15,16,17,18,20,31,32]:
            add(cases,f'lane{lane}_false_lead{lead}','false_sot',early_lane=lane,lead=lead)
        for false_shift in range(8):
            add(cases,f'lane{lane}_false_phase{false_shift}_lead15','false_phase',early_lane=lane,
                lead=15,shifts=[2]*4,false_shift=false_shift)
    for payload in ['zero','b8','sot_runs','lane_sot']:
        add(cases,f'payload_{payload}_zero_skew','payload_pattern',payload=payload)
        add(cases,f'payload_{payload}_mixed','payload_pattern',payload=payload,shifts=[0,2,4,7],skews=[5,0,2,4])
    return cases

def raw_input(case,words):
    sync=56
    streams=[[0]*STEPS for _ in range(4)]
    for lane in range(4):
        t=sync+case['skews'][lane]
        streams[lane][t]=0xb8
        for j,w in enumerate(words):streams[lane][t+1+j]=(w>>(lane*8))&255
        if case['early_lane']==lane and case['false_shift'] is None:
            streams[lane][sync-case['lead']]=0xb8
    raws=[0]*STEPS
    for lane in range(4):
        shift=case['shifts'][lane]
        for t in range(STEPS):
            b=streams[lane][t];prev=streams[lane][t-1] if t else 0
            value=((b<<shift)|(prev>>(8-shift)))&255 if shift else b
            raws[t]|=value<<(8*lane)
    if case['early_lane']>=0 and case['false_shift'] is not None:
        lane=case['early_lane'];s=case['false_shift'];t=sync-case['lead']
        # Isolated sync candidate in a different bit phase, before actual packet.
        raws[t] |= ((0xb8<<s)&255)<<(8*lane)
        if s:raws[t+1] |= (0xb8>>(8-s))<<(8*lane)
    return raws

def header_quality(word):
    h=word&0xffffff;s=ecc(h)^((word>>24)&63)
    if word>>30:return dict(syndrome=s,accepted=False,reason='reserved_ecc_bits')
    corrected=h
    if s and s&(s-1):
        cols=[i for i in range(24) if ecc(1<<i)==s]
        if not cols:return dict(syndrome=s,accepted=False,reason='uncorrectable_syndrome')
        corrected ^= 1<<cols[-1]
    return dict(syndrome=s,accepted=True,corrected_dt=corrected&63,
                corrected_vc=(corrected>>6)&3,corrected_wc=corrected>>8)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output-root',type=Path,required=True)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,default=MODELSIM)
    args=ap.parse_args()
    args_modelsim=args.modelsim_bin
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}',args.name):ap.error('new lowercase run name required')
    run=args.output_root.resolve()/args.name
    run.mkdir(parents=True,exist_ok=False)
    result=dict(simulation='IN_PROGRESS',fixed_commit=COMMIT,inputs=[],commands=[],
                board='NOT_RUN',synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',
                scope='Ideal deserialized bytes; scheduled parser-like wait/done; no electrical model or parser claim')
    try:
        sources=[]
        for rel in ['rtl/csi_rx_byte_align_observed.v','rtl/csi_rx_word_align_observed.v','ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v']:
            data=(SOURCE_ROOT/PREFIX/rel).read_bytes()
            dest=run/'inputs'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
            sources.append(dest);result['inputs'].append(dict(original=str(SOURCE_ROOT/PREFIX/rel),path=str(dest),sha256=sha(data)))
        cases=generate_cases()
        with (run/'raw.hex').open('w') as rawfile,(run/'expected.hex').open('w') as expected:
            for case in cases:
                words=packet(case['payload']);assert len(words)==WORDS
                case['expected_words']=[f'{v:08x}' for v in words]
                for v in raw_input(case,words):rawfile.write(f'{v:08x}\n')
                for v in words:expected.write(f'{v:08x}\n')
        (run/'cases.json').write_text(json.dumps(cases,indent=2)+'\n')
        bench=(HERE/'tb_matrix.sv').read_bytes();(run/'tb_matrix.sv').write_bytes(bench)
        result['bench_sha256']=sha(bench);result['stimulus_sha256']=sha((run/'raw.hex').read_bytes())
        def call(label,exe,args):
            argv=[str(args_modelsim/exe),*map(str,args)];row=dict(argv=argv,cwd=str(run));result['commands'].append(row)
            p=subprocess.run(argv,cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
            row['exit_code']=p.returncode;(run/(label+'.console.log')).write_text(p.stdout,encoding='utf-8')
            if p.returncode:raise RuntimeError(label+' '+p.stdout[-5000:])
        call('version','vsim.exe',['-version']);call('vmap','vmap.exe',['-c']);call('vlib','vlib.exe',['work'])
        call('compile','vlog.exe',['-quiet','-sv','-l','compile.log',*sources,run/'tb_matrix.sv'])
        (run/'run.do').write_text('onerror {quit -code 1}\nonbreak {quit -code 1}\nrun -all\nquit -code 0 -f\n')
        call('run','vsim.exe',['-c','work.tb_matrix',f'-gCASES={len(cases)}','-l','run.log','-do','run.do'])
        log=(run/'run.log').read_text(errors='replace')
        rows=re.findall(r'CASE id=(\d+) count=(\d+) mismatch=(\d+) first_cycle=(-?\d+) first=([\da-f]+) bad_index=(-?\d+) got=([\da-f]+) expected=([\da-f]+) taps=([\da-f]+) offset=([\da-f]+) timeout_same=(\d+) max_age=(\d+)',log)
        if len(rows)!=len(cases):raise RuntimeError(f'missing rows: {len(rows)} / {len(cases)}')
        unexpected=[]
        for row,case in zip(rows,cases):
            i,count,mismatch,first_cycle,first,badi,got,expect,taps,offset,timeout_same,max_age=row
            assert int(i)==case['id']
            observation=dict(count=int(count),mismatches=int(mismatch),first_cycle=int(first_cycle),first_word=first,
                first_bad_index=int(badi),first_bad_got=got,first_bad_expected=expect,taps=taps,offset=offset,
                timeout_and_all_valid_coincidences=int(timeout_same),max_early_lane_age=int(max_age),header=header_quality(int(first,16)))
            if int(mismatch):verdict='KNOWN_FAIL_WRONG_VALID_WORD'
            elif int(count)==WORDS:verdict='PASS_EXACT'
            elif int(count)==0:verdict='SAFE_REJECT_NO_VALID_WORD'
            else:verdict='TRUNCATED_PREFIX'
            case.update(observation=observation,verdict=verdict)
            if case['legal_control'] and verdict!='PASS_EXACT':unexpected.append(case['name'])
        for case in cases:
            requires_rejection=(case['kind']=='overrange_skew' or case['kind']=='false_phase' or (case['kind']=='false_sot' and case['lead']>5))
            case['required_behavior']='exact_output' if case['legal_control'] else ('safe_reject_or_exact' if requires_rejection else 'parser_negative_if_corrupted')
            if requires_rejection and case['verdict'] not in ('PASS_EXACT','SAFE_REJECT_NO_VALID_WORD'):
                unexpected.append(case['name'])
        for item in result['inputs']:
            if sha(Path(item['original']).read_bytes())!=item['sha256'] or sha(Path(item['path']).read_bytes())!=item['sha256']:
                raise RuntimeError('candidate input changed during simulation')
        warnings=[line for name in ['compile.log','run.log'] for line in (run/name).read_text(errors='replace').splitlines() if '** Warning:' in line]
        result.update(simulation='PASS' if not unexpected and not warnings else 'FAIL',
            controls_pass=sum(c['legal_control'] and c['verdict']=='PASS_EXACT' for c in cases),
            controls_total=sum(c['legal_control'] for c in cases),unexpected_control_failures=unexpected,warnings=warnings,
            cases=cases,case_count=len(cases),verdict_counts={k:sum(c['verdict']==k for c in cases) for k in sorted(set(c['verdict'] for c in cases))})
        if unexpected:raise RuntimeError('legal control failure: '+repr(unexpected))
    except Exception as e:
        result.update(simulation='FAIL',error=str(e));raise
    finally:
        (run/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({k:result.get(k) for k in ['simulation','case_count','controls_pass','controls_total','verdict_counts','error']},ensure_ascii=False))

if __name__=='__main__':main()
