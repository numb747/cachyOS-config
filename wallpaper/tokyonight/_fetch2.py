#!/usr/bin/env python3
"""补一轮：要求画面真的带蓝/紫色相，惩罚纯黑白与暖色。"""
import json, urllib.request, urllib.parse, os, math, time, colorsys

OUT = os.path.dirname(os.path.abspath(__file__))
TN = ["1a1b26", "24283b", "222436", "1f2335", "414868",
      "7aa2f7", "bb9af7", "7dcfff", "2ac3de", "c0caf5", "565f89", "9d7cd8"]
SEEDS = ["424153", "663399", "333399"]


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb2lab(rgb):
    def f(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + .055) / 1.055) ** 2.4
    r, g, b = (f(c) for c in rgb)
    x = (r * .4124 + g * .3576 + b * .1805) / .95047
    y = r * .2126 + g * .7152 + b * .0722
    z = (r * .0193 + g * .1192 + b * .9505) / 1.08883

    def g_(t):
        return t ** (1 / 3) if t > .008856 else 7.787 * t + 16 / 116
    x, y, z = g_(x), g_(y), g_(z)
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))


TN_LAB = [rgb2lab(hex2rgb(c)) for c in TN]
d = lambda a, b: math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def is_blue_purple(c):
    r, g, b = (v / 255 for v in hex2rgb(c))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return s > 0.12 and 0.55 <= h <= 0.80      # 蓝 ~ 紫


def chroma(c):
    lab = rgb2lab(hex2rgb(c))
    return math.hypot(lab[1], lab[2])


def score(colors):
    tot = wsum = 0.0
    for i, c in enumerate(colors):
        lab = rgb2lab(hex2rgb(c))
        dd = min(d(lab, t) for t in TN_LAB)
        if lab[0] > 65 and lab[1] > 15:        # 亮暖色，冲突
            dd *= 1.8
        w = 1.0 / (i + 1)
        tot += dd * w
        wsum += w
    s = tot / wsum
    if not any(is_blue_purple(c) for c in colors):   # 没有蓝紫 = 只是暗，不是 Tokyo Night
        s += 22
    if max(chroma(c) for c in colors) < 12:          # 整体接近无彩色（纯黑白）
        s += 18
    return s


def fetch(u):
    r = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
    return json.load(urllib.request.urlopen(r, timeout=30))


pool = {}
for seed in SEEDS:
    for rng in ("1y", "1M"):
        for page in (1, 2, 3):
            q = urllib.parse.urlencode({
                "categories": "010", "purity": "100", "colors": seed,
                "atleast": "1920x1080", "ratios": "16x9",
                "sorting": "toplist", "topRange": rng, "page": page})
            try:
                for w in fetch("https://wallhaven.cc/api/v1/search?" + q)["data"]:
                    pool[w["id"]] = w
            except Exception as e:
                print(f"  ! {seed}/{rng}/p{page}: {e}")
            time.sleep(1.2)
    print(f"  {seed} done  pool={len(pool)}")

old = {w["id"] for w in json.load(open(os.path.join(OUT, "_picks.json")))}
ranked = sorted((w for w in pool.values() if w["id"] not in old),
                key=lambda w: score(w["colors"]))
picks = [w for w in ranked if score(w["colors"]) < 20][:12]

json.dump(picks, open(os.path.join(OUT, "_picks2.json"), "w"), indent=1)
print(f"\n池 {len(pool)} 张（去掉已下载的 {len(old)} 张）-> 新增 {len(picks)} 张")
for i, w in enumerate(picks, 19):
    print(f"{i:2d}. {w['id']}  score={score(w['colors']):5.1f}  "
          f"{w['resolution']:>10}  {' '.join(w['colors'])}")
