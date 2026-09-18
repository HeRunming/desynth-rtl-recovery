"""Small regression checks for the stage-0 evidence contract."""
import json
import tempfile
from pathlib import Path

from artifact_contract import attach_contract, normalize_ports, write_manifest
from semantic_naming import validate_plan
from verifier import check_equivalence


def main():
    legacy = {
        "input_net_ids": [1, 2], "output_net_ids": [3],
        "net_meta": {"1": {"name": "clk"}, "2": {"name": "a[0]"},
                     "3": {"name": "y"}},
    }
    p = normalize_ports(legacy)
    assert p["inputs"]["clk"]["net_id"] == 1
    assert p["outputs"]["y"]["net_id"] == 3
    attach_contract(legacy, stage="test", counts={"ffs": 2})
    assert legacy["schema_version"] == 1
    assert legacy["top_ports"]["inputs"] == ["clk", "a[0]"]
    assert legacy["manifest"]["counts"]["ffs"] == 2

    ok, problems, fixed = validate_plan(
        {"buses": [{"name": "x", "bits": [1, 1, 99]}]}, [1, 2])
    assert not ok and problems["dup"] == [1]
    assert {b["bits"][0] for b in fixed["buses"] if len(b["bits"]) == 1} >= {1, 2}

    bad = check_equivalence("assign x = 1;", "module top; endmodule", "top")
    assert bad["status"] == "model_error" and not bad["ok"]
    missing = check_equivalence(
        "module top; endmodule", "module top; endmodule", "top", "/missing.lib")
    assert missing["status"] == "model_error"

    # Yosys reports a bare unproven $equiv cell with an ERROR prefix.  It is
    # solver evidence, not a counterexample, and must remain UNKNOWN.
    incomplete = check_equivalence(
        "module top(input a, output y); assign y=~a; endmodule",
        "module top(input a, output y); assign y=a; endmodule", "top")
    assert incomplete["status"] == "unknown", incomplete

    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / "input.json"
        src.write_text(json.dumps({"x": 1}))
        out = Path(td) / "artifact.manifest.json"
        manifest = write_manifest(out, stage="test", input_paths={"input": src},
                                  counts={"fallback": 0})
        assert manifest["inputs"]["input"]["sha256"]
        assert json.loads(out.read_text())["schema_version"] == 1
    print("artifact contract regression: OK")


if __name__ == "__main__":
    main()
