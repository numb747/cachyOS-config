#!/usr/bin/env python3
"""cc_common / cc-pet 的判据测试。

  python3 ~/.claude/test-cc.py                    测真实文件
  python3 ~/.claude/test-cc.py /tmp/mutant.py     测变异体（验测试本身有效）
"""
import importlib.util, sys, time
from pathlib import Path

COMMON = sys.argv[1] if len(sys.argv) > 1 else str(Path.home() / ".claude/cc_common.py")
PET = sys.argv[2] if len(sys.argv) > 2 else str(Path.home() / ".claude/cc-pet.py")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


C = load("cc_common", COMMON)
pet = load("pet", PET)

fails = []


def eq(name, got, want):
    ok = got == want
    print(("  ✓ " if ok else "  ✗ ") + f"{name}: {got!r}" + ("" if ok else f"   期望 {want!r}"))
    if not ok:
        fails.append(name)


print("— classify 全分支 —")
eq("交互式 忙碌",       C.classify({"status": "busy", "sessionId": "s1"}, {}), ("busy", "忙碌"))
eq("交互式 空闲",       C.classify({"status": "idle", "sessionId": "s1"}, {}), ("idle", "空闲"))
eq("交互式 busy→idle",  C.classify({"status": "idle", "sessionId": "s1"}, {"s1": "busy"}), ("done", "刚完成"))
eq("交互式 idle→idle",  C.classify({"status": "idle", "sessionId": "s1"}, {"s1": "idle"}), ("idle", "空闲"))
eq("等你回答",          C.classify({"status": "waiting", "waitingFor": "input needed"}, {}), ("waiting", "等你回答"))
eq("等你授权",          C.classify({"status": "waiting", "waitingFor": "permission prompt"}, {}), ("waiting", "等你授权"))
eq("等你放行网络",      C.classify({"status": "waiting", "waitingFor": "sandbox request"}, {}), ("waiting", "等你放行网络"))
eq("未知 waitingFor",   C.classify({"status": "waiting", "waitingFor": "brand new"}, {}), ("waiting", "等待：brand new"))
eq("waiting 无 For",    C.classify({"status": "waiting"}, {}), ("waiting", "等待中"))
eq("后台 done",         C.classify({"status": "idle", "state": "done"}, {}), ("done", "已完成"))
eq("后台 failed",       C.classify({"status": "idle", "state": "failed"}, {}), ("dead", "失败"))
eq("后台 stopped",      C.classify({"status": "idle", "state": "stopped"}, {}), ("dead", "已停止"))
eq("进程退出 done",     C.classify({"state": "done"}, {}), ("dead", "已完成(进程退出)"))
eq("进程退出 无 state", C.classify({}, {}), ("dead", "进程已退出"))

print("— agent_key 兜底 —")
eq("优先 sessionId", C.agent_key({"sessionId": "s", "id": "i", "pid": 1}), "s")
eq("退到 id",        C.agent_key({"id": "i", "pid": 1}), "i")
eq("退到 pid",       C.agent_key({"pid": 1}), "1")
eq("全缺",           C.agent_key({}), "?")

print("— group_agents 刚完成保鲜期 —")
now = time.time()
a = {"status": "idle", "sessionId": "s9", "cwd": "/tmp", "name": "x"}
b = C.group_agents([a], {"s9": "busy"}, {}, now)
eq("刚落 idle 归刚完成", [r["_label"] for r in b["done"]], ["刚完成"])
stale = {"s9": now - C.DONE_STICKY_SEC - 10}
b2 = C.group_agents([a], {"s9": "busy"}, stale, now)
eq(f"超 {C.DONE_STICKY_SEC}s 归空闲", ([r["_label"] for r in b2["idle"]], b2["done"]), (["空闲"], []))

print("— flatten 顺序：最需要注意的在最前 —")
mixed = [
    {"sessionId": "i", "status": "idle"},
    {"sessionId": "w", "status": "waiting", "waitingFor": "input needed"},
    {"sessionId": "b", "status": "busy"},
]
order = [r["sessionId"] for r in C.flatten(C.group_agents(mixed, {}, {}, now))]
eq("waiting 排第一", order, ["w", "b", "i"])

print("— refresh_from_files 必须保住 waitingFor —")
# 文件里只有 status 没有 waitingFor。若直接整条替换，两次 agents 轮询之间
# "等你回答" 会退化成 "等待中"，界面来回跳。
orig_read = C.read_session_file
C.read_session_file = lambda pid: {"status": "waiting"} if pid == 999 else {}
try:
    merged = C.refresh_from_files([{"pid": 999, "status": "busy", "waitingFor": "input needed"}])
    eq("status 被文件覆盖", merged[0]["status"], "waiting")
    eq("waitingFor 保留",   merged[0].get("waitingFor"), "input needed")
    eq("合起来仍翻译得出",  C.classify(merged[0], {}), ("waiting", "等你回答"))
finally:
    C.read_session_file = orig_read

print("— 宽度计算（中文按 2 格）—")
eq("disp_width 中文",   C.disp_width("忙碌"), 4)
eq("disp_width 混排",   C.disp_width("a忙b"), 4)
eq("clip 不超宽(中文)", C.disp_width(C.clip("忙碌运行中", 4)) <= 4, True)
eq("clip 不超宽(ASCII)", C.disp_width(C.clip("abcdefghij", 5)) <= 5, True)
eq("clip 带省略号",     C.clip("忙碌运行中", 4).endswith("…"), True)
eq("clip 不够长不动",   C.clip("忙碌", 10), "忙碌")
eq("clip 恰好等宽不动", C.clip("忙碌", 4), "忙碌")
eq("pad 对齐",          C.disp_width(C.pad("忙碌", 10)), 10)

print("— fmt_dur —")
eq("秒", C.fmt_dur(45), "45s")
eq("分", C.fmt_dur(83), "1m23s")
eq("时", C.fmt_dur(3720), "1h02m")
eq("空", C.fmt_dur(None), "-")

print("— 宠物心情：取最需要注意的那一档，不是多数决 —")
eq("有等待→alert", pet.pet_mood({"waiting": [1], "busy": [1, 2, 3], "idle": [1]}), "alert")
eq("有失败→sad",   pet.pet_mood({"dead": [1], "busy": [1, 2, 3]}), "sad")
eq("有忙碌→work",  pet.pet_mood({"busy": [1], "done": [1], "idle": [9]}), "work")
eq("有刚完成→happy", pet.pet_mood({"done": [1], "idle": [1]}), "happy")
eq("全空闲→sleep", pet.pet_mood({"idle": [1, 2]}), "sleep")
eq("空→sleep",     pet.pet_mood({}), "sleep")

print("— 宠物帧 —")
for mood in pet.PET:
    widths = {tuple(len(l) for l in body) for body, _ in pet.PET[mood]}
    eq(f"{mood} 三行等宽（不等宽换帧会横向抖）", len(widths), 1)
def frame_sig(mood, t):
    body, speech = pet.pet_frame(mood, t)
    return (tuple(body), speech)


for mood in pet.PET:
    seen = {frame_sig(mood, t) for t in range(0, 40)}
    eq(f"{mood} 会换帧", len(seen) > 1, True)
eq("换帧节奏 4 tick 一次", pet.pet_frame("work", 0) == pet.pet_frame("work", 3), True)
eq("第 4 tick 换掉",       pet.pet_frame("work", 0) != pet.pet_frame("work", 4), True)

print("— answerable：拿不准就别答 —")
OPT2 = [{"label": "a"}, {"label": "b"}]
one = {"questions": [{"options": OPT2}]}
eq("单问题带选项 → 可答", C.answerable(one)[0], True)
eq("两个问题 → 也可答（08-26 实测按键序列后放开）",
   C.answerable({"questions": [{"options": OPT2}] * 2})[0], True)
eq("没有选项 → 不可答", C.answerable({"questions": [{"options": []}]})[0], False)
eq("多问题里有一个没选项 → 整体不可答",
   C.answerable({"questions": [{"options": OPT2}, {"options": []}]})[0], False)
eq("拒绝理由指出是第几题",
   "第 2 题" in C.answerable({"questions": [{"options": OPT2}, {"options": []}]})[1], True)
eq("零问题 → 不可答", C.answerable({"questions": []})[0], False)

print("— build_keys（按键序列，全部实测于 2.1.246）—")
D, RT, EN, SP = C.KEY_DOWN, C.KEY_RIGHT, C.KEY_ENTER, C.KEY_SPACE
single = {"multiSelect": False, "options": [{}, {}, {}]}
multi = {"multiSelect": True, "options": [{}, {}, {}]}
# 单问题单选是唯一没有 Submit 标签的情况：Enter 当场提交，不能多按
eq("单选第 1 项 = 直接回车", C.build_keys([single], [[0]]), [EN])
eq("单选第 3 项 = 两次下+回车", C.build_keys([single], [[2]]), [D, D, EN])
# 跨过中间项：步数算错会选到相邻项，这条是最容易写错的地方
eq("多选第 1+3 项", C.build_keys([multi], [[0, 2]]), [SP, D, D, SP, RT, EN])
eq("多选只选第 2 项", C.build_keys([multi], [[1]]), [D, SP, RT, EN])
eq("多选全选", C.build_keys([multi], [[0, 1, 2]]), [SP, D, SP, D, SP, RT, EN])
eq("多选乱序输入也升序处理", C.build_keys([multi], [[2, 0]]), C.build_keys([multi], [[0, 2]]))

print("— build_keys · 多问题（08-26 实测：答完自动跳下一题，最后落在 review 页）—")
# 每题的光标都从 0 开始（Enter 切题后复位），末尾多一次 Enter 提交 review 页
eq("两题单选 [2],[0]", C.build_keys([single, single], [[2], [0]]), [D, D, EN, EN, EN])
eq("两题单选 [0],[1]", C.build_keys([single, single], [[0], [1]]), [EN, D, EN, EN])
eq("三题单选", C.build_keys([single] * 3, [[1], [1], [1]]), [D, EN, D, EN, D, EN, EN])
eq("多问题里混多选", C.build_keys([single, multi], [[1], [0, 2]]),
   [D, EN, SP, D, D, SP, RT, EN])
eq("单问题单选【没有】收尾 Enter", C.build_keys([single], [[1]]).count(EN), 1)
eq("两问题单选【有】收尾 Enter", C.build_keys([single, single], [[1], [1]]).count(EN), 3)

KNOWN = {D, RT, EN, SP}
eq("每一项都是单个已知键（一次性灌会丢键，必须逐个发）",
   [k for k in C.build_keys([single, multi], [[1], [0, 2]]) if k not in KNOWN], [])
for bad, desc in (([[]], "空选"), ([[3]], "越界"), ([[-1]], "负下标"),
                  ([[0, 1]], "单选题给了两个")):
    try:
        C.build_keys([single], bad); eq(f"{desc} 应该报错", "没报错", "ValueError")
    except ValueError:
        eq(f"{desc} 报错了", True, True)
try:
    C.build_keys([single, single], [[0]]); eq("picks 数量对不上应报错", "没报错", "ValueError")
except ValueError:
    eq("picks 数量对不上报错了", True, True)
try:
    C.build_keys([], []); eq("零问题应报错", "没报错", "ValueError")
except ValueError:
    eq("零问题报错了", True, True)

print("— 路由解析（跑真进程树）—")
import os
r = C.resolve_route(os.getpid())
eq("认出了终端", r["term"] is not None or r["nvim_pid"] is not None, True)
eq("链条非空",   len(r["chain"]) > 0, True)
eq("链条首项是自己", r["chain"][0].startswith("python"), True)
eq("坏 pid 不炸", C.resolve_route(999999)["chain"], [])
eq("shell_pid_of 坏 pid", C.shell_pid_of(999999), None)

# ⚠ 关键不变式：链条里可能有多个 nvim（内层带 socket，外层不带）。
# 必须取**第一个**。取错了 socket 就找不到，跳转功能整个哑掉，而上面那些
# 宽松断言("认出了终端")照样绿——这个坑我真踩过一次。
nvims = [e for e in r["chain"] if e.startswith("nvim(")]
if nvims:
    first_nvim_pid = int(nvims[0][len("nvim("):-1])
    eq(f"多个 nvim 时取第一个（共 {len(nvims)} 个）", r["nvim_pid"], first_nvim_pid)
    eq("取到的 nvim 确实有 socket", r["nvim_socket"] is not None, True)
else:
    print("  – 跳过 nvim 相关断言：当前进程链里没有 nvim")

print()
print(f"{len(fails)} 条失败: {fails}" if fails else "全部通过")
sys.exit(1 if fails else 0)
