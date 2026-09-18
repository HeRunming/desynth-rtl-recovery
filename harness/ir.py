"""Immutable-ish source graph and deterministic anonymisation.

The graph is a deliberately small JSON-backed IR.  It keeps the complete
Yosys module as the residual implementation and treats semantic recovery as an
overlay.  No candidate can delete source cells; accepted replacements are
recorded separately and are required to cover their complete source region.
"""
from __future__ import annotations

import copy
import hashlib
import json
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
        module.pop("attributes", None)
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

    data: dict[str, Any]
    top: str
    source_hash: str
    graph_version: str = "source-graph/1"

    @classmethod
    def from_yosys_json(cls, data: Mapping[str, Any], top: str | None = None) -> "SourceGraph":
        clean = _normalise_json(data)
        modules = clean.get("modules", {})
        if not modules:
            raise ValueError("Yosys JSON contains no modules")
        selected = top or (next(iter(modules)) if len(modules) == 1 else None)
        if not selected or selected not in modules:
            raise ValueError(f"top module is required; available={sorted(modules)}")
        return cls(copy.deepcopy(clean), selected, sha256_json(clean))

    def module(self) -> dict[str, Any]:
        return self.data["modules"][self.top]

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
        return copy.deepcopy(self.data)

    def anonymize(self, *, seed: int = 0, hide_ports: bool = False) -> tuple[dict[str, Any], dict[str, Any]]:
        """Return anonymised JSON and a private evaluator mapping.

        The returned public JSON contains no original cell/net/module names or
        source attributes.  The mapping is intentionally separate and should be
        kept by an evaluator, never passed to the recovery worker.
        """
        import random

        rng = random.Random(seed)
        src = self.copy_data()
        old_top = self.top
        old_mod = src["modules"][old_top]
        new_top = "top_0"
        bit_ids = sorted({b for p in old_mod.get("ports", {}).values() for b in p.get("bits", []) if isinstance(b, int)})
        bit_ids += sorted({b for c in old_mod.get("cells", {}).values() for bits in c.get("connections", {}).values() for b in bits if isinstance(b, int) and b not in bit_ids})
        bit_ids = sorted(set(bit_ids))
        shuffled = list(bit_ids)
        rng.shuffle(shuffled)
        bit_map = {old: i + 2 for i, old in enumerate(shuffled)}
        # Keep constants exactly; remap only integer wire ids.
        def remap_bits(bits: Iterable[Any]) -> list[Any]:
            return [bit_map.get(b, b) if isinstance(b, int) else b for b in bits]

        public_mod: dict[str, Any] = {"ports": {}, "cells": {}, "netnames": {}}
        port_items = list(old_mod.get("ports", {}).items())
        rng.shuffle(port_items)
        port_map: dict[str, str] = {}
        for i, (name, port) in enumerate(port_items):
            pname = f"p{i}" if hide_ports else f"p{i}_{port.get('direction', 'x')}"
            port_map[name] = pname
            public_mod["ports"][pname] = {"direction": port["direction"], "bits": remap_bits(port.get("bits", []))}
        cells = list(old_mod.get("cells", {}).items())
        rng.shuffle(cells)
        cell_map: dict[str, str] = {}
        for i, (name, cell) in enumerate(cells):
            cname = f"c{i}"
            cell_map[name] = cname
            item = {k: copy.deepcopy(v) for k, v in cell.items() if k not in {"attributes", "hide_name"}}
            item["connections"] = {pin: remap_bits(bits) for pin, bits in item.get("connections", {}).items()}
            public_mod["cells"][cname] = item
        # Netnames are purely diagnostic; retaining anonymous names helps tools
        # address slices without leaking the original spelling.
        for i, (_, net) in enumerate(sorted(old_mod.get("netnames", {}).items(), key=lambda kv: str(kv[1].get("bits", [])))):
            public_mod["netnames"][f"n{i}"] = {"bits": remap_bits(net.get("bits", []))}
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
