"""
semantic_naming.py —— 让 LLM 从布尔函数结构推断语义命名 + 位序

诚实性原则:
  真实反综合场景里, 网表信号名会被抹掉(只剩 net_12345)。
  所以这里喂给 LLM 的是"匿名化"的布尔函数, 只有 net_id, 没有任何原始名字。
  原始名字(q_net)只用于事后评估命名质量, 绝不进入 prompt。

输出: 命名方案 JSON
  {groups: [{name, bits:[net_id...], role, evidence}], singles: [...]}
"""
import json, os, re, sys, concurrent.futures as cf
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from collections import Counter
from backends import OpenAICompatBackend
from artifact_contract import attach_contract, normalize_ports

# mech_cse.py 产出的共享子表达式引用 (_c0, _c1, ...)
_CREF = re.compile(r"_c\d+")

SYS = """你是硬件逆向专家。给你一组触发器的"下一状态布尔函数"(变量是匿名 net 编号),
请推断它们构成什么功能单元、如何分组成总线、以及总线内的位序。

判断线索:
- 计数器: 最低位是 q <= ~q (每拍翻转); 第i位依赖所有低位的AND(进位链)
- 移位寄存器: 第i位的下一状态 = 第i±1位的当前值
- 状态机: 少数几位, 函数里有大量互斥条件组合
- 数据寄存器/锁存器: q <= (使能 ? 新值 : q) 形式, 有明显保持项
- 寄存器堆: 大量位, 由地址译码(独热)选择写入

只输出 JSON, 不要解释:
{
  "buses": [
    {"name": "小写下划线命名(如 cycle_counter)", "role": "counter|shift_reg|state|data_reg|regfile|flag|other",
     "bits": [按LSB到MSB顺序的net_id], "evidence": "一句话依据"}
  ]
}
要求:
- 每个给定的 net_id 必须恰好出现在一个 bus 的 bits 里
- 单独的1位信号也要作为 bus(bits只有一个元素)
- bits 顺序很重要: 必须是 [LSB, ..., MSB]
- name 要能反映功能, 用英文小写下划线"""


def _inline_small_wires(body: str, wires, max_len: int = 60) -> tuple:
    """把短的 _cN 定义内联回表达式, 长的保留引用并返回其定义。

    为什么必须做 (实测): mech_cse.py 把结构证据从 func 搬进了 cse_wires,
    如果只喂 func, LLM 看到的是 `(_c16 & (_c11 | _c3))` 这种不透明引用 ——
    压缩函数平均 56% 的叶子引用是 _cN, 71% 的函数超过一半不透明。
    而 prompt 里列的判断线索(进位链/XOR/使能保持)恰恰藏在这些定义里。
    **这个退化不报任何错**, 只表现为命名质量静默塌成一堆 "other"。

    策略: 短定义内联 → 结构线索直接可见; 长定义保留具名引用 + where 块 →
    反而比原始扁平形式更可读(有具名中间量, 而非同一大段抄很多遍)。
    """
    if not wires:
        return body, []

    # 必须按**正向**拓扑序展开: cse 保证 _cN 只引用 _cM (M<N), 所以正序处理时
    # 一个定义引用到的 wire 都已经展开完了。
    # (写成 reversed 是错的: 那样只能拿高编号去替低编号的定义, 而低编号从不
    #  引用高编号 —— 替换全是空转, 函数看似工作实则一个都没内联。)
    small, full = {}, {}

    def expand(text: str) -> str:
        return _CREF.sub(lambda m: small.get(m.group(0), m.group(0)), text)

    for wn, we in wires:
        e = expand(we)
        full[wn] = e
        if len(e) <= max_len:
            small[wn] = e

    body = expand(body)

    # 仍被引用的长定义: 要取**闭包** —— 长定义里可能引用别的长定义, 那些也必须
    # 列出, 否则 where 块里会出现没有定义的 _cN (LLM 又看不懂了)。
    need, seen = [], set()
    stack = [w for w in _CREF.findall(body) if w in full and w not in small]
    while stack:
        w = stack.pop()
        if w in seen:
            continue
        seen.add(w)
        need.append(w)
        for w2 in _CREF.findall(full[w]):
            if w2 in full and w2 not in small and w2 not in seen:
                stack.append(w2)

    order = {wn: i for i, (wn, _) in enumerate(wires)}
    rest = [(w, full[w]) for w in sorted(need, key=lambda x: order.get(x, 0))]
    return body, rest


def _needed_defs(text: str, defs) -> list:
    """text 里引用到的 _cN 定义 (含闭包), 保持 defs 原有顺序。

    必须在**截断之后**算: 截断过的 body 引用的 wire 远少于完整 body,
    按完整 body 算再截 where 块, 会留下没有定义的 _cN。
    """
    dmap = dict(defs)
    need, seen = [], set()
    stack = [w for w in _CREF.findall(text) if w in dmap]
    while stack:
        w = stack.pop()
        if w in seen:
            continue
        seen.add(w)
        need.append(w)
        for w2 in _CREF.findall(dmap[w]):
            if w2 in dmap and w2 not in seen:
                stack.append(w2)
    order = {w: i for i, (w, _) in enumerate(defs)}
    return [(w, dmap[w]) for w in sorted(need, key=lambda x: order.get(x, 0))]


def _render_one(func: str, wires, func_cap: int, wire_cap: int) -> tuple:
    """渲染单个 FF 的函数文本 + 需要附带的 wire 定义。

    保证 **body 里出现的每个 _cN 都有定义** —— 装不下就把 max_len 调大、
    内联得更彻底 (极限情况全部内联, body 里一个 _cN 都不剩, 自然不会悬空)。
    宁可 body 长一点被截断, 也不能给 LLM 看无定义的符号。
    """
    if not wires:
        return (func[:func_cap] if func_cap else func), []
    for max_len in (60, 200, 800, 10 ** 9):
        body, rest = _inline_small_wires(func, wires, max_len=max_len)
        shown = body[:func_cap] if func_cap else body
        need = _needed_defs(shown, rest)
        total = sum(len(w) + len(e) + 6 for w, e in need)
        if total <= wire_cap or max_len == 10 ** 9:
            return shown, need
    return shown, need


def build_prompt(ff_items, port_hint, func_cap: int = 0, wire_cap: int = 1200):
    """func_cap: 截断长度, 0 表示不截断。

    注意截断**必须在内联之后**做: 内联会把 _cN 展开成真正的结构线索,
    先截断再内联等于先把线索砍掉。
    """
    lines = [f"触发器数量: {len(ff_items)}", ""]
    if port_hint:
        lines.append(f"该模块的端口(可作为语义线索): {port_hint}")
        lines.append("")
    lines.append("各触发器的下一状态函数:")
    any_wire = False
    for it in ff_items:
        # 由 _render_one 统一处理: 内联 → 截断 → 只取截断后仍被引用的定义闭包。
        # 不能"按完整 body 算闭包再截 where 块" —— 实测那样 57/60 个函数的 body
        # 里都会出现没有定义的 _cN, LLM 照样看不懂 (而且不报错)。
        f, rest = _render_one(it["func"] or "", it.get("cse_wires") or [],
                             func_cap, wire_cap)
        lines.append(f"  FF net_{it['q_id']}:  next = {f}")
        if rest:
            any_wire = True
            lines.append("    其中 (共享子表达式):")
            for wn, we in rest:
                lines.append(f"      {wn} = {we}")
    if any_wire:
        lines.append("")
        lines.append("注: _cN 是自动提取的共享子表达式(等价于把它的定义原地展开),"
                     "多个 FF 引用同一个 _cN 说明它们共享该逻辑 —— 这本身就是"
                     "'属于同一功能单元'的有力线索。")
    return "\n".join(lines)


def name_group(be, ff_items, port_hint="", func_cap=600, retries=3):
    """让 LLM 给一组 FF 命名和分组。返回 buses 列表。
    func_cap: 每个函数截断长度(大设计的函数极长, 会把网关打超时)
    retries : 失败重试(网关 5xx 常见), 每次退避并进一步截短"""
    import time, random
    last = None
    for att in range(retries):
        cap = max(200, func_cap // (2 ** att))
        # 不在这里截断 func: 截断必须发生在 _cN 内联之后, 否则等于先把结构
        # 线索砍掉再展开。cap 交给 build_prompt, 它会先内联再截。
        # 同理 cse_wires 必须原样传下去 —— 之前只传 func, 导致 LLM 看到的是
        # 一堆不透明的 _cN 引用 (实测 71% 的压缩函数过半引用不透明)。
        try:
            raw = be.complete(SYS, build_prompt(ff_items, port_hint,
                                                func_cap=cap,
                                                wire_cap=max(400, cap * 2)))
            break
        except Exception as e:
            last = str(e)[:200]
            time.sleep(2 + random.random() * 3 * (att + 1))
    else:
        return {"error": last, "buses": []}
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        return {"error": "no json", "raw": raw[:300], "buses": []}
    try:
        return json.loads(m.group(0))
    except Exception as e:
        return {"error": f"json parse: {e}", "raw": raw[:300], "buses": []}


def _norm_name(s: str) -> str:
    """归一化 bus 名, 用于判断两条 bus 是否"同一个东西被切成两半"。

    去掉尾部数字/序号后缀: data_register_hi / data_register_2 → data_register。
    """
    s = re.sub(r"\W+", "_", (s or "").strip().lower())
    s = re.sub(r"_(lo|hi|low|high|upper|lower|part|seg|msb|lsb)$", "", s)
    s = re.sub(r"_\d+$", "", s)
    return s.strip("_")


def merge_split_buses(buses, cut_pairs=None, max_gap: int = 4) -> tuple:
    """把被批次边界切断的总线合并回去。

    为什么在输出端做而不是改分批 (实测): 固定大小分批按 q_id 顺序切, 而同一总线
    的 net id 通常连续 —— 这已经是最强的可用信号。两种"更聪明"的扇入聚类都更差
    (平均碎片 2.33 → 2.69 / 6.17), 因为 CPU 数据通路里所有 FF 都共享译码逻辑,
    "共享扇入"区分不出总线, 打乱 q_id 顺序反而丢掉了唯一有效信号。

    cut_pairs: {(上一批最后一个 q_id, 下一批第一个 q_id)} —— 批次切口。
      **不能只靠名字判同一总线**: 试点里 pcpi_rs1 的两半被 LLM 命名成
      data_register 和 control_data_byte, 名字完全不同, 按名字归一化合不上。
      而"切口正好落在批次边界"是这类人为切断的确定性证据。

    合并判据 (role 必须相同, 且满足其一):
      - 归一化名相同, 且两段 net id 区间相邻 (间隔 <= max_gap)
      - 断点恰好是一个批次切口 (LLM 不可能看到跨批的位, 名字不同也应合并)

    返回 (合并后的 buses, 合并次数)。位序按 net id 升序重排 (LSB..MSB)。
    """
    cuts = set(cut_pairs or ())
    segs = []
    for b in buses:
        bits = sorted(int(x) for x in b.get("bits", []))
        if bits:
            segs.append({**b, "bits": bits})
    segs.sort(key=lambda x: x["bits"][0])

    out, merged = [], 0
    cur = None
    for s in segs:
        if cur is None:
            cur = s
            continue
        same_role = cur.get("role", "") == s.get("role", "")
        adjacent = s["bits"][0] - cur["bits"][-1] <= max_gap
        at_cut = (cur["bits"][-1], s["bits"][0]) in cuts
        same_name = _norm_name(cur.get("name")) == _norm_name(s.get("name"))
        if same_role and (at_cut or (same_name and adjacent)):
            cur = {**cur,
                   "bits": sorted(set(cur["bits"]) | set(s["bits"])),
                   "evidence": ((cur.get("evidence") or "") + " | 跨批合并("
                                + ("批次切口" if at_cut else "同名相邻") + "): "
                                + (s.get("evidence") or ""))[:400]}
            merged += 1
        else:
            out.append(cur); cur = s
    if cur is not None:
        out.append(cur)
    return out, merged


def validate_plan(plan, expected_ids):
    """检查命名方案是否覆盖了所有 FF、无重复。返回 (ok, 问题描述, 修正后plan)"""
    seen, dup = set(), []
    buses = plan.get("buses", [])
    for b in buses:
        for nid in b.get("bits", []):
            if nid in seen:
                dup.append(nid)
            seen.add(nid)
    missing = sorted(set(expected_ids) - seen)
    extra = sorted(seen - set(expected_ids))
    # 修正: 丢掉不存在的 id, 漏掉的补成单独 bus
    if extra or missing or dup:
        fixed = []
        used = set()
        for b in buses:
            bits = []
            for n in b.get("bits", []):
                # Check against ``used`` while iterating so duplicates within
                # a single bus are repaired as well as duplicates across buses.
                if n in expected_ids and n not in used:
                    bits.append(n)
                    used.add(n)
            if not bits:
                continue
            fixed.append({**b, "bits": bits})
        for nid in sorted(set(expected_ids) - used):
            fixed.append({"name": f"unnamed_{nid}", "role": "other",
                          "bits": [nid], "evidence": "LLM未覆盖, 自动补齐"})
        plan = {**plan, "buses": fixed}
    return (not missing and not extra and not dup), \
           {"missing": missing, "extra": extra, "dup": dup}, plan


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--mech", required=True, help="hal_mechanical.py 输出的 json")
    ap.add_argument("--groups", help="可选: arch_recovery 的分组(用DANA分组分批喂LLM)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default="gpt-5.5")
    ap.add_argument("--max-ff-per-call", type=int, default=40)
    ap.add_argument("--conc", type=int, default=32)
    ap.add_argument("--no-merge", action="store_true",
                    help="关闭跨批总线合并 (默认开启: 把被批次边界切断的总线合回去)")
    args = ap.parse_args()

    data = json.loads(Path(args.mech).read_text())
    ffs = data["ff_defs"]
    ports = normalize_ports(data)
    # Canonical ports are name -> metadata mappings; normalize_ports also
    # handles legacy top_ports lists and mechanical id arrays.
    port_names = list(ports.get("inputs", {}).keys()) + list(ports.get("outputs", {}).keys())
    port_hint = ", ".join(port_names[:24])

    # 分批: 按 DANA 分组; 没有则按固定大小切
    batches = []
    if args.groups and Path(args.groups).exists():
        gd = json.loads(Path(args.groups).read_text())
        gid_of = {}
        for g in gd.get("groups", []):
            for nid in g.get("bits", g.get("net_ids", [])):
                gid_of[nid] = g.get("gid")
        byg = {}
        for f in ffs:
            byg.setdefault(gid_of.get(f["q_id"], -1), []).append(f)
        # 大组单独成批(必要时切分); 小组合并装箱, 保证每次调用有足够上下文
        small = []
        for k, v in sorted(byg.items(), key=lambda kv: -len(kv[1])):
            if len(v) >= 8:
                for i in range(0, len(v), args.max_ff_per_call):
                    batches.append(v[i:i + args.max_ff_per_call])
            else:
                small.extend(v)
        for i in range(0, len(small), args.max_ff_per_call):
            batches.append(small[i:i + args.max_ff_per_call])
    else:
        # 按 q_id 顺序切固定大小。看着朴素, 但实测是最好的可用方案:
        # 同一总线的 net id 通常连续, 顺序切天然把同总线的位放在一批。
        # 试过两种"更聪明"的扇入聚类, 都更差 (平均碎片 2.33 → 2.69 / 6.17):
        # CPU 数据通路里所有 FF 都共享指令译码逻辑, "共享扇入"不足以区分总线,
        # 而打乱 q_id 顺序反而丢掉了唯一有效的信号。
        # 被批次边界切断的总线由 merge_split_buses() 在输出端事后合并。
        for i in range(0, len(ffs), args.max_ff_per_call):
            batches.append(ffs[i:i + args.max_ff_per_call])

    print(f"共 {len(ffs)} 个FF, 分 {len(batches)} 批, 并发 {args.conc}", flush=True)
    be = OpenAICompatBackend(model=args.model, timeout=600)

    all_buses, errs = [], 0
    invalid_batches = 0
    repair_count = 0
    validation_records = []
    with cf.ThreadPoolExecutor(max_workers=args.conc) as ex:
        futs = {ex.submit(name_group, be, b, port_hint): i for i, b in enumerate(batches)}
        done = 0
        for fu in cf.as_completed(futs):
            i = futs[fu]
            plan = fu.result()
            ids = [f["q_id"] for f in batches[i]]
            ok, prob, plan = validate_plan(plan, ids)
            repairs = sum(len(prob.get(k, [])) for k in ("missing", "extra", "dup"))
            repair_count += repairs
            if not ok:
                invalid_batches += 1
            if plan.get("error") or not ok:
                errs += 1
            validation_records.append({
                "batch": i, "ok": bool(ok), "problems": prob,
                "repairs": repairs, "error": plan.get("error"),
            })
            all_buses.extend(plan.get("buses", []))
            done += 1
            if done % 10 == 0 or done == len(batches):
                print(f"  进度 {done}/{len(batches)}", flush=True)

    n_raw = len(all_buses)
    if not args.no_merge:
        # 批次切口: 相邻两批的 (上批最后一个 q_id, 下批第一个 q_id)。
        # LLM 不可能看到跨批的位, 所以切口处的断裂是人为的, 名字不同也该合并。
        cut_pairs = set()
        for a, b in zip(batches, batches[1:]):
            if a and b:
                cut_pairs.add((int(a[-1]["q_id"]), int(b[0]["q_id"])))
        all_buses, n_merged = merge_split_buses(all_buses, cut_pairs)
        if n_merged:
            print(f"\n跨批合并: {n_raw} → {len(all_buses)} 条 bus "
                  f"({n_merged} 次合并)")

    out = {
        "buses": all_buses, "n_ff": len(ffs), "errors": errs,
        "ports": ports,
        "validation": {
            "batches": len(batches), "invalid_batches": invalid_batches,
            "repair_count": repair_count, "records": validation_records,
        },
    }
    attach_contract(
        out, stage="semantic_naming", input_paths={"mechanical": args.mech},
        counts={
            "ffs": len(ffs), "buses": len(all_buses), "batches": len(batches),
            "invalid_batches": invalid_batches, "repairs": repair_count,
            "errors": errs,
        },
        status="partial" if errs or repair_count else "ok",
    )
    Path(args.out).write_text(json.dumps(out, indent=1))
    print(f"\n生成 {len(all_buses)} 个总线定义, 失败批次 {errs}")
    print(f"写入 {args.out}")

    print("\n角色分布:", dict(Counter(b.get("role", "?") for b in all_buses)))


if __name__ == "__main__":
    main()
