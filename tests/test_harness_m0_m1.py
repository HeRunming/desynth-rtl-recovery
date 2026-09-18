import copy
import json
import tempfile
import unittest
import shutil
from pathlib import Path

from harness.candidate import Candidate
from harness.detect import propose_full_adders
from harness.ir import SourceGraph, sha256_json
from harness.proof import ProofStatus, prove_abc, prove_exhaustive
from harness.recovery import RecoveryRevision


def full_adder_json():
    # Deliberately opaque instance/net names.  This is also the smallest
    # deterministic structural detector fixture: two XOR, two AND, one OR.
    cells = {
        "u_x1": {"type": "$xor", "port_directions": {"A": "input", "B": "input", "Y": "output"}, "connections": {"A": [10], "B": [11], "Y": [20]}},
        "u_x2": {"type": "$xor", "port_directions": {"A": "input", "B": "input", "Y": "output"}, "connections": {"A": [20], "B": [12], "Y": [21]}},
        "u_a1": {"type": "$and", "port_directions": {"A": "input", "B": "input", "Y": "output"}, "connections": {"A": [10], "B": [11], "Y": [22]}},
        "u_a2": {"type": "$and", "port_directions": {"A": "input", "B": "input", "Y": "output"}, "connections": {"A": [20], "B": [12], "Y": [23]}},
        "u_or": {"type": "$or", "port_directions": {"A": "input", "B": "input", "Y": "output"}, "connections": {"A": [22], "B": [23], "Y": [24]}},
    }
    return {"modules": {"opaque_top": {"ports": {
        "in_a": {"direction": "input", "bits": [10]}, "in_b": {"direction": "input", "bits": [11]}, "in_c": {"direction": "input", "bits": [12]},
        "sum_out": {"direction": "output", "bits": [21]}, "carry_out": {"direction": "output", "bits": [24]},
    }, "cells": cells, "netnames": {}}}}


class HarnessM0M1(unittest.TestCase):
    def setUp(self):
        self.graph = SourceGraph.from_yosys_json(full_adder_json(), "opaque_top")

    def test_anonymization_is_deterministic_and_hides_names(self):
        public1, private1 = self.graph.anonymize(seed=17, hide_ports=True)
        public2, private2 = self.graph.anonymize(seed=17, hide_ports=True)
        self.assertEqual(public1, public2)
        self.assertEqual(private1["public_hash"], private2["public_hash"])
        text = json.dumps(public1)
        for name in ("opaque_top", "u_x1", "u_or", "sum_out"):
            self.assertNotIn(name, text)
        self.assertNotEqual(self.graph.source_hash, sha256_json(public1))

    def test_detector_and_proof_accept_full_adder(self):
        candidates = propose_full_adders(self.graph)
        self.assertEqual(len(candidates), 1)
        result = prove_exhaustive(self.graph, candidates[0])
        self.assertEqual(result.status, ProofStatus.PROVEN)
        self.assertEqual(result.checked_cases, 8)

    @unittest.skipUnless(Path("/Users/blackbox/try_hai/oss-cad-suite/bin/yosys").is_file(), "Yosys toolchain unavailable")
    def test_abc_proof_backend_accepts_candidate(self):
        candidate = propose_full_adders(self.graph)[0]
        with tempfile.TemporaryDirectory() as td:
            result = prove_abc(self.graph, candidate, artifact_dir=td, timeout_s=20)
            self.assertEqual(result.status, ProofStatus.PROVEN, result.reason)
            self.assertTrue((Path(td) / "abc.log").exists())

    def test_counterexample_timeout_and_transaction_safety(self):
        candidate = propose_full_adders(self.graph)[0]
        bad = copy.deepcopy(candidate)
        bad.output_bits = (candidate.output_bits[1], candidate.output_bits[0])
        rejected = prove_exhaustive(self.graph, bad)
        self.assertEqual(rejected.status, ProofStatus.COUNTEREXAMPLE)
        timed = prove_exhaustive(self.graph, candidate, timeout_s=0.0)
        self.assertEqual(timed.status, ProofStatus.TIMEOUT)

        revision = RecoveryRevision(self.graph)
        self.assertEqual(revision.residual_manifest()["residual_cells"], 5)
        accepted = revision.accept(candidate, prove_exhaustive(self.graph, candidate))
        self.assertEqual(accepted.residual_manifest()["replaced_cells"], 5)
        self.assertEqual(accepted.residual_manifest()["residual_cells"], 0)
        with self.assertRaises(ValueError):
            accepted.accept(candidate, prove_exhaustive(self.graph, candidate))
        rolled = accepted.rollback()
        self.assertEqual(rolled.revision, 0)
        self.assertEqual(rolled.residual_manifest()["residual_cells"], 5)
        with tempfile.TemporaryDirectory() as td:
            manifest = accepted.export(td)
            self.assertTrue(Path(manifest).exists())
            self.assertTrue((Path(td) / "source_graph.json").exists())
            self.assertTrue((Path(td) / "semantic_overlay.json").exists())

    def test_source_hash_binding_rejects_stale_candidate(self):
        candidate = propose_full_adders(self.graph)[0]
        candidate.source_hash = "stale"
        result = prove_exhaustive(self.graph, candidate)
        self.assertEqual(result.status, ProofStatus.MODEL_ERROR)


if __name__ == "__main__":
    unittest.main()
