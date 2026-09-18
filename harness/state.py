"""Explicit state/event semantics for the supported Yosys primitives."""
from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Any


@dataclass(frozen=True)
class StateElement:
    cell: str
    kind: str
    q_bits: tuple[int, ...]
    d_bits: tuple[Any, ...]
    clock_bits: tuple[int, ...]
    clock_polarity: int
    reset_bits: tuple[Any, ...] = ()
    reset_polarity: int | None = None
    reset_value: tuple[str, ...] = ()
    enable_bits: tuple[Any, ...] = ()
    enable_polarity: int | None = None
    initial_value: tuple[str, ...] = ()

    def as_dict(self):
        return asdict(self)


@dataclass(frozen=True)
class StateModel:
    elements: tuple[StateElement, ...]
    unsupported: tuple[dict[str, str], ...]

    def as_dict(self):
        domains = {}
        for element in self.elements:
            domains.setdefault(f"{element.clock_bits}:{element.clock_polarity}", []).append(element.cell)
        return {"elements": [e.as_dict() for e in self.elements], "unsupported": list(self.unsupported), "clock_domains": domains}


def initial_bits(module):
    """Yosys init lives on netnames, MSB first; maps are LSB-indexed."""
    result = {}; errors = []
    for name, net in module.get('netnames', {}).items():
        raw = net.get('attributes', {}).get('init')
        if raw is None: continue
        bits = net.get('bits', [])
        if not isinstance(raw, str) or len(raw) != len(bits) or set(raw) - set('01x'):
            errors.append(f'invalid initialization {name}'); continue
        for bit, value in zip(bits, reversed(raw)):
            if not isinstance(bit, int):
                errors.append(f'initialization on constant {name}'); continue
            if value == 'x': continue
            if bit in result and result[bit] != value: errors.append(f'conflicting initialization bit {bit}')
            result[bit] = value
    return result, errors


def parameter_int(cell, name):
    raw = cell.get('parameters', {}).get(name)
    if isinstance(raw, int) and not isinstance(raw, bool): return raw
    if isinstance(raw, str) and raw and not set(raw) - set('01'): return int(raw, 2)
    raise ValueError(f'missing or nonbinary parameter {name}')


def extract_state_model(graph):
    module = graph.module(); elements = []; unsupported = []
    init, errors = initial_bits(module)
    unsupported.extend({'cell': '', 'type': '', 'reason': e} for e in errors)
    supported = {'$dff', '$adff', '$dffe', '$adffe'}
    q_all = set()
    for name, cell in module.get('cells', {}).items():
        kind = cell.get('type', '')
        if kind not in supported:
            if not kind.startswith('$') or any(x in kind.lower() for x in ('ff', 'latch', 'tribuf', 'mem')):
                unsupported.append({'cell': name, 'type': kind, 'reason': 'unsupported state/library primitive'})
            continue
        try:
            conn = cell['connections']; q = conn['Q']; d = conn['D']; clk = conn['CLK']
            width = parameter_int(cell, 'WIDTH'); edge = parameter_int(cell, 'CLK_POLARITY')
            if width < 1 or len(q) != width or len(d) != width or len(clk) != 1 or edge not in (0,1):
                raise ValueError('invalid state widths/clock polarity')
            if any(not isinstance(b, int) or b < 2 for b in q+clk): raise ValueError('invalid Q/clock bits')
            if len(set(q)) != len(q) or q_all.intersection(q): raise ValueError('duplicate state bit')
            q_all.update(q)
            reset = (); reset_value = (); polarity = None; enable = (); en_polarity = None
            if kind in {'$adff', '$adffe'}:
                reset = tuple(conn['ARST']); polarity = parameter_int(cell, 'ARST_POLARITY')
                raw = cell['parameters']['ARST_VALUE']
                if len(reset) != 1 or polarity not in (0,1) or not isinstance(raw,str) or len(raw)!=width or set(raw)-set('01'):
                    raise ValueError('invalid asynchronous reset model')
                reset_value = tuple(reversed(raw))
            if kind in {'$dffe', '$adffe'}:
                enable = tuple(conn['EN']); en_polarity = parameter_int(cell, 'EN_POLARITY')
                if len(enable)!=1 or en_polarity not in (0,1): raise ValueError('invalid enable model')
            elements.append(StateElement(name,kind,tuple(q),tuple(d),tuple(clk),edge,reset,polarity,reset_value,enable,en_polarity,tuple(init.get(b,'x') for b in q)))
        except (KeyError, ValueError, TypeError) as exc:
            unsupported.append({'cell':name,'type':kind,'reason':str(exc)})
    if set(init)-q_all:
        unsupported.append({'cell':'','type':'','reason':'initialization on nonstate bits'})
    return StateModel(tuple(elements),tuple(unsupported))


def require_supported_state(graph):
    model = extract_state_model(graph)
    if model.unsupported: raise ValueError('unsupported state model: '+ '; '.join(x['reason'] for x in model.unsupported))
    return model
