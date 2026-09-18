import unittest

from harness.ir import SourceGraph
from harness.state import extract_state_model, require_supported_state


def state_json(kind="$dff"):
    cell = {
        "type": kind,
        "port_directions": {"D": "input", "Q": "output", "CLK": "input"},
        "connections": {"D": [10], "Q": [11], "CLK": [12]},
        "parameters": {"CLK_POLARITY": "1", "WIDTH": "1"},
    }
    if kind == "$adff":
        cell["port_directions"]["ARST"] = "input"; cell["connections"]["ARST"] = [13]
        cell["parameters"].update({"ARST_POLARITY": "0", "ARST_VALUE": "0"})
    if kind == "$dffe":
        cell["port_directions"]["EN"] = "input"; cell["connections"]["EN"] = [14]
        cell["parameters"]["EN_POLARITY"] = "1"
    return {"modules": {"top": {"ports": {}, "cells": {"s0": cell}, "netnames": {}}}}


class StateModelTest(unittest.TestCase):
    def test_dff_event_and_domain(self):
        model = extract_state_model(SourceGraph.from_yosys_json(state_json()))
        self.assertEqual(len(model.elements), 1)
        self.assertEqual(model.elements[0].clock_polarity, 1)
        self.assertEqual(model.elements[0].clock_bits, (12,))
        self.assertFalse(model.unsupported)

    def test_async_reset_and_enable_are_preserved(self):
        for kind in ("$adff", "$dffe"):
            model = extract_state_model(SourceGraph.from_yosys_json(state_json(kind)))
            element = model.elements[0]
            if kind == "$adff": self.assertEqual((element.reset_bits, element.reset_polarity), ((13,), 0))
            else: self.assertEqual((element.enable_bits, element.enable_polarity), ((14,), 1))

    def test_unknown_latch_is_unsupported(self):
        data = state_json(); data["modules"]["top"]["cells"]["s0"]["type"] = "$dlatch"
        graph = SourceGraph.from_yosys_json(data)
        model = extract_state_model(graph)
        self.assertEqual(model.unsupported[0]["type"], "$dlatch")
        with self.assertRaises(ValueError): require_supported_state(graph)


if __name__ == "__main__": unittest.main()
