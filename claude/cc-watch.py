#!/usr/bin/env python3
"""
Claude Code 多会话看板（纯文本版）—— 一眼看清各终端里的 claude 在干嘛。

判据全部来自 cc_common，与宠物版 cc-pet.py 共用同一套实现，避免两边漂移。
这个文件只负责渲染。

用法:
  cc-watch.py                 常驻看板，2 秒刷新
  cc-watch.py -n 5            改刷新间隔
  cc-watch.py --once          打一次快照就退出（适合塞进 tmux 状态栏）
  cc-watch.py --no-bell       进入"需要处理"时不响铃
  cc-watch.py --cwd ~/proj    只看某个目录下起的会话
"""
from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cc_common as C  # noqa: E402

# ---- 配色 ----
R = "\033[0m"; B = "\033[1m"; D = "\033[2m"
RED = "\033[31m"; GRN = "\033[32m"; YEL = "\033[33m"; CYN = "\033[36m"

GROUP_COLOR = {"waiting": YEL, "busy": CYN, "done": GRN, "idle": D, "dead": D}


def render(agents: list[dict], prev: dict, done_at: dict, err: str | None,
           interval: int) -> str:
    now = time.time()
    cols = shutil.get_terminal_size((100, 30)).columns
    buckets = C.group_agents(agents, prev, done_at, now)

    name_w, dur_w, stat_w = 18, 8, 14
    dir_w = max(12, cols - name_w - dur_w - stat_w - 8)

    out = []
    n_wait = len(buckets["waiting"])
    total = len(agents)
    head = f"{B}Claude Code 会话看板{R}  {D}{total} 个会话"
    if n_wait:
        head += f"{R} · {YEL}{B}{n_wait} 个等你处理{R}{D}"
    head += f" · {time.strftime('%H:%M:%S')} · 每 {interval}s 刷新 · Ctrl+C 退出{R}"
    out.append(head)
    out.append("")

    if err:
        out.append(f"  {RED}读取失败：{err}{R}")
        out.append("")

    for gkey, icon, title in C.GROUPS:
        rows = buckets[gkey]
        if not rows:
            continue
        color = GROUP_COLOR[gkey]
        out.append(f" {color}{icon} {B}{title}{R}{D} ({len(rows)}){R}")
        for r in rows:
            name = r.get("name") or r.get("id") or str(r.get("pid", "?"))
            d = C.short_dir(r.get("cwd", ""))
            bg = f"{D}[bg]{R}" if r.get("kind") == "background" else ""
            since = r.get("_since")
            dur = C.fmt_dur(now - since if since else None)
            out.append(
                f"   {color}{icon}{R} "
                f"{C.pad(C.clip(name, name_w), name_w)} "
                f"{D}{C.pad(C.clip(d, dir_w), dir_w)}{R} "
                f"{color}{C.pad(r['_label'], stat_w)}{R}"
                f"{D}{dur}{R} {bg}"
            )
        out.append("")

    if total == 0 and not err:
        out.append(f"  {D}当前没有运行中的 Claude Code 会话{R}")

    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--interval", type=int, default=2, help="刷新间隔秒数")
    ap.add_argument("--once", action="store_true", help="打一次快照就退出")
    ap.add_argument("--no-bell", action="store_true", help="进入等待状态时不响铃")
    ap.add_argument("--cwd", help="只看该目录下起的会话")
    args = ap.parse_args()

    prev: dict = {}
    prev_waiting: set = set()
    done_at: dict = {}

    def one_round() -> str:
        nonlocal prev, prev_waiting
        agents, err = C.fetch_agents(args.cwd)
        screen = render(agents, prev, done_at, err, args.interval)

        # 新进入"等待"的会话才响铃，避免一直卡着一直响
        cur_waiting = {C.agent_key(a) for a in agents if a.get("status") == "waiting"}
        if not args.no_bell and (cur_waiting - prev_waiting):
            sys.stdout.write("\a")
        prev_waiting = cur_waiting

        prev = {C.agent_key(a): a.get("status") for a in agents}
        return screen

    if args.once:
        print(one_round())
        return 0

    sys.stdout.write("\033[?1049h\033[?25l")  # 备用屏 + 隐藏光标
    try:
        while True:
            sys.stdout.write("\033[H\033[2J" + one_round())
            sys.stdout.flush()
            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
