"""Run the project's own TD configuration through the normal native stages."""
from __future__ import annotations

import os
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, unescape

from common import atomic_bytes, contained, validate_threads
from run_options import parameter_lines, reset_run_options, tcl_word
from reports import report_lines


STAGE_PATTERN = re.compile(r'^TD_SIMPLE_STAGE (\w+) (START|DONE|REUSED)$', re.MULTILINE)


def canonical_project_paths(text, directory):
    """Match TD's run snapshot spelling without changing any registered input.

    On reopen TD compares AL paths with the canonical paths in <run>/*.prj.
    A self-reference such as ../fpga_prj/constraints/x.sdc can otherwise make
    an unchanged synthesis checkpoint fail PRJ-8817 after it is copied.
    """
    directory = Path(directory).resolve()

    def value(raw):
        decoded = unescape(raw, {'&quot;': '"', '&apos;': "'"})
        relative = Path(os.path.relpath((directory / decoded).resolve(), directory)).as_posix()
        return escape(relative, {'"': '&quot;'})

    def files(match):
        return re.sub(r'(<File\b[^>]*\bPath=")([^"]*)(")',
                      lambda item: item[1] + value(item[2]) + item[3], match[0])

    text = re.sub(r'<Source_Files\b[^>]*>.*?</Source_Files>', files, text, flags=re.DOTALL)

    def include(match):
        tag = match[0]
        if re.search(r'\bName="IncludeDir"', tag):
            tag = re.sub(r'(\bVal=")([^"]*)(")',
                         lambda item: item[1] + value(item[2]) + item[3], tag, count=1)
        return tag

    return re.sub(r'<Option\b[^>]*>', include, text)


def prepare_project(checkout, spec):
    checkout = Path(checkout).resolve()
    project = spec['project']
    project_root = checkout if project['root'] == '.' else contained(checkout, project['root'])
    project_file = contained(project_root, project['al'])
    text = project_file.read_text(encoding='utf-8-sig')
    model = ET.fromstring(text.replace('UsedInP&R', 'UsedInP&amp;R'))
    name = model.findtext('Name')
    if name != project_file.stem or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*', name or ''):
        raise ValueError('The .al filename must match the native project Name')
    if (model.findtext('HardWare/Device') != 'PH1A90SEG324' or
            (model.findtext('HardWare/Speed') or '').lstrip('-') != '2'):
        raise ValueError('This server is configured for PH1A90SEG324-2')
    for item in model.findall('.//Source_Files//File'):
        relative = item.get('Path', '')
        candidate = project_file.parent / relative
        if (os.path.isabs(relative) or re.match(r'^[A-Za-z]:', relative) or
                not candidate.resolve().is_relative_to(project_root.resolve()) or not candidate.is_file()):
            raise ValueError('Missing or external registered project input: ' + relative)
    for item in model.findall('.//Option[@Name="IncludeDir"]'):
        candidate = project_file.parent / item.get('Val', '')
        if not candidate.resolve().is_relative_to(project_root.resolve()) or not candidate.is_dir():
            raise ValueError('Missing or external include directory')
    original = text
    text = canonical_project_paths(text, project_file.parent)
    reuse = spec.get('resume', {}).get('checkpoint_level', 0)
    reset = [run for run in project.get('td_reset', [])
             if run == 'syn_1' and not reuse or run == 'phy_1' and reuse < 2]
    text = reset_run_options(text, reset)
    text = re.sub(r'(<Project\b[^>]*\bPath=")[^"]*', r'\g<1>.', text, count=1)
    if text != original:
        atomic_bytes(project_file, text.encode('utf-8'))
    return project_file, name


def build_script(checkout, spec, destination):
    threads = spec['project'].get('seed_threads', {}).get(str(spec['seed']), spec['project']['threads'])
    synthesis_threads = spec['project'].get('synth_threads', threads)
    validate_threads(threads)
    validate_threads(synthesis_threads, 'synth_threads')
    project_file, name = prepare_project(checkout, spec)
    run_root = project_file.parent / (name + '_Runs')
    seed = spec['seed']
    target = spec['project']['target']
    reuse = spec.get('resume', {}).get('checkpoint_level', 0)
    archive = ' '.join(tcl_word(value) for value in
                       (sys.executable, '-I', '-B', Path(__file__).with_name('logs.py').as_posix(),
                        '--job', Path(destination).resolve().parent.as_posix(), '--stage'))
    parameters = parameter_lines(spec['project'], reuse)
    lines = [
        'proc td_set_threads {run requested report} {',
        '    set_param -run $run flow thread $requested',
        '    report_run_param $run -file $report',
        '    set input [open $report r]',
        '    set body [read $input]; close $input',
        '    set effective auto',
        '    foreach line [split $body "\\n"] {',
        '        if {[lrange $line 0 2] eq {set_param flow thread}} {set effective [lindex $line 3]}',
        '    }',
        '    puts "TD_SIMPLE_THREADS $run requested=$requested effective=$effective"; flush stdout',
        '    if {$effective ne $requested} {error "TD thread setting did not take effect for $run: requested=$requested effective=$effective"}',
        '}',
        'proc td_archive {stage run state since} {',
        '    puts [exec ' + archive + ' $stage --run $run --state $state --since $since]',
        '    flush stdout',
        '}',
        'proc td_stage {stage run step marker} {',
        '    set since [clock seconds]',
        '    puts "TD_SIMPLE_STAGE $stage START"; flush stdout',
        '    set code [catch {',
        '        launch_runs -step $step $run',
        '        wait_run $run',
        '        global td_run_root',
        '        set directory [file join $td_run_root $run]',
        '        if {![file isfile [file join $directory $marker]]} {error "TD stage did not finish: $stage"}',
        '        if {[llength [glob -nocomplain -directory $directory .*error.f]]} {error "TD reported a run error: $stage"}',
        '    } message options]',
        '    set state DONE',
        '    if {$code} {set state FAILED}',
        '    if {[catch {td_archive $stage $run $state $since} archive_error]} {',
        '        puts stderr "TD_SIMPLE_LOG_CAPTURE_ERROR $stage: $archive_error"',
        '        if {!$code} {error $archive_error}',
        '    }',
        '    if {$code} {return -options $options $message}',
        '    puts "TD_SIMPLE_STAGE $stage DONE"; flush stdout',
        '}',
        'proc td_build {} {',
        '    global td_run_root',
        '    set td_run_root ' + tcl_word(run_root.as_posix()),
        '    cd ' + tcl_word(project_file.parent.as_posix()),
        '    import_device ph1_90.db -package PH1A90SEG324 -speed 2',
        '    open_project ' + tcl_word(project_file.name) + ' -noanalyze',
        *parameters,
        *(['    td_set_threads syn_1 ' + str(synthesis_threads) + ' ' + tcl_word((Path(destination).resolve().parent / 'thread-syn_1.params').as_posix())] if not reuse else []),
        '    td_set_threads phy_1 ' + str(threads) + ' ' + tcl_word((Path(destination).resolve().parent / 'thread-phy_1.params').as_posix()),
        '    set_param -run phy_1 flow enable_seed off',
        *([f'    set_param -run phy_1 place seed {seed}'] if reuse < 2 else []),
    ]
    if not reuse:
        lines += ['    reset_runs syn_1', '    td_stage synthesis syn_1 opt_gate .opt_gate.end.f']
    else:
        if reuse == 1:
            lines += ['    reset_runs phy_1']
        else:
            lines += ['    reset_runs phy_1 -prev_step'] * spec['resume']['rollback_steps']
        for stage in ('synthesis', 'placement', 'routing')[:reuse]:
            lines += ['    puts "TD_SIMPLE_STAGE ' + stage + ' REUSED"; flush stdout']
    if target != 'synth' and reuse < 2:
        lines += ['    td_stage placement phy_1 opt_place .opt_place.end.f']
    if target not in ('synth', 'place') and reuse < 3:
        lines += ['    td_stage routing phy_1 opt_route .opt_route.end.f']
    if target in ('full', 'bitgen'):
        lines += ['    td_stage bitgen phy_1 bitgen .bitgen.end.f',
                  '    set bit_file [file join $td_run_root phy_1 ' + tcl_word(name + '.bit') + ']',
                  '    if {![file isfile $bit_file] || [file size $bit_file] == 0} {error "TD produced no bitstream"}']
    selected_run = 'syn_1' if target == 'synth' else 'phy_1'
    lines += ['    close_project',
              '    open_project ' + tcl_word(project_file.name) + ' -noanalyze',
              '    open_run ' + selected_run,
              '    puts "TD_SIMPLE_STAGE reports START"; flush stdout',
              '    report_area -io_info -file ' + tcl_word((run_root / selected_run / 'simple.area').as_posix()),
              ('    update_timing' if target == 'synth' else
               '    update_timing -mode ' + ('manhattan' if target == 'place' else 'final')),
              '    report_timing_summary -file ' + tcl_word((run_root / selected_run / 'simple.timing').as_posix()),
              *report_lines(run_root, selected_run, target),
              '    puts "TD_SIMPLE_STAGE reports DONE"; flush stdout',
              '    close_project',
              '    puts "TD_SIMPLE_STAGE reopen START"; flush stdout',
              '    open_project ' + tcl_word(project_file.name) + ' -noanalyze',
              '    open_run ' + selected_run,
              '    close_project',
              '    puts "TD_SIMPLE_STAGE reopen DONE"; flush stdout',
              '}',
              'if {[catch {td_build} td_message td_options]} {',
              '    puts stderr $td_message',
              '    if {[dict exists $td_options -errorinfo]} {puts stderr [dict get $td_options -errorinfo]}',
              '    exit 1',
              '}',
              'puts "TD_SIMPLE_COMPLETE"; flush stdout',
              'exit 0']
    destination = Path(destination)
    atomic_bytes(destination, ('\n'.join(lines) + '\n').encode('utf-8'))
    return project_file, run_root


def stage_status(log):
    result = {name: 'NOT_RUN' for name in ('synthesis', 'placement', 'routing', 'bitgen', 'reports', 'reopen')}
    if Path(log).exists():
        for stage, state in STAGE_PATTERN.findall(Path(log).read_text(encoding='utf-8', errors='replace')):
            result[stage] = 'RUNNING' if state == 'START' else state
    return result


def timing_status(run_root, run=None, not_before=None):
    reports = [Path(run_root) / name / 'simple.timing' for name in
               ([run] if run else ['phy_1', 'syn_1'])]
    report = next((path for path in reports if path.is_file()), None)
    if report is None:
        return {'state': 'NOT_RUN'}
    text = report.read_text(encoding='utf-8', errors='replace')
    values = {}
    for key in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
        match = re.search(r'\b' + key + r'\s*[:=]?\s*([+-]?[0-9]+(?:\.[0-9]+)?)', text)
        if match:
            values[key] = float(match.group(1))
    values['state'] = ('NEGATIVE' if any(value < 0 for value in values.values()) else
                       'NONNEGATIVE_REPORTED' if {'SWNS', 'HWNS'} <= values.keys() else 'REPORT_AVAILABLE')
    if not_before is not None and report.stat().st_mtime < not_before:
        values['state'] = 'STALE'
    values['report'] = str(report)
    return values
