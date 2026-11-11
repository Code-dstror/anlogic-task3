"""Prepare a latency-shortened identity CCM arm, preserving all arithmetic."""
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
original=(PROJECT/'src_fpga/rtl/wide_color_pipeline.v').read_text()
candidate=original.replace('    reg hdr;','    localparam integer PRE_LAST = IDENTITY_CCM ? 2 : 4;\n    reg hdr;',1)
candidate=candidate.replace('!pre_valid[4] || tone_input_ready','!pre_valid[PRE_LAST] || tone_input_ready')
candidate=candidate.replace('.s_hdr(pre_hdr[4])','.s_hdr(pre_hdr[PRE_LAST])')
candidate=candidate.replace('.s_preset(pre_preset[9:8])','.s_preset(pre_preset[PRE_LAST*2+:2])')
candidate=candidate.replace('.s_valid(rst_n && pre_valid[4])','.s_valid(rst_n && pre_valid[PRE_LAST])')
candidate=candidate.replace('.s_sof(pre_sof[4]),.s_eol(pre_eol[4]),.s_clipped(pre_clipped[4])',
                            '.s_sof(pre_sof[PRE_LAST]),.s_eol(pre_eol[PRE_LAST]),.s_clipped(pre_clipped[PRE_LAST])')
candidate=candidate.replace('assign highlight_weight[pixel*6+:6]=weight4;',
                            'assign highlight_weight[pixel*6+:6]=IDENTITY_CCM ? weight2 : weight4;')
candidate=candidate.replace('assign corrected_rgb[pixel*42+channel*14 +:14]=corrected;',
                            '// Identity CCM needs no extra two-cycle matrix delay.\n                assign corrected_rgb[pixel*42+channel*14 +:14]=value;')
assert candidate!=original and candidate.count('PRE_LAST')==8
for label,text in [('baseline',original),('candidate',candidate)]:
    path=HERE/label/'wide_color_pipeline.v'
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text,newline='\n')

old=PROJECT.parent/'camera_hdr_quality_r1/analysis/tone'
for name in ('probe.v','probe.sdc','probe.tcl'):
    data=(old/name).read_text()
    if name=='probe.tcl':
        data=data.replace('if {[file isfile candidate.flag]} {add_define {HDR_QUALITY_PROBE=1}}','add_define {HDR_QUALITY_PROBE=1}')
    (HERE/name).write_text(data,newline='\n')
s=(old/'run_probe.py').read_text()
s=s.replace('BASELINE = "1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba"','BASELINE = "camera_fusion_r1_initial"')
s=s.replace('LIMIT_SECONDS = 120','LIMIT_SECONDS = 150')
s=s.replace('payload[name] = (PROJECT / "src_fpga" / name).read_bytes() if candidate else fixed_bytes(name)',
'''payload[name] = ((HERE / ("candidate" if candidate else "baseline") / "wide_color_pipeline.v").read_bytes()
                         if name == "rtl/wide_color_pipeline.v" else (PROJECT / "src_fpga" / name).read_bytes())''')
a=s.index('    fixed_files = git("ls-tree"')
b=s.index('    work = PROJECT / ',a)
s=s[:a]+'''    ip_files = tuple(p.relative_to(PROJECT / "src_fpga").as_posix()
                     for prefix in IP_PREFIXES for p in (PROJECT / "src_fpga" / prefix).rglob("*") if p.is_file())
    common = {name: (PROJECT / "src_fpga" / name).read_bytes() for name in (*ip_files, *RTL[2:], DATA[0])}
'''+s[b:]
s=s.replace('"tmp/tone_native"','"tmp/color_pipe_equiv"')
(HERE/'run_ab.py').write_text(s,newline='\n')
print('Prepared exact-arithmetic identity pipeline A/B')
