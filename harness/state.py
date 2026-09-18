"""State/event extraction from canonical Yosys cells.

This module is intentionally conservative.  A missing or unfamiliar event
semantic is an explicit unsupported condition, never a guessed synchronous
posedge/reset model.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Any


@dataclass(frozen=True)
class StateElement:
    cell: str
    kind: str
    q_bits: tuple[int, ...]
    d_bits: tuple[int, ...]
    clock_bits: tuple[int, ...]
    clock_polarity: int
    reset_bits: tuple[int, ...] = ()
    reset_polarity: int | None = None
    reset_value: tuple[Any, ...] = ()
    enable_bits: tuple[int, ...] = ()
    enable_polarity: int | None = None
    initial_value: tuple[Any, ...] = ()

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class StateModel:
    elements: tuple[StateElement, ...]
    unsupported: tuple[dict[str, str], ...]

    def as_dict(self) -> dict[str, Any]:
        domains: dict[str, list[str]] = {}
        for e in self.elements:
            key = f"{e.clock_bits}:{e.clock_polarity}"
            domains.setdefault(key, []).append(e.cell)
        return {"elements": [e.as_dict() for e in self.elements], "unsupported": list(self.unsupported), "clock_domains": domains}


def _int_param(cell: dict, name: str, default: int) -> int:
    raw = cell.get("parameters", {}).get(name, str(default))
    if isinstance(raw, int): return raw
    if isinstance(raw, str):
        try: return int(raw, 2) if set(raw) <= {"0", "1"} else int(raw, 0)
        except ValueError: return default
    return default


def extract_state_model(graph) -> StateModel:
    elements: list[StateElement] = []
    unsupported: list[dict[str, str]] = []
    supported = {"$dff", "$adff", "$dffe", "$adffe"}
    for name, cell in graph.module().get("cells", {}).items():
        kind = cell.get("type", "")
        if kind.startswith("$") and any(token in kind for token in ("ff", "latch", "tribuf")) and kind not in supported:
            unsupported.append({"cell": name, "type": kind, "reason": "unsupported sequential or tri-state primitive"})
            continue
        if kind not in supported:
            continue
        conn = cell.get("connections", {})
        required = ["D", "Q", "CLK"]
        if kind in {"$adff", "$adffe"}: required.append("ARST")
        if kind in {"$dffe", "$adffe"}: required.append("EN")
        missing = [p for p in required if p not in conn]
        if missing:
            unsupported.append({"cell": name, "type": kind, "reason": "missing pins: " + ",".join(missing)})
            continue
        initial = tuple(cell.get("attributes", {}).get("init", [])) if isinstance(cell.get("attributes", {}).get("init"), list) else ()
        reset = tuple(conn.get("ARST", []))
        enable = tuple(conn.get("EN", []))
        elements.append(StateElement(
            cell=name, kind=kind, q_bits=tuple(conn["Q"]), d_bits=tuple(conn["D"]),
            clock_bits=tuple(conn["CLK"]), clock_polarity=_int_param(cell, "CLK_POLARITY", 1),
            reset_bits=reset, reset_polarity=_int_param(cell, "ARST_POLARITY", 1) if reset else None,
            reset_value=tuple(cell.get("parameters", {}).get("ARST_VALUE", [])) if reset else (),
            enable_bits=enable, enable_polarity=_int_param(cell, "EN_POLARITY", 1) if enable else None,
            initial_value=initial,
        ))
    return StateModel(tuple(elements), tuple(unsupported))


def require_supported_state(graph) -> StateModel:
    model = extract_state_model(graph)
    if model.unsupported:
        details = "; ".join(f"{x['cell']}:{x['type']} ({x['reason']})" for x in model.unsupported[:5])
        raise ValueError("unsupported state model: " + details)
    return model
