"""Native TD tiny probe for reset exceptions surviving packing, with timing sentinels."""
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

RTL = r"""module r4_reset_scope(input sys_clk,pixel_clk,cold_n,data,
 output [2:0] q_src,q_dst,status,output q_d,q_ce);
 (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] remote_pipe,local_pipe;
 (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] source_release,sink_release;
 (* preserve="true" *) reg ordinary_d,ordinary_ce;
 always @(posedge sys_clk or negedge cold_n)
   if(!cold_n)remote_pipe<=0;else remote_pipe<={remote_pipe[1:0],1'b1};
 always @(posedge pixel_clk or negedge cold_n)
   if(!cold_n)local_pipe<=0;else local_pipe<={local_pipe[1:0],1'b1};
 wire joint_n=cold_n&&remote_pipe[2]&&local_pipe[2];
 always @(posedge pixel_clk or negedge joint_n)
   if(!joint_n)source_release<=0;else source_release<={source_release[1:0],1'b1};
 always @(posedge sys_clk or negedge joint_n)
   if(!joint_n)sink_release<=0;else sink_release<={sink_release[1:0],1'b1};
 always @(posedge pixel_clk or negedge cold_n)
   if(!cold_n)begin ordinary_d<=0;ordinary_ce<=0;end
   else begin ordinary_d<=remote_pipe[2];if(remote_pipe[2])ordinary_ce<=data;end
 assign q_src=source_release;assign q_dst=sink_release;
 assign status=remote_pipe^local_pipe;assign q_d=ordinary_d;assign q_ce=ordinary_ce;
endmodule
"""


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def timing(path):
    lines = path.read_text().splitlines()
    rows = []
    for i, line in enumerate(lines):
        if not line.startswith("Begin Point"):
            continue
        end = next((j for j in range(i + 1, len(lines)) if lines[j].startswith("Begin Point")), len(lines))
        block = lines[i:end]
        launch = re.search(r"triggered by clock (\S+)", line)
        capture = re.search(r"triggered by clock (\S+)", lines[i + 1])
        q = next((j for j, row in enumerate(block) if row.startswith("clk2q")), None)
        nets = [re.search(r"net: (.*?),", row).group(1) for row in block[:q + 14 if q is not None else 0]
                if "net:" in row and re.search(r"net: (.*?),", row)]
        kind = lines[i + 2].split(":", 1)[1].strip()
        rows.append({"line": i + 1, "begin": line, "end": lines[i + 1], "kind": kind,
                     "launch": launch.group(1) if launch else None,
                     "capture": capture.group(1) if capture else None,
                     "slack": lines[i - 1], "first_nets": nets,
                     "q": block[q] if q is not None else ""})
    return rows


def summary(rows):
    return {
        "foreign_asr": [r for r in rows if r["kind"] in ("recovery", "removal") and r["launch"] != r["capture"]],
        "local_asr": [r for r in rows if r["kind"] in ("recovery", "removal") and r["launch"] == r["capture"]],
        "local_data": [r for r in rows if r["kind"] in ("setup", "hold") and r["launch"] == r["capture"]],
        "foreign_data": [r for r in rows if r["kind"] in ("setup", "hold") and r["launch"] != r["capture"]],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe name")
    run = PROJECT / "tmp/r4_reset_sdc" / args.name
    run.mkdir(parents=True, exist_ok=False)
    (run / "probe.v").write_text(RTL, newline="\n")
    (run / "base.sdc").write_text(
        "create_clock -name sys_probe -period 7.502 -waveform {0.229 3.980} [get_ports {sys_clk}]\n"
        "create_clock -name pixel_probe -period 8 [get_ports {pixel_clk}]\n", newline="\n")
    old, new = [], []
    for source, target in (("remote_pipe[2]*", "q_src"), ("local_pipe[2]*", "q_dst")):
        for bit in range(3):
            to = f"[get_regs {{{target}[{bit}]*}}]"
            old.append(f"set_false_path -from [get_regs {{{source}}}] -to [get_pins -of [get_cells -of [get_pins -of {to} -filter {{DIRECTION == output}}]] -filter {{REF_NAME == sr || REF_NAME == asr}}]")
            new.append(f"set_false_path -from [get_regs {{{source}}}] -through [get_nets {{joint_n*}}] -to {to}")
    for name, rows in (("old", old), ("new", new)):
        (run / f"{name}.sdc").write_text("\n".join(rows) + "\n", newline="\n")
    root = run.as_posix()
    build = f"""cd {{{root}}}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project r4_reset_scope . -family ph1 -device PH1A90SEG324 -speed -2
top_module r4_reset_scope
add_files ./probe.v
add_files ./base.sdc
set_param -run syn_1 flow thread 1
launch_runs syn_1
wait_run syn_1
close_project
exit 0
"""
    (run / "build.tcl").write_text(build, newline="\n")
    gate = f"{root}/r4_reset_scope_Runs/syn_1/r4_reset_scope_gate.db"
    report = "report_timing_summary -report_type max_min -ep_num 100 -path_num 3"
    for case in ("old", "new"):
        text = f"""cd {{{root}}}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db {{{gate}}}
update_timing
{report} -file {case}_baseline_gate.timing
read_sdc {{{root}/{case}.sdc}}
update_timing
{report} -file {case}_bound_gate.timing
puts "R4_GATE_{case}_FROM_REMOTE=[get_regs {{remote_pipe[2]*}}] FROM_LOCAL=[get_regs {{local_pipe[2]*}}] THROUGH=[get_nets {{joint_n*}}]"
puts "R4_GATE_{case}_TO=[get_regs {{q_src[0]* q_src[1]* q_src[2]* q_dst[0]* q_dst[1]* q_dst[2]*}}]"
place
update_timing -mode manhattan
{report} -file {case}_bound_place.timing
export_db {case}_place.db
puts "R4_PLACE_{case}_FROM_REMOTE=[get_regs {{remote_pipe[2]*}}] FROM_LOCAL=[get_regs {{local_pipe[2]*}}] THROUGH=[get_nets {{joint_n*}}]"
puts "R4_PLACE_{case}_TO=[get_regs {{q_src[0]* q_src[1]* q_src[2]* q_dst[0]* q_dst[1]* q_dst[2]*}}]"
check_timing -file {case}_place_check.timing
"""
        if case == "old":
            text += f"read_sdc {{{root}/old.sdc}}\nupdate_timing -mode manhattan\n{report} -file old_reapplied_place.timing\n"
        else:
            text += f"route\nupdate_timing -mode final\n{report} -file new_bound_route.timing\ncheck_timing -file new_route_check.timing\nexport_db new_route.db\n"
        text += f'puts "R4_{case}_SCOPE_DONE"\nexit 0\n'
        (run / f"{case}.tcl").write_text(text, newline="\n")

    result = {"status": "IN_PROGRESS", "scope": "TINY_14FF_SDC_BINDING_NOT_PRODUCTION_QUALIFICATION",
              "td_root": str(args.td_root), "runner_sha256": sha(Path(__file__)), "run": str(run),
              "inputs": [{"path": p.name, "sha256": sha(p)} for p in sorted(run.glob('*')) if p.is_file()]}
    try:
        for name in ("build", "old", "new"):
            cmd = [sys.executable, str(REPO / "tools/run_td.py"), str(run / f"{name}.tcl"),
                   "--td-root", str(args.td_root), "--workdir", str(run), "--log", str(run / f"{name}.log")]
            result.setdefault("commands", []).append(cmd)
            subprocess.run(cmd, cwd=REPO, check=True)
        results = {p.stem: summary(timing(p)) for p in run.glob('*.timing') if '_check' not in p.stem}
        result["reports"] = results
        assert results['old_baseline_gate']['foreign_asr'], "baseline must actually exercise foreign reset checks"
        assert not results['old_bound_gate']['foreign_asr'], "old selector should work at gate"
        assert results['old_bound_place']['foreign_asr'], "old physical pin selector must reproduce packing loss"
        assert not results['old_reapplied_place']['foreign_asr'], "late binding must repair the old selector"
        for stage in ('gate', 'place', 'route'):
            rows = results[f'new_bound_{stage}']
            assert not rows['foreign_asr'], f"new exception lost across {stage}"
            assert rows['local_asr'], f"new exception accidentally removed local ASR in {stage}"
            assert rows['local_data'], f"new exception accidentally removed local data in {stage}"
            assert rows['foreign_data'], f"new exception accidentally removed real foreign data/CE in {stage}"
        r = results['new_bound_route']
        assert any(x['kind'] == 'hold' for x in r['local_data']), "routed local hold must remain checked"
        assert any(x['kind'] == 'removal' for x in r['local_asr']), "routed local removal must remain checked"
        check = (run / 'new_route_check.timing').read_text()
        assert 'There are 0 invalid constraints.' in check
        assert 'There are 0 constraints that have no timing paths.' in check
        result['status'] = 'PASS'
        print('R4_RESET_SDC_SCOPE_PASS', {stage: {k: len(v) for k, v in results[f'new_bound_{stage}'].items()}
                                           for stage in ('gate', 'place', 'route')})
    except Exception as error:
        result['status'] = 'FAIL';result['error'] = str(error);raise
    finally:
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
