"""Verify remote strategy/reset semantics and checkpoint invalidation."""
from __future__ import annotations

from pathlib import Path
import shutil
import sys
import tempfile
import tkinter
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'server/td/simple'))
from common import atomic_json, project_config
from checkpoints import continuation
from flow import build_script
from run_options import parameter_lines, reset_run_options, validate_run_options


class NativeRunOptionsTests(unittest.TestCase):
    def setUp(self):
        output = ROOT / 'server/td/local/simple-tests'
        output.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=output)
        self.root = Path(self.temporary.name)
        self.checkout = self.root / 'parent/checkout'
        shutil.copytree(ROOT / 'server/td/examples/smoke', self.checkout)
        self.project = project_config(dict(id='camera', root='.', al='td_smoke.al', watch=['td_smoke.v'],
                                            threads=8, seeds=[1], target='full'))
        self.parent = dict(id='parent', state='DONE', spec=dict(project=self.project, seed=1))
        self.runs = self.checkout / 'td_smoke_Runs'
        for run, suffix, step in [('syn_1', 'gate', 'opt_gate'), ('phy_1', 'place', 'opt_place'),
                                   ('phy_1', 'pr', 'opt_route')]:
            directory = self.runs / run
            directory.mkdir(parents=True, exist_ok=True)
            (directory / ('td_smoke_' + suffix + '.db')).write_bytes(b'native fixture')
            (directory / ('.' + step + '.end.f')).touch()
        atomic_json(self.root / 'parent/result.json', dict(stages={
            'synthesis': 'DONE', 'placement': 'DONE', 'routing': 'DONE', 'bitgen': 'DONE'}))

    def tearDown(self):
        self.temporary.cleanup()

    def test_strategy_and_reset_invalidate_only_required_checkpoints(self):
        for changes, expected in [({'td_strategies': {'phy_1': 'TimingHigh'}}, 1),
                                   ({'td_strategies': {'syn_1': 'RuntimeOptimize'}}, 0),
                                   ({'td_reset': ['phy_1']}, 1), ({'td_reset': ['syn_1']}, 0),
                                   ({'td_options': {'phy_1': {'route': {'effort': 'high'}}}}, 2),
                                   ({'td_options': {'phy_1': {'bitgen': {'compress': 'on'}}}}, 3)]:
            with self.subTest(changes=changes):
                project, resume = continuation(self.parent, self.root, 'full', 1, changes)
                self.assertEqual(resume['checkpoint_level'], expected)
                self.assertEqual(self.parent['spec']['project'], self.project)

    def test_parent_reset_is_not_repeated_by_bitgen_continuation(self):
        self.project.update(td_reset=['syn_1', 'phy_1'], td_strategies={'phy_1': 'TimingHigh'},
                            td_options={'phy_1': {'route': {'post_route_opt': 'medium'}}})
        project, resume = continuation(self.parent, self.root, 'bitgen', 1, {})
        self.assertNotIn('td_reset', project)
        self.assertEqual(resume['checkpoint_level'], 3)
        self.assertEqual(project['td_options'], self.project['td_options'])
        self.assertEqual(parameter_lines(project, 3), [
            '    puts "TD_SIMPLE_PROPERTY \\"phy_1\\" \\"route\\" \\"post_route_opt\\" \\"medium\\""',
            '    set_param -run "phy_1" "route" "post_route_opt" "medium"'])

    def test_reset_clears_inherited_overrides_then_applies_new_properties(self):
        self.project.update(td_strategies={'phy_1': 'TimingHigh'},
                            td_options={'phy_1': {'place': {'effort': 'high'}, 'route': {'effort': 'high'}},
                                        'syn_1': {'rtl': {'min_control_set': 2}}})
        project, resume = continuation(self.parent, self.root, 'full', 1, dict(
            td_reset=['phy_1'], td_strategies={'phy_1': 'RuntimeOptimize'},
            td_options={'phy_1': {'route': {'post_route_opt': 'medium'}}}))
        self.assertEqual(project['td_options']['phy_1'], {'route': {'post_route_opt': 'medium'}})
        self.assertEqual(project['td_options']['syn_1'], self.project['td_options']['syn_1'])
        self.assertEqual(project['td_strategies']['phy_1'], 'RuntimeOptimize')
        self.assertEqual(resume['checkpoint_level'], 1)
        with self.assertRaisesRegex(ValueError, 'invalidate routing'):
            continuation(self.parent, self.root, 'bitgen', 1, {'td_reset': ['phy_1']})

    def test_job_local_reset_preserves_sources_and_unselected_native_run(self):
        source = self.checkout / 'td_smoke.al'
        text = source.read_text()
        text = text.replace('<PlaceProperty>', '<PlaceProperty><effort>high</effort>')
        text = text.replace('<UserParams></UserParams>', '<UserParams><param>set_param gate mapper_effort low</param></UserParams>', 1)
        source.write_text(text)
        reset = reset_run_options(text, ['phy_1'])
        model = ET.fromstring(reset.replace('UsedInP&R', 'UsedInP&amp;R'))
        self.assertEqual(model.findtext("Runs/Run[@Name='syn_1']/UserParams/param"), 'set_param gate mapper_effort low')
        self.assertEqual(model.find("Runs/Run[@Name='phy_1']/Strategy").get('Name'), 'Default_PhysicalDesign_Strategy')
        self.assertIsNone(model.find("Runs/Run[@Name='phy_1']/Strategy/PlaceProperty"))
        self.assertIn('<File Path="td_smoke.v">', reset)
        self.assertEqual(source.read_text(), text)
        with self.assertRaisesRegex(ValueError, 'missing native runs'):
            reset_run_options('<Project/>', ['syn_1'])

    def test_script_orders_strategy_overrides_and_separate_native_thread_counts(self):
        self.project.update(threads=8, synth_threads=32, td_reset=['phy_1'],
                            td_strategies={'phy_1': 'TimingHigh'},
                            td_options={'phy_1': {'route': {'post_route_opt': 'medium'}}})
        spec = dict(project=self.project, seed=1)
        script = self.root / 'build.tcl'
        build_script(self.checkout, spec, script)
        text = script.read_text()
        self.assertLess(text.index('set_strategy -run'), text.index('set_param -run "phy_1" "route"'))
        self.assertIn('td_set_threads syn_1 32 ', text)
        self.assertIn('td_set_threads phy_1 8 ', text)
        self.assertEqual(tkinter.Tcl().eval('info complete {' + text + '}'), '1')

    def test_shared_synthesis_does_not_reset_reused_synthesis_options(self):
        source = self.checkout / 'td_smoke.al'
        text = source.read_text().replace('<UserParams></UserParams>',
                '<UserParams><param>set_param gate mapper_effort low</param></UserParams>', 1)
        source.write_text(text)
        self.project.update(td_reset=['syn_1', 'phy_1'], td_strategies={'syn_1': 'RuntimeOptimize'})
        script = self.root / 'build.tcl'
        build_script(self.checkout, dict(project=self.project, seed=1, resume={'checkpoint_level': 1}), script)
        self.assertIn('set_param gate mapper_effort low', source.read_text())
        self.assertNotIn('set_strategy -run "syn_1"', script.read_text())
        self.assertNotIn('td_set_threads syn_1 ', script.read_text())

    def test_thread_readback_detects_auto_fallback_and_keeps_the_native_record(self):
        script = self.root/'thread-check.tcl'
        build_script(self.checkout,dict(project=self.project,seed=1),script)
        interpreter=tkinter.Tcl()
        interpreter.eval(script.read_text().split('proc td_archive',1)[0])
        interpreter.createcommand('set_param',lambda *values:'')
        actual=['auto']
        def report(run,flag,path):
            Path(path).write_text('set_param flow thread '+actual[0]+'\n')
            return ''
        interpreter.createcommand('report_run_param',report)
        output=self.root/'thread-phy_1.params'
        with self.assertRaisesRegex(tkinter.TclError,'did not take effect'):
            interpreter.call('td_set_threads','phy_1','8',output.as_posix())
        self.assertEqual(output.read_text(),'set_param flow thread auto\n')
        actual[0]='8'
        interpreter.call('td_set_threads','phy_1','8',output.as_posix())

    def test_invalid_native_threads_are_rejected_before_project_or_script_mutation(self):
        original=(self.checkout/'td_smoke.al').read_bytes()
        self.project['threads']=12
        script=self.root/'invalid.tcl'
        with self.assertRaises(ValueError):
            build_script(self.checkout,dict(project=self.project,seed=1),script)
        self.assertFalse(script.exists())
        self.assertEqual((self.checkout/'td_smoke.al').read_bytes(),original)

    def test_scalar_lists_are_tcl_data_and_hook_fields_still_rejected(self):
        values = ['A=1', 'B=spaces here', 'C=[error injected]', 'D=$token', 'E=one;error injected', True, 3]
        project = dict(td_options={'syn_1': {'rtl': {'verilog_defines': values}}})
        validate_run_options(project)
        line = parameter_lines(project, 0)[-1].strip()
        interpreter = tkinter.Tcl()
        interpreter.eval('proc set_param {args} {set ::captured $args}')
        interpreter.eval(line)
        captured = interpreter.splitlist(interpreter.eval('set ::captured'))
        self.assertEqual(interpreter.splitlist(captured[-1]), tuple(values[:-2] + ['on', '3']))
        for field in ({'td_options': {'phy_1': {'flow': {'thread': 32}}}},
                      {'td_options': {'phy_1': {'place': {'tcl_beforestep': 'exec bad'}}}},
                      {'td_reset': ['phy_1', 'phy_1']}, {'td_reset': [{}]},
                      {'td_strategies': {'phy_2': 'TimingHigh'}},
                      {'td_options': {'phy_1': {'route': {'effort': [[1]]}}}}):
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_run_options(field)


if __name__ == '__main__':
    unittest.main()
