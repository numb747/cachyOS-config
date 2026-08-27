#!/usr/bin/env python3
"""用 pty 无头驱动 cc-pet.py：验证它能跑、能画、按键有反应、能干净退出。"""
import os, pty, re, select, struct, subprocess, sys, termios, fcntl, time

ROWS, COLS = 30, 110
ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][B0]|\x1b[=>]|\r")

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

env = dict(os.environ, TERM="xterm-256color", LANG="zh_CN.UTF-8", LC_ALL="zh_CN.UTF-8")
p = subprocess.Popen([sys.executable, os.path.expanduser("~/.claude/cc-pet.py")],
                     stdin=slave, stdout=slave, stderr=slave,
                     env=env, start_new_session=True)
os.close(slave)

buf = bytearray()

def pump(sec):
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([master], [], [], 0.1)
        if r:
            try:
                d = os.read(master, 65536)
            except OSError:
                break
            if not d:
                break
            buf.extend(d)

def screen():
    """把收到的字节还原成'最后一屏'的纯文本（粗略：去 ANSI + 按行去重空白）。"""
    txt = ANSI.sub("", buf.decode("utf-8", "replace"))
    return txt

def expect(label, needle, present=True):
    ok = (needle in screen()) == present
    print(("  ✓ " if ok else "  ✗ ") + f"{label}: {'找到' if needle in screen() else '没找到'} {needle!r}")
    return ok

fails = 0

print("— 启动 2.5s，看能不能画出来 —")
pump(2.5)
for lbl, nd in [("标题", "Claude 会话看板"),
                ("底栏", "Enter 跳过去"),
                ("宠物身体", "/\\_/\\"),
                ("会话数", "个会话")]:
    fails += not expect(lbl, nd)

print("— 宠物有没有在动（换帧）—")
before = screen()
pump(1.2)
after = screen()
moved = len(after) > len(before)
print(("  ✓ " if moved else "  ✗ ") + f"输出仍在增长（{len(before)} → {len(after)} 字节）")
fails += not moved

print("— 按 j 移动选择 —")
buf.clear(); os.write(master, b"j"); pump(0.8)
fails += not expect("选中标记", "▸")

print("— 按 Enter 看路由 —")
buf.clear(); os.write(master, b"\r"); pump(1.5)
got_route = ("跳转路由" in screen()) or ("认不出终端" in screen()) or ("进程已退出" in screen())
print(("  ✓ " if got_route else "  ✗ ") + f"Enter 有响应")
if not got_route:
    print("    实际尾部:", repr(screen()[-400:]))
fails += not got_route

print("— 按 q 退出 —")
os.write(master, b"q")
try:
    rc = p.wait(timeout=5)
    print(f"  ✓ 干净退出，退出码 {rc}")
    fails += (rc != 0)
except subprocess.TimeoutExpired:
    print("  ✗ 没退出，强杀")
    p.kill(); fails += 1

print()
print(f"{fails} 条失败" if fails else "全部通过")
sys.exit(1 if fails else 0)
