#!/usr/bin/env python3
"""
Claude Code 会话监测 —— 共用逻辑。

cc-watch.py（纯文本看板）和 cc-pet.py（curses 宠物版）都从这里取判据，
避免两份实现各自漂移。这里只放纯函数和数据采集，不含任何渲染。

数据源:
  1. `claude agents --json`         权威列表，唯一提供 waitingFor（区分"等授权"/"等回答"）
  2. ~/.claude/sessions/<pid>.json  含 statusUpdatedAt，用来算"这个状态持续多久了"；
                                    读一次约 0.5ms，可以高频轮询
"""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

SESSIONS_DIR = Path.home() / ".claude" / "sessions"

# 分组定义：(键, 图标, 中文标题)。顺序即显示顺序，也是"最需要注意"的排序。
GROUPS = [
    ("waiting", "▲", "需要你处理"),
    ("busy",    "●", "运行中"),
    ("done",    "✔", "刚完成"),
    ("idle",    "○", "空闲"),
    ("dead",    "∙", "进程已退出"),
]

# waitingFor 的中文说法（实测见过 "input needed"；其余按官方枚举翻）
WAIT_CN = {
    "permission prompt": "等你授权",
    "input needed":      "等你回答",
    "sandbox request":   "等你放行网络",
    "worker request":    "等 worker",
    "dialog open":       "对话框开着",
}

# 刚从 busy 落到 idle 之后，标记成"刚完成"保持多少秒
DONE_STICKY_SEC = 90


# ---------------------------------------------------------------- 数据采集

def fetch_agents(cwd_filter: str | None = None) -> tuple[list[dict], str | None]:
    """调 claude agents --json（约 0.2s）。返回 (列表, 错误信息)。"""
    cmd = ["claude", "agents", "--json"]
    if cwd_filter:
        cmd += ["--cwd", cwd_filter]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except FileNotFoundError:
        return [], "找不到 claude 命令"
    except subprocess.TimeoutExpired:
        return [], "claude agents 超时"
    if out.returncode != 0:
        return [], (out.stderr or "").strip()[:120] or f"退出码 {out.returncode}"
    try:
        data = json.loads(out.stdout or "[]")
    except json.JSONDecodeError:
        return [], "输出不是合法 JSON"
    return (data if isinstance(data, list) else []), None


def read_session_file(pid) -> dict:
    """读 ~/.claude/sessions/<pid>.json。约 0.5ms，可高频调用。读不到返回 {}。"""
    if not pid:
        return {}
    try:
        d = json.loads((SESSIONS_DIR / f"{pid}.json").read_text())
    except (OSError, json.JSONDecodeError):
        return {}  # 文件可能正被写、或进程已退出
    return d if isinstance(d, dict) else {}


def status_since(pid) -> float | None:
    """当前状态是从什么时候开始的（epoch 秒）。"""
    d = read_session_file(pid)
    ts = d.get("statusUpdatedAt") or d.get("startedAt")
    return ts / 1000.0 if ts else None


def refresh_from_files(agents: list[dict]) -> list[dict]:
    """用 sessions/*.json 里的新鲜 status 覆盖列表里的旧值。

    `claude agents --json` 贵（0.2s）只能低频调，文件便宜（0.5ms）可以高频调。
    但文件里**没有 waitingFor**，所以只覆盖 status，waitingFor 保留上一次的值——
    否则会在两次 agents 轮询之间把"等你回答"退化成"等待中"，界面来回跳。
    """
    out = []
    for a in agents:
        d = read_session_file(a.get("pid"))
        if d.get("status"):
            a = {**a, "status": d["status"]}
        out.append(a)
    return out


# ---------------------------------------------------------------- 纯函数

def agent_key(a: dict) -> str:
    """会话的稳定标识。三个来源都可能缺，兜到 pid/id。"""
    return str(a.get("sessionId") or a.get("id") or a.get("pid") or "?")


def classify(a: dict, prev: dict) -> tuple[str, str]:
    """返回 (分组键, 状态文案)。prev 是上一轮的 {agent_key: status}。"""
    st = a.get("status")
    state: str = str(a.get("state") or "")  # 交互式会话没有 state，统一成空串

    if st == "waiting":
        wf = a.get("waitingFor") or ""
        return "waiting", WAIT_CN.get(wf, f"等待：{wf}" if wf else "等待中")

    if st is None:
        # 没有 status 说明进程已退出，只剩后台会话记录
        return "dead", {"done": "已完成(进程退出)", "failed": "失败",
                        "stopped": "已停止"}.get(state, state or "进程已退出")

    if st == "busy":
        return "busy", "忙碌"

    if st == "idle":
        if state == "failed":
            return "dead", "失败"
        if state == "stopped":
            return "dead", "已停止"
        if state == "done":
            return "done", "已完成"
        # 交互式会话没有 done 状态，只能靠"刚从 busy 掉下来"推断
        if prev.get(agent_key(a)) == "busy":
            return "done", "刚完成"
        return "idle", "空闲"

    return "idle", st or "?"


def fmt_dur(sec: float | None) -> str:
    if sec is None or sec < 0:
        return "-"
    s = int(sec)
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{(s % 3600) // 60:02d}m"


def short_dir(p: str) -> str:
    home = str(Path.home())
    if p == home:
        return "~"
    if p.startswith(home + "/"):
        return "~/" + p[len(home) + 1:]
    return p


def disp_width(s: str) -> int:
    """显示宽度，中文按 2 格算。"""
    return sum(2 if ord(c) > 0x2E80 else 1 for c in s)


def clip(s: str, n: int) -> str:
    """按显示宽度截断。不变式：结果宽度 <= n。

    省略号本身占 1 格，必须从预算里先扣掉，否则截出来的串反而超宽、把列冲歪。
    """
    if n <= 0:
        return ""
    if disp_width(s) <= n:
        return s
    budget = n - 1  # 给 … 留位
    w, out = 0, []
    for ch in s:
        cw = 2 if ord(ch) > 0x2E80 else 1
        if w + cw > budget:
            break
        out.append(ch)
        w += cw
    return "".join(out) + "…"


def pad(s: str, n: int) -> str:
    return s + " " * max(0, n - disp_width(s))


# ---------------------------------------------------------------- 分组

def group_agents(agents: list[dict], prev: dict, done_at: dict,
                 now: float | None = None) -> dict[str, list[dict]]:
    """把会话分到 GROUPS 的各个桶里，并给每条补上 _group/_label/_since。

    done_at 是调用方持有的 {agent_key: 落到 idle 的时刻}，用来让"刚完成"保鲜一段时间。
    这个函数会就地更新它。
    """
    now = time.time() if now is None else now
    buckets: dict[str, list[dict]] = {g[0]: [] for g in GROUPS}

    for a in agents:
        key = agent_key(a)
        grp, label = classify(a, prev)

        # "刚完成"只保鲜 DONE_STICKY_SEC 秒，之后归入空闲
        if grp == "done" and a.get("status") == "idle":
            done_at.setdefault(key, now)
            if now - done_at[key] > DONE_STICKY_SEC:
                grp, label = "idle", "空闲"
        elif grp != "done":
            done_at.pop(key, None)

        since = status_since(a.get("pid"))
        if since is None:
            started = a.get("startedAt")
            since = started / 1000.0 if started else None

        buckets[grp].append({**a, "_group": grp, "_label": label, "_since": since})

    return buckets


def flatten(buckets: dict[str, list[dict]]) -> list[dict]:
    """按 GROUPS 顺序摊平成一个列表（最需要注意的在前），供上下键选择用。"""
    out = []
    for gkey, _, _ in GROUPS:
        out.extend(buckets.get(gkey, []))
    return out


# ---------------------------------------------------------------- 跳转路由

def nvim_socket_of(pid) -> str | None:
    """从 /proc/<pid>/environ 里读 NVIM —— nvim 会把自己的 socket 路径注入到
    :terminal 起的所有子进程环境里。

    这比"往上走找 nvim 再拼 /run/user/UID/nvim.<pid>.0"可靠得多：
      · 任意 socket 路径都认（--listen 自定义路径也行）
      · 不依赖"取第一个还是最后一个 nvim"那个容易搞反的启发式
    """
    try:
        env = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
    except OSError:
        return None
    for item in env:
        if item.startswith(b"NVIM="):
            sock = item[5:].decode("utf-8", "replace")
            return sock if Path(sock).is_socket() else None
    return None


def resolve_route(pid) -> dict:
    """找出这个 claude 进程待在哪个 nvim / 哪个终端窗口里。

    socket 以 /proc environ 的 NVIM 为准；进程链只用来认终端模拟器和做展示。
    不套 nvim 直接在终端里跑也支持，此时 nvim_socket 为 None。
    """
    route: dict = {"pid": pid, "nvim_pid": None,
                   "nvim_socket": nvim_socket_of(pid),
                   "term_pid": None, "term": None, "chain": []}
    p = pid
    for _ in range(12):
        try:
            comm = Path(f"/proc/{p}/comm").read_text().strip()
            stat = Path(f"/proc/{p}/stat").read_text().split()
        except OSError:
            break
        route["chain"].append(f"{comm}({p})")

        # ⚠ 链条里可能有两个 nvim（内层带 socket、外层不带），取第一个。
        if comm == "nvim" and route["nvim_pid"] is None:
            route["nvim_pid"] = p

        if comm in ("kitty", "alacritty", "foot", "wezterm", "ghostty",
                    "gnome-terminal-", "konsole", "xterm"):
            route["term_pid"], route["term"] = p, comm
            break

        try:
            p = int(stat[3])  # ppid
        except (IndexError, ValueError):
            break
        if p <= 1:
            break
    return route


def nvim_expr(socket: str, expr: str, timeout: float = 3.0) -> tuple[str, str | None]:
    """对某个 nvim 实例求值一个表达式（只读）。返回 (输出, 错误)。"""
    try:
        # ⚠ stdin 必须断掉。调用方可能是 curses 应用，它的 stdin 是 raw 模式的 tty；
        #   nvim 继承过去后 --remote-expr 会返回空串且退出码为 0——静默的空结果，
        #   比报错难查得多（实测：同一时刻同一 socket，普通进程算得出、curses 里是空）。
        r = subprocess.run(["nvim", "--server", socket, "--remote-expr", expr],
                           capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        return "", "找不到 nvim"
    except subprocess.TimeoutExpired:
        return "", "nvim 无响应"
    if r.returncode != 0:
        return "", (r.stderr or "").strip()[:160] or f"退出码 {r.returncode}"
    return r.stdout.strip(), None


def shell_pid_of(claude_pid) -> int | None:
    """claude 的直接父进程就是 nvim terminal 里跑的那个 shell。"""
    try:
        return int(Path(f"/proc/{claude_pid}/stat").read_text().split()[3])
    except (OSError, IndexError, ValueError):
        return None


# ================================================================ 待答问题
#
# 下面这一段依赖 transcript 的 JSONL 结构。官方明说那是内部格式、版本间会变
# （见 docs/en/sessions "Where transcripts are stored"）。所以：
#   · 解析失败一律返回"读不出来"，绝不猜
#   · 注入前会再核一次，状态对不上就中止
# 当前实测通过的版本：Claude Code 2.1.246

PROJECTS_DIR = Path.home() / ".claude" / "projects"


def transcript_of(session_id: str) -> Path | None:
    """按 sessionId 找 transcript 文件。直接 glob，不去猜目录名编码规则。"""
    if not session_id:
        return None
    hits = list(PROJECTS_DIR.glob(f"*/{session_id}.jsonl"))
    return hits[0] if hits else None


def find_pending_ask(session_id: str) -> tuple[dict | None, str | None]:
    """找出"发出去了但还没有结果"的 AskUserQuestion。返回 (pending, 说不了的原因)。

    判据：一个 tool_use 的 id 在整个 transcript 里找不到对应的 tool_result。
    这个判据不依赖任何字段的具体含义，比按时间取最后一条稳。
    """
    path = transcript_of(session_id)
    if path is None:
        return None, "找不到 transcript 文件"
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as e:
        return None, f"读不了 transcript: {e}"

    uses: dict[str, tuple[str, dict]] = {}
    results: set[str] = set()
    for line in lines:
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        content = (rec.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for blk in content:
            if not isinstance(blk, dict):
                continue
            if blk.get("type") == "tool_use" and blk.get("id"):
                uses[blk["id"]] = (blk.get("name", "?"), blk.get("input") or {})
            elif blk.get("type") == "tool_result" and blk.get("tool_use_id"):
                results.add(blk["tool_use_id"])

    open_uses = [(i, n, inp) for i, (n, inp) in uses.items() if i not in results]
    if not open_uses:
        return None, "没有未闭合的工具调用（可能已经被答掉了）"

    asks = [(i, inp) for i, n, inp in open_uses if n == "AskUserQuestion"]
    if not asks:
        names = "、".join(sorted({n for _, n, _ in open_uses}))
        return None, f"在等的不是选择题（{names}），只能去终端里处理"

    tool_id, inp = asks[-1]
    questions = inp.get("questions") or []
    if not questions:
        return None, "问题结构读不出来（transcript 格式可能变了）"
    return {"id": tool_id, "questions": questions}, None


def answerable(pending: dict) -> tuple[bool, str]:
    """能不能就地代答。不能的话给出原因——宁可不做，也不要按错。"""
    qs = pending.get("questions") or []
    if not qs:
        return False, "问题结构读不出来（transcript 格式可能变了）"
    for i, q in enumerate(qs, 1):
        if not (q.get("options") or []):
            where = f"第 {i} 题" if len(qs) > 1 else "这题"
            return False, f"{where}没有预设选项，只能自己打字"
    return True, ""


# ---- 按键序列（全部实测于 Claude Code 2.1.246）----
#
# 心智模型：顶部是一排标签 [第1题][第2题]…[✔ Submit]，光标在当前标签的选项列表里。
#   · 单选题：↓ 移动，Enter = 选中【并切到下一个标签】
#   · 多选题：空格勾选当前项，↓ 移动，→ = 切到下一个标签
#   · Submit 标签：Enter 提交（光标停在 "Submit answers"）
#
# ⚠ 有一个例外：**单个单选题没有 Submit 标签**，Enter 当场就提交完了。
#   其余情况（多个问题、或单个多选题）最后都要多按一次 Enter。
#
# ⚠ 数字键在这个选择器里**无效**（实测发 "2" 光标不动，Enter 仍选中第 1 项）。
#   信任文件夹那个对话框倒是认数字键，但那是另一个界面，别混。
KEY_DOWN = "\\x1b[B"
KEY_RIGHT = "\\x1b[C"
KEY_ENTER = "\\r"
KEY_SPACE = " "


def build_keys(questions: list[dict], picks: list[list[int]]) -> list[str]:
    """按顺序答完所有问题并提交。picks 与 questions 等长，每项是 0-based 下标列表。

    返回**逐个**按键的列表。⚠ 必须一个一个发、中间留间隔：实测把 5 个键一次性灌进去，
    首个空格和末尾回车会在 TUI 重绘的间隙里被丢掉（review 页只勾上了一项，
    而且停在没提交的状态）。
    """
    if not questions:
        raise ValueError("没有问题")
    if len(picks) != len(questions):
        raise ValueError(f"picks 有 {len(picks)} 组，问题有 {len(questions)} 个，对不上")

    seq: list[str] = []
    for n, (q, picked) in enumerate(zip(questions, picks), 1):
        where = f"第 {n} 题" if len(questions) > 1 else "这题"
        n_opts = len(q.get("options") or [])
        if not picked:
            raise ValueError(f"{where}没有选中任何项")
        for i in picked:
            if not 0 <= i < n_opts:
                raise ValueError(f"{where}下标 {i} 超出 0..{n_opts - 1}")

        if not q.get("multiSelect"):
            if len(picked) != 1:
                raise ValueError(f"{where}是单选，却给了 {len(picked)} 个")
            # 每题的光标都从第 1 项开始（实测：Enter 切到下一题后光标复位到 0）
            seq += [KEY_DOWN] * picked[0]
            seq.append(KEY_ENTER)      # 选中 + 切到下一个标签
        else:
            cur = 0
            for idx in sorted(set(picked)):
                seq += [KEY_DOWN] * (idx - cur)
                seq.append(KEY_SPACE)
                cur = idx
            seq.append(KEY_RIGHT)      # 切到下一个标签

    # 单个单选题在上面那个 Enter 就已经提交了，没有 Submit 标签可停。
    if len(questions) > 1 or questions[0].get("multiSelect"):
        seq.append(KEY_ENTER)          # 在 "Submit answers" 上提交
    return seq


# ---- 注入 ----

_TERMBUF_EXPR = (
    'join(map(filter(range(1,bufnr("$")),'
    ' "getbufvar(v:val,\\"&buftype\\")==\\"terminal\\""),'
    ' "v:val.\\":\\".jobpid(getbufvar(v:val,\\"terminal_job_id\\"))'
    '.\\":\\".getbufvar(v:val,\\"terminal_job_id\\")"), ",")'
)


def ancestors(pid) -> list[int]:
    """pid 自身 + 一路向上的祖先。"""
    out, p = [], pid
    for _ in range(16):
        try:
            ppid = int(Path(f"/proc/{p}/stat").read_text().split()[3])
        except (OSError, IndexError, ValueError):
            break
        out.append(int(p))
        if ppid <= 1:
            break
        p = ppid
    return out


def find_nvim_buffer(socket: str, claude_pid: int) -> tuple[int | None, int | None, str | None]:
    """在 nvim 里找承载这个 claude 的 terminal buffer。返回 (bufnr, jobid, 错误)。

    ⚠ 不能只比 claude 的直接父进程。nvim 的 `:terminal cmd` 在 cmd 是复合命令时
    会留一层 `sh -c` 不 exec 掉，中间还可能夹 env/包装脚本，层数不定。
    所以拿 claude 的**整条祖先链**去和各 buffer 的 jobpid 求交集。
    """
    out, err = nvim_expr(socket, _TERMBUF_EXPR)
    if err:
        return None, None, err
    chain = set(ancestors(claude_pid))
    seen = []
    for triple in out.split(","):
        parts = triple.split(":")
        if len(parts) != 3:
            continue
        buf, jpid, jid = parts
        try:
            jpid_i = int(jpid)
        except ValueError:
            continue
        seen.append(jpid_i)
        if jpid_i in chain:
            try:
                return int(buf), int(jid), None
            except ValueError:
                return None, None, f"解析失败: {triple!r}"
    return None, None, (f"祖先链 {sorted(chain)} 和 buffer 的 jobpid {seen} 没有交集")


KEY_GAP_SEC = 0.22  # 逐键间隔。实测 0 会丢键；留够让 TUI 走完一次重绘


def inject(socket: str, job_id: int, keys: str | list[str],
           gap: float = KEY_GAP_SEC) -> str | None:
    """把按键**逐个**送进那个 terminal 里跑着的程序。返回错误信息，成功返回 None。"""
    seq = [keys] if isinstance(keys, str) else list(keys)
    for i, k in enumerate(seq):
        out, err = nvim_expr(socket, f'chansend({job_id}, "{k}")')
        if err:
            return f"第 {i + 1}/{len(seq)} 个键失败: {err}"
        if out.strip() in ("0", "-1"):
            return f"第 {i + 1}/{len(seq)} 个键 chansend 返回 {out.strip()}，没送进去"
        if i < len(seq) - 1:
            time.sleep(gap)
    return None


def recheck_still_pending(session_id: str, tool_id: str) -> str | None:
    """注入前的最后一道闸：确认那道题还在等。

    如果这中间你已经在终端里自己答了，选择器就没了，这时候再灌箭头键
    会打进输入框——所以状态对不上必须中止。
    """
    agents, err = fetch_agents()
    if err:
        return f"核对状态失败：{err}"
    me = next((a for a in agents if a.get("sessionId") == session_id), None)
    if me is None:
        return "这个会话已经不在了"
    if me.get("status") != "waiting":
        return f"它已经不在等待状态了（现在是 {me.get('status')}），可能你已经答过了"
    pending, why = find_pending_ask(session_id)
    if pending is None:
        return f"待答问题不见了：{why}"
    if pending["id"] != tool_id:
        return "等的已经是另一道题了"
    return None
