#!/usr/bin/env python3
"""校验 docs/arch/ 下的架构地图。退出码 0 = 全部通过。

✗ 错误（必须修）：渲染失败 · 节点数超上限 · @src 的文件不存在 · @src 锚点找不到或不唯一 ·
  @src 用了行号（代码一挪就漂，改用锚点）· @link 目标不存在 · @src/@link 引用的节点 id 不在图里 ·
  一个节点多条 @link · 用了 :::changed 却没写 classDef changed · @note 挂在不存在的节点上 ·
  @commit 缺失或不是有效提交 · 有图从总览沿 @link 走不到
· 提示（逐条确认）：没标 @src 的节点 —— 必须都是外部系统 / 存储，否则补上；计划中（planned）的节点单独列出
"""
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

LIMIT = {"00": 10}   # 按文件名前缀；其余 15
DEFAULT_LIMIT = 15
META = re.compile(r"^\s*%%\s*@(src|link|commit|note)\s+(\S+)(?:\s+(\S+))?(?:\s+(.*\S))?")
NODE = re.compile(r'<g class="([^"]*)" id="[^"]*-flowchart-([^"]+)-\d+"')


def git(root, *args):
    r = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def main():
    arch = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/arch").resolve()
    if not arch.is_dir():
        sys.exit(f"没有目录：{arch}")
    root = Path(git(arch, "rev-parse", "--show-toplevel") or arch)
    overview = arch / "00-overview.mmd"
    files = sorted(arch.glob("*.mmd"))
    errors, notes = [], []
    links = defaultdict(set)   # 图 → 它 @link 到的图
    mmd = Path.home() / ".local/bin/mmd"

    if not overview.exists():
        errors.append("缺 00-overview.mmd")

    with tempfile.TemporaryDirectory() as tmp:
        for f in files:
            name, text = f.name, f.read_text()
            metas = [m.groups() for m in map(META.match, text.splitlines()) if m]

            out = Path(tmp) / (f.stem + ".svg")
            r = subprocess.run([str(mmd) if mmd.exists() else "mmd", "-q", "-i", str(f), "-o", str(out)],
                               capture_output=True, text=True)
            if r.returncode != 0 or not out.exists():
                msg = (r.stderr or r.stdout).strip().splitlines()
                errors.append(f"{name}: 渲染失败\n    " + "\n    ".join(msg[-6:]))
                continue
            found = NODE.findall(out.read_text())
            nodes = {n for _, n in found}
            planned = {n for cls, n in found if "planned" in cls.split()}
            limit = LIMIT.get(name[:2], DEFAULT_LIMIT)
            if len(nodes) > limit:
                errors.append(f"{name}: {len(nodes)} 个节点，超过上限 {limit} —— 收拢成一个节点，细节拆到下一层用 @link 连")

            if name == overview.name:
                c = next((n for k, n, *_ in metas if k == "commit"), None)
                if not c:
                    errors.append(f"{name}: 缺 %% @commit <hash>")
                else:
                    h = c.removesuffix("+dirty")
                    if c == "none":
                        notes.append("@commit none：设计阶段，还没有对应的代码提交")
                    elif git(root, "cat-file", "-e", f"{h}^{{commit}}") is None:
                        errors.append(f"{name}: @commit {c} 不是这个仓库里的有效提交")
                    else:
                        behind = git(root, "rev-list", "--count", f"{h}..HEAD")
                        if behind and behind != "0":
                            notes.append(f"地图基于 {c}，HEAD 已经领先 {behind} 个提交")

            seen_link, has_src = set(), set()
            for mark in ("changed", "planned"):
                if f":::{mark}" in text and f"classDef {mark}" not in text:
                    errors.append(f"{name}: 用了 :::{mark} 但没写 classDef {mark}（虚线框不会显示）")

            for kind, node, val, anchor in metas:
                if kind == "commit":
                    continue
                if kind == "note":
                    if node != "*" and nodes and node not in nodes:
                        errors.append(f"{name}: @note 挂在不存在的节点「{node}」上 —— 节点改名就改 id，删了就改成 "
                                      f"`@note * （原 {node}）…`，用户的备注不能丢")
                    continue
                if not val:
                    errors.append(f"{name}: @{kind} {node} 少了目标")
                    continue
                if nodes and node not in nodes:
                    errors.append(f"{name}: @{kind} 引用的节点 id「{node}」不在图里（图里的 id：{', '.join(sorted(nodes))}）")
                if kind == "src":
                    has_src.add(node)
                    p = (root / val).resolve()
                    if re.search(r":\d+$", val):
                        errors.append(f"{name}: @src {node} 用了行号 {val} —— 代码一挪就漂，改成「路径 锚点文字」")
                    elif not p.is_relative_to(root) or not p.is_file():
                        errors.append(f"{name}: @src {node} → {val} 不存在（路径相对 git 根 {root}）")
                    elif not anchor:
                        errors.append(f"{name}: @src {node} 缺锚点 —— 写成「{val} <定义那一行里的一段文字>」")
                    else:
                        hits = [i for i, l in enumerate(p.read_text(errors="replace").splitlines(), 1) if anchor in l]
                        if not hits:
                            errors.append(f"{name}: @src {node} → {val} 里找不到锚点「{anchor}」")
                        elif len(hits) > 1:
                            errors.append(f"{name}: @src {node} 锚点「{anchor}」在 {val} 里出现 {len(hits)} 次"
                                          f"（行 {', '.join(map(str, hits[:5]))}）—— 加长到唯一")
                elif kind == "link":
                    if node in seen_link:
                        errors.append(f"{name}: 节点 {node} 有多条 @link，双击只能进一张图 —— 只留一条")
                    seen_link.add(node)
                    t = (f.parent / val).resolve()
                    if not t.exists():
                        errors.append(f"{name}: @link {node} → {val} 不存在")
                    links[f.resolve()].add(t)

            if planned:
                notes.append(f"{name}: 计划中、还没实现的节点：{', '.join(sorted(planned))}")
            bare = sorted(nodes - has_src - planned)
            if bare:
                notes.append(f"{name}: 没标 @src 的节点：{', '.join(bare)} —— 确认每个都是外部系统 / 存储")

    # 从总览沿 @link 能走到的图
    reach, stack = set(), [overview.resolve()]
    while stack:
        g = stack.pop()
        if g in reach:
            continue
        reach.add(g)
        stack.extend(links[g])
    for f in files:
        if f.resolve() not in reach:
            errors.append(f"{f.name}: 从 00-overview 沿 @link 走不到它")

    for n in notes:
        print("·", n)
    for e in errors:
        print("✗", e)
    if errors:
        sys.exit(1)
    print(f"✓ {len(files)} 张图全部通过")


if __name__ == "__main__":
    main()
