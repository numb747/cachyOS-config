#!/usr/bin/env python3
"""
Claude Code 会话看板 · 宠物版（curses TUI）

一只 ASCII 猫蹲在顶上反映所有会话的整体状态，下面是可上下选择的会话列表。
选中一个在等你的会话按 Enter，能**就地把选择题答掉**，不用切过去。

三个时钟各走各的（这是流畅的关键）：
  · 宠物动画   100ms  —— 纯本地，零成本
  · 状态刷新   400ms  —— 读 ~/.claude/sessions/*.json，约 0.5ms，几乎免费
  · 权威列表   1.5s   —— `claude agents --json`，0.2s 一次，放后台线程避免卡住动画

按键（刻意避开 <C-/>，那个被 toggleterm 占了；也避开 Esc，nvim terminal mode 会截）：
  列表里：  ↑↓ / jk 选择    Enter 代答    r 刷新    q 退出
  代答面板：↑↓ / jk 移动    空格 勾选(多选题)    Enter 发送    q 取消
"""
from __future__ import annotations

import argparse
import curses
import locale
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cc_common as C  # noqa: E402

locale.setlocale(locale.LC_ALL, "")

FRAME_MS = 100
FILE_POLL_SEC = 0.4
AGENT_POLL_SEC = 1.5
MSG_TTL_SEC = 8.0

# ---------------------------------------------------------------- 宠物
# 每个状态一组帧，每帧 = (三行身体, 旁白)。三行必须等宽，否则换帧时会横向抖。
PET = {
    "sleep": [
        ([r" /\_/\ ", r"( -.- )", r" >   < "], ""),
        ([r" /\_/\ ", r"( -.- )", r" >   < "], "z"),
        ([r" /\_/\ ", r"( -.- )", r" >   < "], "zZ"),
        ([r" /\_/\ ", r"( -.- )", r" >   < "], "zZz"),
    ],
    "work": [
        ([r" /\_/\ ", r"( o.o )", r" >|_|< "], ""),
        ([r" /\_/\ ", r"( o.o )", r" <|_|> "], ""),
        ([r" /\_/\ ", r"( -.o )", r" >|_|< "], ""),
        ([r" /\_/\ ", r"( o.o )", r" <|_|> "], ""),
    ],
    "alert": [
        ([r" /\_/\ ", r"( O_O )", r"\_| |_/"], "!"),
        ([r" /\_/\ ", r"( O_O )", "/_| |_\\"], "!"),
        ([r" /\_/\ ", r"( O_O )", r"\_| |_/"], "! !"),
        ([r" /\_/\ ", r"( O_O )", "/_| |_\\"], "!"),
    ],
    "happy": [
        ([r" /\_/\ ", r"( ^_^ )", r" >   < "], "*"),
        ([r" /\_/\ ", r"( ^-^ )", r" >   < "], " *"),
        ([r" /\_/\ ", r"( ^_^ )", r" >   < "], "  *"),
        ([r" /\_/\ ", r"( ^-^ )", r" >   < "], " *"),
    ],
    "sad": [
        ([r" /\_/\ ", r"( x_x )", r" >   < "], ""),
        ([r" /\_/\ ", r"( x_x )", r" >   < "], "..."),
    ],
}

# 心情取"最需要注意的那一档"，不是多数决：一个会话在等你，
# 哪怕另外五个都在跑，它也该是警觉脸。
PET_MOOD_ORDER = [("waiting", "alert"), ("dead", "sad"),
                  ("busy", "work"), ("done", "happy")]


def pet_mood(buckets: dict) -> str:
    for gkey, mood in PET_MOOD_ORDER:
        if buckets.get(gkey):
            return mood
    return "sleep"


def pet_frame(mood: str, tick: int) -> tuple[list[str], str]:
    frames = PET[mood]
    return frames[(tick // 4) % len(frames)]   # 4 tick ≈ 400ms 换一帧，不然晃眼


# ---------------------------------------------------------------- 后台轮询

class AgentPoller(threading.Thread):
    """把 0.2s 的 `claude agents --json` 挪到后台，主循环不因此掉帧。"""

    def __init__(self, interval: float, cwd: str | None):
        super().__init__(daemon=True)
        self.interval, self.cwd = interval, cwd
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._wake = threading.Event()
        self.agents: list[dict] = []
        self.err: str | None = None

    def run(self):
        while not self._stop.is_set():
            data, err = C.fetch_agents(self.cwd)
            with self._lock:
                self.agents, self.err = data, err
            self._wake.wait(self.interval)
            self._wake.clear()

    def snapshot(self) -> tuple[list[dict], str | None]:
        with self._lock:
            return list(self.agents), self.err

    def refresh_now(self):
        self._wake.set()

    def stop(self):
        self._stop.set()
        self._wake.set()


# ---------------------------------------------------------------- 绘制

ATTR: dict = {}


def init_colors():
    curses.start_color()
    curses.use_default_colors()
    spec = {"waiting": (curses.COLOR_YELLOW, 1), "busy": (curses.COLOR_CYAN, 2),
            "done": (curses.COLOR_GREEN, 3), "idle": (-1, 4),
            "dead": (curses.COLOR_RED, 5), "_sel": (curses.COLOR_MAGENTA, 6)}
    for key, (fg, idx) in spec.items():
        curses.init_pair(idx, fg, -1)
        ATTR[key] = curses.color_pair(idx)
    ATTR["idle"] |= curses.A_DIM
    ATTR["_sel"] |= curses.A_BOLD


_ESC_MAP = {ord("A"): curses.KEY_UP, ord("B"): curses.KEY_DOWN,
            ord("C"): curses.KEY_RIGHT, ord("D"): curses.KEY_LEFT}


def read_key(win) -> int:
    """取一个按键。

    ⚠ halfdelay 下 ncurses 不一定把箭头键合成 KEY_UP/KEY_DOWN，
    有时会把 ESC、'['、'B' 拆成三次 getch 返回——上下键就整个失灵，
    而且是静默的（实测：面板里按 ↓ 光标不动，结果选中了第 1 项）。
    这里自己把拆开的序列拼回去。
    """
    ch = win.getch()
    if ch != 27:
        return ch
    win.nodelay(True)
    try:
        if win.getch() != ord("["):
            return -1
        return _ESC_MAP.get(win.getch(), -1)
    finally:
        win.nodelay(False)
        curses.halfdelay(max(1, FRAME_MS // 100))


def put(win, y: int, x: int, text: str, attr=0) -> int:
    """在 (y,x) 写一段，按**显示宽度**返回新的 x。越界自动裁掉，不抛异常。"""
    maxy, maxx = win.getmaxyx()
    if y < 0 or y >= maxy or x >= maxx - 1:
        return x
    text = C.clip(text, maxx - 1 - x)
    if not text:
        return x
    try:
        win.addstr(y, x, text, attr)
    except curses.error:
        pass   # 右下角那一格写不进去是 curses 的老毛病
    return x + C.disp_width(text)


def draw_header(win, rows, mood, tick):
    body, speech = pet_frame(mood, tick)
    mood_attr = ATTR.get({"alert": "waiting", "work": "busy", "happy": "done",
                          "sad": "dead"}.get(mood, "idle"), curses.A_DIM)
    for i, line in enumerate(body):
        put(win, i, 2, line, mood_attr)
    put(win, 1, 11, speech, mood_attr | curses.A_BOLD)

    n_wait = sum(1 for r in rows if r["_group"] == "waiting")
    put(win, 0, 17, "Claude 会话看板", curses.A_BOLD)
    x = put(win, 1, 17, f"{len(rows)} 个会话", curses.A_DIM)
    if n_wait:
        x = put(win, 1, x, " · ", curses.A_DIM)
        put(win, 1, x, f"{n_wait} 个等你处理", ATTR["waiting"] | curses.A_BOLD)
    put(win, 2, 17, time.strftime("%H:%M:%S"), curses.A_DIM)


def draw_list(win, y0, rows, sel_key):
    maxy, maxx = win.getmaxyx()
    name_w, stat_w, dur_w = 22, 12, 7
    dir_w = max(10, maxx - (4 + name_w + stat_w + dur_w + 6))
    icons = {g[0]: g[1] for g in C.GROUPS}
    y = y0
    for n, r in enumerate(rows):
        if y >= maxy - 2:
            put(win, y, 2, f"…还有 {len(rows) - n} 条放不下", curses.A_DIM)
            break
        gkey = r["_group"]
        attr = ATTR.get(gkey, 0)
        selected = C.agent_key(r) == sel_key
        x = put(win, y, 1, "▸" if selected else " ", ATTR["_sel"])
        x = put(win, y, x + 1, icons.get(gkey, "·"), attr)
        name = r.get("name") or r.get("id") or str(r.get("pid", "?"))
        x = put(win, y, x + 1, C.pad(C.clip(name, name_w), name_w),
                attr | (curses.A_BOLD if selected else 0))
        x = put(win, y, x + 1,
                C.pad(C.clip(C.short_dir(r.get("cwd", "")), dir_w), dir_w), curses.A_DIM)
        x = put(win, y, x + 1, C.pad(r["_label"], stat_w), attr)
        since = r.get("_since")
        x = put(win, y, x, C.fmt_dur(time.time() - since if since else None), curses.A_DIM)
        if r.get("kind") == "background":
            put(win, y, x + 1, "[bg]", curses.A_DIM)
        y += 1
    return y


def panel_rows(panel) -> list[tuple[int, int]]:
    """把所有问题的所有选项摊平成 [(题号, 选项号)]，光标就在这上面走。"""
    return [(qi, oi) for qi, q in enumerate(panel["questions"])
            for oi in range(len(q.get("options") or []))]


def unanswered(panel) -> list[int]:
    """还没选的题号（0-based）。单选题也要求选一个才让发。"""
    return [qi for qi in range(len(panel["questions"])) if not panel["picks"][qi]]


def draw_panel(win, y0, panel):
    """代答面板。把要发生什么原样摆出来——按下去是不可撤销的。"""
    maxy, maxx = win.getmaxyx()
    qs = panel["questions"]
    rows = panel_rows(panel)
    cur_row = rows[panel["cursor"]] if rows else None

    y = _line(win, y0, 2, f"代答 · {panel['name']}"
              + (f"   共 {len(qs)} 题" if len(qs) > 1 else ""), ATTR["_sel"])
    y = _line(win, y, 2, "─" * min(maxx - 4, 76), curses.A_DIM)

    for qi, q in enumerate(qs):
        if y >= maxy - 4:
            put(win, y, 2, "…放不下，把窗口拉高", curses.A_DIM)
            break
        multi = bool(q.get("multiSelect"))
        head = q.get("question", "?")
        if len(qs) > 1:
            head = f"{qi + 1}. {head}"
        y = _line(win, y, 2, C.clip(head, maxx - 4), curses.A_BOLD)
        tag = "多选（空格可勾多个）" if multi else "单选"
        if not panel["picks"][qi]:
            tag += " · 未选"
        y = _line(win, y, 4, tag,
                  (ATTR["waiting"] if not panel["picks"][qi] else curses.A_DIM))

        for oi, o in enumerate(q.get("options", [])):
            if y >= maxy - 4:
                break
            on_cursor = cur_row == (qi, oi)
            picked = oi in panel["picks"][qi]
            mark = ("☑" if picked else "☐") if multi else ("◉" if picked else "○")
            a = ATTR["_sel"] if on_cursor else 0
            x = put(win, y, 3, "▸ " if on_cursor else "  ", ATTR["_sel"])
            x = put(win, y, x, f"{mark} ", ATTR["done"] if picked else a)
            put(win, y, x, C.clip(o.get("label", "?"), maxx - x - 2),
                a | (curses.A_BOLD if on_cursor else 0))
            y += 1
            desc = o.get("description")
            if desc and on_cursor and y < maxy - 4:
                put(win, y, 7, C.clip(desc, maxx - 9), curses.A_DIM)
                y += 1
        y += 1

    if panel.get("note"):
        _line(win, y, 2, panel["note"], ATTR["waiting"] | curses.A_BOLD)
    return y


def _line(win, y, x, text, attr=0):
    put(win, y, x, text, attr)
    return y + 1


def draw(win, rows, sel_key, mood, tick, err, msg, panel):
    win.erase()
    maxy, _ = win.getmaxyx()
    draw_header(win, rows, mood, tick)
    y = 4
    if err:
        put(win, y, 2, f"读取失败：{err}", ATTR["dead"]); y += 2
    if panel:
        draw_panel(win, y, panel)
        miss = unanswered(panel)
        if miss:
            footer = ("↑↓/jk 移动   空格 选中   q 取消   "
                      + (f"还差第 {'、'.join(str(i + 1) for i in miss)} 题没选"
                         if len(panel["questions"]) > 1 else "还没选"))
        else:
            footer = "↑↓/jk 移动   空格 改选   Enter 发送   q 取消"
    else:
        draw_list(win, y, rows, sel_key)
        footer = "↑↓/jk 选择   Enter 代答   r 刷新   q 退出"
        if not rows:
            put(win, y, 2, "当前没有运行中的 Claude Code 会话", curses.A_DIM)
    if msg and time.time() - msg[1] < MSG_TTL_SEC:
        put(win, maxy - 2, 2, msg[0], ATTR["_sel"])
    put(win, maxy - 1, 2, footer, curses.A_DIM)
    win.noutrefresh()
    curses.doupdate()


# ---------------------------------------------------------------- 代答

def open_panel(row: dict) -> tuple[dict | None, str]:
    """尝试为这个会话开代答面板。开不了就说清楚为什么——宁可不做，也不要按错。"""
    name = row.get("name") or str(row.get("pid"))
    if row.get("status") != "waiting":
        return None, f"{name} 现在不在等待状态"
    sid = row.get("sessionId")
    if not sid:
        return None, f"{name} 没有 sessionId，读不了它在问什么"

    pending, why = C.find_pending_ask(sid)
    if pending is None:
        return None, f"{name}：{why}"
    ok, reason = C.answerable(pending)
    if not ok:
        return None, f"{name}：{reason}"

    pid = row.get("pid")
    route = C.resolve_route(pid)
    if not route["nvim_socket"]:
        return None, f"{name}：它不在带 socket 的 nvim 里（链 {' < '.join(route['chain'])}），送不进按键"
    buf, job, err = C.find_nvim_buffer(route["nvim_socket"], pid)
    if job is None:
        return None, f"{name}：{err}"

    qs = pending["questions"]
    return {
        "name": name, "sid": sid, "pending": pending,
        "questions": qs,
        "picks": [set() for _ in qs],   # 每题一个 set，单选题里最多一个元素
        "cursor": 0,                    # 走在 panel_rows() 摊平后的列表上
        "socket": route["nvim_socket"], "job": job, "buf": buf, "note": "",
    }, ""


def send_answer(panel) -> str:
    qs = panel["questions"]
    miss = unanswered(panel)
    if miss:
        return (f"第 {'、'.join(str(i + 1) for i in miss)} 题还没选，用空格选一下"
                if len(qs) > 1 else "还没选，用空格选一下")
    picks = [sorted(panel["picks"][i]) for i in range(len(qs))]
    labels = ["、".join(qs[qi]["options"][i].get("label", "?") for i in picks[qi])
              for qi in range(len(qs))]

    # 最后一道闸：这中间你可能已经自己在终端里答了。那时选择器早没了，
    # 再灌箭头键会打进输入框——所以状态对不上必须中止。
    guard = C.recheck_still_pending(panel["sid"], panel["pending"]["id"])
    if guard:
        return f"已中止：{guard}"
    try:
        keys = C.build_keys(qs, picks)
    except ValueError as e:
        return f"按键序列生成失败：{e}"
    err = C.inject(panel["socket"], panel["job"], keys)
    if err:
        return f"注入失败：{err}"
    if len(qs) == 1:
        return f"已替你选了「{labels[0]}」"
    return "已替你答完 " + " / ".join(f"{i + 1}.{l}" for i, l in enumerate(labels))


# ---------------------------------------------------------------- 主循环

def run(stdscr, args):
    curses.curs_set(0)
    curses.halfdelay(max(1, FRAME_MS // 100))
    stdscr.keypad(True)
    try:
        curses.set_escdelay(25)   # 别为了等转义序列卡住整个界面
    except (AttributeError, curses.error):
        pass
    init_colors()

    poller = AgentPoller(args.agent_interval, args.cwd)
    poller.start()

    prev: dict = {}
    done_at: dict = {}
    rows: list[dict] = []
    sel_key: str | None = None
    msg: tuple[str, float] | None = None
    panel: dict | None = None
    tick = 0
    last_poll = 0.0

    while True:
        now = time.time()
        agents, err = poller.snapshot()
        if now - last_poll >= FILE_POLL_SEC:
            merged = C.refresh_from_files(agents)
            buckets = C.group_agents(merged, prev, done_at, now)
            rows = C.flatten(buckets)
            prev = {C.agent_key(a): a.get("status") for a in merged}
            last_poll = now

        by_group: dict = {}
        for r in rows:
            by_group.setdefault(r["_group"], []).append(r)
        mood = pet_mood(by_group)

        keys = [C.agent_key(r) for r in rows]
        if sel_key not in keys:
            sel_key = keys[0] if keys else None

        draw(stdscr, rows, sel_key, mood, tick, err, msg, panel)
        tick += 1

        ch = read_key(stdscr)
        if ch == -1:
            continue
        if ch == curses.KEY_RESIZE:
            continue

        # ---------- 代答面板里 ----------
        if panel:
            # ⚠ 别叫 rows —— 那是外面会话列表的变量名，覆盖掉之后
            #   下一帧还没到刷新点时会拿它去画列表，画出一堆元组。
            prows = panel_rows(panel)
            if ch in (ord("q"), ord("Q")):
                panel, msg = None, ("已取消，什么都没发", time.time())
            elif ch in (curses.KEY_DOWN, ord("j")):
                panel["cursor"] = min(panel["cursor"] + 1, len(prows) - 1)
            elif ch in (curses.KEY_UP, ord("k")):
                panel["cursor"] = max(panel["cursor"] - 1, 0)
            elif ch == ord(" ") and prows:
                qi, oi = prows[panel["cursor"]]
                if panel["questions"][qi].get("multiSelect"):
                    panel["picks"][qi] ^= {oi}
                else:
                    panel["picks"][qi] = {oi}      # 单选题是单选钮，直接顶掉
            elif ch in (curses.KEY_ENTER, 10, 13):
                panel["note"] = "发送中…"
                draw(stdscr, rows, sel_key, mood, tick, err, msg, panel)
                result = send_answer(panel)
                panel, msg = None, (result, time.time())
                poller.refresh_now()
                last_poll = 0.0
            continue

        # ---------- 列表里 ----------
        if ch in (ord("q"), ord("Q")):
            break
        elif ch in (curses.KEY_DOWN, ord("j")) and keys:
            i = keys.index(sel_key) if sel_key in keys else -1
            sel_key = keys[min(i + 1, len(keys) - 1)]
        elif ch in (curses.KEY_UP, ord("k")) and keys:
            i = keys.index(sel_key) if sel_key in keys else 1
            sel_key = keys[max(i - 1, 0)]
        elif ch in (ord("r"), ord("R")):
            poller.refresh_now()
            last_poll = 0.0
            msg = ("已请求刷新", time.time())
        elif ch in (curses.KEY_ENTER, 10, 13) and sel_key:
            row = next((r for r in rows if C.agent_key(r) == sel_key), None)
            if row:
                panel, why = open_panel(row)
                if panel is None:
                    msg = (why, time.time())

    poller.stop()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd", help="只看该目录下起的会话")
    ap.add_argument("--agent-interval", type=float, default=AGENT_POLL_SEC,
                    help="claude agents --json 的轮询间隔秒数")
    args = ap.parse_args()
    try:
        curses.wrapper(run, args)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
