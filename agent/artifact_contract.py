#!/usr/bin/env python3
"""Shared, dependency-free metadata for pipeline JSON artifacts.

The first versions of the pipeline used ``input_net_ids``/``top_ports`` in
different shapes.  This module provides a small compatibility layer: new
artifacts contain ``ports`` as a name -> metadata mapping while all legacy
fields remain untouched.
"""
from __future__ import annotations

import hashlib
import json
import platform
from pathlib import Path
from typing import Any, Mapping, Optional, Union

SCHEMA_VERSION = 1


def _port_items(value: Any) -> list[tuple[str, Optional[int]]]:
    """Read a port collection from the old and new representations."""
    if isinstance(value, Mapping):
        out = []
        for name, meta in value.items():
            if isinstance(meta, Mapping):
                nid = meta.get("net_id", meta.get("id"))
            else:
                nid = meta if isinstance(meta, int) else None
            out.append((str(name), nid))
        return out
    if isinstance(value, (list, tuple)):
        out = []
        for item in value:
            if isinstance(item, Mapping):
                name = item.get("name", item.get("port"))
                if name is not None:
                    out.append((str(name), item.get("net_id", item.get("id"))))
            elif item is not None:
                out.append((str(item), None))
        return out
    return []


def normalize_ports(data: Mapping[str, Any]) -> dict[str, dict[str, dict[str, Optional[int]]]]:
    """Return canonical ``ports.inputs/outputs`` without changing *data*.

    Accepted inputs include ``ports`` (mapping or list values), ``top_ports``
    (the HAL fact format), and the mechanical extractor's legacy id arrays
    combined with ``net_meta``.
    """
    existing = data.get("ports")
    top = data.get("top_ports")
    meta = data.get("net_meta") or {}

    result: dict[str, dict[str, dict[str, Optional[int]]]] = {
        "inputs": {}, "outputs": {}
    }
    for direction in ("inputs", "outputs"):
        source = existing.get(direction) if isinstance(existing, Mapping) else None
        if source is None and isinstance(top, Mapping):
            source = top.get(direction)
        items = _port_items(source)
        if not items:
            ids = data.get(f"{direction[:-1]}_net_ids", []) or []
            for raw_id in ids:
                try:
                    nid = int(raw_id)
                except (TypeError, ValueError):
                    continue
                m = meta.get(str(nid), meta.get(nid, {}))
                name = m.get("name") if isinstance(m, Mapping) else None
                items.append((str(name or f"net_{nid}"), nid))
        for name, nid in items:
            if name in result[direction]:
                # Keep the first mapping deterministic; duplicate names are
                # still represented by the legacy id arrays/net_meta.
                continue
            result[direction][name] = {"net_id": nid}
    return result


def attach_contract(data: dict[str, Any], *, stage: Optional[str] = None,
                    input_paths: Optional[Mapping[str, Union[str, Path]]] = None,
                    counts: Optional[Mapping[str, Any]] = None,
                    status: str = "ok") -> dict[str, Any]:
    """Add versioned ports and a reproducibility manifest in-place."""
    ports = normalize_ports(data)
    data["schema_version"] = int(data.get("schema_version", SCHEMA_VERSION))
    data["ports"] = ports
    # Keep the lightweight HAL fact shape available to old consumers.
    data["top_ports"] = {
        direction: list(ports[direction].keys())
        for direction in ("inputs", "outputs")
    }
    previous = data.get("manifest")
    previous_stage = previous.get("stage", "unknown") if isinstance(previous, Mapping) else "unknown"
    manifest: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "stage": stage or previous_stage,
        "status": status,
        "tool": {
            "python": platform.python_version(),
            "contract": "artifact_contract/1",
        },
        "counts": dict(counts or {}),
    }
    if input_paths:
        manifest["inputs"] = {
            str(name): file_fingerprint(path)
            for name, path in input_paths.items()
        }
    data["manifest"] = manifest
    return data


def file_fingerprint(path: Union[str, Path]) -> dict[str, Any]:
    p = Path(path)
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return {"path": str(p), "sha256": h.hexdigest(), "bytes": p.stat().st_size}


def write_manifest(path: Union[str, Path], *, stage: str,
                   input_paths: Optional[Mapping[str, Union[str, Path]]] = None,
                   counts: Optional[Mapping[str, Any]] = None,
                   status: str = "ok") -> dict[str, Any]:
    """Write a standalone ``*.manifest.json`` for shell-driven stages."""
    payload = {
        "schema_version": SCHEMA_VERSION,
        "stage": stage,
        "status": status,
        "tool": {"python": platform.python_version(), "contract": "artifact_contract/1"},
        "counts": dict(counts or {}),
    }
    if input_paths:
        payload["inputs"] = {str(k): file_fingerprint(v) for k, v in input_paths.items()}
    out = Path(path)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    return payload
