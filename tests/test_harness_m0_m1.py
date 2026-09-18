import copy
import json
import os
import stat
import tempfile
import unittest
import shutil
from pathlib import Path

from harness.candidate import Candidate
from harness.detect import propose_full_adders
from harness.emit import emit_residual, verify_residual_export
from harness.ir import SourceGraph, sha256_json
from harness.proof import ProofStatus, prove_abc, prove_exhaustive
from harness.recovery import RecoveryRevision


def full_adder_json():
    return json.loads((Path(__file__).resolve().parents[1] / "examples/harness/full_adder.json").read_text())


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
        self.graph.data["modules"]["opaque_top"]["cells"]["u_x1"]["type"] = "$and"
        self.assertEqual(propose_full_adders(self.graph)[0].operation, "full_adder")

    def test_anonymization_preserves_constants(self):
        data = full_adder_json()
        data["modules"]["opaque_top"]["cells"]["u_const"] = {
            "type": "$and", "port_directions": {"A": "input", "B": "input", "Y": "output"},
            "connections": {"A": ["0"], "B": [10], "Y": [30]},
        }
        graph = SourceGraph.from_yosys_json(data, "opaque_top")
        public, _ = graph.anonymize(seed=3, hide_ports=True)
        const_cell = next(c for c in public["modules"]["top_0"]["cells"].values() if c["connections"].get("A") == ["0"])
        self.assertEqual(const_cell["connections"]["A"], ["0"])

    def test_anonymization_remaps_orphan_netname_bits(self):
        data = full_adder_json(); data["modules"]["opaque_top"]["netnames"] = {"orphan": {"bits": [999]}}
        graph = SourceGraph.from_yosys_json(data, "opaque_top")
        public, _ = graph.anonymize(seed=3, hide_ports=True)
        self.assertNotIn("999", json.dumps(public))

    def test_detector_and_proof_accept_full_adder(self):
        candidates = propose_full_adders(self.graph)
        self.assertEqual(len(candidates), 1)
        result = prove_exhaustive(self.graph, candidates[0])
        self.assertEqual(result.status, ProofStatus.PROVEN)
        self.assertEqual(result.checked_cases, 8)

    @unittest.skipUnless(Path("/Users/blackbox/try_hai/oss-cad-suite/bin/yosys").is_file(), "Yosys toolchain unavailable")
    def test_lossless_residual_emit_is_reimport_equivalent(self):
        with tempfile.TemporaryDirectory() as td:
            revision = RecoveryRevision(self.graph)
            rtl = emit_residual(revision, td)
            ok, log = verify_residual_export(revision, rtl, artifact_dir=Path(td) / "cec")
            self.assertTrue(ok, log[-1000:])
            manifest = json.loads((Path(td) / "manifest.json").read_text())
            self.assertTrue(manifest["emitted_rtl"])
            self.assertEqual(manifest["verification_scope"], "source_graph_export_pending_check")

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
        self.assertEqual(accepted.residual_manifest()["semantic_covered_cells"], 5)
        self.assertEqual(accepted.residual_manifest()["residual_cells"], 5)
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
        empty = copy.deepcopy(candidate); empty.region_cells = ()
        self.assertEqual(prove_exhaustive(self.graph, empty).status, ProofStatus.MODEL_ERROR)

    @unittest.skipUnless(Path("/Users/blackbox/try_hai/oss-cad-suite/bin/yosys").is_file(), "Yosys toolchain unavailable")
    def test_abc_nonzero_exit_is_not_proven(self):
        candidate = propose_full_adders(self.graph)[0]
        with tempfile.TemporaryDirectory() as td:
            fake = Path(td) / "fake_abc"
            fake.write_text("#!/bin/sh\necho 'Networks are equivalent.'\nexit 7\n")
            fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
            result = prove_abc(self.graph, candidate, abc=str(fake), artifact_dir=Path(td) / "art")
            self.assertNotEqual(result.status, ProofStatus.PROVEN)

    def test_side_output_cannot_be_omitted(self):
        candidate = propose_full_adders(self.graph)[0]
        candidate.output_bits = (candidate.output_bits[0],)
        result = prove_exhaustive(self.graph, candidate)
        self.assertEqual(result.status, ProofStatus.MODEL_ERROR)


if __name__ == "__main__":
    unittest.main()
