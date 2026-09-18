#!/usr/bin/env python3
"""
lift_runner.py —— 全量结构提升 (multiprocessing 安全, 设计无关)

由 pico_lift_runner.py 泛化而来: 路径改为命令行参数, 以便在任意设计上跑。

用法:
  python3 lift_runner.py --mech mech.json --names names.json --out lift.json \
                         [--workers N] [--timeout T]
"""
import sys, json, re, time, argparse, multiprocessing as mp
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def lift_one(task):
    """Worker: 在自己的 fork 进程里跑, 有独立的 z3 context。"""
    from struct_lift import lift_bus
    nm, bits, raw_funcs, rst_id, timeout, verilog, cse_wires = task
    try:
        r = lift_bus(nm, bits, raw_funcs, rst_net_id=rst_id,
                     timeout_budget=timeout,
                     verilog=verilog, cse_wires=cse_wires)
    except Exception as e:                      # 单条 bus 失败不该拖垮全局
        return nm, {"lifted": False, "bits": bits,
                    "error": f"{type(e).__name__}: {e}"}
    # z3 对象含 ctypes 指针, 不能跨进程 pickle, 必须先剥掉
    return nm, {k: v for k, v in r.items()
                if k not in ('H_z3', 'D_z3', 'T_z3')}


def build_buses(names: dict, ffset: set) -> list:
    """去重 bus 名, 过滤掉不含 FF 的 bus。与 assemble_lifted 保持一致。"""
    buses, used = [], set()
    for b in names.get('buses', []):
        nm = re.sub(r'\W', '_', b.get('name') or 'unnamed')
        final = nm
        suffix = 1
        while final in used:
            final = f"{nm}_{suffix}"
            suffix += 1
        used.add(final)
        bits = [x for x in b.get('bits', []) if x in ffset]
        if not bits:
            continue
        buses.append({'name': final, 'bits': bits, 'role': b.get('role', '')})

    # 补上没被命名覆盖的 FF, 否则这些位会被静默丢掉
    named = {n for b in buses for n in b['bits']}
    for nid in sorted(ffset - named):
        buses.append({'name': f'unnamed_{nid}', 'bits': [nid], 'role': 'other'})
    return buses


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mech', required=True)
    ap.add_argument('--names', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--timeout', type=int, default=10,
                    help='每条 bus 的 z3 时间预算 (秒)')
    ap.add_argument('--rst', type=int, default=None,
                    help='复位 net id; 默认按名字自动找')
    ap.add_argument('--verilog', action='store_true',
                    help='强制按 Verilog/CSE 形式解析 (带 cse_prefix 的输入会自动识别)')
    args = ap.parse_args()

    d = json.loads(Path(args.mech).read_text())
    names = json.loads(Path(args.names).read_text())
    ff_map = {ff['q_id']: ff['func'] for ff in d['ff_defs']}
    wire_map = {ff['q_id']: ff.get('cse_wires') for ff in d['ff_defs']}
    meta = {int(k): v for k, v in d['net_meta'].items()}
    ffset = set(d['ff_q_ids'])

    # mech_cse.py 处理过的文件带 cse_prefix 标记, 其 func 是 Verilog 形式
    # (n123/~/1'b1) 且带 _cN wire 引用, 必须走 parse_v_z3。自动识别而不是靠
    # 手工传参: 传错会让 parse_z3 静默跳过不认识的 token 而算出错误函数。
    verilog = args.verilog or bool(d.get('cse_prefix'))
    if verilog:
        n_w = sum(1 for v in wire_map.values() if v)
        print(f"输入为 CSE/Verilog 形式 (cse_prefix={d.get('cse_prefix')!r}), "
              f"{n_w} 个函数带 wire 定义", flush=True)

    rst_id = args.rst
    if rst_id is None:
        rst_id = next((nid for nid, v in meta.items()
                       if any(x in v['name'].lower()
                              for x in ('rst', 'reset', 'clr'))
                       and v['cat'] == 'input'), None)
    print(f"rst_id={rst_id}  name={meta[rst_id]['name'] if rst_id else '?'}",
          flush=True)

    buses = build_buses(names, ffset)
    total_bits = sum(len(b['bits']) for b in buses)
    print(f"buses={len(buses)}  FF-bits={total_bits}", flush=True)

    tasks = [(b['name'], b['bits'], [ff_map.get(n) for n in b['bits']],
              rst_id, args.timeout, verilog,
              [wire_map.get(n) for n in b['bits']]) for b in buses]

    ctx = mp.get_context('fork')       # fork: 子进程继承已加载的模块
    t0 = time.time()
    results = {}
    with ctx.Pool(processes=args.workers) as pool:
        for i, (nm, r) in enumerate(
                pool.imap_unordered(lift_one, tasks, chunksize=3)):
            results[nm] = r
            if (i + 1) % 50 == 0:
                n_lift = sum(1 for x in results.values() if x.get('lifted'))
                print(f"  {i+1}/{len(tasks)}  lifted={n_lift}  "
                      f"({time.time()-t0:.0f}s)", flush=True)

    dt = time.time() - t0
    print(f"\n完成 {len(results)} 条 bus, 用时 {dt:.1f}s", flush=True)

    lifted = {nm: r for nm, r in results.items() if r.get('lifted')}
    by_type: dict = {}
    for r in lifted.values():
        by_type[r['type']] = by_type.get(r['type'], 0) + 1
    errs = [nm for nm, r in results.items() if r.get('error')]

    lifted_bits = sum(len(results[nm]['bits']) for nm in lifted)
    print(f"已提升:   {len(lifted)}/{len(results)} bus")
    print(f"按类型:   {by_type}")
    print(f"复位已证: {sum(1 for r in results.values() if r.get('rst_proven'))}"
          f"/{len(results)}")
    print(f"FF 位覆盖: {lifted_bits}/{total_bits} "
          f"({100*lifted_bits/total_bits:.1f}%)")
    if errs:
        print(f"出错 {len(errs)} 条: {errs[:5]}")

    Path(args.out).write_text(json.dumps(results, indent=1))
    print(f"写出 {args.out}")


if __name__ == '__main__':
    main()
