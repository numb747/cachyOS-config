#!/usr/bin/env python3
"""生成 Tokyo Night 风格的壁纸预览页。"""
import json, os, glob, html

OUT = os.path.dirname(os.path.abspath(__file__))
meta = {w["id"]: w for f in ("_picks.json", "_picks2.json")
        for w in json.load(open(os.path.join(OUT, f)))}

NOTES = {
    "1qkz23": ("美少女战士 · 极简月牙", "底色几乎就是 #1a1b26，月牙的淡蓝紫≈#c0caf5。配透明终端最干净，桌面图标完全不受干扰。"),
    "k875o6": ("美少女战士 · Q版头像", "同系列极简款，深靛蓝底 + 蓝紫描线。比上一张更活泼一点。"),
    "xe6mrd": ("青蓝发光少女", "深蓝黑底 + 青色发光线条，正是 #7dcfff / #2ac3de。冲击力最强的一张。"),
    "ogjmdp": ("水下法阵", "8K。深蓝渐变 + 亮青蓝魔法阵，留白大，压得住桌面元素。"),
    "ogjwvl": ("紫樱街道倒影", "蓝天 + 紫樱 + 湿地倒影，蓝紫比例接近 #7aa2f7 / #bb9af7。唯一一张亮色系但仍然对味的。"),
    "ml2191": ("雨天铁道少女", "阴天灰蓝紫调，非常贴 storm 变体的 #24283b。氛围最好。"),
    "w55gjr": ("紫调少女 · 黑底", "纯黑底 + 淡紫人物≈#bb9af7。极简，居中构图。"),
    "vpe31p": ("霓虹房间白发少女", "8K。整体淡紫雾调，霓虹线条像 #bb9af7 / #7dcfff 的描边。"),

    "rqq3gm": ("蓝白双色调少女", "只有两个色阶的风格化处理，蓝比 Tokyo Night 更亮更饱和。"),
    "6ldydx": ("星空流星双人", "蓝紫为主基调很对，但彩虹色流星带一点杂色。"),
    "xe93pd": ("城市摩托少女", "冷蓝灰城市调，右上角有一点红叶暖色点缀。"),
    "gww6me": ("雨夜公路", "冷灰蓝雨夜，车尾灯是小面积红色。写实氛围向。"),
    "jex3gp": ("紫光病房", "紫光很像 #bb9af7，构图偏叙事性、内容偏私密。"),
    "3q25qd": ("星空白衣少女", "淡蓝紫柔光，整体偏亮，和透明终端的对比会弱一些。"),
    "8geml1": ("暗紫灰双人", "暗紫灰调，细节多，杂色也多一点。"),
    "e86v1l": ("雨中废墟枪械少女", "冷灰蓝，偏灰、紫味不足，但暗度很够。"),
    "1qd39g": ("暗巷俯视", "冷调暗巷，地面黄线是唯一暖色。"),

    "vpqpem": ("浪客行 · 宫本武藏", "纯黑白钢笔画。和 Tokyo Night 不冲突，但不是同色系。"),
    "og5v3m": ("烙印勇士 · 蚀之日", "黑底 + 等高线纹理，排版感强。"),
    "xe762v": ("黑金属字体少女", "纯黑 + 白，字体设计向。"),
    "qrzrmq": ("极简人物剪影", "99% 纯黑，极致省电（OLED）。"),
    "vpp688": ("宽荧幕黑底人物", "上下黑边构图，中间一条画面。"),
    "rqdvwq": ("雨中武士", "黑白 + 一道红光。"),
    "1qq37g": ("黑底伸出的手", "留白极多。"),
    "zp9ywo": ("ASCII art 少女", "终端字符画风格，程序员桌面很对味，但纯黑白。"),

    "1q1ywg": ("红色鸟居", "暖红主导，和 Tokyo Night 直接冲突。"),
    "d8oe73": ("夏日蓝天绿植", "高亮度暖绿 + 亮蓝天，色调完全另一路。"),
    "21oymx": ("便利店少女", "货架暖光和红色促销牌太多。"),
    "rq6j57": ("绿色瀑布", "青绿主导，且不是二次元人物向。"),
    "5y33j5": ("粉紫天使", "粉色占比过高。"),
}

# D 档不是 wallhaven 来的，单独描述
ASCII_NOTES = {
    "a7-黑金属少女": ("黑金属少女", "留白最狠、主体最清楚的一张。乐队 logo 的字形转成字符后反而更有味道。我的首选。"),
    "a6-烙印勇士": ("烙印勇士 · 蚀之日", "构图对称，中间日蚀留一个洞。最像终端里直接跑出来的东西。"),
    "a3-浪客行": ("浪客行 · 宫本武藏", "主体压在右侧，左边整片空。放图标或挂件最舒服的一张。"),
    "a1-紫调少女": ("紫调少女", "极简，主体很小，几乎全是留白。安静。"),
    "a5-月牙极简": ("美少女战士 · 月牙", "用的稀疏字符集，颗粒更粗，像老式 ANSI art。"),
    "a9-剪影极简": ("人物剪影", "字符占屏只有 0.7%，极致留白。"),
    "a2-雨中武士": ("雨中武士", "满构图，细节密。当代码背景可能有点吵。"),
    "a4-青蓝少女": ("青蓝少女", "唯一一张青色系明显的，#7dcfff 味道最重。"),
    "a8-水下法阵": ("水下法阵", "源图有上下黑边，转完像一个悬浮的终端窗口，意外地合适。"),
    "b1-霓虹房间": ("霓虹房间", "已重做：裁到半身 + 改用边缘通道驱动字符密度，脸和大衣轮廓现在能认出来了。右侧青色霓虹保留。"),
    "c1-点阵少女": ("点阵少女 · wallhaven", "现成的，不是生成的。点阵风格，带一个细边框。"),
    "c2-网点少女": ("网点少女 · wallhaven", "现成的，半调网点风格，接近漫画印刷质感。"),
}

TIERS = [
    ("D-ASCII", "D · ASCII art", "由 A/C 档源图生成，Tokyo Night 调色板 + MesloLGS Nerd Font。无任何 logo。末尾两张 c1/c2 是 wallhaven 现成的。"),
    ("A-最搭", "A · 最搭", "深靛蓝/紫底 + 蓝紫青点缀，和 Tokyo Night 同一套色相。闭眼选。"),
    ("B-可选", "B · 可选", "整体冷调，但某个维度有偏差（更亮、更灰、或带少量暖色）。"),
    ("C-暗调单色", "C · 暗调单色", "纯黑白。不冲突、够暗，但严格说不算同色系。"),
    ("其他", "其他 · 不推荐", "算法排进来但实际配色不搭，留着供你否决。"),
]

css = """
:root{--bg:#1a1b26;--bg2:#24283b;--fg:#c0caf5;--dim:#565f89;
--blue:#7aa2f7;--purple:#bb9af7;--cyan:#7dcfff;--green:#9ece6a;--red:#f7768e}
*{box-sizing:border-box}
body{margin:0;padding:40px 32px 80px;background:var(--bg);color:var(--fg);
font:15px/1.65 -apple-system,"Noto Sans CJK SC","Source Han Sans SC",sans-serif}
h1{font-size:26px;margin:0 0 6px;color:#fff;font-weight:600}
h1 small{color:var(--purple);font-weight:400;font-size:15px;margin-left:10px}
.sub{color:var(--dim);margin-bottom:34px}
.swatches{display:flex;gap:6px;margin:14px 0 34px}
.sw{width:52px;height:26px;border-radius:5px;font:10px/26px monospace;
text-align:center;color:#1a1b26}
h2{font-size:18px;margin:44px 0 4px;color:var(--blue);font-weight:600}
h2 .n{color:var(--dim);font-weight:400;font-size:13px;margin-left:8px}
.tip{color:var(--dim);font-size:13px;margin-bottom:18px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:20px}
.card{background:var(--bg2);border:1px solid #2f344d;border-radius:10px;
overflow:hidden;transition:.15s}
.card:hover{border-color:var(--purple);transform:translateY(-3px)}
.card img{width:100%;aspect-ratio:16/9;object-fit:cover;display:block;background:#000}
.body{padding:12px 14px 14px}
.t{color:#fff;font-weight:600;margin-bottom:5px}
.t .idx{color:var(--purple);font-family:monospace;margin-right:7px}
.d{color:var(--dim);font-size:13px;margin-bottom:10px}
.meta{display:flex;gap:8px;align-items:center;flex-wrap:wrap;font:11px monospace}
.res{color:var(--green)}
.dots{display:flex;gap:3px}
.dot{width:13px;height:13px;border-radius:3px;border:1px solid #00000055}
a{color:var(--cyan);text-decoration:none}
a:hover{text-decoration:underline}
.acts{margin-top:9px;display:flex;gap:12px;font-size:12px}
code{background:#1a1b26;padding:1px 5px;border-radius:3px;color:var(--green);
font-size:12px}
"""

parts = [f"<!doctype html><meta charset=utf-8><title>Tokyo Night 二次元壁纸</title>"
         f"<style>{css}</style>",
         "<h1>Tokyo Night 二次元壁纸<small>42 张 · 含 10 张自动生成的 ASCII art</small></h1>",
         "<div class=sub>点图片看原图。文件在 "
         "<code>~/Pictures/Wallpapers/tokyonight/</code></div>",
         "<div class=swatches>" + "".join(
             f"<div class=sw style='background:#{c}'>{c[:3]}</div>"
             for c in ["1a1b26", "24283b", "414868", "7aa2f7", "bb9af7",
                       "7dcfff", "9ece6a", "c0caf5"]) + "</div>"]

for folder, title, tip in TIERS:
    files = sorted(glob.glob(os.path.join(OUT, folder, "*")))
    if not files:
        continue
    parts.append(f"<h2>{title}<span class=n>{len(files)} 张</span></h2>"
                 f"<div class=tip>{html.escape(tip)}</div><div class=grid>")
    for f in files:
        base = os.path.basename(f)
        stem = base.rsplit(".", 1)[0]
        rel = f"{folder}/{base}".replace("#", "%23")
        if folder == "D-ASCII":
            idx = stem.split("-")[0]
            name, note = ASCII_NOTES.get(stem, (stem, ""))
            thumb = f"thumbs/D-{stem}.jpg"
            res = "3840x2160" if idx[0] in "ab" else "1920x1080"
            dots = "".join(f"<div class=dot style='background:{c}'></div>"
                           for c in ["#1a1b26", "#414868", "#7aa2f7",
                                     "#bb9af7", "#c0caf5"])
            links = "" if idx[0] != "c" else (
                "<a href='https://wallhaven.cc/w/qrozxl' target=_blank>wallhaven ↗</a>"
                if idx == "c1" else
                "<a href='https://wallhaven.cc/w/9omgp1' target=_blank>wallhaven ↗</a>")
        else:
            idx, wid = stem.split("-")[0], stem.split("-")[1]
            w = meta[wid]
            name, note = NOTES.get(wid, ("", ""))
            thumb = f"thumbs/{idx}-{wid}.jpg"
            res = w["resolution"]
            dots = "".join(f"<div class=dot style='background:{c}'></div>"
                           for c in w["colors"])
            links = (f"<a href='{w['url']}' target=_blank>wallhaven ↗</a>"
                     f"<a href='{html.escape(w['source'] or w['url'])}' "
                     f"target=_blank>出处 ↗</a>")
        parts.append(
            f"<div class=card><a href='{rel}' target=_blank>"
            f"<img src='{thumb}' loading=lazy></a><div class=body>"
            f"<div class=t><span class=idx>{idx}</span>{html.escape(name)}</div>"
            f"<div class=d>{html.escape(note)}</div>"
            f"<div class=meta><span class=res>{res}</span>"
            f"<div class=dots>{dots}</div></div>"
            f"<div class=acts><a href='{rel}' target=_blank>原图</a>{links}"
            f"</div></div></div>")
    parts.append("</div>")

open(os.path.join(OUT, "index.html"), "w").write("\n".join(parts))
print("wrote", os.path.join(OUT, "index.html"))
