"""Candidate/strict replay of independent adversarial vectors; no device APIs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

HERE=Path(__file__).resolve().parent
RTL_NAMES=['physical_csi_word_core.v','csi_rx_byte_align_observed.v','csi_rx_word_align_observed.v']
IP_NAME='vendor/anlogic_camera/phy/csi_rx_word_gear_box.v'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def blocks(lines):
    output=[];current=[]
    for line in lines:
        if line.startswith('start_case(') and current:
            output.append(current);current=[]
        current.append(line)
    if current:output.append(current)
    return output

def leaf_body(recovery):
    lines=json.loads((HERE/'vectors/leaf.json').read_text(encoding='utf-8'))['body']
    output=[]
    for block in blocks(lines):
        text='\n'.join(block)
        if recovery and any(name in text.splitlines()[0] for name in ('postFS_','decoder_reset_after_FS','bad_header_next_FS_min_gap')):
            text=text.replace("40'h0000000002","40'h0100000002")
            text=text.replace("finish_case(32'h00000002,1'b1","finish_case(32'h00000002,1'b0")
        output.append(text)
    # Original vectors end the non-saturation branch with `end`.
    body='\n'.join(output)
    assert body.endswith('end')
    extra=['start_case("repeated_bad_header_CRC_stalled_next_FS","REPEATED_FAILURE_OWNERSHIP");']
    good=lambda n: ((1 if recovery or n==1 else 0)<<32)|n
    def want(c,n,abort=0):extra.append(f"want(4'd{c},1'b{abort},1'b0,1'b0,40'h{good(n):010x});")
    want(7,1);extra.append("head(32'h00000000);")
    for n in range(1,5):
        extra.append('ready=0;')
        if n%2:
            extra.append(f"put(32'h{0x00097e2b if n==1 else 0x80000000:08x});idle(6);")
            want(1,n,1)
        else:
            # Independent known WC5 packet: payload01..05, CRC deliberately flipped.
            extra.extend(["head(32'h2e00052b);","put(32'h04030201);","put(32'h00dd1205);idle(6);"])
            want(2,n,1)
        want(7,n+1)
        extra.extend(["head(32'h00000000);","idle(5);ready=1;idle(10);"])
    want(6,5);extra.extend(["head(32'h07000001);", "verify(diag[63:32]===32'h00097e2b,\"first RX loss must remain the first header after repeated recovery\");",
        f"finish_case(32'd5,1'b{int(not recovery)},3'b011,0);"])
    return body[:-3]+'\n'+'\n'.join(extra)+'\nend'

def closed_body(recovery):
    lines=json.loads((HERE/'vectors/closedloop.json').read_text(encoding='utf-8'))['body']
    output=[]
    for block in blocks(lines):
        text='\n'.join(block)
        if recovery and 'actual_bad_header_00097e2b_feedback' in text.splitlines()[0]:
            text=text.replace("want(4'd7,1'b0,32'd2)","want(4'd7,1'b1,32'd2)")
            text=text.replace("want(4'd6,1'b0,32'd2)","want(4'd6,1'b1,32'd2)")
            text=text.replace("finish_case(2,1'b1","finish_case(2,1'b0")
        output.append(text)
    # This board WORD raw window contains actual lane3 early false acquisition.
    # Prefix and following packets are rebased healthy digital controls; no
    # claim that their state/timing duplicates the board's absolute cohort.
    raw=json.loads((HERE/'vectors/board_raw40.json').read_text(encoding='utf-8'))['raw_words']
    good_payload=bytes((i*37+31)&255 for i in range(60))
    golden=[]
    for i in range(12):
        b=good_payload[5*i:5*i+5]
        value=sum(((b[j]<<2)|((b[4]>>(2*j))&3))<<(10*j) for j in range(4))
        golden.append(f"golden[{i}]=40'h{value:010x};")
    extra=['start_case("board_raw40_rejected_then_healthy_FS",1\'b1);',*golden,
        "want(4'd7,1'b1,32'd1);want(4'd5,1'b1,32'd1);want(4'd7,1'b1,32'd2);want(4'd6,1'b1,32'd2);",
        "short_packet(32'h00000000,40);"]
    extra += [f"ww(32'h{value:08x});" for value in raw]
    extra += ['zero(40);check(headers==1,"overage raw window must not produce a parser header");check(!ee&&!ce&&!fault,"rejected raw window invented a parser fault");',
        "short_packet(32'h00000000,40);", "ww(32'hb8b8b8b8);ww(32'h1e003c2b);"]
    # Independently recorded correct packet words in the prior oracle vectors.
    h=json.loads((HERE/'vectors/closedloop.json').read_text(encoding='utf-8'))['body']
    first=h.index('ww(32\'h1e003c2b);')
    payload=[]
    for line in h[first+1:]:
        if line=='zero(40);':break
        payload.append(line)
    assert len(payload)==16
    extra+=payload+["zero(40);short_packet(32'h07000001,40);finish_case(2,1'b0,3'b000,0,12);"]
    return '\n'.join(output+['\n'.join(extra)])

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source-root',type=Path,required=True)
    ap.add_argument('--output-root',type=Path,required=True)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    ap.add_argument('--mode',choices=['strict','recovery'],required=True)
    args=ap.parse_args()
    if not re.fullmatch('[a-z0-9_]+',args.name):ap.error('ASCII lowercase/digit/underscore name required')
    run=args.output_root.resolve()/args.name;run.mkdir(parents=True,exist_ok=False)
    result=dict(status='IN_PROGRESS',mode=args.mode,source_root=str(args.source_root.resolve()),inputs=[],commands=[],simulation='IN_PROGRESS',synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    started=time.monotonic()
    def copy(src,dest):
        target=run/'inputs'/dest;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(src.read_bytes())
        result['inputs'].append(dict(original=str(src.resolve()),path=str(target),sha256=sha(target)));return target
    def command(name,words):
        argv=[str(args.modelsim_bin/words[0]),*map(str,words[1:])];result['commands'].append(dict(cwd=str(run),argv=argv))
        p=subprocess.run(argv,cwd=run,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace',timeout=90)
        (run/(name+'.console.log')).write_text(p.stdout,encoding='utf-8')
        if p.returncode:raise RuntimeError(name+': '+p.stdout[-3000:])
    try:
        sources=[copy(args.source_root/'src_fpga/rtl'/name,Path('rtl')/name) for name in RTL_NAMES]
        sources += [copy(args.source_root/'src_fpga/ip'/IP_NAME,Path('ip')/IP_NAME)]
        for group in ('vectors','templates'):
            for path in (HERE/group).glob('*'):
                if path.is_file():copy(path,Path(group)/path.name)
        recovery=args.mode=='recovery'
        leaf=(HERE/'templates/leaf.sv').read_text(encoding='utf-8').replace('__CASES__',leaf_body(recovery))
        leaf=leaf.replace('.SEQUENCE_INITIAL(INITIAL_SEQUENCE)) dut(',f'.SEQUENCE_INITIAL(INITIAL_SEQUENCE),.FRAME_RESYNC_ENABLE({int(recovery)})) dut(')
        closed=(HERE/'templates/closedloop.sv').read_text(encoding='utf-8').replace('__CASES__',closed_body(recovery))
        closed=closed.replace('#(.RX_DIAG_ENABLE(1)) dut(',f'#(.RX_DIAG_ENABLE(1),.FRAME_RESYNC_ENABLE({int(recovery)})) dut(')
        leaf_path=run/'tb_parser.sv';closed_path=run/'tb_closedloop.sv';leaf_path.write_text(leaf,encoding='utf-8');closed_path.write_text(closed,encoding='utf-8')
        result['generated_benches']=[dict(path=str(p),sha256=sha(p)) for p in (leaf_path,closed_path)]
        command('version',['vsim.exe','-version']);command('vmap',['vmap.exe','-c']);command('work',['vlib.exe','work'])
        command('compile',['vlog.exe','-quiet','-sv','-l','compile.log',*sources,leaf_path,closed_path])
        for name,top,extra in [('leaf','tb_parser',[]),('saturation','tb_parser',["-gINITIAL_SEQUENCE=32'hfffffffe"]),('closedloop','tb_closedloop',[])]:
            command(name,['vsim.exe','-c','-voptargs=+acc','work.'+top,*extra,'-l',name+'.log','-do','run -all; quit -f'])
            if name!='closedloop':(run/(name+'_tokens.csv')).write_bytes((run/'tokens.csv').read_bytes())
        logs={name:(run/(name+'.log')).read_text(errors='replace') for name in ('leaf','saturation','closedloop')}
        result['cases']=[dict(suite=name,name=m[0],status=m[1],details=m[2]) for name,body in logs.items() for m in re.findall(r'CASE\|([^|]+)\|(PASS|FAIL)\|([^\r\n]+)',body)]
        result['metrics']=[line.lstrip('# ') for body in logs.values() for line in body.splitlines() if 'RESULT|' in line]
        result['mismatches']=[line.lstrip('# ') for body in logs.values() for line in body.splitlines() if 'MISMATCH|' in line]
        result['known_contract_exposures']=[line for line in result['mismatches'] if 'packet_done_to_new_SYNC_same_boundary' in line]
        result['unexpected_mismatches']=[line for line in result['mismatches'] if line not in result['known_contract_exposures']]
        result['warnings']=[line for name in ('compile',*logs) for line in (run/(name+'.log')).read_text(errors='replace').splitlines() if re.search(r'\*\* (Warning|Error|Fatal)',line)]
        if len(result['metrics'])!=3 or len(result['cases'])!=95:raise RuntimeError('missing bounded result/cases')
        for item in result['inputs']:
            if sha(Path(item['original']))!=item['sha256'] or sha(Path(item['path']))!=item['sha256']:raise RuntimeError('input drift '+item['original'])
        result['status']='FAIL' if result['unexpected_mismatches'] or result['warnings'] else ('PASS_WITH_CONTRACT_EXPOSURE' if result['known_contract_exposures'] else 'PASS')
        result['simulation']=result['status']
    except Exception as exc:result.update(status='FAIL',simulation='FAIL',error=str(exc));raise
    finally:
        result['elapsed_seconds']=round(time.monotonic()-started,3)
        (run/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({k:result.get(k) for k in ('status','mode','metrics','mismatches','warnings','error')},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
