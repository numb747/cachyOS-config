# kitty 标签栏，两种画法，改 STYLE 一行切换：
#
#   "pill" 圆头药丸 + 序号，照 nvim 里 tabby 的样子（lua/plugins/tabby.lua）：
#          当前标签实心药丸，其余标签不给背景块。
#   "dot"  手机桌面那种页码点，● 当前 ○ 其余。
#
# 两种都有过（2026-11-13）：先做药丸，看过实际屏幕后改成点 —— 底部已经有 tmux 窗口列表
# （同样是「序号 + 药丸」）和 lualine，药丸容易被认成又一排 tmux 标签；后来用户想再看看药丸，
# 两种都留着。
#
# 不显示标题：本机每个 kitty 标签跑的都是同一条 nvim 命令，标题都一样，显示了也分不出。
# 用 Ctrl+Shift+Alt+T 给标签起过名的，序号/点后面跟名字。
#
# 颜色一律从 draw_data 取，不写死 —— 那几个值来自 noctalia 生成的
# themes/noctalia.conf（active_tab_* / inactive_tab_foreground），换壁纸自动跟上。
#
# ★ 这个文件 kitty 只在进程启动时读一次（load_custom_draw_tab 是 @run_once），
#   改完要开一个新的 kitty 进程才看得到，Ctrl+Shift+F5 重载配置不够。
# ★ 圆头写 \u 转义，不写字面字符（同 tabby.lua 的教训）；码位要在 kitty.conf
#   symbol_map 的范围内，否则落到没有该字形的字体上变方块。

from kitty.fast_data_types import Screen, get_boss
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb
from kitty.utils import color_as_int

STYLE = "pill"  # "pill" | "dot"

SEP_L = "\ue0b6"  # 圆头左
SEP_R = "\ue0b4"  # 圆头右
DOT_ACTIVE = "\u25cf"  # ●
DOT_INACTIVE = "\u25cb"  # ○
GAP = "  "  # 标签之间的留白，嫌挤/嫌散改这一个值
MAX_NAME = 20  # 起过的名字超过这么长就截断


def _rgb(c) -> int:
    return as_rgb(color_as_int(c))


def _name(tab: TabBarData) -> str:
    t = get_boss().tab_for_id(tab.tab_id)
    name = (t.name if t else "") or ""
    if len(name) > MAX_NAME:
        name = name[: MAX_NAME - 1] + "…"
    return name


def _draw_pill(draw_data: DrawData, screen: Screen, tab: TabBarData, index: int, name: str) -> None:
    label = f"{index}" + (f" {name}" if name else "")
    if tab.is_active:
        screen.cursor.fg = _rgb(draw_data.active_bg)
        screen.draw(SEP_L)
        screen.cursor.fg = _rgb(draw_data.active_fg)
        screen.cursor.bg = _rgb(draw_data.active_bg)
        screen.draw(f" {label} ")
        screen.cursor.fg = _rgb(draw_data.active_bg)
        screen.cursor.bg = 0
        screen.draw(SEP_R)
    else:
        # 多两个空格补上药丸两个圆头的宽度，切换时其余标签不会左右跳
        screen.cursor.fg = _rgb(draw_data.inactive_fg)
        screen.draw(f"  {label}  ")


def _draw_dot(draw_data: DrawData, screen: Screen, tab: TabBarData, name: str) -> None:
    if tab.is_active:
        screen.cursor.fg = _rgb(draw_data.active_bg)
        screen.draw(DOT_ACTIVE)
    else:
        screen.cursor.fg = _rgb(draw_data.inactive_fg)
        screen.draw(DOT_INACTIVE)
    if name:
        screen.draw(f" {name}")


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    name = _name(tab)
    # 0 = 默认背景，跟窗口一样吃 background_opacity，所以标签栏也是透的
    screen.cursor.bg = 0
    screen.cursor.bold = screen.cursor.italic = False
    screen.draw(GAP)
    if STYLE == "dot":
        _draw_dot(draw_data, screen, tab, name)
    else:
        _draw_pill(draw_data, screen, tab, index, name)
    screen.draw(GAP)
    end = screen.cursor.x
    screen.cursor.fg = 0
    return end
