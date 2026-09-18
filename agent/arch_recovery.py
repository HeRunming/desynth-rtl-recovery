#!/usr/bin/env python3
"""
arch_recovery.py —— PicoRV32 架构还原报告 (并发)

对 HAL 分出的每个寄存器组, 并发调 LLM 识别其功能语义,
汇总成一份"这个 CPU 由哪些功能单元组成"的架构还原报告。

验证核心命题: HAL 分块 + LLM 语义识别, 能否还原真实 CPU 的架构。
"""
import sys, json, time, re
from concurrent.futures import ThreadPoolExecutor, as_completed
sys.path.insert(0, ".")
from backends import OpenAICompatBackend

FUNCS_JSON = "/tmp/pico_funcs.json"
CONCURRENCY = 32          # 并发数 (API 可承受 200, 保守取 32)
MAX_CHARS_PER_BLOCK = 120000

SYSTEM = "你是硬件逆向工程专家, 擅长从门级布尔函数识别功能单元。回答必须简洁、结构化。"

PROMPT_TMPL = """下面是 RISC-V CPU (PicoRV32) 里一个 {width}位寄存器组的下一状态逻辑,
由 HAL 从门级网表精确提取的布尔函数 (net_xxx 是内部信号, cpuregs/其它名字是恢复出的信号名)。

请判断这个寄存器组是什么功能单元, 严格按以下格式回答(不要多余内容):
UNIT: <功能单元名称, 如 寄存器堆/程序计数器PC/指令寄存器/ALU结果寄存器/流水线状态机/移位器/乘法器/内存地址寄存器/其它>
CONFIDENCE: <高/中/低>
REASON: <一句话依据>

寄存器组的下一状态逻辑:
{block}"""


def classify_group(backend, group, ff_next):
    lines = []
    for ff in group["ffs"]:
        fn = ff_next.get(ff, {}).get("next_state")
        qn = ff_next.get(ff, {}).get("q_net", ff)
        if fn:
            lines.append(f"{qn} <= {fn};")
    block = "\n".join(lines)[:MAX_CHARS_PER_BLOCK]
    prompt = PROMPT_TMPL.format(width=group["width"], block=block)
    t0 = time.time()
    try:
        resp = backend.complete(SYSTEM, prompt)
        unit = _extract(resp, "UNIT")
        conf = _extract(resp, "CONFIDENCE")
        reason = _extract(resp, "REASON")
        return {"id": group["id"], "width": group["width"], "ok": True,
                "unit": unit, "confidence": conf, "reason": reason,
                "seconds": round(time.time() - t0, 1)}
    except Exception as e:
        return {"id": group["id"], "width": group["width"], "ok": False,
                "error": str(e)[:120], "seconds": round(time.time() - t0, 1)}


def _extract(text, key):
    m = re.search(rf"{key}\s*[:：]\s*(.+)", text)
    return m.group(1).strip()[:80] if m else "?"


def main():
    d = json.load(open(FUNCS_JSON))
    groups = d["register_groups"]
    ff_next = d["ff_next_state"]
    # 只跑有意义的组 (宽度>=2, 单bit的多是零散控制位, 太多且噪声大)
    targets = [g for g in groups if g["width"] >= 2]
    print(f"总寄存器组 {len(groups)}, 待识别(宽度>=2) {len(targets)} 个, 并发 {CONCURRENCY}")

    backend = OpenAICompatBackend(model="gpt-5.5", timeout=300)
    results = []
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=CONCURRENCY) as ex:
        futs = {ex.submit(classify_group, backend, g, ff_next): g for g in targets}
        done = 0
        for fut in as_completed(futs):
            r = fut.result()
            results.append(r)
            done += 1
            if done % 10 == 0 or done == len(targets):
                print(f"  进度 {done}/{len(targets)} ({time.time()-t0:.0f}s)")

    results.sort(key=lambda x: -x["width"])
    json.dump(results, open("arch_recovery_results.json", "w"),
              ensure_ascii=False, indent=2)
    print(f"\n总耗时 {time.time()-t0:.0f}s, 结果存 arch_recovery_results.json")

    # 汇总
    ok = [r for r in results if r.get("ok")]
    print(f"\n=== 识别成功 {len(ok)}/{len(targets)} ===")
    from collections import Counter
    units = Counter(r["unit"] for r in ok)
    print("=== 功能单元分布 ===")
    for u, c in units.most_common():
        print(f"  {c:>3}组  {u}")


if __name__ == "__main__":
    main()
