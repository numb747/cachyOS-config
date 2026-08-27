#!/usr/bin/env python3
"""探测：两个问题的 AskUserQuestion 选择器怎么操作。

要回答的：
  1. 顶部标签栏长什么样（单问题 multiSelect 时见过 `← ☒ 标签 ✔ Submit →`）
  2. 答完第 1 题会不会自动跳到第 2 题
  3. Submit 在哪、怎么到
判据用底栏 "to navigate"（去空白后比对）—— 选项名会在回显的提示语里假阳性。
"""
import fcntl, os, pty, re, select, shutil, struct, subprocess, sys, termios, time

CLEAN = [re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"),
         re.compile(r"\x1b\[[0-9;?<>=]*[a-zA-Z]"),
         re.compile(r"\x1b[()][B0]|\x1b[=>]|\x1b[78]|\x0f|\x0e")]
W = "/tmp/cc-multiq"
shutil.rmtree(W, ignore_errors=True); os.makedirs(W)

m, s = pty.openpty()
fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 150, 0, 0))
env = dict(os.environ, TERM="xterm-256color", LANG="zh_CN.UTF-8", LC_ALL="zh_CN.UTF-8")
for k in ("CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_ENTRYPOINT"):
    env.pop(k, None)

p = subprocess.Popen(
    ["claude", "--dangerously-skip-permissions",
     "调用一次 AskUserQuestion，在 questions 数组里放【两个】问题。"
     "第一题 header 叫 颜色，问喜欢什么颜色，两个选项 label 是 AAA 和 BBB。"
     "第二题 header 叫 水果，问喜欢什么水果，两个选项 label 是 CCC 和 DDD。"
     "两题都是单选（multiSelect 不设或设 false）。不要做别的事。"],
    cwd=W, stdin=s, stdout=s, stderr=s, env=env, start_new_session=True)
os.close(s)
buf = bytearray()


def pump(sec):
    e = time.time() + sec
    while time.time() < e:
        r, _, _ = select.select([m], [], [], 0.12)
        if r:
            try: d = os.read(m, 65536)
            except OSError: return
            if not d: return
            buf.extend(d)


def txt():
    t = buf.decode("utf-8", "replace")
    for rx in CLEAN: t = rx.sub("", t)
    return t.replace("\r", "")


def norm(x): return re.sub(r"\s+", "", x)


def wait(needle, sec, label):
    e = time.time() + sec
    while time.time() < e:
        pump(1.2)
        if norm(needle) in norm(txt()):
            print(f"  ✓ {label}"); return True
    print(f"  ✗ 等 {label} 超时"); return False


def step(label, keys, wait_sec=3.0):
    buf.clear()
    if keys: os.write(m, keys)
    pump(wait_sec)
    print(f"\n═══ {label} ═══")
    out = txt().strip()
    print(out[-700:] if out else "(无输出)")
    return out


if wait("trust this folder", 25, "信任框"):
    os.write(m, b"\r"); pump(3)

print("等两问题选择器弹出…")
if not wait("to navigate", 100, "选择器出现"):
    print(txt()[-1500:]); p.kill(); sys.exit(1)
pump(2.5)

step("① 初始画面：看有没有标签栏、光标在哪", None, 1.0)
step("② 按 Enter（选第 1 题的 AAA）—— 会自动跳第 2 题吗？", b"\r", 4.0)
step("③ 按 ↓（若已在第 2 题，应移到 DDD）", b"\x1b[B", 3.0)
step("④ 按 Enter", b"\r", 6.0)
step("⑤ 再等等看最终状态", None, 12.0)

print("\n" + "=" * 60)
t = txt()
for n in ("AAA", "BBB", "CCC", "DDD"):
    print(f"  最终文本里 {n}: {t[-900:].count(n)} 次")

os.write(m, b"\x03"); time.sleep(0.3); os.write(m, b"\x03"); time.sleep(0.5)
p.terminate()
try: p.wait(timeout=5)
except subprocess.TimeoutExpired: p.kill()
