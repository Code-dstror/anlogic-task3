"""Independent 217-case scanner audit of an explicit production source root."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import subprocess
import sys

BASELINE_COMMIT = 'b68fdc2d79b9ae3579174366f0fdce89dfc9f389'


def reference_window(mask: int) -> tuple[int, int]:
    """Enumerate maximal noncircular intervals; earliest start wins ties."""
    intervals = []
    for start in range(32):
        if mask & (1 << start) and (start == 0 or not mask & (1 << (start - 1))):
            stop = start + 1
            while stop < 32 and mask & (1 << stop):
                stop += 1
            intervals.append((start, stop))
    if not intervals:
        return 0, 16
    start, stop = min(intervals, key=lambda interval: (-(interval[1] - interval[0]), interval[0]))
    return stop - start, start + (stop - start) // 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--modelsim-bin', required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--source-root', type=Path, required=True,
                        help='Actual candidate project root; source is copied verbatim, never patched')
    parser.add_argument('--output-root', type=Path,
                        help='New run directories are created here; defaults to this project tmp')
    parser.add_argument('--select', help='Comma separated exact case names for a minimal replay')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,40}', args.name):
        parser.error('Use a new lowercase run name')
    here = Path(__file__).resolve().parent
    project = here.parents[2]
    source_root = args.source_root.resolve()
    source_path = source_root / 'src_fpga/rtl/ph1a_rx_delay_scan.v'
    run_dir = (args.output_root.resolve() if args.output_root else
               project / 'tmp/runtime_recovery/scanner_matrix') / args.name
    run_dir.mkdir(parents=True, exist_ok=False)
    source = source_path.read_bytes()
    exported = run_dir / 'ph1a_rx_delay_scan.frozen.v'
    exported.write_bytes(source)
    simulation_source = exported
    runner_sha256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    commands = []
    tool_bin = Path(args.modelsim_bin).resolve()
    rng = random.Random(20261028)
    cases: list[dict] = []

    def matrix(name: str, mask: int, count: int = 80, **options: int) -> None:
        bits = list(range(1, 128))
        rng.shuffle(bits)
        if options.pop('contiguous', 0):
            pattern = (1 << count) - 1
        else:
            pattern = 1 | sum(1 << bit for bit in bits[:count - 1])
        second = options.get('SECOND_MASK', mask)
        stuck = options.get('STUCK_MASK', 0)
        first_effective = mask if count >= 64 and not stuck else 0
        effective = first_effective
        scans = 32
        if not effective and options.get('MAX_SCANS', 1) == 2:
            effective = second if count >= 64 and not stuck else 0
            scans = 64
        length, tap = reference_window(effective)
        item = dict(id=len(cases), name=name, type='matrix', MASK=mask,
                    PATTERN=pattern, EXPECT_LEN=length, EXPECT_TAP=tap,
                    EXPECT_SCANS=scans, presented_all_lane_edges=count,
                    expected_pass_mask=f'{effective:08x}', **options)
        cases.append(item)

    for name, mask in [('all', 0xffffffff), ('none', 0), ('last', 0x80000000),
                       ('first', 1), ('normal', 0x7fc0), ('tie', 0x00f0003c),
                       ('nonwrap', 0xe0000007), ('alternating_a', 0x55555555),
                       ('alternating_b', 0xaaaaaaaa)]:
        matrix(name, mask)
    for bit in range(32):
        matrix(f'onehot_{bit}', 1 << bit)
        matrix(f'onehole_{bit}', 0xffffffff ^ (1 << bit))
    for index in range(96):
        mask = rng.getrandbits(32)
        if index % 3 == 0:
            mask &= rng.getrandbits(32)
        matrix(f'random_{index:03d}', mask, count=rng.randint(65, 110), START_AGE=rng.randint(9, 28))
    for count in (63, 64, 65):
        matrix(f'external_burst_{count}', 0xffffffff, count=count, contiguous=1,
               TRACE=1 if count == 64 else 0)
    matrix('minimum_tap31_burst64', 0x80000000, count=64, contiguous=1)
    for stuck in range(1, 16):
        matrix(f'sticky_lanes_{stuck:x}', 0xffffffff, STUCK_MASK=stuck)
    matrix('stagger_lane_retirement', 0xffffffff, STAGGER=1, START_AGE=12)
    for phase in range(10):
        matrix(f'reset_stopped_clock_state_{phase}', 0x00ff0000, RESET_STATE=phase)
    matrix('two_failed_scans', 0, MAX_SCANS=2, SECOND_MASK=0)
    matrix('retry_after_new_activity', 0, MAX_SCANS=2, SECOND_MASK=0xf0, REARM_GAP=400)
    matrix('successful_first_no_retry', 0x7fc0, MAX_SCANS=2)
    matrix('reset_restores_two_scan_budget', 0, MAX_SCANS=2, SECOND_MASK=0, RESET_STATE=10)
    # Full production score/settle/acquire parameters, external contiguous bursts.
    for count in (63, 64, 65):
        matrix(f'production_external_burst_{count}', 0xffffffff, count=count,
               contiguous=1, TEST_LEN=32767, SETTLE=256, WAIT_LIMIT=8388608,
               MAX_SCANS=2, START_AGE=264, TRACE=1 if count == 64 else 0)

    activity = [
        ('eighth_at_last_edge', 0, 8, 16, 16, 17),
        ('eighth_before_last_edge', 0, 8, 16, 15, 16),
        ('only_seven', 1, 8, 16, 16, -1),
        ('one_lane_only_seven', 2, 8, 16, 16, -1),
        ('under_threshold_each_window', 3, 8, 16, 16, -1),
        ('old_seven_plus_new_one', 4, 8, 16, 16, -1),
        ('staggered_final_lane_last_edge', 5, 8, 16, 16, 17),
        ('no_activity', 6, 8, 16, 16, -1),
        ('one_edge_one_change', 0, 1, 1, 1, 2),
        ('fifteen_at_last_edge', 0, 15, 16, 16, 17),
        ('wait_one_cannot_accumulate_eight', 3, 8, 1, 1, -1),
    ]
    for name, kind, threshold, wait, last, expect in activity:
        cases.append(dict(id=len(cases), name=name, type='activity', KIND=kind,
                          THRESHOLD=threshold, WAIT_LIMIT=wait, LAST_CHANGE=last, EXPECT_EDGE=expect))

    total_available_cases = len(cases)
    if args.select:
        names = args.select.split(',')
        selected = {item['name']: item for item in cases if item['name'] in names}
        if set(names) != set(selected):
            parser.error(f'Unknown case names: {sorted(set(names)-set(selected))}')
        cases = [dict(selected[name], original_id=selected[name]['id'], id=index)
                 for index, name in enumerate(names)]

    instances = [f'localparam integer CASE_COUNT={len(cases)};',
                 'wire [CASE_COUNT-1:0] finished,failed_case;']
    for item in cases:
        params = []
        for key, value in item.items():
            if not key.isupper():
                continue
            if key in ('MASK', 'SECOND_MASK'):
                formatted = f"32'h{value:08x}"
            elif key == 'PATTERN':
                formatted = f"128'h{value:032x}"
            else:
                formatted = str(value)
            params.append(f'.{key}({formatted})')
        ident = item['id']
        module = 'scanner_matrix_case' if item['type'] == 'matrix' else 'scanner_activity_case'
        params.insert(0, f'.ID({ident})')
        instances.append(f'{module} #({",".join(params)}) case_{ident}(finished[{ident}],failed_case[{ident}]);')
    (run_dir / 'scanner_cases.svh').write_text('\n'.join(instances) + '\n', encoding='utf-8')
    (run_dir / 'CASES.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    frozen_harness = run_dir / 'scanner_matrix.fixed.sv'
    frozen_harness.write_bytes((here/'scanner_matrix.sv').read_bytes())
    (run_dir / 'REFERENCE.md').write_text(
        'Each mask is converted to maximal contiguous intervals in Python; the longest interval, '
        'then the smallest start wins. No ring joining. The selected tap is start + length//2.\n'
        'A stimulus pattern is scheduled from public O_delay_vaild, independent of internal state. '
        'All patterns start after settling and include a fresh lane-low interval. '
        'The contract reference counts the first qualifying all-lane-valid edge in its 64-edge total. '
        'A 63/64/65-edge contiguous burst therefore fails/passes/passes.\n'
        'Internal state observations are restricted to reset injection, phase coverage and trace logging.\n', encoding='utf-8')

    def invoke(executable: str, arguments: list[str], label: str, timeout: int = 90) -> int:
        argv = [str(tool_bin / executable), *arguments]
        try:
            completed = subprocess.run(argv, cwd=run_dir, timeout=timeout,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                encoding='utf-8', errors='replace', creationflags=subprocess.CREATE_NO_WINDOW)
        except Exception as exc:
            (run_dir / f'{label}.console.log').write_text(str(exc), encoding='utf-8')
            (run_dir / 'RESULTS.json').write_text(json.dumps(dict(
                status='BLOCKED', simulation='NOT_RUN', phase=label, error=str(exc),
                source_root=str(source_root), source_path=str(source_path),
                source_sha256=hashlib.sha256(source).hexdigest(), commands=commands + [dict(argv=argv)],
                scope='Tool failed to start; no RTL simulation result. Board/electrical NOT_RUN.'), indent=2), encoding='utf-8')
            raise
        (run_dir / f'{label}.console.log').write_text(completed.stdout, encoding='utf-8')
        commands.append(dict(argv=argv, exit_code=completed.returncode, timeout_seconds=timeout))
        if completed.returncode:
            print(completed.stdout)
        return completed.returncode

    lib = run_dir / 'work'
    for exe, argv, label in [
        ('vlib.exe', [str(lib)], 'vlib'),
        ('vmap.exe', ['-c'], 'vmap_create'),
        ('vmap.exe', ['work', str(lib)], 'vmap_work'),
        ('vlog.exe', ['-sv', '-work', str(lib), f'+incdir+{run_dir}', '-l',
                      str(run_dir/'compile.log'), str(simulation_source), str(frozen_harness)], 'compile'),
    ]:
        if invoke(exe, argv, label):
            raise RuntimeError(f'{label} failed; see {run_dir}')
    simulation_exit = invoke('vsim.exe', ['-c', '-lib', 'work', 'scanner_matrix_tb', '-l',
                       str(run_dir/'simulation.log'), '-do', 'run -all; quit -f'], 'simulation', timeout=180)
    log = (run_dir/'simulation.log').read_text(encoding='utf-8', errors='replace')
    outcome_lines = [line for line in log.splitlines() if re.search(r'(?:CASE|ACTIVITY) id=', line)]
    failures = []
    for line in outcome_lines:
        match = re.search(r'id=(\d+) verdict=FAIL', line)
        if match:
            ident = int(match.group(1))
            failures.append(dict(case=cases[ident], observed=line))
    summary = re.search(r'SCANNER_MATRIX_COMPLETE cases=(\d+) passed=(\d+) failed=(\d+)', log)
    source_stable = source_path.read_bytes() == source
    completed = (simulation_exit == 0 and bool(summary) and len(outcome_lines) == len(cases)
                 and not re.search(r'\*\*\s+(?:Error|Fatal):', log) and source_stable)
    result = dict(status='PASS' if completed and not failures else 'FAIL',
                  complete=completed, case_count=len(cases),
                  passed=int(summary.group(2)) if summary else None,
                  failed=int(summary.group(3)) if summary else None,
                  random_mask_cases=sum(item['name'].startswith('random_') for item in cases),
                  available_case_count=total_available_cases,
                  baseline_commit=BASELINE_COMMIT, source_root=str(source_root),
                  source_kind='actual_candidate_working_tree_verbatim_snapshot',
                  source_path=str(source_path), source_stable=source_stable,
                  source_sha256=hashlib.sha256(source).hexdigest(),
                  exported_source=str(exported),
                  production_source_substitutions=0, runner_sha256=runner_sha256,
                  simulation_source=str(simulation_source),
                  simulation_source_sha256=hashlib.sha256(simulation_source.read_bytes()).hexdigest(),
                  harness_sha256=hashlib.sha256(frozen_harness.read_bytes()).hexdigest(),
                  failures=failures, commands=commands,
                  scope='Digital unit simulation only. Synthesis/P&R/STA/board NOT_RUN.',
                  log=str(run_dir/'simulation.log'))
    (run_dir/'RESULTS.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('status','complete','case_count','passed','failed','source_sha256','log')}, indent=2))
    for failure in failures:
        print(f"FAIL {failure['case']['name']}: {failure['observed']}")
    return 0 if result['status']=='PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
