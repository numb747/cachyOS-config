#!/usr/bin/env python3
"""端到端：在隔离的 headless nvim 的 terminal buffer 里跑一个真 claude 会话，
让它弹选择题，然后完全走 cc_common 的链路把它答掉。

验的是全链条：找会话 → 定位 nvim/buffer/jobid → 读 transcript 找待答题
              → 生成按键 → 复核 → 注入 → 确认答对了哪一项。
"""
import os, re, shutil, subprocess, sys, time
# cc_common 和本脚本同目录（装完都在 ~/.claude/）。按脚本自身位置解析，
# 别写死绝对路径——否则换用户名或从包里直接跑就 ImportError。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cc_common as C

MULTI = len(sys.argv) > 1 and sys.argv[1] == "multi"
SOCK = "/tmp/e2e-nvim%s.sock" % ("-m" if MULTI else "")
WORK = "/tmp/cc-e2e%s" % ("-m" if MULTI else "")
# 单选选第 2 项；多选选第 1 和第 3 项（跨过中间那项，能验出移动步数算错）
EXPECT = ["蓝色"] if not MULTI else ["红色", "绿色"]
NOT_EXPECT = ["红色", "绿色"] if not MULTI else ["蓝色"]

shutil.rmtree(WORK, ignore_errors=True); os.makedirs(WORK)
for f in (SOCK,):
    try: os.unlink(f)
    except OSError: pass

nv = subprocess.Popen(["nvim", "--headless", "--listen", SOCK, "-n", "-u", "NONE"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(30):
    if os.path.exists(SOCK): break
    time.sleep(0.2)
else:
    print("✗ nvim socket 没起来"); sys.exit(1)
print("✓ 隔离的 headless nvim 已启动")


def ex(expr):
    return C.nvim_expr(SOCK, expr, timeout=8)


def cleanup():
    nv.terminate()
    try: nv.wait(timeout=5)
    except subprocess.TimeoutExpired: nv.kill()


try:
    # 在 nvim 里开 terminal 跑 claude（先 cd 过去，再让它自己回答信任框）
    prompt = ("调用 AskUserQuestion，multiSelect 设为 true，问我喜欢哪些颜色，"
              "三个选项 label 就叫 红色 蓝色 绿色。不要做别的事。") if MULTI else \
             ("调用 AskUserQuestion 问我：红色、蓝色、绿色 选一个，"
              "label 就叫 红色 蓝色 绿色。不要做别的事。")
    # ⚠ 必须摘掉 CLAUDE_CODE_CHILD_SESSION：我自己就是个 claude 会话，
    #   继承这个标记的子会话不写 transcript，而整套检测就靠 transcript。
    unset = "env -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT"
    cmd = f"terminal cd {WORK} && {unset} claude --dangerously-skip-permissions '{prompt}'"
    ex(f'execute({cmd!r})')
    time.sleep(2)

    out, err = ex('getbufvar(bufnr("%"),"terminal_job_id")')
    job = int(out)
    print(f"✓ terminal buffer 起来了，job_id={job}")

    # 信任框：Enter 选默认第 1 项
    time.sleep(3)
    C.inject(SOCK, job, "\\r")
    print("✓ 已过信任框")

    # 等 claude 进程出现在 agents 列表里，并进入 waiting
    print("等它进入 waiting（最多 120s）…")
    sid, reached = None, False
    t_end, last = time.time() + 120, None
    while time.time() < t_end and not reached:
        me = next((a for a in C.fetch_agents()[0] if a.get("cwd") == WORK), None)
        if me:
            sid = me.get("sessionId")
            cur = (me.get("status"), me.get("waitingFor"))
            if cur != last:
                print(f"    [{int(120 - (t_end - time.time()))}s] status={cur[0]} waitingFor={cur[1]}")
                last = cur
            reached = me.get("status") == "waiting"
        time.sleep(2)
    if reached:
        print("  ✓ 进入 waiting")
    else:
        print("  ✗ 等 waiting 超时")
        dump, _ = ex('join(getbufline(bufnr("%"),1,"$"), "\\n")')
        print("── terminal buffer 末尾 ──")
        print("\n".join(l for l in dump.split("\n") if l.strip())[-1200:])
        cleanup(); sys.exit(1)
    if not sid:
        print("✗ 没拿到 sessionId"); cleanup(); sys.exit(1)

    time.sleep(2)  # 让 transcript 落盘

    # ---- 走正式链路 ----
    print("\n── 走 cc_common 的链路 ──")
    pending, why = C.find_pending_ask(sid)
    if pending is None:
        print(f"✗ 没找到待答题: {why}"); cleanup(); sys.exit(1)
    ok, reason = C.answerable(pending)
    print(f"  待答 id={pending['id'][:20]}…  可代答={ok} {reason}")
    q = pending["questions"][0]
    print(f"  问: {q['question']}")
    for i, o in enumerate(q.get("options", [])):
        print(f"    [{i}] {o['label']}")
    assert ok, "应该可代答"

    labels = [o["label"] for o in q["options"]]
    print(f"  multiSelect={q.get('multiSelect')}")
    if not all(e in labels for e in EXPECT):
        print(f"✗ 选项对不上: {labels}"); cleanup(); sys.exit(1)
    idxs = sorted(labels.index(e) for e in EXPECT)
    print(f"  要选: {[(i, labels[i]) for i in idxs]}")

    keys = C.build_keys(q, idxs)
    print(f"  按键序列: {keys!r}")

    guard = C.recheck_still_pending(sid, pending["id"])
    print(f"  复核闸: {'通过' if guard is None else guard}")
    if guard: cleanup(); sys.exit(1)

    err = C.inject(SOCK, job, keys)
    print(f"  注入: {'成功' if err is None else '失败 ' + err}")
    if err: cleanup(); sys.exit(1)

    # ---- 验证真的选中了 EXPECT_LABEL ----
    print("\n等它把答案处理完（最多 60s）…")
    picked = None
    deadline = time.time() + 60
    while time.time() < deadline:
        time.sleep(3)
        p2, _ = C.find_pending_ask(sid)
        if p2 is not None and p2["id"] == pending["id"]:
            continue                     # 还没答上
        # 题闭合了，去 transcript 里读 tool_result 看选了啥
        path = C.transcript_of(sid)
        if not path: break
        import json
        for line in path.read_text(errors="replace").splitlines():
            try: rec = json.loads(line)
            except Exception: continue
            c = (rec.get("message") or {}).get("content")
            if not isinstance(c, list): continue
            for blk in c:
                if isinstance(blk, dict) and blk.get("type") == "tool_result" \
                        and blk.get("tool_use_id") == pending["id"]:
                    picked = json.dumps(blk.get("content"), ensure_ascii=False)
        if picked: break

    print("\n" + "=" * 60)
    if picked:
        print("tool_result 内容:", picked[:400])
        # ⚠ 只能看等号后面的"答案"部分。整串里含问题原文，
        #   而问题原文往往把所有选项名都念一遍，直接全串搜必然假阳性。
        import re as _re
        answers = _re.findall(r'=\\"(.*?)\\"', picked)
        ans_text = " | ".join(answers)
        print("解析出的答案:", ans_text or "(解析失败)")
        hit = bool(answers) and all(e in ans_text for e in EXPECT)
        others = [l for l in NOT_EXPECT if l in ans_text]
        ok = hit and not others
        print(f"判定: {'✓ 精确选中 ' + '、'.join(EXPECT) if ok else '✗ 选错了'}")
        if not hit:  print(f"      少选了: {[e for e in EXPECT if e not in picked]}")
        if others:   print(f"      多选了: {others}")
        sys.exit(0 if ok else 1)
    else:
        print("✗ 没能确认结果 —— dump terminal buffer 看卡在哪：")
        dump, _ = ex('join(getbufline(bufnr("%"),1,"$"), "\n")')
        print("\n".join(l for l in dump.split("\n") if l.strip())[-1500:])
        sys.exit(1)
finally:
    cleanup()
