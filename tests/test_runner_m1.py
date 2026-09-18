import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from harness.ir import load_yosys_json
from harness.jobs import JobStore
from harness.runner import run_recovery
from harness.emit import emit_recovered, verify_residual_export


@unittest.skipUnless(shutil.which(os.environ.get('YOSYS','yosys')) and shutil.which(os.environ.get('ABC','yosys-abc')), 'Yosys/ABC required')
class RunnerM1(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.graph = load_yosys_json(Path(__file__).resolve().parents[1]/'examples/harness/full_adder.json')

    def tearDown(self):
        self.tmp.cleanup()

    def run_graph(self, **kwargs):
        return run_recovery(self.graph, self.root, **kwargs)

    def test_resume_validated_proof_without_new_attempt(self):
        first = self.run_graph()
        self.assertTrue(first['whole_design_proven'], first)
        second = self.run_graph()
        self.assertTrue(second['whole_design_proven'], second)
        self.assertTrue(second['candidates'][0]['reused'])
        self.assertNotEqual(first['run_id'], second['run_id'])
        self.assertEqual(first['rtl_sha256'], second['rtl_sha256'])
        with JobStore(self.root/'jobs.sqlite') as jobs:
            self.assertEqual(len(jobs.list_attempts()), 1)
        self.assertEqual(json.loads((self.root/first['run_id']/'report.json').read_text()), first)

    def test_emit_timeout_invalidates_latest_success(self):
        first = self.run_graph()
        self.assertTrue(first['whole_design_proven'], first)
        result = self.run_graph(final_budget_s=0)
        self.assertFalse(result['whole_design_proven'])
        self.assertEqual(result['status'], 'unproven')
        self.assertEqual(result['replaced_cells'], 0)
        self.assertTrue(result['fallback'])
        self.assertEqual([x['status'] for x in result['failures']], ['timeout','timeout'])
        self.assertEqual(json.loads((self.root/'report.json').read_text()), result)
        self.assertTrue(json.loads((self.root/first['run_id']/'report.json').read_text())['whole_design_proven'])

    def test_bad_emitted_rtl_falls_back_to_complete_source(self):
        def corrupt(*args, **kwargs):
            rtl = emit_recovered(*args, **kwargs)
            text = rtl.read_text()
            self.assertIn(' + ', text)
            rtl.write_text(text.replace(' + ', ' ^ '))
            return rtl
        with patch('harness.runner.emit_recovered', side_effect=corrupt):
            result = self.run_graph()
        self.assertTrue(result['whole_design_proven'], result)
        self.assertTrue(result['fallback'])
        self.assertEqual(result['accepted_candidates'], 0)
        self.assertEqual(result['replaced_cells'], 0)
        self.assertEqual(result['retained_source_cells'], 5)
        self.assertEqual(len(result['failures']), 1)

    def test_emit_tool_error_preserved_and_fallback_verified(self):
        with patch('harness.runner.emit_recovered', side_effect=OSError('tool unavailable')):
            result = self.run_graph()
        self.assertTrue(result['whole_design_proven'], result)
        self.assertTrue(result['fallback'])
        self.assertEqual(result['failures'][0]['status'], 'tool_error')
        self.assertEqual(result['replaced_cells'], 0)

    def test_post_proof_edit_cannot_publish_unproved_rtl(self):
        def mutate_after_snapshot(revision, rtl, **kwargs):
            verdict = verify_residual_export(revision, rtl, **kwargs)
            if ' + ' in rtl.read_text():
                rtl.write_text(rtl.read_text().replace(' + ', ' ^ '))
            return verdict
        with patch('harness.runner.verify_residual_export', side_effect=mutate_after_snapshot):
            result = self.run_graph()
        self.assertTrue(result['whole_design_proven'], result)
        self.assertTrue(result['fallback'])
        self.assertEqual(result['replaced_cells'], 0)
        self.assertIn('differs from proven snapshot', result['failures'][0]['reason'])
        proof = json.loads(Path(result['verification']).read_text())
        self.assertEqual(result['rtl_sha256'], proof['rtl_sha256'])
        self.assertEqual(Path(result['rtl']).name, 'candidate.v')

    def test_tampered_cached_evidence_reproved(self):
        first = self.run_graph()
        self.assertTrue(first['whole_design_proven'], first)
        with JobStore(self.root/'jobs.sqlite') as jobs:
            record = Path(jobs.list_attempts()[0]['result']['proof_record'])
        record.write_text('{}')
        second = self.run_graph()
        self.assertTrue(second['whole_design_proven'], second)
        self.assertFalse(second['candidates'][0]['reused'])
        with JobStore(self.root/'jobs.sqlite') as jobs:
            self.assertEqual(len(jobs.list_attempts()), 2)

    def test_unexpected_worker_exception_never_leaves_success(self):
        first = self.run_graph()
        self.assertTrue(first['whole_design_proven'], first)
        with patch('harness.runner.propose_full_adders', side_effect=RuntimeError('fault injection')):
            result = self.run_graph()
        self.assertEqual(result['status'], 'runner_error')
        self.assertFalse(result['whole_design_proven'])
        self.assertEqual(json.loads((self.root/'report.json').read_text()), result)


if __name__ == '__main__':
    unittest.main()
