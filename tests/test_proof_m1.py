"""Acceptance must depend on evidence, never a caller-created PROVEN flag."""
import copy
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import unittest

from harness.candidate import Candidate
from harness.ir import SourceGraph
from harness.proof import (ProofResult, ProofStatus, ProofStore, _abc_status,
                           _eval_bit, _run, _scalar_cell, prove_abc,
                           prove_exhaustive, verify_proof_evidence)


def fixture(primitive=False):
    cells = {}
    for name, kind, a, b, y in [
        ("n0", "xor", 0, 1, 5), ("n1", "xor", 5, 2, 6),
        ("n2", "and", 0, 1, 7), ("n3", "and", 5, 2, 8),
        ("n4", "or", 7, 8, 9),
    ]:
        cells[name] = {"type": f"$_{kind.upper()}_" if primitive else "$" + kind,
                       "connections": {"A": [a + 10], "B": [b + 10], "Y": [y + 10]},
                       "port_directions": {"A": "input", "B": "input", "Y": "output"}}
    data = {"modules": {"top": {"cells": cells, "netnames": {}, "ports": {
        "i": {"direction": "input", "bits": [10, 11, 12]},
        "o": {"direction": "output", "bits": [16, 19]},
    }}}}
    graph = SourceGraph.from_yosys_json(data, "top")
    return graph, Candidate("fa", graph.source_hash, tuple(cells), (10, 11, 12), (16, 19), "full_adder")


class ProofM1(unittest.TestCase):
    def test_integer_zero_and_one_are_variables(self):
        self.assertEqual(_eval_bit(0, {0: 1}, {}, set(), {}), 1)
        self.assertEqual(_eval_bit(1, {1: 0}, {}, set(), {}), 0)
        self.assertEqual(_eval_bit("0", {}, {}, set(), {}), 0)
        self.assertEqual(_eval_bit("1", {}, {}, set(), {}), 1)
        with self.assertRaises(ValueError): _eval_bit("x", {}, {}, set(), {})

    def test_scalar_domain_and_primitives(self):
        for primitive in (False,):
            graph, candidate = fixture(primitive)
            proof = prove_exhaustive(graph, candidate)
            self.assertEqual(proof.status, ProofStatus.PROVEN, proof.reason)
            self.assertTrue(verify_proof_evidence(graph, candidate, proof))
        primitive_graph, _ = fixture(True)
        self.assertEqual(_scalar_cell(primitive_graph.module()["cells"]["n0"]), "^")
        cell = graph.module()["cells"]["n0"]
        for kind in ("$pmux", "$logic_not", "$add", "$xor"):
            bad = copy.deepcopy(cell); bad["type"] = kind
            if kind == "$xor": bad["connections"]["A"] = [0, 1]
            with self.assertRaises(ValueError): _scalar_cell(bad)

    def test_forged_status_and_truth_table_rejected(self):
        graph, candidate = fixture()
        fake = ProofResult(ProofStatus.PROVEN, candidate.candidate_hash, "exhaustive", 8, source_hash=graph.source_hash)
        self.assertFalse(verify_proof_evidence(graph, candidate, fake))
        proof = prove_exhaustive(graph, candidate)
        proof.artifact["truth_table"][0]["actual"][0] ^= 1
        self.assertFalse(verify_proof_evidence(graph, candidate, proof))

    def test_all_attempts_survive_and_loading_checks_files(self):
        graph, candidate = fixture()
        with tempfile.TemporaryDirectory() as td:
            proof = prove_exhaustive(graph, candidate, artifact_dir=Path(td) / "proof")
            store = ProofStore(Path(td) / "store")
            first, second = store.save(proof), store.save(proof)
            self.assertNotEqual(first, second)
            self.assertTrue(verify_proof_evidence(graph, candidate, store.load(first)))
            (Path(proof.artifact["dir"]) / "truth_table.json").write_text("[]")
            with self.assertRaises(ValueError): store.load(first)
            self.assertFalse(verify_proof_evidence(graph, candidate, proof))

    def test_abc_verdict_is_anchored_and_exit_code_required(self):
        self.assertEqual(_abc_status("Networks are equivalent. Time = 0.01 sec\n", 0), ProofStatus.PROVEN)
        self.assertEqual(_abc_status("Networks are NOT EQUIVALENT.\n", 0), ProofStatus.COUNTEREXAMPLE)
        for log in ("not sure if equivalent", "echo Networks are equivalent.", "Networks are equivalent.\nUNDECIDED", "Networks are equivalent. garbage"):
            self.assertNotEqual(_abc_status(log, 0), ProofStatus.PROVEN)
        self.assertEqual(_abc_status("Networks are equivalent.\n", 7), ProofStatus.TOOL_ERROR)

    def test_timeout_persists_partial_logs_and_reaps_process(self):
        import subprocess
        import sys
        with tempfile.TemporaryDirectory() as td:
            records = []
            with self.assertRaises(subprocess.TimeoutExpired):
                _run([sys.executable, "-u", "-c", "import time; print('before timeout'); time.sleep(60)"], Path(td), "slow", time.monotonic() + 0.15, records)
            self.assertIn("before timeout", (Path(td) / "slow.stdout").read_text())
            self.assertTrue(records[0]["timeout"])
            self.assertIsNotNone(records[0]["returncode"])

    def test_model_rejection_and_budget_exhaustion(self):
        graph, candidate = fixture()
        bad_data = graph.data
        bad_data["modules"]["top"]["cells"]["n0"]["type"] = "$pmux"
        bad_graph = SourceGraph.from_yosys_json(bad_data, "top")
        candidate.source_hash = bad_graph.source_hash
        self.assertEqual(prove_exhaustive(bad_graph, candidate).status, ProofStatus.MODEL_ERROR)
        graph, candidate = fixture()
        self.assertEqual(prove_exhaustive(graph, candidate, timeout_s=0).status, ProofStatus.TIMEOUT)
        with tempfile.TemporaryDirectory() as td:
            tool = Path(td) / "sleeping_yosys"
            tool.write_text(f"#!{sys.executable}\nimport time\nprint('starting', flush=True)\ntime.sleep(60)\n")
            tool.chmod(0o700)
            result = prove_abc(graph, candidate, yosys=str(tool), abc="/usr/bin/true", timeout_s=1.0, artifact_dir=Path(td) / "evidence")
            self.assertEqual(result.status, ProofStatus.TIMEOUT)
            root = Path(result.artifact["dir"])
            self.assertTrue((root / "result.json").exists())
            self.assertIn("starting", (root / "yosys_version.stdout").read_text())
            self.assertTrue(result.artifact["processes"][0]["timeout"])

    def test_unknown_tools_and_deadline_are_persisted(self):
        graph, candidate = fixture()
        with tempfile.TemporaryDirectory() as td:
            proof = prove_abc(graph, candidate, yosys="/nonexistent/yosys", artifact_dir=td)
            self.assertEqual(proof.status, ProofStatus.TOOL_ERROR)
            self.assertTrue((Path(proof.artifact["dir"]) / "result.json").is_file())

    @unittest.skipUnless(os.environ.get("YOSYS") or shutil.which("yosys"), "set YOSYS and ABC for real EDA proof")
    def test_real_abc_and_tamper_detection(self):
        graph, candidate = fixture()
        with tempfile.TemporaryDirectory() as td:
            proof = prove_abc(graph, candidate, artifact_dir=td)
            self.assertEqual(proof.status, ProofStatus.PROVEN, proof.reason)
            self.assertTrue(verify_proof_evidence(graph, candidate, proof))
            bad = copy.deepcopy(candidate); bad.output_bits = tuple(reversed(bad.output_bits))
            negative = prove_abc(graph, bad, artifact_dir=td)
            self.assertEqual(negative.status, ProofStatus.COUNTEREXAMPLE, negative.reason)
            self.assertNotEqual(proof.artifact["dir"], negative.artifact["dir"])
            self.assertTrue(verify_proof_evidence(graph, candidate, proof))
            (Path(proof.artifact["dir"]) / "gate.aig").write_bytes(b"corrupted")
            self.assertFalse(verify_proof_evidence(graph, candidate, proof))


if __name__ == "__main__":
    unittest.main()
