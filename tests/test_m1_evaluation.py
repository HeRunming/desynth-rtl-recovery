import json
import tempfile
import unittest
from pathlib import Path

from scripts.evaluate_harness_m1 import evaluate


class M1EvaluationTest(unittest.TestCase):
    def test_fixture_report_tracks_residual_and_proof(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "fa.json"
            p.write_text(Path("examples/harness/full_adder.json").read_text())
            row = evaluate(p, "opaque_top", 17)
            self.assertEqual(row["candidate_count"], 1)
            self.assertEqual(row["proven_count"], 1)
            self.assertEqual(row["recovery"]["residual_cells"], 0)
            self.assertTrue(row["recovery"]["cell_ownership_closed"])


if __name__ == "__main__": unittest.main()
