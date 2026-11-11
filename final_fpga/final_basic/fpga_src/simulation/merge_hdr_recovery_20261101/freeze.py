"""Freeze test/reference inputs against an externally supplied production seal SHA."""
from pathlib import Path
import argparse
import hashlib
import json
import sys

EXT = Path(__file__).resolve().parent
PROJECT = EXT.parents[2]
sys.path.insert(0, str(EXT))
from binding import LOCK, atomic, read, sha


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source-seal', default='docs/SOURCE_SEAL_LOCAL_20261101.json')
    ap.add_argument('--source-seal-sha256', required=True)
    ap.add_argument('--short-gate', action='append', required=True,
                    help='Candidate-local actual short qualification JSON; repeat for each required short gate')
    args = ap.parse_args()
    if LOCK.exists():
        raise RuntimeError('Existing test lock is retained; use a new test campaign for changed inputs')
    seal = PROJECT / args.source_seal
    if sha(seal) != args.source_seal_sha256:
        raise RuntimeError('Source seal does not match externally supplied SHA256')
    authority = read(seal)
    gates = []
    for relative in args.short_gate:
        path = (PROJECT / relative).resolve()
        if not path.is_relative_to(PROJECT.resolve()):
            raise RuntimeError('Short gate must belong to this candidate')
        result = read(path)
        status = result.get('status', '')
        if status != 'PASS' and not status.startswith('PASS_'):
            raise RuntimeError('Short gate did not actually PASS: ' + relative)
        gates.append(dict(path=path.relative_to(PROJECT).as_posix(), sha256=sha(path), status=status))
    provenance_path = EXT / 'PROVENANCE.json'
    provenance = read(provenance_path)
    for row in provenance['files']:
        row['sha256'] = sha(EXT / row['path'])
    provenance['adaptations'] = ['New HDR-only campaign; old FAIL, lock7054, original STATE and SDR PASS retained unchanged',
                               'Count each real DDR member finish handshake and verify both descriptors; legacy commit observes LONG only',
                               'One complete R3 cross-VC overlap, eight retained-good warmups and first product SOURCE10 remain unchanged',
                               'Original six-hour deadline1793534251.7473004 retained; one10800-second HDR case maximum']
    atomic(provenance_path, provenance)
    paths = {p for p in EXT.rglob('*') if p.is_file() and p.suffix in {'.py', '.sv', '.v', '.vh', '.json', '.md'}}
    paths.update(PROJECT / 'src_fpga/simulation' / p for p in ['MAIN_FIXTURE.json', 'run_main.py', 'tb_dual_imx415.sv', 'dual_csi_word_source.sv', 'dual_throughput_monitor.vh'])
    paths.add(PROJECT / 'BASELINE_INPUTS.json')
    paths.update(PROJECT / row['path'] for row in gates)
    paths.update(PROJECT / row['path'] for row in read(PROJECT / 'BASELINE_INPUTS.json')['files']
                 if row['path'].startswith('verification_reference/'))
    for relative, digest in authority['production_inputs'].items():
        if sha(PROJECT / relative) != digest:
            raise RuntimeError('Production drift before test freeze: ' + relative)
    result = dict(schema=1, campaign='dual_hdr_merge_r1_hdr_recovery_20261101',
                  source_kind='LOCAL_SEALED_TREE_NOT_PUSHED',
                  source_seal_path=Path(args.source_seal).as_posix(),
                  source_seal_sha256=args.source_seal_sha256,
                  short_gates=gates,
                  test_inputs={p.relative_to(PROJECT).as_posix(): sha(p) for p in sorted(paths)},
                  max_parallel=1, case_wall_limit_seconds=10800, total_wall_limit_seconds=21600,
                  original_plan_deadline_epoch=1793534251.7473004)
    atomic(LOCK, result)
    print(json.dumps(dict(status='FROZEN', lock_path=str(LOCK), lock_sha256=sha(LOCK),
                          source_seal_sha256=args.source_seal_sha256, test_inputs=len(paths))))


if __name__ == '__main__':
    main()
