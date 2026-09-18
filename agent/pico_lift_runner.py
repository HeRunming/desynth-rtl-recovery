#!/usr/bin/env python3
"""
pico_lift_runner.py —— PicoRV32 全量结构提升 (multiprocessing 安全)

用法:
  python3 pico_lift_runner.py [--workers N] [--timeout T]
"""
import sys, json, re, time, argparse, multiprocessing as mp
sys.path.insert(0, '/Users/blackbox/try_hai/agent')

MECH_JSON   = '/tmp/pico_mech.json'
NAMES_JSON  = '/tmp/pico_names4.json'
OUT_JSON    = '/tmp/pico_lift_results.json'


def lift_one(task):
    """Worker: runs in its own forked process with a fresh z3 context."""
    from struct_lift import lift_bus
    nm, bits, raw_funcs, rst_id, timeout = task
    r = lift_bus(nm, bits, raw_funcs, rst_net_id=rst_id, timeout_budget=timeout)
    # strip non-serialisable z3 objects before returning across process boundary
    return nm, {k: v for k, v in r.items()
                if k not in ('H_z3', 'D_z3', 'T_z3')}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--workers',  type=int, default=6)
    ap.add_argument('--timeout',  type=int, default=10,
                    help='max seconds per bus for z3')
    args = ap.parse_args()

    d     = json.load(open(MECH_JSON))
    names = json.load(open(NAMES_JSON))
    ff_map = {ff['q_id']: ff['func'] for ff in d['ff_defs']}
    meta   = {int(k): v for k, v in d['net_meta'].items()}
    ffset  = set(d['ff_q_ids'])

    # resetn = net_413  (active-low; peel_reset now tries both polarities)
    rst_id = next((nid for nid, v in meta.items()
                   if any(x in v['name'].lower() for x in ('rst','reset','clr'))
                   and v['cat'] == 'input'), None)
    print(f"rst_id={rst_id}  name={meta[rst_id]['name'] if rst_id else '?'}", flush=True)

    # Build deduplicated bus list
    buses, used = [], {}
    for b in names.get('buses', []):
        nm = re.sub(r'\W', '_', b.get('name') or 'unnamed')
        if nm in used:
            used[nm] += 1; nm = f"{nm}_{used[nm]}"
        else:
            used[nm] = 0
        bits = [x for x in b.get('bits', []) if x in ffset]
        if not bits:
            continue
        buses.append({'name': nm, 'bits': bits, 'role': b.get('role', '')})

    total_bits = sum(len(b['bits']) for b in buses)
    print(f"buses={len(buses)}  FF-bits={total_bits}", flush=True)

    tasks = [
        (b['name'], b['bits'],
         [ff_map.get(n) for n in b['bits']],
         rst_id, args.timeout)
        for b in buses
    ]

    # Use fork so child processes inherit the already-loaded modules
    ctx = mp.get_context('fork')
    t0 = time.time()
    results = {}

    with ctx.Pool(processes=args.workers) as pool:
        for i, (nm, r) in enumerate(
                pool.imap_unordered(lift_one, tasks, chunksize=3)):
            results[nm] = r
            if (i + 1) % 50 == 0:
                dt = time.time() - t0
                lifted_so_far = sum(1 for x in results.values() if x.get('lifted'))
                print(f"  {i+1}/{len(tasks)}  lifted={lifted_so_far}  ({dt:.0f}s)",
                      flush=True)

    dt = time.time() - t0
    print(f"\nFinished {len(results)} buses in {dt:.1f}s", flush=True)

    lifted  = {nm: r for nm, r in results.items() if r.get('lifted')}
    by_type: dict = {}
    for r in lifted.values():
        by_type[r['type']] = by_type.get(r['type'], 0) + 1
    rst_n = sum(1 for r in results.values() if r.get('rst_proven'))

    print(f"Lifted:  {len(lifted)}/{len(results)}")
    print(f"By type: {by_type}")
    print(f"Reset detected: {rst_n}/{len(results)}")

    # Coverage by FF bits
    lifted_bits = sum(len(results[nm]['bits']) for nm in lifted)
    print(f"Lifted FF-bits: {lifted_bits}/{total_bits} "
          f"({100*lifted_bits/total_bits:.1f}%)")

    json.dump(results, open(OUT_JSON, 'w'), indent=1)
    print(f"Saved {OUT_JSON}")


if __name__ == '__main__':
    main()
