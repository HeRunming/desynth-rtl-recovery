#!/usr/bin/env python3
"""
regroup.py —— 用 LLM 对 DANA 混合组做语义重聚类

问题: DANA 按结构相似性分组, 会把功能无关的位聚在一起
      (如把 alu_out_q + count_cycle + 13个instr_xxx译码标志 混成一组)。

方案: 对混合组, 让 LLM 看每个位的布尔函数, 按"共享输入锥/逻辑模式"
      把位重新聚成功能子组, 再对每个子组识别功能。

诚实性: 聚类只依据布尔函数结构(真实反综合场景可得), 不依赖 q_net 名字
        (真实场景名字会被抹掉)。名字仅用于事后验证聚类是否正确。
"""
import sys, json, re, time
from concurrent.futures import ThreadPoolExecutor, as_completed
sys.path.insert(0, ".")
from backends import OpenAICompatBackend

SYSTEM = "你是硬件逆向专家, 擅长从布尔函数的结构相似性对信号做功能聚类。"

# 关键: 把 q_net 名字匿名化, 只给布尔函数结构, 避免"作弊"
REGROUP_PROMPT = """下面是一个寄存器组里 {n} 个触发器的下一状态布尔函数(bit_0..bit_{last})。
它们被结构分析工具聚在一组, 但可能实际属于多个不同的功能单元。

请仅根据布尔函数的结构(共享哪些输入信号、逻辑模式是否相似、是否属于同一数据通路)
把这些 bit 重新聚类成若干功能子组。同一功能单元的位通常共享大量输入信号、有相似的更新条件。

严格按 JSON 输出(不要多余内容):
{{"clusters": [{{"bits": [0,1,2], "guess": "功能猜测", "reason": "依据"}}, ...]}}

各 bit 的下一状态函数:
{funcs}"""

CLASSIFY_PROMPT = """这是 RISC-V CPU 里一组功能相关的触发器的下一状态逻辑(布尔函数)。
判断它们构成什么功能单元, 严格按格式:
UNIT: <功能单元名>
CONFIDENCE: <高/中/低>
REASON: <一句依据>

{funcs}"""


def anonymize(fn):
    """把 net_xxx 保留(它们本就是匿名的), 无需额外处理。"""
    return fn


def regroup_one(backend, group, ff_next):
    """对一个混合组重新聚类, 返回子聚类。"""
    ffs = group["ffs"]
    # 构造匿名化的 bit 函数列表
    bit_funcs = []
    bit_to_qnet = {}
    for i, ff in enumerate(ffs):
        fn = ff_next.get(ff, {}).get("next_state") or "(常量/保持)"
        bit_to_qnet[i] = ff_next.get(ff, {}).get("q_net", ff)
        bit_funcs.append(f"bit_{i}: {fn[:1500]}")
    funcs_str = "\n".join(bit_funcs)[:100000]

    prompt = REGROUP_PROMPT.format(n=len(ffs), last=len(ffs)-1, funcs=funcs_str)
    try:
        resp = backend.complete(SYSTEM, prompt)
        m = re.search(r"\{.*\}", resp, re.DOTALL)
        clusters = json.loads(m.group(0))["clusters"] if m else []
    except Exception as e:
        return {"id": group["id"], "error": str(e)[:100], "clusters": []}

    # 用 q_net 名字验证每个子聚类的纯度(仅评估用)
    out_clusters = []
    for c in clusters:
        bits = c.get("bits", [])
        qnets = [bit_to_qnet.get(b, "?") for b in bits]
        bases = {}
        for q in qnets:
            b = re.sub(r'[\[\(]\d+[\]\)]?.*', '', q).rstrip('_')
            b = re.sub(r'_\d+$', '', b)
            bases[b] = bases.get(b, 0) + 1
        purity = max(bases.values()) / len(qnets) if qnets else 0
        out_clusters.append({
            "bits": bits, "size": len(bits),
            "llm_guess": c.get("guess", "?"),
            "signal_bases": bases,          # 真实成分(验证用)
            "purity": round(purity, 2),     # 纯度: 主导信号占比
        })
    return {"id": group["id"], "width": group["width"], "clusters": out_clusters}


def main():
    d = json.load(open("/tmp/pico_funcs.json"))
    rs = json.load(open("arch_recovery_results.json"))
    ff_next = d["ff_next_state"]

    # 找混合组
    mixed_ids = [r["id"] for r in rs if r.get("ok") and "其它" in r.get("unit", "")]
    mixed_groups = [g for g in d["register_groups"] if g["id"] in mixed_ids]
    print(f"对 {len(mixed_groups)} 个混合组做 LLM 语义重聚类 (并发)")

    backend = OpenAICompatBackend(model="gpt-5.5", timeout=300)
    results = []
    with ThreadPoolExecutor(max_workers=16) as ex:
        futs = {ex.submit(regroup_one, backend, g, ff_next): g for g in mixed_groups}
        for fut in as_completed(futs):
            results.append(fut.result())

    json.dump(results, open("regroup_results.json", "w"), ensure_ascii=False, indent=2)

    # 评估: 重聚类后子组的纯度
    print("\n=== 重聚类结果 (纯度=子组内主导信号占比, 越高说明拆得越干净) ===")
    total_sub, pure_sub = 0, 0
    for r in sorted(results, key=lambda x: x.get("width", 0), reverse=True):
        if "error" in r:
            print(f"  组{r['id']}: 失败 {r['error']}"); continue
        print(f"\n  组{r['id']} ({r['width']}位) -> 拆成 {len(r['clusters'])} 个子组:")
        for c in r["clusters"]:
            total_sub += 1
            if c["purity"] >= 0.8: pure_sub += 1
            dom = max(c["signal_bases"], key=c["signal_bases"].get) if c["signal_bases"] else "?"
            flag = "✓" if c["purity"] >= 0.8 else " "
            print(f"    {flag} {c['size']}位 纯度{c['purity']} 主导={dom} | LLM猜:{c['llm_guess'][:30]}")
    print(f"\n=== 汇总: {pure_sub}/{total_sub} 个子组纯度>=0.8 (拆分成功) ===")


if __name__ == "__main__":
    main()
