"""Regression cases at anonymization and replacement admission boundaries."""
import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

from harness.detect import propose_full_adders
from harness.emit import emit_recovered, verify_residual_export
from harness.ir import SourceGraph
from harness.proof import ProofStatus, prove_exhaustive
from harness.recovery import RecoveryRevision
from harness.state import extract_state_model


YOSYS = os.environ.get("YOSYS", "/Users/blackbox/try_hai/oss-cad-suite/bin/yosys")


def fixture():
    path = Path(__file__).resolve().parents[1] / "examples/harness/full_adder.json"
    return json.loads(path.read_text())


class AdmissionEdges(unittest.TestCase):
    def test_anonymization_rejects_unlowered_semantics_before_dropping_fields(self):
        for field in ("processes", "memories"):
            with self.subTest(field=field):
                data = fixture()
                data["modules"]["opaque_top"][field] = {"unlowered_state": {}}
                graph = SourceGraph.from_yosys_json(data)
                self.assertIn("unlowered memory/process unsupported", graph.validate())
                with self.assertRaisesRegex(ValueError, "cannot anonymize unsupported source graph"):
                    graph.anonymize(seed=17, hide_ports=True)
                self.assertEqual(graph.data["modules"]["opaque_top"][field], {"unlowered_state": {}})

    def test_anonymization_rejects_blackbox_and_unmodeled_cell(self):
        for invalid in ("blackbox", "unmodeled_cell"):
            with self.subTest(invalid=invalid):
                data = fixture()
                module = data["modules"]["opaque_top"]
                if invalid == "blackbox":
                    module["attributes"] = {"blackbox": "1"}
                else:
                    module["cells"]["u_x1"]["type"] = "UNKNOWN_LIBRARY_CELL"
                with self.assertRaisesRegex(ValueError, "cannot anonymize unsupported source graph"):
                    SourceGraph.from_yosys_json(data).anonymize()

    def test_anonymization_preserves_arbitrary_and_explicit_initial_state_order(self):
        for initial, expected in ((None, ("x", "x", "x")),
                                  ("101", ("1", "0", "1")),
                                  ("1x0", ("0", "x", "1"))):
            with self.subTest(initial=initial):
                data = {"modules": {"state_top": {
                    "ports": {"clock": {"direction": "input", "bits": [10]},
                              "data": {"direction": "input", "bits": [11, 12, 13]},
                              "state": {"direction": "output", "bits": [30, 31, 32]}},
                    "cells": {"state_register": {
                        "type": "$dff", "parameters": {"WIDTH": "11", "CLK_POLARITY": "1"},
                        "port_directions": {"D": "input", "CLK": "input", "Q": "output"},
                        "connections": {"D": [11, 12, 13], "CLK": [10], "Q": [30, 31, 32]},
                    }},
                    "netnames": {"source_state_bus": {"bits": [30, 31, 32]}},
                }}}
                if initial is not None:
                    data["modules"]["state_top"]["netnames"]["source_state_bus"]["attributes"] = {"init": initial}
                graph = SourceGraph.from_yosys_json(data)
                self.assertEqual(extract_state_model(graph).elements[0].initial_value, expected)
                public, mapping = graph.anonymize(seed=17, hide_ports=True)
                anonymous = SourceGraph.from_yosys_json(public)
                self.assertEqual(anonymous.validate(), [])
                state = extract_state_model(anonymous).elements[0]
                self.assertEqual(state.initial_value, expected)
                self.assertEqual(state.q_bits, tuple(mapping["bits"][str(b)] for b in (30, 31, 32)))
                self.assertNotIn("source_state_bus", json.dumps(public))

    def port_only_revision(self):
        data = fixture()
        # 24 is the highest bit in the fixture cells. This input has no alias
        # and used to collide with the first new two-bit adder temporary.
        data["modules"]["opaque_top"]["ports"]["unused"] = {
            "direction": "input", "bits": [25],
        }
        graph = SourceGraph.from_yosys_json(data)
        self.assertEqual(graph.validate(), [])
        candidate = propose_full_adders(graph)[0]
        return RecoveryRevision(graph).accept(candidate, prove_exhaustive(graph, candidate))

    def test_replacement_reserves_port_only_wire_ids(self):
        revision = self.port_only_revision()
        implementation = revision.implementation_graph()
        self.assertEqual(implementation.validate(), [])
        module = implementation.module()
        self.assertEqual(module["ports"]["unused"]["bits"], [25])
        driven = {bit for cell in module["cells"].values()
                  for pin, bits in cell["connections"].items()
                  if cell["port_directions"][pin] == "output" for bit in bits}
        self.assertNotIn(25, driven)
        self.assertEqual(len(module["cells"]), 2)

    def side_output_candidate(self):
        data = fixture()
        # t = a ^ b is shared by the FA and an externally visible side output.
        data["modules"]["opaque_top"]["ports"]["side"] = {
            "direction": "output", "bits": [20],
        }
        graph = SourceGraph.from_yosys_json(data)
        candidate = propose_full_adders(graph)[0]
        return graph, candidate

    def test_side_output_requires_retained_dependency_closure(self):
        graph, candidate = self.side_output_candidate()
        self.assertEqual(candidate.retained_cells, ("u_x1",))
        self.assertEqual(candidate.validate(graph), [])
        proof = prove_exhaustive(graph, candidate)
        self.assertEqual(proof.status, ProofStatus.PROVEN)
        revision = RecoveryRevision(graph).accept(candidate, proof)
        implementation = revision.implementation_graph()
        self.assertEqual(implementation.validate(), [])
        self.assertEqual(implementation.module()["cells"]["u_x1"], graph.module()["cells"]["u_x1"])
        self.assertEqual(revision.residual_manifest()["planned_replaced_cells"], 4)
        missing_retention = copy.deepcopy(candidate)
        missing_retention.retained_cells = ()
        self.assertTrue(any("side outputs" in error for error in missing_retention.validate(graph)))
        self.assertEqual(prove_exhaustive(graph, missing_retention).status, ProofStatus.MODEL_ERROR)
        with self.assertRaisesRegex(ValueError, "side outputs"):
            RecoveryRevision(graph).accept(missing_retention, proof)

    @unittest.skipUnless(Path(YOSYS).is_file(), "Yosys toolchain unavailable")
    def test_side_output_retention_survives_emission_and_whole_design_proof(self):
        graph, candidate = self.side_output_candidate()
        revision = RecoveryRevision(graph).accept(candidate, prove_exhaustive(graph, candidate))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rtl = emit_recovered(revision, root / "emit", yosys=YOSYS)
            manifest = json.loads((root / "emit/manifest.json").read_text())
            self.assertEqual(manifest["replaced_cells"], 4)
            self.assertEqual(manifest["residual_cells"], 1)
            ok, log = verify_residual_export(revision, rtl, yosys=YOSYS, artifact_dir=root / "proof")
            self.assertTrue(ok, log[-2500:])

    @unittest.skipUnless(Path(YOSYS).is_file(), "Yosys toolchain unavailable")
    def test_port_only_wire_survives_actual_rtl_and_whole_design_proof(self):
        revision = self.port_only_revision()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rtl = emit_recovered(revision, root / "emit", yosys=YOSYS)
            ok, log = verify_residual_export(revision, rtl, yosys=YOSYS, artifact_dir=root / "proof")
            self.assertTrue(ok, log[-2500:])


if __name__ == "__main__":
    unittest.main()
