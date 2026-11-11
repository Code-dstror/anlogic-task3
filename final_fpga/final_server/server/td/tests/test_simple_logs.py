"""Raw phase log retention, partial termination and honest warning indexing."""
from __future__ import annotations

import csv
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TEST_TEMP = ROOT / 'server/td/local/simple-tests'
TEST_TEMP.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / 'server/td/simple'))
from common import atomic_json
from logs import capture_stage, finalize_logs, summarize_warnings
from flow import timing_status


class LogCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=TEST_TEMP)
        self.job = Path(self.temporary.name)
        self.project = self.job / 'checkout/project/camera.al'
        self.project.parent.mkdir(parents=True)
        self.project.write_text('<Project/>')
        self.runs = self.project.parent / 'camera_Runs'
        self.native = self.runs / 'phy_1'
        self.native.mkdir(parents=True)
        atomic_json(self.job / 'paths.json', dict(project=str(self.project), run_root=str(self.runs)))

    def tearDown(self):
        self.temporary.cleanup()

    def test_archives_are_immutable_and_do_not_include_databases_or_bits(self):
        (self.native / 'run.log').write_bytes(b'placement original\n' * 10000)
        (self.native / 'run.logw').write_bytes(b'\xff\x00raw native companion\n')
        (self.native / 'camera_pr.db').write_bytes(b'database stays on server')
        (self.native / 'camera.bit').write_bytes(b'bit uses the normal exporter')
        captured = capture_stage(self.job, 'placement', 'phy_1', 'DONE')
        self.assertEqual(captured['errors'], [])
        (self.native / 'run.log').write_bytes(b'now route\n')
        capture_stage(self.job, 'placement', 'phy_1', 'DONE')
        archive = self.job / 'stage-logs/placement/phy_1'
        self.assertEqual((archive / 'run.log').read_bytes(), b'placement original\n' * 10000)
        self.assertEqual((archive / 'run.logw').read_bytes(), b'\xff\x00raw native companion\n')
        self.assertFalse((archive / 'camera_pr.db').exists())
        self.assertFalse((archive / 'camera.bit').exists())

    def test_terminal_capture_preserves_cancelled_route_and_project_messages(self):
        body = b'ROUTE-1234 WARNING: partial route\n' * 5000
        (self.native / 'run.log').write_bytes(body)
        (self.native / 'route.messages').write_bytes(b'raw native message payload\n')
        (self.project.parent / 'td_20261022.logw').write_bytes(b'project-wide raw log\n')
        (self.job / 'td.log').write_text('TD_SIMPLE_STAGE synthesis REUSED\nTD_SIMPLE_STAGE routing START\n')
        captured = finalize_logs(self.job, 'CANCELLED')
        self.assertEqual(captured['state'], 'CAPTURED')
        self.assertEqual((self.job / 'stage-logs/routing/phy_1/run.log').read_bytes(), body)
        self.assertEqual((self.job / 'stage-logs/terminal/phy_1/run.log').read_bytes(), body)
        metadata = json.loads((self.job / 'stage-logs/routing/capture.json').read_text())
        self.assertEqual(metadata['state'], 'CANCELLED')
        self.assertTrue((self.job / 'stage-logs/terminal/project/td_20261022.logw').exists())

    def test_warning_csv_keeps_source_line_code_and_suppression_notice(self):
        (self.native / 'run.log').write_text('header\nTMR-5506 CRITICAL-WARNING: async reset\n'
                                             'HDL-5007 WARNING: Similar messages will be suppressed\n')
        capture_stage(self.job, 'routing', 'phy_1', 'DONE')
        summary = summarize_warnings(self.job)
        self.assertEqual(summary['visible_warning_occurrences'], 2)
        self.assertEqual(summary['suppression_notices'], 1)
        self.assertFalse(summary['warning_inventory_complete'])
        with (self.job / 'warnings.csv').open(encoding='utf-8', newline='') as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(rows[0]['code'], 'TMR-5506')
        self.assertEqual(rows[0]['line'], '2')
        self.assertEqual(rows[0]['severity'], 'CRITICAL-WARNING')
        self.assertEqual(rows[1]['line'], '3')

    def test_reused_or_old_log_is_not_claimed_to_have_been_generated_in_this_stage(self):
        (self.native / 'run.log').write_bytes(b'old native log\n')
        captured = capture_stage(self.job, 'routing', 'phy_1', 'FAILED', since=9999999999)
        self.assertTrue(captured['files'][0]['predates_stage'])

    def test_successful_linux_critical_check_is_not_a_warning_but_real_issues_remain(self):
        body = ('RUN-0008 : Do critical warning check and 0 issue(s) found.\n'
                'RUN-0008 : Do critical warning check and 1 issue(s) found.\n'
                'TMR-5506 CRITICAL-WARNING: async reset\n')
        (self.native / 'run.log').write_text(body)
        capture_stage(self.job, 'routing', 'phy_1', 'DONE')
        summary = summarize_warnings(self.job)
        self.assertEqual(summary['visible_warning_occurrences'], 2)
        with (self.job / 'warnings.csv').open(encoding='utf8', newline='') as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual([row['line'] for row in rows], ['2', '3'])
        self.assertEqual([row['code'] for row in rows], ['RUN-0008', 'TMR-5506'])
        self.assertEqual((self.job / 'stage-logs/routing/phy_1/run.log').read_text(), body)

    def test_binary_message_companions_are_preserved_without_claiming_a_text_warning_count(self):
        body = b'\0HDL-5007 WARNING: binary payload\xff'
        (self.native / 'run.logw').write_bytes(body)
        capture_stage(self.job, 'routing', 'phy_1', 'DONE')
        summary = summarize_warnings(self.job)
        self.assertEqual(summary['visible_warning_occurrences'], 0)
        self.assertFalse(summary['files'][0]['indexed_as_text'])
        self.assertEqual((self.job / 'stage-logs/routing/phy_1/run.logw').read_bytes(), body)

    def test_raw_logw_keeps_warnings_suppressed_in_the_short_console_log(self):
        (self.native / 'run.log').write_text('HDL-5007 WARNING: Similar messages will be suppressed\n')
        body = 'HDL-5007 WARNING: concrete instance ' + ('x' * 120) + '\n'
        (self.native / 'run.logw').write_text(body * 20001)
        capture_stage(self.job, 'routing', 'phy_1', 'DONE')
        summary = summarize_warnings(self.job)
        raw = next(item for item in summary['files'] if item['path'].endswith('run.logw'))
        self.assertEqual(raw['visible_warning_lines'], 20001)
        self.assertEqual(raw['suppression_notices'], 0)
        self.assertEqual(summary['suppression_notices'], 1)
        self.assertEqual((self.job / 'stage-logs/routing/phy_1/run.logw').read_text(), body * 20001)

    def test_phase_commands_parameters_and_status_are_saved_as_data(self):
        contents = {'camera.tcl': 'TD generated stage commands\n', 'run.sh': 'TD launch script\n',
                    'route_qor_suggestion.tcl': 'set_param route post_route_opt high\n',
                    'route.params': 'route step parameters\n', 'flow.status': 'route flow statistics\n'}
        for name, text in contents.items():
            (self.native / name).write_text(text)
        capture_stage(self.job, 'routing', 'phy_1', 'DONE')
        for name, text in contents.items():
            self.assertEqual((self.job / 'stage-logs/routing/phy_1' / name).read_text(), text)

    def test_external_native_path_is_rejected(self):
        atomic_json(self.job / 'paths.json', dict(run_root=str(self.job.parent / 'outside')))
        with self.assertRaises(ValueError):
            capture_stage(self.job, 'routing', 'phy_1', 'FAILED')

    def test_physical_timing_is_not_replaced_by_the_inherited_shared_synthesis_report(self):
        synthesis = self.runs / 'syn_1'
        synthesis.mkdir()
        (synthesis / 'simple.timing').write_text('SWNS: 39.154 STNS: 0 HWNS: 0 HTNS: 0')
        (self.native / 'simple.timing').write_text('SWNS: -6.5 STNS: -14 HWNS: -3 HTNS: -49')
        self.assertEqual(timing_status(self.runs)['SWNS'], -6.5)
        self.assertEqual(timing_status(self.runs, 'phy_1')['state'], 'NEGATIVE')
        self.assertEqual(timing_status(self.runs, 'syn_1')['SWNS'], 39.154)

    def test_missing_physical_report_does_not_fall_back_to_an_inherited_synthesis_success(self):
        synthesis = self.runs / 'syn_1'
        synthesis.mkdir()
        (synthesis / 'simple.timing').write_text('SWNS: 39.154 STNS: 0 HWNS: 0 HTNS: 0')
        self.assertEqual(timing_status(self.runs, 'phy_1'), {'state': 'NOT_RUN'})

    def test_failed_continuation_does_not_present_an_inherited_timing_report_as_current(self):
        report = self.native / 'simple.timing'
        report.write_text('SWNS: 1 STNS: 0 HWNS: 1 HTNS: 0')
        os.utime(report, (1, 1))
        self.assertEqual(timing_status(self.runs, 'phy_1', not_before=2)['state'], 'STALE')


if __name__ == '__main__':
    unittest.main()
