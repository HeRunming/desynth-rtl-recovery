#!/usr/bin/env python3
"""公共子表达式提取 (CSE)。

动机
----
结构提升把 next-state f 拆成 H = f1 & ~f0 与 D = f0。这两半引用的信号
集合重叠度接近 100% —— 抽样测得完全一致 —— 所以 H/D 拆分本身会把同一份
组合逻辑重述两遍, 文本反而比 raw 膨胀 1.5×。

本模块把重复出现的子表达式抽成命名 wire, 让 always 块里只留下结构:

    if (~(A & B & C)) q <= (A & B & D);        →   wire w0 = (A & B);
                                                   if (~(w0 & C)) q <= (w0 & D);

正确性
------
提出去的 wire 是纯组合的, 用 `assign` 在 always 块外连续求值; always 块在
时钟沿采样它, 与内联展开的语义完全一致。这是纯文本层面的重写, 不改变任何
布尔函数, 所以不需要 z3 重新证明 —— 但仍然用仿真交叉验证 (见 verify_cse)。

依赖 z3_to_verilog 的输出是全括号化的: 每个复合表达式都自带一对外层括号,
所以下面的递归下降解析器无歧义, 不需要处理运算符优先级。
"""
from __future__ import annotations
import re
from typing import Dict, List, Tuple, Optional
from collections import Counter

__all__ = ["ExprDAG", "cse_expressions"]

# 节点: ('leaf', name) | (op, child_id, ...)   op ∈ ~ & | ^ ?: ==
TOK = re.compile(r"""
      \d+'[bdh][0-9a-fA-FxzXZ_]+      # 4'b1010
    | [A-Za-z_][\w$.]*(?:\[\d+\])?    # sig / hier.path / sig[3]
    | ~ | & | \| | \^ | \( | \) | \? | : | ==
""", re.X)


class ExprDAG:
    """哈希消解 (hash-consed) 的表达式 DAG。

    结构相同的子表达式共享同一个节点 id, 这是 CSE 能工作的前提。
    """

    def __init__(self):
        self.nodes: List[tuple] = []
        self._intern: Dict[tuple, int] = {}
        self._size: Dict[int, int] = {}       # 节点 → 叶子数
        self._txt: Dict[int, str] = {}        # 节点 → 展开文本 (缓存)

    # ── 构造 ──────────────────────────────────────────────
    def mk(self, node: tuple) -> int:
        i = self._intern.get(node)
        if i is None:
            i = len(self.nodes)
            self.nodes.append(node)
            self._intern[node] = i
        return i

    def leaf(self, name: str) -> int:
        return self.mk(("leaf", name))

    # ── 解析 ──────────────────────────────────────────────
    def parse(self, s: str) -> int:
        toks = TOK.findall(s)
        pos = [0]

        def peek() -> Optional[str]:
            return toks[pos[0]] if pos[0] < len(toks) else None

        def take() -> str:
            t = toks[pos[0]]; pos[0] += 1; return t

        def expr() -> int:
            """一个完整表达式。全括号化保证: 要么是叶子, 要么 '(' 开头。"""
            t = peek()
            if t is None:
                raise ValueError(f"意外结束: {s[:80]}")
            if t == "~":
                take()
                return self.mk(("~", expr()))
            if t == "(":
                take()
                first = expr()
                nxt = peek()
                if nxt == ")":
                    take()
                    return first          # 冗余括号 (~x) 这类
                if nxt == "?":            # ITE
                    take(); th = expr()
                    assert peek() == ":", f"缺 ':' in {s[:80]}"
                    take(); el = expr()
                    assert peek() == ")"; take()
                    return self.mk(("?:", first, th, el))
                op = nxt                  # & | ^ ==
                assert op in ("&", "|", "^", "=="), f"未知运算符 {op}"
                kids = [first]
                while peek() == op:
                    take(); kids.append(expr())
                assert peek() == ")", f"缺 ')' in {s[:80]} 剩 {toks[pos[0]:pos[0]+4]}"
                take()
                # n 元结点: 排序使 (a&b) 与 (b&a) 共享 (== 不可交换处理为有序)
                if op in ("&", "|", "^"):
                    kids = tuple(sorted(kids))
                return self.mk((op, *kids))
            # 叶子
            return self.leaf(take())

        r = expr()
        if pos[0] != len(toks):
            raise ValueError(f"尾部残留 {toks[pos[0]:pos[0]+5]} in {s[:80]}")
        return r

    # ── 重写 ──────────────────────────────────────────────
    def rewrite(self, remap: Dict[int, int], roots: Dict[str, int]) -> None:
        """把 remap 里的结点替换掉, 并把替换沿父边向上传播。

        按 id 升序处理: 构造时子结点总先于父结点 intern, 所以升序即拓扑序,
        处理到某个父结点时它的孩子已经定稿。新建的结点 id 更大, 保持该不变量。
        """
        m = dict(remap)
        n_orig = len(self.nodes)
        for i in range(n_orig):
            n = self.nodes[i]
            if n[0] == "leaf" or i in m:
                continue
            kids = tuple(m.get(c, c) for c in n[1:])
            if kids == n[1:]:
                continue
            if n[0] in ("&", "|", "^"):
                kids = tuple(sorted(set(kids)))
                if len(kids) == 1:
                    m[i] = kids[0]
                    continue
            j = self.mk((n[0], *kids))
            if j != i:
                m[i] = j
        for k, r in list(roots.items()):
            if r in m:
                roots[k] = m[r]

    # ── 可达性 ────────────────────────────────────────────
    def reachable_uses(self, roots) -> Counter:
        """从根出发统计每个结点被多少条父边引用 (根算一次)。

        必须按可达性统计: rewrite 会在 nodes 里留下不再被引用的死结点,
        直接遍历 self.nodes 数边会把死结点的边也算进去, 从而高估引用数。
        """
        uses: Counter = Counter()
        seen = set()
        stack = []
        for r in roots:
            uses[r] += 1
            stack.append(r)
        while stack:
            i = stack.pop()
            if i in seen:
                continue
            seen.add(i)
            n = self.nodes[i]
            if n[0] == "leaf":
                continue
            for c in n[1:]:
                uses[c] += 1
                if c not in seen:
                    stack.append(c)
        return uses

    # ── 度量 ──────────────────────────────────────────────
    def size(self, i: int) -> int:
        """子树叶子数, 作为 '值不值得提出来' 的代价度量。"""
        if i in self._size:
            return self._size[i]
        n = self.nodes[i]
        v = 1 if n[0] == "leaf" else sum(self.size(c) for c in n[1:])
        self._size[i] = v
        return v

    # ── 发射 ──────────────────────────────────────────────
    def to_verilog(self, i: int, wire_of: Dict[int, str] = None,
                   _root: bool = True) -> str:
        """还原为 Verilog。wire_of 里的节点替换成 wire 名 (根节点除外)。"""
        if wire_of and not _root and i in wire_of:
            return wire_of[i]
        n = self.nodes[i]
        op = n[0]
        if op == "leaf":
            return n[1]
        if op == "~":
            inner = self.to_verilog(n[1], wire_of, False)
            return f"(~{inner})"
        if op == "?:":
            c, t, e = (self.to_verilog(x, wire_of, False) for x in n[1:])
            return f"({c} ? {t} : {e})"
        parts = [self.to_verilog(c, wire_of, False) for c in n[1:]]
        return "(" + f" {op} ".join(parts) + ")"


def factor_nary(dag: "ExprDAG", roots: Dict[str, int],
                min_ops: int = 10, min_uses: int = 32,
                max_rounds: int = 400) -> int:
    """把 n 元 & / | 结点里频繁共现的操作数子集提出成新结点。

    为什么需要这一步: 纯子树 CSE 只能提取"完整的子树"。但寄存器堆这种结构里,
    32 个位切片各自是一个 10+ 操作数的 AND, 它们共享其中 ~10 个操作数, 却因为
    每位还多带一个自己的地址译码项而不构成同一棵子树。结果是那个共享的写使能
    在 32 行里逐字重复。

    这里做的是: 对同一运算符的 n 元结点, 找出频繁共现的操作数子集 S,
    新建结点 (op, *S), 并把原结点重写成 (op, S结点, ...剩余操作数)。
    因为 & 和 | 都满足结合律与交换律, 这个重写保持语义。

    返回提取出的子集个数。就地修改 dag 与 roots。
    """
    made = 0
    for _ in range(max_rounds):
        # ── 收集当前 *从根可达的* n 元 & / | 结点 ─────────────
        #  必须限制在可达结点上: rewrite 会留下不再被引用的死结点, 若把它们
        #  也算进来, 每轮都会在死结点里"发现"同一个可提取子集、重写死结点、
        #  活的 DAG 却毫无变化 —— 循环永不收敛, 且结果取决于残留了哪些死结点。
        live = set(dag.reachable_uses(roots.values()))
        groups: Dict[str, List[int]] = {"&": [], "|": []}
        for i in live:
            n = dag.nodes[i]
            if n[0] in ("&", "|") and len(n) - 1 >= min_ops:
                groups[n[0]].append(i)

        best = None          # (收益, op, 子集frozenset, [结点id])
        for op, ids in groups.items():
            if len(ids) < min_uses:
                continue
            opsets = {i: frozenset(dag.nodes[i][1:]) for i in ids}

            # 只保留出现在 >= min_uses 个结点里的 "热" 操作数,
            # 否则签名会被各自独有的译码项打散。
            freq: Counter = Counter()
            for s in opsets.values():
                freq.update(s)
            hot = {o for o, c in freq.items() if c >= min_uses}
            if not hot:
                continue

            sig: Dict[frozenset, List[int]] = {}
            for i, s in opsets.items():
                k = s & hot
                if len(k) >= 2:
                    sig.setdefault(k, []).append(i)

            # 候选 1: 完全相同的热签名
            cands: Dict[frozenset, List[int]] = dict(sig)
            # 候选 2: 两两签名的交集 —— 捕捉 "大部分相同, 少数不同" 的情况
            keys = sorted(sig, key=lambda k: -len(sig[k]))[:40]
            for a in range(len(keys)):
                for b in range(a + 1, len(keys)):
                    inter = keys[a] & keys[b]
                    if len(inter) >= 2 and inter not in cands:
                        cands[inter] = [i for k in keys
                                        for i in sig[k] if inter <= k]

            for sub, users in cands.items():
                users = [i for i in users if sub <= opsets[i]]
                if len(users) < min_uses:
                    continue
                # 收益: 每个用户少写 (|sub|-1) 个操作数; 减去 wire 自身一次
                gain = (len(users) - 1) * (sum(dag.size(o) for o in sub) - 1)
                if gain <= 0:
                    continue
                if best is None or gain > best[0]:
                    best = (gain, op, sub, users)

        if best is None:
            break

        _, op, sub, users = best
        sub_id = dag.mk((op, *tuple(sorted(sub))))
        made += 1
        # ── 重写用户结点 ────────────────────────────────────
        remap: Dict[int, int] = {}
        for i in users:
            if i == sub_id:
                continue
            rest = [o for o in dag.nodes[i][1:] if o not in sub]
            kids = tuple(sorted([sub_id] + rest))
            new_i = dag.mk((op, *kids)) if len(kids) > 1 else kids[0]
            if new_i != i:
                remap[i] = new_i
        if not remap:
            break
        dag.rewrite(remap, roots)
    return made


def cse_expressions(exprs: Dict[str, str],
                    min_size: int = 3,
                    min_uses: int = 2,
                    max_wires: int = 4000,
                    factor: bool = True,
                    ) -> Tuple[Dict[str, str], List[Tuple[str, str]]]:
    """对一组具名表达式做全局 CSE。

    参数
    ----
    exprs     : {标签 → Verilog 表达式}。标签只用于把结果对回去。
    min_size  : 子树至少这么多叶子才考虑提取 (太小的 wire 不划算)。
    min_uses  : 至少被引用这么多次才提取。
    max_wires : wire 数量上限, 按 收益 = (引用数-1)×大小 取最优的那些。

    返回
    ----
    (新表达式表, [(wire名, wire表达式)] 按拓扑序)
    """
    dag = ExprDAG()
    roots: Dict[str, int] = {}
    for k, s in exprs.items():
        if s is None:
            continue
        st = s.strip()
        if not st:
            continue
        roots[k] = dag.parse(st)

    # ── n 元操作数因式提取 (可选) ─────────────────────────
    #  参数刻意取得很挑: 实测少数几个大的、被高度共享的操作数子集
    #  (5 个提取, 0.085x) 明显优于大量小提取 (199 个提取, 0.146x),
    #  而且快三个数量级 —— 小提取会把纯子树 CSE 本可整棵共享的结构打碎。
    if factor:
        factor_nary(dag, roots)

    # ── 统计引用数 (DAG 上每个节点被多少个父边指向) ─────────
    #  用 DAG 边计数而不是展开树计数: 我们要的是 "会在文本里出现几次"。
    #  只统计从根可达的结点 —— factor_nary 会留下死结点。
    uses = dag.reachable_uses(roots.values())

    # ── 候选打分 ────────────────────────────────────────
    cand = []
    for i, n in enumerate(dag.nodes):
        if n[0] == "leaf":
            continue
        u, sz = uses[i], dag.size(i)
        if u >= min_uses and sz >= min_size:
            cand.append(((u - 1) * sz, i))       # 节省的叶子数
    cand.sort(reverse=True)
    chosen = sorted(i for _, i in cand[:max_wires])

    wire_of: Dict[int, str] = {i: f"w{k}" for k, i in enumerate(chosen)}

    # ── wire 定义, 拓扑序 (子节点先于父节点) ────────────────
    #  chosen 是升序的 node id; DAG 构造保证子节点 id < 父节点 id,
    #  因为节点是自底向上 intern 的。所以升序即拓扑序。
    wires: List[Tuple[str, str]] = []
    for i in chosen:
        wires.append((wire_of[i], dag.to_verilog(i, wire_of, _root=True)))

    new_exprs = {k: dag.to_verilog(r, wire_of, _root=True)
                 for k, r in roots.items()}
    for k in exprs:
        if k not in new_exprs:
            new_exprs[k] = exprs[k]
    return new_exprs, wires
