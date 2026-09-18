"""Hash-bound source graph and deterministic anonymisation.

The graph is a deliberately small JSON-backed IR.  It keeps the complete
Yosys module as the residual implementation and treats semantic recovery as an
overlay.  No candidate can delete source cells; accepted replacements are
recorded separately and are required to cover their complete source region.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode()).hexdigest()


def _normalise_json(data: Mapping[str, Any]) -> dict[str, Any]:
    """Drop volatile creator/source attributes while retaining logic."""
    out = copy.deepcopy(dict(data))
    out.pop("creator", None)
    for module in out.get("modules", {}).values():
        attrs = module.get("attributes", {})
        module["attributes"] = {k: v for k, v in attrs.items() if k not in {"src", "hdlname", "top"}}
        if not module["attributes"]: module.pop("attributes")
        for collection in (module.get("cells", {}), module.get("netnames", {})):
            for obj in collection.values():
                attrs = obj.get("attributes")
                if isinstance(attrs, dict):
                    obj["attributes"] = {k: v for k, v in attrs.items() if k not in {"src", "hdlname"}}
                    if not obj["attributes"]:
                        obj.pop("attributes", None)
    return out


@dataclass(frozen=True)
class SourceGraph:
    """A canonical source graph with an immutable content hash."""

    _data: str
    top: str
    source_hash: str
    graph_version: str = "source-graph/1"

    def __post_init__(self) -> None:
        raw = self._data if isinstance(self._data, str) else canonical_json(self._data)
        object.__setattr__(self, "_data", raw)
        self.assert_integrity()

    @property
    def data(self) -> dict[str, Any]:
        """Return a copy; callers cannot mutate the hash-bound source graph."""
        return json.loads(self._data)

    @classmethod
    def from_yosys_json(cls, data: Mapping[str, Any], top: str | None = None) -> "SourceGraph":
        clean = _normalise_json(data)
        modules = clean.get("modules", {})
        if not modules:
            raise ValueError("Yosys JSON contains no modules")
        selected = top or (next(iter(modules)) if len(modules) == 1 else None)
        if not selected or selected not in modules:
            raise ValueError(f"top module is required; available={sorted(modules)}")
        if len(modules) != 1:
            raise ValueError("M1 requires a flattened single-module input")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", selected):
            raise ValueError("unsupported top identifier")
        return cls(canonical_json(clean), selected, sha256_json(clean))

    def module(self) -> dict[str, Any]:
        # Do not let a detector or proof backend mutate the canonical graph.
        return json.loads(self._data)["modules"][self.top]

    def assert_integrity(self) -> None:
        if hashlib.sha256(self._data.encode()).hexdigest() != self.source_hash:
            raise ValueError("source graph hash mismatch")

    def validate(self) -> list[str]:
        from .state import extract_state_model
        errors = []
        self.assert_integrity()
        mod = self.module()
        if mod.get("memories") or mod.get("processes"):
            errors.append("unlowered memory/process unsupported")
        if mod.get("attributes", {}).get("blackbox") or mod.get("attributes", {}).get("whitebox"):
            errors.append("blackbox/whitebox module unsupported")
        cells = mod.get("cells", {})
        supported = {"$not", "$and", "$or", "$xor", "$xnor", "$mux",
                     "$add", "$sub", "$mul", "$eq", "$ne", "$lt", "$le", "$gt", "$ge",
                     "$logic_not", "$logic_and", "$logic_or", "$reduce_and", "$reduce_or", "$reduce_xor", "$reduce_xnor", "$reduce_bool",
                     "$shl", "$shr", "$sshl", "$sshr", "$dff", "$adff", "$dffe", "$adffe"}
        drivers = {}; needed = set()
        def drive(bit, who):
            if not isinstance(bit, int) or isinstance(bit, bool) or bit < 2:
                errors.append(f"invalid driven bit {bit!r}"); return
            if bit in drivers: errors.append(f"multiple drivers on bit {bit}")
            drivers[bit] = who
        def need(bit):
            if isinstance(bit, int) and not isinstance(bit, bool) and bit >= 2: needed.add(bit)
            elif bit not in ("0", "1"): errors.append(f"unsupported bit/constant {bit!r}")
        for name, port in mod.get("ports", {}).items():
            if not port.get("bits"): errors.append(f"empty port {name}")
            if port.get("direction") == "input":
                for bit in port["bits"]: drive(bit, "port:" + name)
            elif port.get("direction") == "output":
                for bit in port["bits"]: need(bit)
            else: errors.append(f"unsupported port direction {name}")
        for name, cell in cells.items():
            if cell.get("type") not in supported: errors.append(f"unsupported cell {name}:{cell.get('type')}")
            if not cell.get("connections"): errors.append(f"empty cell {name}")
            for pin, bits in cell.get("connections", {}).items():
                direction = cell.get("port_directions", {}).get(pin)
                if direction == "output":
                    for bit in bits: drive(bit, name)
                elif direction == "input":
                    for bit in bits: need(bit)
                else: errors.append(f"unknown pin direction {name}.{pin}")
        for bit in needed - drivers.keys(): errors.append(f"undriven bit {bit}")
        # Combinational cycles are illegal even when disconnected from a port.
        comb = {name: cell for name, cell in cells.items() if cell.get("type") not in {"$dff", "$adff", "$dffe", "$adffe"}}
        edges = {name: set() for name in comb}
        for name, cell in comb.items():
            for pin, bits in cell.get("connections", {}).items():
                if cell.get("port_directions", {}).get(pin) == "input":
                    edges[name].update(drivers[b] for b in bits if b in drivers and drivers[b] in comb)
        ready = [n for n, deps in edges.items() if not deps]; visited = set()
        reverse = {n: set() for n in comb}
        for n, deps in edges.items():
            for dep in deps: reverse[dep].add(n)
        while ready:
            n = ready.pop(); visited.add(n)
            for user in reverse[n]:
                edges[user].discard(n)
                if not edges[user]: ready.append(user)
        if len(visited) != len(comb): errors.append("combinational cycle")
        if not any(p.get("direction") == "output" for p in mod.get("ports", {}).values()): errors.append("no output obligations")
        errors.extend(item["reason"] for item in extract_state_model(self).unsupported)
        return sorted(set(errors))

    def counts(self) -> dict[str, int]:
        mod = self.module()
        cells = mod.get("cells", {})
        states = sum(1 for c in cells.values() if c.get("type") in {"$dff", "$adff", "$dffe", "$adffe"})
        return {
            "ports": len(mod.get("ports", {})),
            "cells": len(cells),
            "nets": len(mod.get("netnames", {})),
            "state_cells": states,
        }

    def manifest(self) -> dict[str, Any]:
        from .state import extract_state_model
        return {
            "schema": self.graph_version,
            "top": self.top,
            "source_hash": self.source_hash,
            "counts": self.counts(),
            "state_model": extract_state_model(self).as_dict(),
        }

    def copy_data(self) -> dict[str, Any]:
        return json.loads(self._data)

    def anonymize(self, *, seed: int = 0, hide_ports: bool = False) -> tuple[dict[str, Any], dict[str, Any]]:
        """Return anonymised JSON and a private evaluator mapping.

        The returned public JSON contains no original cell/net/module names or
        source attributes.  The mapping is intentionally separate and should be
        kept by an evaluator, never passed to the recovery worker.
        """
        import random

        # Admission must happen before rebuilding the public module: unsupported
        # processes/memories and other semantic fields must never disappear into
        # an apparently valid anonymous graph.
        errors = self.validate()
        if errors:
            raise ValueError("cannot anonymize unsupported source graph: " + "; ".join(errors))
        rng = random.Random(seed)
        src = self.copy_data()
        old_top = self.top
        old_mod = src["modules"][old_top]
        new_top = "top_0"
        bit_ids = {b for p in old_mod.get("ports", {}).values() for b in p.get("bits", []) if isinstance(b, int)}
        bit_ids.update(b for c in old_mod.get("cells", {}).values() for bits in c.get("connections", {}).values() for b in bits if isinstance(b, int))
        bit_ids.update(b for net in old_mod.get("netnames", {}).values() for b in net.get("bits", []) if isinstance(b, int))
        if any(b < 2 for b in bit_ids):
            raise ValueError("Yosys constants must be strings '0'/'1', not integer wire IDs")
        shuffled = sorted(bit_ids); rng.shuffle(shuffled)
        bit_map = {old: i + 2 for i, old in enumerate(shuffled)}
        def remap_bits(bits: Iterable[Any]) -> list[Any]:
            return [bit_map[b] if isinstance(b, int) else b for b in bits]
        public_mod: dict[str, Any] = {"ports": {}, "cells": {}, "netnames": {}}
        # Semantic module attributes must not be erased to launder a blackbox.
        public_mod["attributes"] = {k: v for k,v in old_mod.get("attributes", {}).items() if k in {"blackbox", "whitebox"}}
        port_items = list(old_mod.get("ports", {}).items()); rng.shuffle(port_items)
        port_map = {}
        for i, (name, port) in enumerate(port_items):
            pname = f"p{i}" if hide_ports else f"p{i}_{port.get('direction', 'x')}"
            port_map[name] = pname
            public_mod["ports"][pname] = {"direction": port["direction"], "bits": remap_bits(port.get("bits", []))}
        cells = list(old_mod.get("cells", {}).items()); rng.shuffle(cells)
        cell_map = {}
        for i, (name, cell) in enumerate(cells):
            cname = f"c{i}"; cell_map[name] = cname
            item = {k: copy.deepcopy(cell[k]) for k in ("type", "parameters", "port_directions") if k in cell}
            item["connections"] = {pin: remap_bits(bits) for pin, bits in cell.get("connections", {}).items()}
            public_mod["cells"][cname] = item
        from .state import initial_bits
        init, conflicts = initial_bits(old_mod)
        if conflicts: raise ValueError("; ".join(conflicts))
        # One anonymous alias per bit: no original bus grouping, declaration
        # order, or source name is visible. Preserve semantic initialization.
        for old, new in sorted(bit_map.items(), key=lambda item: item[1]):
            net = {"bits": [new]}
            if old in init: net["attributes"] = {"init": init[old]}
            public_mod["netnames"][f"n{new}"] = net
        public = {"modules": {new_top: public_mod}}
        mapping = {
            "source_hash": self.source_hash,
            "top": {"source": old_top, "anonymous": new_top},
            "bits": {str(k): v for k, v in bit_map.items()},
            "ports": port_map,
            "cells": cell_map,
            "public_hash": sha256_json(public),
        }
        return public, mapping


def load_yosys_json(path: str | Path, top: str | None = None) -> SourceGraph:
    p = Path(path)
    return SourceGraph.from_yosys_json(json.loads(p.read_text()), top=top)


def save_json(path: str | Path, value: Any) -> None:
    Path(path).write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
