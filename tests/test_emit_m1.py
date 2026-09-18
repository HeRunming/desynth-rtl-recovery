import json
import hashlib
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from harness.emit import emit_recovered, emit_residual, verify_residual_export
from harness.ir import SourceGraph
from harness.recovery import RecoveryRevision

YOSYS = os.environ.get("YOSYS", "/Users/blackbox/try_hai/oss-cad-suite/bin/yosys")


@unittest.skipUnless(Path(YOSYS).is_file(), "Yosys toolchain unavailable")
class WholeDesignM1(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="harness m1 space ")
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def revision(self, rtl):
        (self.root / "input.v").write_text(rtl)
        p = subprocess.run([YOSYS, "-p", "read_verilog input.v; hierarchy -top top; proc; write_json input.json"], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        graph = SourceGraph.from_yosys_json(json.loads((self.root / "input.json").read_text()), "top")
        return RecoveryRevision(graph)

    def verify(self, rev, rtl, label="proof"):
        return verify_residual_export(rev, rtl, yosys=YOSYS, artifact_dir=self.root / label)

    def test_actual_full_adder_replacement_is_reimport_proven(self):
        from harness.detect import propose_full_adders
        from harness.proof import prove_exhaustive
        rev = self.revision("module top(input a,b,c,output s,y); wire t=a^b; assign s=t^c; assign y=(a&b)|(t&c); endmodule")
        candidate = propose_full_adders(rev.graph)[0]
        accepted = rev.accept(candidate, prove_exhaustive(rev.graph, candidate))
        rtl = emit_recovered(accepted, self.root / "recovered", yosys=YOSYS)
        self.assertIn(" + ", rtl.read_text())
        manifest = json.loads((self.root / "recovered/manifest.json").read_text())
        self.assertTrue(manifest["semantic_replacements_emitted"])
        self.assertEqual(manifest["replaced_cells"], 5)
        self.assertEqual(manifest["residual_cells"], 0)
        ok, log = self.verify(accepted, rtl)
        self.assertTrue(ok, log[-2500:])

    def test_wide_signed_combinational_and_space_paths(self):
        rev = self.revision("module top(input signed [7:0] a,b,output [11:0] y); assign y=a&b; endmodule")
        rtl = emit_residual(rev, self.root / "emit space", yosys=YOSYS)
        ok, log = self.verify(rev, rtl)
        self.assertTrue(ok, log[-2500:])
        verdict = json.loads((self.root / "proof/verification.json").read_text())
        self.assertEqual(verdict["backends"], ["yosys_sat", "abc_cec"])
        self.assertEqual(verdict["output_bits"], 12)
        self.assertEqual(verdict["state_bits"], 0)

    def test_proof_evidence_binds_tools_versions_commands_and_files(self):
        rev = self.revision("module top(input a,b,output y); assign y=a^b; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        ok, log = self.verify(rev, rtl)
        self.assertTrue(ok, log[-2500:])
        root = self.root / "proof"
        verdict = json.loads((root / "verification.json").read_text())
        self.assertEqual(verdict["evidence_kind"], "trusted_tool_execution_not_certificate")
        self.assertEqual(set(verdict["tools"]), {"yosys", "abc"})
        for name, tool in verdict["tools"].items():
            self.assertEqual(tool["sha256"], hashlib.sha256(Path(tool["path"]).read_bytes()).hexdigest())
            self.assertEqual(tool["version"], (root / f"{name}_version.log").read_text().strip())
            self.assertTrue(tool["version"])
            if "delegated_executable" in tool:
                target = tool["delegated_executable"]
                self.assertEqual(target["sha256"], hashlib.sha256(Path(target["path"]).read_bytes()).hexdigest())
        records = {record["label"]: record for record in verdict["processes"]}
        self.assertEqual(set(records), {"yosys_version", "abc_version", "gold_normalize", "gate_normalize",
                                       "whole_design_sat", "gold_aig", "gate_aig", "whole_design_abc"})
        self.assertEqual(records["whole_design_abc"]["argv"], [verdict["tools"]["abc"]["path"], "-c", "cec gold.aig gate.aig"])
        for record in records.values():
            self.assertEqual(record["returncode"], 0)
            self.assertEqual(record["status"], "finished")
            self.assertEqual(record["cwd"], str(root.resolve()))
            self.assertIn(record["log"], verdict["artifacts_sha256"])
        for name, digest in verdict["artifacts_sha256"].items():
            self.assertEqual(digest, hashlib.sha256((root / name).read_bytes()).hexdigest())
        for name in ("candidate.v", "source_graph.json", "state_contracts.json", "gold_cut.json", "gate_cut.json",
                     "gold.aig", "gate.aig", "whole_design_sat.ys", "residual_cec.log"):
            self.assertIn(name, verdict["artifacts_sha256"])

    def test_tool_version_failure_is_recorded_and_not_proven(self):
        rev = self.revision("module top(input a,output y); assign y=a; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        fake = self.root / "broken yosys"
        fake.write_text("#!/bin/sh\necho 'version unavailable'\nexit 7\n")
        fake.chmod(0o700)
        with patch.dict(os.environ, {"ABC": str(Path(YOSYS).with_name("yosys-abc"))}):
            ok, _ = verify_residual_export(rev, rtl, yosys=str(fake), artifact_dir=self.root / "failed proof")
        self.assertFalse(ok)
        verdict = json.loads((self.root / "failed proof/verification.json").read_text())
        self.assertFalse(verdict["proven"])
        self.assertEqual(verdict["tools"]["yosys"]["sha256"], hashlib.sha256(fake.read_bytes()).hexdigest())
        self.assertEqual(verdict["processes"][0]["returncode"], 7)
        self.assertEqual(verdict["processes"][0]["label"], "yosys_version")
        self.assertIn("yosys_version.log", verdict["artifacts_sha256"])

    def test_sequential_init_enable_async_reset_roundtrip(self):
        rev = self.revision("module top(input clk,rst,en,input [3:0] d,output reg [3:0] q=4'b1010); always @(negedge clk or posedge rst) if(rst) q<=4'b0110; else if(en) q<=d; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        ok, log = self.verify(rev, rtl)
        self.assertTrue(ok, log[-2500:])
        verdict = json.loads((self.root / "proof/verification.json").read_text())
        self.assertEqual(verdict["state_bits"], 4)

    def test_output_mutation_rejected(self):
        rev = self.revision("module top(input [3:0] a,b,output [3:0] y); assign y=a^b; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        text = rtl.read_text(); self.assertIn(" ^ ", text)
        rtl.write_text(text.replace(" ^ ", " & "))
        ok, _ = self.verify(rev, rtl)
        self.assertFalse(ok)
        self.assertNotEqual(json.loads((self.root / "proof/verification.json").read_text())["status"], "proven")

    def test_unobservable_state_D_mutation_rejected(self):
        rev = self.revision("module top(input clk,d,output y); reg q; always @(posedge clk) q<=d; assign y=d; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        text = rtl.read_text(); self.assertIn("<= d;", text)
        rtl.write_text(text.replace("<= d;", "<= ~d;"))
        ok, log = self.verify(rev, rtl)
        self.assertFalse(ok, log)

    def test_init_edge_and_missing_provenance_rejected(self):
        rev = self.revision("module top(input clk,d,output reg q=1'b0); always @(posedge clk) q<=d; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        original = rtl.read_text()
        self.assertIn("1'h0", original)
        for i, modified in enumerate((original.replace("1'h0", "1'h1"), original.replace("posedge", "negedge"), original.replace("__harness_q_", "__destroyed_q_"))):
            with self.subTest(mutation=i):
                rtl.write_text(modified)
                ok, log = self.verify(rev, rtl, f"proof{i}")
                self.assertFalse(ok, log)
        rtl.write_text(original)
        ok, log = self.verify(rev, rtl, "restored")
        self.assertTrue(ok, log[-2500:])

    def test_adding_initial_constraint_rejected(self):
        rev = self.revision("module top(input clk,d,output reg q); always @(posedge clk) q<=d; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        rtl.write_text(rtl.read_text().replace("reg q;", "reg q = 1'b0;"))
        ok, log = self.verify(rev, rtl)
        self.assertFalse(ok, log)

    def test_timeout_persisted(self):
        rev = self.revision("module top(input a,output y); assign y=a; endmodule")
        rtl = emit_residual(rev, self.root / "emit", yosys=YOSYS)
        ok, _ = verify_residual_export(rev, rtl, timeout_s=0, artifact_dir=self.root / "timeout")
        self.assertFalse(ok)
        self.assertEqual(json.loads((self.root / "timeout/verification.json").read_text())["status"], "timeout")

    def test_multiclock_rejected(self):
        rev = self.revision("module top(input a,b,d,output reg q,r); always @(posedge a) q<=d; always @(posedge b) r<=d; endmodule")
        with self.assertRaisesRegex(ValueError, "one clock"):
            emit_residual(rev, self.root / "emit", yosys=YOSYS)

    def test_unsupported_blackbox_fails_closed(self):
        rev = self.revision("module top(input a,output y); UNKNOWN foo(a,y); endmodule")
        with self.assertRaises(ValueError):
            emit_residual(rev, self.root / "emit", yosys=YOSYS)


if __name__ == "__main__":
    unittest.main()
