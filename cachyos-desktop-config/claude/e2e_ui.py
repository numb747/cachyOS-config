#!/usr/bin/env python3
"""界面级端到端：真的用 cc-pet 的 UI 把一道题答掉。

  隔离 headless nvim → terminal 里跑真 claude → 让它弹三选一
  → pty 里跑 cc-pet（--cwd 限定只看这个会话）
  → 在界面里按 Enter 开面板、↓ 选第 2 项、Enter 发送
  → 回 transcript 核对 tool_result 真的是第 2 项
"""
import fcntl, json, os, pty, re, select, shutil, struct, subprocess, sys, termios, time
# cc_common 和本脚本同目录（装完都在 ~/.claude/）。按脚本自身位置解析，
# 别写死绝对路径——否则换用户名或从包里直接跑就 ImportError。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cc_common as C

MULTIQ = len(sys.argv) > 1 and sys.argv[1] == "multiq"
SOCK = "/tmp/ui-nvim%s.sock" % ("-q" if MULTIQ else "")
WORK = "/tmp/cc-ui%s" % ("-q" if MULTIQ else "")
CLEAN = [re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"),
         re.compile(r"\x1b\[[0-9;?<>=]*[a-zA-Z]"),
         re.compile(r"\x1b[()][B0]|\x1b[=>]|\x1b[78]|\x0f|\x0e")]

shutil.rmtree(WORK, ignore_errors=True); os.makedirs(WORK)
try: os.unlink(SOCK)
except OSError: pass

nv = subprocess.Popen(["nvim", "--headless", "--listen", SOCK, "-n", "-u", "NONE"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(30):
    if os.path.exists(SOCK): break
    time.sleep(0.2)

ui = None
def cleanup():
    if ui and ui.poll() is None:
        ui.kill()
    nv.terminate()
    try: nv.wait(timeout=5)
    except subprocess.TimeoutExpired: nv.kill()

try:
    unset = "env -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT"
    prompt = ("调用一次 AskUserQuestion，questions 数组里放【两个】问题。"
              "第一题 header 叫 颜色，问喜欢哪个颜色，三个选项 label 是 红色 蓝色 绿色。"
              "第二题 header 叫 水果，问喜欢哪个水果，三个选项 label 是 苹果 香蕉 橙子。"
              "两题都单选。不要做别的事。") if MULTIQ else \
             "调用 AskUserQuestion 问我：红色、蓝色、绿色 选一个，label 就叫 红色 蓝色 绿色。不要做别的事。"
    C.nvim_expr(SOCK, f'execute({f"terminal cd {WORK} && {unset} claude --dangerously-skip-permissions {prompt!r}"!r})', 8)
    time.sleep(2)
    job = int(C.nvim_expr(SOCK, 'getbufvar(bufnr("%"),"terminal_job_id")', 8)[0])
    time.sleep(3); C.inject(SOCK, job, "\\r")          # 过信任框
    print(f"✓ 测试会话已起（nvim job {job}）")

    print("等它进入 waiting…")
    sid = None
    end = time.time() + 120
    while time.time() < end:
        me = next((a for a in C.fetch_agents()[0] if a.get("cwd") == WORK), None)
        if me and me.get("status") == "waiting":
            sid = me["sessionId"]; break
        time.sleep(2)
    if not sid:
        print("✗ 没进 waiting"); cleanup(); sys.exit(1)
    print(f"✓ waiting，sessionId={sid[:8]}…")

    pending, _ = C.find_pending_ask(sid)
    QS = pending["questions"]
    ALL_LABELS = [[o["label"] for o in q["options"]] for q in QS]
    print(f"  共 {len(QS)} 题: {ALL_LABELS}")
    ok_ans, why_ans = C.answerable(pending)
    print(f"  answerable = {ok_ans} {why_ans}")
    assert ok_ans, f"应该可代答: {why_ans}"
    # 两题都刻意选【非默认】项：下标算错会选到相邻项
    WANT = [2, 1] if MULTIQ else [1]          # 多问题: 绿色 + 香蕉；单问题: 蓝色
    WANT_LABELS = [ALL_LABELS[i][WANT[i]] for i in range(len(QS))]
    print(f"  要选: {[(i, l) for i, l in zip(WANT, WANT_LABELS)]}")
    # 界面里光标走的是【摊平后】的行：第 i 题第 j 项 = 前面所有题的选项数之和 + j
    CURSOR_STEPS = []
    flat = 0
    for qi, w in enumerate(WANT):
        CURSOR_STEPS.append((flat + w, qi))
        flat += len(ALL_LABELS[qi])

    # ---- 起 cc-pet 的界面 ----
    m, s = pty.openpty()
    fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 200, 0, 0))
    ui = subprocess.Popen([sys.executable, os.path.expanduser("~/.claude/cc-pet.py"),
                           "--cwd", WORK],
                          stdin=s, stdout=s, stderr=s, start_new_session=True,
                          env=dict(os.environ, TERM="xterm-256color",
                                   LANG="zh_CN.UTF-8", LC_ALL="zh_CN.UTF-8"))
    os.close(s)
    buf = bytearray()

    def pump(sec):
        e = time.time() + sec
        while time.time() < e:
            r, _, _ = select.select([m], [], [], 0.1)
            if r:
                try: d = os.read(m, 65536)
                except OSError: return
                if not d: return
                buf.extend(d)

    def screen():
        t = buf.decode("utf-8", "replace")
        for rx in CLEAN: t = rx.sub("", t)
        return t.replace("\r", "")

    def norm(x): return re.sub(r"\s+", "", x)

    pump(3.5)
    print("\n── 界面首屏 ──")
    print(screen()[-500:])
    ok_list = norm("等你回答") in norm(screen())
    print(f"  列表显示「等你回答」: {'✓' if ok_list else '✗'}")

    # 测试进程里独立算一遍，和 cc-pet 里的结果对照
    _r = C.resolve_route(next(a for a in C.fetch_agents()[0] if a.get("cwd") == WORK)["pid"])
    _pid = next(a for a in C.fetch_agents()[0] if a.get("cwd") == WORK)["pid"]
    print(f"\n[对照] claude pid={_pid} socket={_r['nvim_socket']}")
    print(f"[对照] 祖先链={C.ancestors(_pid)}")
    print(f"[对照] nvim 报的 buffer 列表={C.nvim_expr(_r['nvim_socket'], C._TERMBUF_EXPR, 8)[0]!r}")
    print(f"[对照] find_nvim_buffer={C.find_nvim_buffer(_r['nvim_socket'], _pid)}")

    print("\n按 Enter 开代答面板…")
    buf.clear(); os.write(m, b"\r"); pump(4)
    panel_txt = screen()
    print(panel_txt[-700:])
    flat_labels = [l for grp in ALL_LABELS for l in grp]
    ok_panel = all(norm(l) in norm(panel_txt) for l in flat_labels) and norm("代答") in norm(panel_txt)
    print(f"  面板列出全部选项: {'✓' if ok_panel else '✗'}")
    if not ok_panel:
        print("✗ 面板没开出来"); cleanup(); sys.exit(1)

    print("\n在面板里逐题选（↑↓ 走摊平后的行，空格选中）…")
    pos = 0
    for target, qi in CURSOR_STEPS:
        while pos < target:
            buf.clear(); os.write(m, b"\x1b[B"); pump(0.7); pos += 1
        buf.clear(); os.write(m, b" "); pump(1.0)
        print(f"  第 {qi+1} 题已选 → 光标行 {pos}")
    print(screen()[-600:])

    print("\n按 Enter 发送…")
    buf.clear(); os.write(m, b"\r"); pump(12)
    print(screen()[-500:])
    sent = norm("已替你选了") in norm(screen()) or norm("已替你答完") in norm(screen())
    print(f"  界面回报已发送: {'✓' if sent else '✗'}")

    # ---- 回 transcript 核实 ----
    print("\n核实 transcript 里的 tool_result…")
    answer = None
    end = time.time() + 60
    while time.time() < end and answer is None:
        time.sleep(3)
        path = C.transcript_of(sid)
        if not path: continue
        for line in path.read_text(errors="replace").splitlines():
            try: rec = json.loads(line)
            except Exception: continue
            c = (rec.get("message") or {}).get("content")
            if not isinstance(c, list): continue
            for blk in c:
                if isinstance(blk, dict) and blk.get("type") == "tool_result" \
                        and blk.get("tool_use_id") == pending["id"]:
                    raw = json.dumps(blk.get("content"), ensure_ascii=False)
                    got = re.findall(r'=\\"(.*?)\\"', raw)
                    if got: answer = " | ".join(got)

    os.write(m, b"q"); time.sleep(0.5)
    print("\n" + "=" * 60)
    print(f"tool_result 里的答案: {answer!r}")
    got = [a.strip() for a in (answer or "").split("|")]
    good = got == WANT_LABELS
    print(f"期望: {WANT_LABELS}")
    print(f"实得: {got}")
    print(f"判定: {'✓ 界面代答成功，逐题精确命中' if good else '✗ 没对上'}")
    cleanup()
    sys.exit(0 if (good and ok_list and ok_panel and sent) else 1)
except Exception as e:
    import traceback; traceback.print_exc()
    cleanup(); sys.exit(1)
