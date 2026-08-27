#!/usr/bin/env python3
"""把图片转成 Tokyo Night 配色的 ASCII art 壁纸。

管线：magick 降采样 -> PPM -> 字符映射 + 调色板吸附 -> SVG -> rsvg-convert -> PNG
每个字符显式指定 x 坐标，不依赖字体 advance，网格保证对齐。
"""
import subprocess, sys, os, math, html

OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "MesloLGS Nerd Font Mono"
W, H = 3840, 2160
COLS = 320
CELLW = W / COLS                 # 12.0
CELLH = CELLW / 0.6              # 20.0  等宽字典型宽高比
ROWS = int(H / CELLH)            # 108
BG = "#1a1b26"

# 亮度 -> 字符（由暗到亮）。经典 70 级斜坡，渐变最平滑。
RAMP70 = (" .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao"
          "*#MW&8%B@$")
# 稀疏斜坡：颗粒更粗、更像终端 ANSI art
RAMP10 = " .:-=+*#%@"

# Tokyo Night 冷色子集（吸附目标）
PALETTE = ["#1a1b26", "#20222f", "#24283b", "#2f334d", "#414868", "#565f89",
           "#6a76a8", "#7aa2f7", "#9d7cd8", "#bb9af7", "#7dcfff", "#2ac3de",
           "#89ddff", "#a9b1d6", "#c0caf5", "#d5dcf5"]
MONO = ["#1a1b26", "#232538", "#2f334d", "#414868", "#565f89", "#6a76a8",
        "#7f8bbf", "#939fd0", "#a9b1d6", "#c0caf5", "#d8def7", "#eef0fb"]


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb2lab(rgb):
    def f(c):
        c /= 255.0
        return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4
    r, g, b = (f(c) for c in rgb)
    x = (r * .4124 + g * .3576 + b * .1805) / .95047
    y = r * .2126 + g * .7152 + b * .0722
    z = (r * .0193 + g * .1192 + b * .9505) / 1.08883

    def g_(t):
        return t ** (1 / 3) if t > .008856 else 7.787 * t + 16 / 116
    x, y, z = g_(x), g_(y), g_(z)
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))


def build_snap(pal, lmin=46, lmax=94):
    """色相取自源像素，明度重新映射到 [lmin,lmax]。

    字符疏密已经负责表达结构了，颜色再跟着变暗只会让画面糊成一团；
    统一把落笔的字符推到亮端，才有 ASCII art 该有的对比。
    """
    labs = [(p, rgb2lab(hex2rgb(p))) for p in pal]
    cache = {}

    def snap(rgb, n):
        key = (rgb[0] >> 3, rgb[1] >> 3, rgb[2] >> 3, int(n * 12))
        if key in cache:
            return cache[key]
        lab = list(rgb2lab(rgb))
        lab[0] = lmin + n * (lmax - lmin)
        best = min(labs, key=lambda pl: (lab[0] - pl[1][0]) ** 2 * 2.2 +
                   (lab[1] - pl[1][1]) ** 2 + (lab[2] - pl[1][2]) ** 2)[0]
        cache[key] = best
        return best
    return snap


def sample(path, cols, rows, sig=4, crop=None, sharp=None):
    """降采样成 cols x rows 的 RGB 网格。先拉满色阶再加 S 曲线提对比。

    crop:  magick geometry，如 "5120x2880+1800+880"，先裁再降采样。
    sharp: 降采样前先 unsharp，保住五官边缘（缩到几百像素时细节最容易糊掉）。
    """
    args = ["magick", path]
    if crop:
        args += ["-crop", crop, "+repage"]
    args += ["-colorspace", "sRGB", "-auto-level",
             "-sigmoidal-contrast", f"{sig}x45%"]
    if sharp:
        args += ["-unsharp", sharp]
    args += ["-resize", f"{cols}x{rows}!", "-depth", "8", "ppm:-"]
    raw = subprocess.run(args, capture_output=True, check=True).stdout
    # 解析 P6 头：magick 输出可能带注释行
    pos, fields = 0, []
    while len(fields) < 4:
        while raw[pos:pos + 1].isspace():
            pos += 1
        if raw[pos:pos + 1] == b"#":
            while raw[pos:pos + 1] not in (b"\n", b""):
                pos += 1
            continue
        s = pos
        while not raw[pos:pos + 1].isspace():
            pos += 1
        fields.append(raw[s:pos])
    pos += 1
    assert fields[0] == b"P6", fields[0]
    w, h = int(fields[1]), int(fields[2])
    px = raw[pos:]
    return [[tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
             for x in range(w)] for y in range(h)]


def edge_map(path, cols, rows, crop=None, blur=2, amt=3):
    """梯度幅值图。用于主体和背景亮度接近、亮度通道分不开的柔光插画。"""
    args = ["magick", path]
    if crop:
        args += ["-crop", crop, "+repage"]
    args += ["-colorspace", "gray", "-blur", f"0x{blur}", "-edge", str(amt),
             "-normalize", "-resize", f"{cols}x{rows}!", "-depth", "8", "pgm:-"]
    raw = subprocess.run(args, capture_output=True, check=True).stdout
    pos, fields = 0, []
    while len(fields) < 4:
        while raw[pos:pos + 1].isspace():
            pos += 1
        if raw[pos:pos + 1] == b"#":
            while raw[pos:pos + 1] not in (b"\n", b""):
                pos += 1
            continue
        s = pos
        while not raw[pos:pos + 1].isspace():
            pos += 1
        fields.append(raw[s:pos])
    pos += 1
    w, h = int(fields[1]), int(fields[2])
    px = raw[pos:]
    return [[px[y * w + x] for x in range(w)] for y in range(h)]


def render(src, dest, ramp, pal, gamma=1.0, boost=1.0, floor=0.0, sig=4,
           crop=None, cols=COLS, sharp=None, edge=0.0, edge_blur=2, edge_amt=3):
    """floor: 归一化亮度低于此值的像素直接留空白 —— 控制留白率，是观感的关键。

    cols: 字符列数。列数越高细节越足、字越小；人物脸部想看清就得提上去。
    edge: 0..1，字符密度里边缘通道占的比重。柔光插画靠亮度分不开主体时调高它。
    """
    cellw = W / cols
    cellh = cellw / 0.6
    rows = int(H / cellh)
    grid = sample(src, cols, rows, sig, crop, sharp)
    egrid = (edge_map(src, cols, rows, crop, edge_blur, edge_amt)
             if edge > 0 else None)
    snap = build_snap(pal)
    body, drawn = [], 0
    for y, row in enumerate(grid):
        ty = (y + 0.82) * cellh          # 基线位置
        runs, cur, xs, col = [], [], [], None
        for x, rgb in enumerate(row):
            lum = .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2]
            n = (lum / 255) ** gamma * boost
            if egrid:
                n = n * (1 - edge) + (egrid[y][x] / 255) * edge
            if n <= floor:
                n = 0.0
            else:                         # 阈值以上重新拉回 0..1，不浪费斜坡层级
                n = (n - floor) / (1 - floor)
            lum = min(255, n * 255)
            ch = ramp[min(len(ramp) - 1, int(lum / 256 * len(ramp)))]
            if ch == " ":
                if cur:
                    runs.append((col, xs, cur)); cur, xs = [], []
                col = None
                continue
            c = snap(rgb, n)
            if c != col and cur:
                runs.append((col, xs, cur)); cur, xs = [], []
            col = c
            cur.append(ch)
            xs.append(f"{x * cellw:g}")
        if cur:
            runs.append((col, xs, cur))
        for c, xs, chs in runs:
            drawn += len(chs)
            body.append(f'<tspan x="{" ".join(xs)}" y="{ty:g}" fill="{c}">'
                        f'{html.escape("".join(chs))}</tspan>')

    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="{BG}"/>'
           f'<text font-family="{FONT}" font-size="{cellh:g}" '
           f'xml:space="preserve">{"".join(body)}</text></svg>')
    sp = dest + ".svg"
    open(sp, "w").write(svg)
    subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H),
                    "-o", dest, sp], check=True)
    os.remove(sp)
    return os.path.getsize(dest), drawn / (cols * rows)


if __name__ == "__main__":
    D = dict          # 每项: (源, 名, 斜坡, 调色板, kwargs)
    JOBS = [
        ("A-最搭/11-w55gjr.png",     "a1-紫调少女",   RAMP70, PALETTE,
         D(gamma=.70, boost=1.25, floor=.10, sig=5)),
        ("C-暗调单色/15-rqdvwq.png", "a2-雨中武士",   RAMP70, PALETTE,
         D(gamma=.70, boost=1.20, floor=.20, sig=5)),
        ("C-暗调单色/05-vpqpem.png", "a3-浪客行",     RAMP70, MONO,
         D(gamma=.65, boost=1.25, floor=.12, sig=4)),
        ("A-最搭/10-xe6mrd.jpg",     "a4-青蓝少女",   RAMP70, PALETTE,
         D(gamma=.75, boost=1.15, floor=.26, sig=5)),
        ("A-最搭/02-1qkz23.png",     "a5-月牙极简",   RAMP10, PALETTE,
         D(gamma=.90, boost=1.00, floor=.08, sig=3)),
        ("C-暗调单色/06-og5v3m.png", "a6-烙印勇士",   RAMP70, MONO,
         D(gamma=.70, boost=1.20, floor=.32, sig=5)),
        ("C-暗调单色/07-xe762v.jpg", "a7-黑金属少女", RAMP70, MONO,
         D(gamma=.55, boost=1.35, floor=.24, sig=6)),
        ("A-最搭/20-ogjmdp.png",     "a8-水下法阵",   RAMP70, PALETTE,
         D(gamma=.70, boost=1.20, floor=.32, sig=5)),
        ("C-暗调单色/08-qrzrmq.png", "a9-剪影极简",   RAMP10, PALETTE,
         D(gamma=.70, boost=1.20, floor=.10, sig=4)),
        # 柔光插画：主体和背景亮度接近，必须靠 edge 通道才分得开
        ("A-最搭/27-vpe31p.jpg",     "b1-霓虹房间",   RAMP70, PALETTE,
         D(gamma=.72, boost=1.30, floor=.12, sig=4, cols=360, edge=.72,
           crop="2048x1152+3560+880")),
    ]
    os.makedirs(os.path.join(OUT, "D-ASCII"), exist_ok=True)
    for src, name, ramp, pal, kw in JOBS:
        sp = os.path.join(OUT, src)
        if not os.path.exists(sp):
            print(f"  ! 缺源文件 {src}"); continue
        dp = os.path.join(OUT, "D-ASCII", name + ".png")
        try:
            sz, fill = render(sp, dp, ramp, pal, **kw)
            print(f"  {name:14s} {sz/1e6:5.1f}MB  字符占屏 {fill*100:4.1f}%")
        except Exception as e:
            print(f"  ! {name}: {e}")
