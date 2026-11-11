"""Diagnostic completeness, stale-report handling and large report delivery."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import sys
import tempfile
import time
import tkinter
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'server/td/simple'))
from common import COMMAND_BRANCH, REMOTE, RESULT_BRANCH, SOURCE_BRANCH, atomic_json, encoded, read_json
from client import receive
from reports import DEFINITIONS, clock_tree_info, collect_reports, report_lines


FULL_TREE = '''<clock_summary>
<groups size="1"><clock_group name="clk" endpoints="1"/></groups>
<clock_group name="clk"><clock name="clk"><pin name="clk" inst="">
<model name="lslice" loads="1"><pin name="register.clk"><latency slow_corner="1ps" fast_corner="1ps"/></pin></model>
</pin></clock></clock_group></clock_summary>'''
from service import Controller


class DiagnosticReportsTests(unittest.TestCase):
    def setUp(self):
        directory = ROOT / 'server/td/local/simple-tests'
        directory.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=directory)
        self.job = Path(self.temporary.name)
        self.project = self.job / 'checkout/td_smoke.al'
        shutil.copytree(ROOT / 'server/td/examples/smoke', self.project.parent)
        self.runs = self.project.parent / 'td_smoke_Runs'
        self.started = time.time() - 1
        self.spec = dict(source_commit='a' * 40, seed=1,
                         project=dict(id='tiny', target='full', root='.', al='td_smoke.al', threads=1))

    def tearDown(self):
        self.temporary.cleanup()

    def generate(self, missing=None, fail=None, empty=None, tree_full=True):
        text = '\n'.join(report_lines(self.runs, 'phy_1', 'full'))
        messages = []
        interpreter = tkinter.Tcl()
        interpreter.createcommand('puts', lambda *values: messages.append(' '.join(values)) or '')
        interpreter.createcommand('flush', lambda *values: '')
        interpreter.createcommand('get_clocks', lambda *values: 'clk')
        for name, filename, command, unused in DEFINITIONS:
            if name == missing:
                continue
            def execute(*values, report_id=name, report_filename=filename):
                if report_id == fail:
                    raise tkinter.TclError('native report rejected')
                path = Path(values[-1])
                body = FULL_TREE if report_id == 'clock_tree' and tree_full else '<clock_summary><groups/></clock_summary>' if report_id == 'clock_tree' else 'native report bytes'
                path.write_text('' if report_id == empty else body, encoding='utf-8')
                return ''
            interpreter.createcommand(command.split()[0], execute)
        interpreter.eval(text)
        (self.job / 'td.log').write_text('\n'.join(messages), encoding='utf-8')
        for subrun, filename in [('syn_1', 'td_smoke_rtl.area'), ('syn_1', 'td_smoke_gate.area'),
                                 ('phy_1', 'td_smoke_phy.area'), ('phy_1', 'td_smoke_chk.timing')]:
            path = self.runs / subrun / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('native stage report')
        return collect_reports(self.job, self.spec, self.runs, self.project, self.started)

    def test_complete_reports_include_native_checks_source_and_full_tree_scope(self):
        result = self.generate()
        self.assertEqual(result['state'], 'COMPLETE')
        manifest = read_json(self.job / 'reports.json')
        self.assertEqual(manifest['source_commit'], self.spec['source_commit'])
        self.assertEqual((manifest['endpoints_per_group'], manifest['paths_per_endpoint']), (100, 3))
        tree = next(entry for entry in manifest['files'] if entry['id'] == 'clock_tree')
        self.assertEqual(tree['scope'], 'FULL_TOPOLOGY')
        self.assertEqual((tree['pin_nodes'], tree['expanded_load_pins'], tree['latency_nodes']), (2, 1, 1))
        self.assertEqual({entry['id'] for entry in manifest['native_reports']},
                         {'rtl_area', 'gate_area', 'physical_area', 'check_timing'})

    def test_missing_command_failed_command_and_empty_file_are_not_called_complete(self):
        for changes, report, state in [({'missing': 'noise'}, 'noise', 'UNAVAILABLE'),
                                       ({'fail': 'logic_level'}, 'logic_level', 'FAILED'),
                                       ({'empty': 'path_skew'}, 'path_skew', 'EMPTY')]:
            with self.subTest(changes=changes):
                result = self.generate(**changes)
                self.assertEqual(result['state'], 'PARTIAL')
                entry = next(item for item in read_json(self.job / 'reports.json')['files'] if item['id'] == report)
                self.assertEqual(entry['state'], state)

    def test_summary_only_clock_export_is_explicitly_incomplete(self):
        result = self.generate(tree_full=False)
        self.assertEqual(result['state'], 'PARTIAL')
        self.assertEqual(result['scope_limited'], ['clock_tree'])

    def test_truncated_groups_and_collapsed_loads_are_not_called_full_topology(self):
        path = self.job / 'clock_tree.txt'
        for body in [FULL_TREE.replace('loads="1"', 'loads="2"'),
                     FULL_TREE.replace('<groups size="1">', '<groups size="2"><clock_group name="missing"/>'),
                     FULL_TREE.replace('<clock name="clk">', '<different_clock>').replace('</clock>', '</different_clock>')]:
            with self.subTest(body=body):
                path.write_text(body)
                self.assertEqual(clock_tree_info(path)['scope'], 'TRUNCATED_TOPOLOGY')
        path.write_text('<clock_summary><broken>')
        self.assertEqual(clock_tree_info(path)['scope'], 'UNRECOGNIZED_FORMAT')

    def test_native_logical_endpoint_aliases_do_not_hide_physical_topology(self):
        path = self.job / 'clock_tree.txt'
        path.write_text(FULL_TREE.replace('endpoints="1"', 'endpoints="2"'))
        info = clock_tree_info(path)
        self.assertEqual(info['scope'], 'FULL_TOPOLOGY')
        self.assertEqual((info['declared_endpoints'], info['expanded_load_pins']), (2, 1))

    def test_parent_diagnostics_are_cleared_only_in_the_child_report_directory(self):
        directory = self.runs / 'phy_1/controller-reports'
        directory.mkdir(parents=True)
        (directory / 'noise.csv').write_text('old parent report')
        database = self.runs / 'phy_1/td_smoke_pr.db'
        database.write_bytes(b'keep native DB')
        report_lines(self.runs, 'phy_1', 'synth')
        self.assertFalse((directory / 'noise.csv').exists())
        self.assertEqual(database.read_bytes(), b'keep native DB')

    def test_inherited_native_checks_remain_labelled_inherited(self):
        self.generate()
        native = self.runs / 'phy_1/td_smoke_chk.timing'
        os.utime(native, (self.started - 100, self.started - 100))
        self.spec['resume'] = dict(job='source-parent')
        result = collect_reports(self.job, self.spec, self.runs, self.project, self.started)
        entry = next(item for item in read_json(self.job / 'reports.json')['native_reports'] if item['id'] == 'check_timing')
        self.assertEqual(result['state'], 'COMPLETE')
        self.assertEqual(entry['state'], 'INHERITED')
        self.assertEqual(entry['inherited_from'], 'source-parent')

    def test_forty_five_mib_report_resumes_across_upload_budget_and_downloads_exactly(self):
        root = self.job / 'controller'
        project = dict(id='tiny', root='.', al='tiny.al', target='full', threads=1, seeds=[1])
        atomic_json(root / 'config.json', dict(remote=REMOTE, source_branch=SOURCE_BRANCH,
                    command_branch=COMMAND_BRANCH, result_branch=RESULT_BRANCH,
                    project_manifest='server/td/projects.json', fallback_projects=[project],
                    poll_seconds=60, max_parallel=8))
        controller = Controller(root)
        try:
            controller.store.enqueue(dict(id='large', source_commit='a' * 40, project=project, seed=1))
            job = controller.jobs_root / 'large'
            path = job / 'checkout/tiny_Runs/phy_1/controller-reports/timing_detail.rpt.txt'
            path.parent.mkdir(parents=True)
            with path.open('wb') as stream:
                for number in range(45):
                    stream.write(bytes([number]) * 1024**2)
            atomic_json(job / 'paths.json', dict(run_root=str(job / 'checkout/tiny_Runs')))
            atomic_json(job / 'reports.json', dict(state='COMPLETE', marker='report manifest'))
            controller.store.state('large', 'DONE')
            first, ledger, pending = controller.artifact_plan(budget=32 * 1024**2)
            self.assertGreater(pending, 0)
            atomic_json(root / 'uploaded.json', ledger)
            second, unused, pending = controller.artifact_plan()
            self.assertEqual(pending, 0)
            files = dict(first, **second)
            class Repository:
                def blob(self, commit, name, limit=2 * 1024**2):
                    body = files[name]
                    if len(body) > limit:
                        raise ValueError('chunk limit exceeded')
                    return body
            downloaded = self.job / 'download'
            result = receive(Repository(), 'fixture', 'large', downloaded)
            self.assertEqual(result['pending'], [])
            actual = downloaded / path.relative_to(job)
            with path.open('rb') as a, actual.open('rb') as b:
                self.assertEqual(hashlib.file_digest(a, 'sha256').digest(), hashlib.file_digest(b, 'sha256').digest())
            self.assertEqual(read_json(downloaded / 'reports.json')['marker'], 'report manifest')
        finally:
            for handler in tuple(controller.log.handlers):
                handler.close(); controller.log.removeHandler(handler)


if __name__ == '__main__':
    unittest.main()
