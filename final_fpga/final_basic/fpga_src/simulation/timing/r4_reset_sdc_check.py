"""Check the exact R3-to-R4 SDC delta and current dedicated-reset RTL topology."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = "946d970c2f660eaf7dad85eea91931ec76c12200"
REL = "refactor/hdr_jpeg_timing/fpga_prj/constraints/stream_cdc.sdc"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def commands(text):
    return [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    baseline = subprocess.check_output(['git', 'show', f'{BASE}:{REL}'], cwd=REPO)
    current = (REPO / REL).read_bytes()
    dead = 'set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_session_ctl/abort_hold_pipe[*]}]'
    changes, expected, deleted = [], [], 0
    for line in commands(baseline.decode()):
        if line == dead:
            deleted += 1
            continue
        if 'REF_NAME == sr || REF_NAME == asr' not in line:
            expected.append(line)
            continue
        source, target = re.findall(r'\[get_regs \{([^}]+)\}\]', line)
        root = target.rsplit('/', 1)[0]
        through = root + '/fifo_async_reset_n*'
        if '/u_pair_drain/u_request/' in target:
            assert source.endswith('/u_pair_drain/dfi_rst_n*')
            through += ' ' + root.replace('/u_request', '/u_ack') + '/fifo_async_reset_n*'
        else:
            assert re.search(r'/u_member[01]/capture_fifo/(source|sink)_reset_release_pipe\[[012]\]\*$', target)
            assert source.endswith('/dfi_rst*') or source.endswith('/ingress/i_rst_n*')
        new = f'set_false_path -from [get_regs {{{source}}}] -through [get_nets {{{through}}}] -to [get_regs {{{target}}}]'
        changes.append({'old': line, 'new': new, 'source': source, 'through': through, 'target': target})
        expected.append(new)
    assert len(changes) == 15 and deleted == 1
    assert commands(current.decode()) == expected, 'unexpected active constraint delta outside the approved 15 replacements + 1 empty rule removal'
    rtl = PROJECT / 'src_fpga/rtl'
    topology = {}
    for name in ('raw_capture_fifo_eram_safe.v', 'control_message_fifo_ip.v'):
        path = rtl / name
        source = path.read_text()
        assert 'assign fifo_async_reset_n = i_source_rst_n && i_sink_rst_n;' in source
        # The exception's THROUGH net occurs only at these asynchronous reset
        # sensitivities, never in a D/CE equation. Check every lexical use.
        uses = [line.strip() for line in source.splitlines() if 'fifo_async_reset_n' in line]
        assert len(uses) == 6
        assert source.count('always @(posedge i_source_clk or negedge fifo_async_reset_n)') == 1
        assert source.count('always @(posedge i_sink_clk or negedge fifo_async_reset_n)') == 1
        assert "source_reset_release_pipe <= {source_reset_release_pipe[1:0], 1'b1};" in source
        assert "sink_reset_release_pipe <= {sink_reset_release_pipe[1:0], 1'b1};" in source
        topology[name] = {'sha256': sha(path.read_bytes()), 'joint_reset_uses': uses}
    path = rtl / 'reset_release_sync.v'
    assert 'assign o_rst_n = release_pipe[2];' in path.read_text()
    topology[path.name] = {'sha256': sha(path.read_bytes()), 'output': 'release_pipe[2]'}
    path = rtl / 'full_raw_capture_frontend.v'; source = path.read_text()
    for fragment in ('.o_rst_n(pix_rst)', '.o_rst_n(dfi_rst)', '.i_rst_n(pix_rst)',
                     '.i_source_rst_n(pix_rst)', '.i_sink_rst_n(dfi_rst)'):
        assert fragment in source
    topology[path.name] = {'sha256': sha(path.read_bytes()), 'alias_connections_checked': True}
    path = rtl / 'paired_raw_capture_drain_cdc.v'; source = path.read_text()
    assert '.o_rst_n(dfi_rst_n)' in source
    assert source.count('.i_source_rst_n(source_rst_n)') == 1
    assert source.count('.i_sink_rst_n(dfi_rst_n)') == 1
    assert source.count('.i_source_rst_n(dfi_rst_n)') == 1
    assert source.count('.i_sink_rst_n(source_rst_n)') == 1
    topology[path.name] = {'sha256': sha(path.read_bytes()), 'request_ack_same_joint_function': True}
    result = {'status': 'PASS', 'baseline_commit': BASE, 'baseline_sha256': sha(baseline),
              'source': REL, 'source_sha256': sha(current), 'replacement_count': len(changes),
              'empty_rule_deletion_count': deleted, 'all_other_active_constraints_unchanged': True,
              'changes': changes, 'removed_empty_rule': dead, 'topology': topology,
              'production_synthesis': 'NOT_RUN', 'production_physical': 'NOT_RUN', 'production_timing': 'NOT_RUN'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('R4_RESET_SDC_DELTA_PASS sha256=' + result['source_sha256'])


if __name__ == '__main__':
    main()
