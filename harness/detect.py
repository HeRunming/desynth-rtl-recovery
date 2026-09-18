"""Bounded, name-independent scalar structural candidate discovery."""
from __future__ import annotations
from collections import defaultdict
from .candidate import Candidate


def _one_bit(cell, pin):
    bits = cell.get('connections', {}).get(pin, [])
    return bits[0] if len(bits) == 1 and type(bits[0]) is int else None


def propose_full_adders(graph, *, limit=1000):
    """Index motifs by input sets, avoiding Cartesian whole-netlist scans.

    All results remain untrusted candidates. Region boundary/side-output checks
    and independent proof take place after discovery.
    """
    cells = graph.module().get('cells', {})
    pairs = defaultdict(list); xor_users = defaultdict(list); xors = []
    for name, cell in cells.items():
        typ = cell.get('type')
        if typ not in {'$xor','$and','$or'}: continue
        a,b,y = (_one_bit(cell,p) for p in ('A','B','Y'))
        if None in (a,b,y) or a==b: continue
        pairs[(typ,frozenset((a,b)))].append((name,y))
        if typ == '$xor':
            item=(name,a,b,y); xors.append(item)
            xor_users[a].append(item); xor_users[b].append(item)
    result=[]; seen=set()
    consumers=defaultdict(set); drivers={}
    for name, cell in cells.items():
        for pin, bits in cell.get('connections',{}).items():
            for bit in bits:
                if cell.get('port_directions',{}).get(pin)=='input': consumers[bit].add(name)
                else: drivers[bit]=name
    outputs={b for p in graph.module().get('ports',{}).values() if p['direction']=='output' for b in p['bits']}
    for x1,a,b,mid in xors:
        for x2,x,y,summ in xor_users[mid]:
            cin = y if x==mid else x
            if x1==x2 or cin in (a,b): continue
            for and1,ab in pairs[('$and',frozenset((a,b)))]:
                for and2,ac in pairs[('$and',frozenset((mid,cin)))]:
                    for or1,carry in pairs[('$or',frozenset((ab,ac)))]:
                        region=tuple(sorted((x1,x2,and1,and2,or1)))
                        if len(set(region))!=5: continue
                        key=(region,summ,carry)
                        if key in seen: continue
                        seen.add(key)
                        region_set=set(region); keep=set(); stack=[]
                        for name in region:
                            bit=cells[name]['connections']['Y'][0]
                            if bit not in (summ,carry) and (consumers[bit]-region_set or bit in outputs): stack.append(name)
                        while stack:
                            name=stack.pop()
                            if name in keep: continue
                            keep.add(name)
                            for pin,bits in cells[name]['connections'].items():
                                if cells[name]['port_directions'][pin]=='input':
                                    stack.extend(drivers[bit] for bit in bits if drivers.get(bit) in region_set)
                        result.append(Candidate(f'fa_{x2}_{or1}',graph.source_hash,region,(*sorted((a,b)),cin),(summ,carry),'full_adder',evidence={'detector':'xor_and_or_motif','shared':mid},retained_cells=tuple(sorted(keep))))
                        if len(result)>=limit: return result
    return result
