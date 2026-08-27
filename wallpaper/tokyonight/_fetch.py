#!/usr/bin/env python3
"""按 Tokyo Night 配色从 wallhaven 挑选二次元壁纸。"""
import json, urllib.request, urllib.parse, os, math, time

OUT = os.path.dirname(os.path.abspath(__file__))

# Tokyo Night (night / storm / moon 共通口径) 调色板
TN = ["1a1b26", "24283b", "222436", "1f2335", "414868",
      "7aa2f7", "bb9af7", "7dcfff", "2ac3de", "9ece6a",
      "c0caf5", "565f89", "f7768e", "9d7cd8"]

# wallhaven 支持的颜色筛选值里，最贴近 Tokyo Night 的几个
SEEDS = ["424153", "663399", "333399", "0066cc", "999999"]


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb2lab(rgb):
    def f(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (f(c) for c in rgb)
    x = (r * .4124 + g * .3576 + b * .1805) / .95047
    y = (r * .2126 + g * .7152 + b * .0722) / 1.0
    z = (r * .0193 + g * .1192 + b * .9505) / 1.08883

    def g_(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    x, y, z = g_(x), g_(y), g_(z)
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))


TN_LAB = [rgb2lab(hex2rgb(c)) for c in TN]


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def score(colors):
    """越低越贴近 Tokyo Night。colors 按显著性排序，权重递减。"""
    total, wsum = 0.0, 0.0
    for i, c in enumerate(colors):
        lab = rgb2lab(hex2rgb(c))
        d = min(dist(lab, t) for t in TN_LAB)
        w = 1.0 / (i + 1)
        # 高亮度暖色（橙/黄/红底色）额外惩罚，和 Tokyo Night 的冷暗调冲突
        if lab[0] > 65 and lab[1] > 15:
            d *= 1.6
        total += d * w
        wsum += w
    return total / wsum


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


pool = {}
for seed in SEEDS:
    for page in (1, 2):
        q = urllib.parse.urlencode({
            "categories": "010",     # 只要 anime
            "purity": "100",         # 只要 sfw
            "colors": seed,
            "atleast": "1920x1080",
            "ratios": "16x9",
            "sorting": "toplist",
            "topRange": "1y",
            "page": page,
        })
        try:
            data = fetch("https://wallhaven.cc/api/v1/search?" + q)["data"]
        except Exception as e:
            print(f"  ! {seed} p{page}: {e}")
            continue
        for w in data:
            pool[w["id"]] = w
        print(f"  {seed} p{page}: +{len(data)}  (pool={len(pool)})")
        time.sleep(1.2)

ranked = sorted(pool.values(), key=lambda w: score(w["colors"]))
picks = ranked[:18]

json.dump(picks, open(os.path.join(OUT, "_picks.json"), "w"), indent=1)
print(f"\n候选池 {len(pool)} 张 -> 取最贴近的 {len(picks)} 张")
for i, w in enumerate(picks, 1):
    print(f"{i:2d}. {w['id']}  score={score(w['colors']):5.1f}  "
          f"{w['resolution']:>10}  {' '.join(w['colors'])}")
