"""Generate bounded native diagnostics and describe exactly what was written."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import time
import xml.etree.ElementTree as ET

from common import atomic_json, contained
from run_options import tcl_word


PROFILE = 'timing-diagnostics-v2'
# TD 2026.2 accepts these native options although its public command reference
# omits them. A positive level limit enables the topology; expanding buckets
# emits each load pin and its corner latency instead of just the model count.
CLOCK_TREE_LEVELS = 1000000
MARKER = re.compile(r'^TD_SIMPLE_REPORT (\w+) (GENERATED|EMPTY|MISSING|FAILED|UNAVAILABLE|NOT_APPLICABLE)$', re.MULTILINE)
DEFINITIONS = (
    ('timing_detail', 'timing_detail.rpt', 'report_timing_summary -report_type max_min -ep_num 100 -path_num 3 -include_ignored', False),
    ('clock_intersection', 'clock_intersection.txt', 'report_clock_intersection -delay_type max_min', False),
    ('clock_tree', 'clock_tree.txt', f'report_clock_summary -clocks [get_clocks *] -levels {CLOCK_TREE_LEVELS} -expand_buckets', False),
    ('path_skew', 'path_skew.rpt', 'report_path_skew -delay_type max_min -ep_num 100 -path_num 3', False),
    ('noise', 'noise.csv', 'report_noise -phase true', True),
    ('device_settings', 'device_settings.txt', 'report_cfgs', False),
    ('high_fanout', 'high_fanout.txt', 'report_hfn {stage} -limit 100 -timing', False),
    ('logic_level', 'logic_level.rpt', 'report_logic_level -worst_n 100', False),
    ('timing_exception', 'timing_exception.rpt', 'report_timing_exception -ep_num 100 -path_num 3', False),
    ('run_parameters', 'run_parameters.txt', 'report_run_param {run}', False),
)


def report_directory(run_root, run):
    if run not in ('syn_1', 'phy_1'):
        raise ValueError('Use a native synthesis or physical run')
    return contained(Path(run_root), run + '/controller-reports')


def report_lines(run_root, run, target):
    directory = report_directory(run_root, run)
    if directory.is_symlink():
        raise ValueError('Diagnostic report directory must not be a symlink')
    # A continuation owns its copy. Remove only our known derived reports so an
    # unavailable command cannot make a copied parent report appear freshly made.
    for filename in [item[1] for item in DEFINITIONS] + ['device_settings.json']:
        path = directory / filename
        if path.is_symlink():
            raise ValueError('Linked diagnostic report is not writable')
        path.unlink(missing_ok=True)
    stage = 'gate' if target == 'synth' else 'place' if target == 'place' else 'route'
    lines = [
        '    file mkdir ' + tcl_word(directory.as_posix()),
        'proc td_diagnostic_report {id command destination} {',
        '    if {![llength [info commands [lindex $command 0]]]} {',
        '        puts "TD_SIMPLE_REPORT $id UNAVAILABLE"; return',
        '    }',
        '    if {[catch {uplevel #0 $command} message]} {',
        '        puts "TD_SIMPLE_REPORT $id FAILED"',
        '        puts stderr "TD_SIMPLE_REPORT_MESSAGE $id: $message"',
        '    } elseif {![file isfile $destination]} {',
        '        puts "TD_SIMPLE_REPORT $id MISSING"',
        '    } elseif {[file size $destination] == 0} {',
        '        puts "TD_SIMPLE_REPORT $id EMPTY"',
        '    } else {puts "TD_SIMPLE_REPORT $id GENERATED"}',
        '    flush stdout',
        '}',
    ]
    for name, filename, command, routed_only in DEFINITIONS:
        if routed_only and stage != 'route':
            lines += ['    puts "TD_SIMPLE_REPORT ' + name + ' NOT_APPLICABLE"']
            continue
        destination = tcl_word((directory / filename).as_posix())
        command = command.format(stage=stage, run=run) + ' -file ' + destination
        # The command is fixed controller code. No request supplies Tcl here.
        lines += ['    td_diagnostic_report ' + name + ' ' + tcl_word(command) + ' ' + destination]
    return lines


def file_info(path, job, started, parent=None):
    path, job = Path(path), Path(job).resolve()
    if path.is_symlink() or not path.resolve().is_relative_to(job):
        raise ValueError('Report leaves its owned job')
    stat = path.stat()
    with path.open('rb') as stream:
        checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
    return dict(path=path.relative_to(job).as_posix(), bytes=stat.st_size, mtime=stat.st_mtime,
                sha256=checksum, inherited_from=parent if stat.st_mtime < started else None)


def clock_tree_info(path):
    """Check actual native XML, including collapsed loads and missing groups.

    Native endpoint counters include logical aliases and need not equal the
    expanded physical pins. Record both; their equality is not a coverage test.
    """
    try:
        root = ET.parse(path).getroot()
        if root.tag != 'clock_summary':
            return dict(scope='UNRECOGNIZED_FORMAT')
        pins = root.findall('.//pin')
        clocks = root.findall('.//clock')
        declared = root.findall('./groups/clock_group')
        detailed = root.findall('./clock_group')
        missing = sorted({item.get('name') for item in declared} - {item.get('name') for item in detailed}, key=str)
        models = root.findall('.//model')
        collapsed = sum(int(item.get('loads', '0')) > len(item.findall('./pin')) for item in models)
        max_depth = 0
        pending = [(root, 0)]
        while pending:
            node, depth = pending.pop()
            depth += node.tag == 'pin'
            max_depth = max(max_depth, depth)
            pending.extend((child, depth) for child in node)
        info = dict(pin_nodes=len(pins), clock_nodes=len(clocks),
                    expanded_load_pins=sum(len(item.findall('./pin')) for item in models),
                    latency_nodes=len(root.findall('.//latency')),
                    declared_endpoints=sum(int(item.get('endpoints', '0')) for item in declared),
                    missing_groups=missing, unexpanded_buckets=collapsed,
                    max_pin_depth=max_depth, requested_levels=CLOCK_TREE_LEVELS)
        if not pins:
            scope = 'SUMMARY_ONLY'
        elif (missing or collapsed or max_depth >= CLOCK_TREE_LEVELS or not clocks or
              info['declared_endpoints'] and not models):
            scope = 'TRUNCATED_TOPOLOGY'
        else:
            scope = 'FULL_TOPOLOGY'
        return dict(scope=scope, **info)
    except (ET.ParseError, ValueError):
        return dict(scope='UNRECOGNIZED_FORMAT')


def collect_reports(job, spec, run_root, project_file, started):
    job = Path(job).resolve()
    run_root, project_file = Path(run_root), Path(project_file)
    if not run_root.resolve().is_relative_to(job) or not project_file.resolve().is_relative_to(job):
        raise ValueError('Diagnostic paths leave the job')
    target = spec['project']['target']
    run = 'syn_1' if target == 'synth' else 'phy_1'
    directory = report_directory(run_root, run)
    text = (job / 'td.log').read_text(encoding='utf-8', errors='replace') if (job / 'td.log').exists() else ''
    states = dict(MARKER.findall(text))
    parent = spec.get('resume', {}).get('job')
    entries = []
    for name, filename, command, routed_only in DEFINITIONS:
        state = states.get(name, 'NOT_RUN')
        entry = dict(id=name, state=state, run=run, command=command, generated_is_analysis_pass=False)
        path = directory / filename
        if state in ('GENERATED', 'EMPTY'):
            if not path.is_file():
                entry['state'] = 'MISSING'
            elif path.stat().st_mtime < started:
                entry['state'] = 'STALE'
            else:
                entry.update(file_info(path, job, started))
                if name == 'clock_tree' and path.stat().st_size:
                    entry.update(clock_tree_info(path))
        entries.append(entry)
    # Native flow already emits these reports. Re-running check_timing after
    # reopening a routed DB can crash TD2026.2, so retain the actual flow output.
    native = []
    native_types = [('rtl_area', 'syn_1', ('*_rtl.area',)), ('gate_area', 'syn_1', ('*_gate.area',)),
                    ('physical_area', 'phy_1', ('*_phy.area', '*_place.area', 'simple.area')),
                    ('check_timing', 'phy_1', ('*_chk.timing',))]
    for name, subrun, patterns in native_types:
        if subrun == 'phy_1' and (target == 'synth' or target == 'place' and name == 'check_timing'):
            native.append(dict(id=name, state='NOT_APPLICABLE'))
            continue
        paths = [path for pattern in patterns for path in sorted((run_root / subrun).glob(pattern)) if path.is_file()]
        if not paths:
            native.append(dict(id=name, state='MISSING'))
            continue
        info = file_info(paths[0], job, started, parent)
        state = 'INHERITED' if info['inherited_from'] else 'STALE' if info['mtime'] < started else 'AVAILABLE'
        native.append(dict(id=name, state=state, **info))
    directory.mkdir(parents=True, exist_ok=True)
    model = ET.fromstring(project_file.read_text(encoding='utf-8-sig').replace('UsedInP&R', 'UsedInP&amp;R'))
    settings = dict(source='native report_cfgs plus current AL',
                    hardware={item.tag: item.text for item in model.find('HardWare')},
                    device_settings_xml=ET.tostring(model.find('Device_Settings'), encoding='unicode') if model.find('Device_Settings') is not None else None,
                    configurations_xml=ET.tostring(model.find('Configurations'), encoding='unicode') if model.find('Configurations') is not None else None,
                    runs_xml=ET.tostring(model.find('Runs'), encoding='unicode') if model.find('Runs') is not None else None)
    atomic_json(directory / 'device_settings.json', settings)
    entries.append(dict(id='device_settings_source', state='GENERATED',
                        **file_info(directory / 'device_settings.json', job, started)))
    complete = (all(item['state'] in ('GENERATED', 'NOT_APPLICABLE') for item in entries) and
                all(item['state'] in ('AVAILABLE', 'INHERITED', 'NOT_APPLICABLE') for item in native))
    limited = [item['id'] for item in entries if item.get('scope') not in (None, 'FULL_TOPOLOGY')]
    document = dict(schema=1, profile=PROFILE, source_commit=spec['source_commit'], project=spec['project']['id'],
                    seed=spec['seed'], run=run, target=target, collected_at=time.time(),
                    endpoints_per_group=100, paths_per_endpoint=3, files=entries, native_reports=native,
                    state='COMPLETE' if complete and not limited else 'PARTIAL')
    atomic_json(job / 'reports.json', document)
    return dict(state=document['state'], profile=PROFILE, manifest='reports.json',
                generated=sum(item['state'] == 'GENERATED' for item in entries),
                unavailable=[item['id'] for item in entries if item['state'] not in ('GENERATED', 'NOT_APPLICABLE')],
                native_missing=[item['id'] for item in native if item['state'] in ('MISSING', 'STALE')],
                scope_limited=limited)
