# 02 · Hyprland：键位方案与窗口行为

对应文件：`config/hypr/mykeys.lua`（422 行，35 条 `hl.bind`）
＋ 3 个改过的官方文件 ＋ `config/hypr/patches/*.patch`

键位纯速查见 [06-keymap-cheatsheet.md](06-keymap-cheatsheet.md)。本篇讲**为什么这么设计**。

---

## 挂载方式

```lua
-- ~/.config/hypr/hyprland.lua 末尾唯一的一行改动
require("mykeys")
```

两条必须知道的 API 语义（都是实测得出的）：

- **`hl.bind` 对同一键位是「叠加」不是「覆盖」。**
  想替换官方键位，必须先 `hl.unbind("键位字符串")`。unbind 一个不存在的键位不报错，
  所以脚本可以放心幂等执行。
- **`hl.config` 是「逐项合并」不是整块替换。**
  已实测：`mykeys.lua` 设了 `input.follow_mouse` 之后，官方 `inputs.lua` 里的
  `accel_profile = "flat"` 仍然保留。所以可以安心只写自己关心的那几项。

---

## 设计取舍逐条

### 全屏状态下的方向切焦点（第 2 节）

Hyprland 原生的 `movefocus` 在全屏时会失灵——整块屏幕只有一个窗口，「左边」无从谈起。

做法：**先摘全屏 → 在真实平铺布局上判方向 → 把同样的全屏级别还给新窗口**。
于是方向感和全屏模式两个都保住了。顶部的开关：

```lua
local KEEP_FULLSCREEN_ON_FOCUS = true   -- true=全屏轮播  false=退出全屏再切
```

用 `fullscreen_state{internal=,client=}` 而不是 `fullscreen{mode=}`，因为前者是
**幂等赋值**、后者是 **toggle**，且两者的编号约定不一致，toggle 很容易写反。

原生替代方案 `binds.movefocus_cycles_fullscreen = true` 一行就够，但它是「循环」不是
「方向」——H 和 L 会退化成上一个/下一个，空间方向感丢失。所以没用它。

### 为什么关窗是 `ALT+W` 而不是 `CTRL+W`

Wayland 下合成器的全局 bind **直接截获**按键，应用一点都收不到。而 `CTRL+W` 在三个
高频场景都有要紧用途：终端 readline 删除前一个单词、浏览器关标签页、编辑器关文件。
拿它换「关窗口」得不偿失。`ALT+W` 保住了同一个字母的肌肉记忆，代价只是带菜单栏的
应用里 Alt+W 原本的「Window」菜单助记键。

### 分屏终端为什么是「往某方向开一个新窗口」

平铺布局里**没有**「把当前窗口劈成两半」这个动作——窗口数量决定分几块。所以实现是两步：

```lua
hl.dispatch(hl.dsp.layout("preselect " .. dir))       -- 预选下一个新窗口落在哪边
hl.dispatch(hl.dsp.exec_cmd(launchPrefix .. TERMINAL)) -- 紧接着把终端拉起来
```

`preselect` 是一次性的，被这个新窗口消费掉后自动失效。
想要纯预选（自己手动开任意程序）就把第二行删掉。
`ALT+SHIFT+\` 是另一回事：翻转**已有的**两个窗口的分割方向。

### Caps Lock 当 Esc：走 XKB，不是键位绑定

```lua
hl.config({ input = { kb_options = "caps:escape" } })
```

改的是键盘布局本身，所以整个 Wayland 会话（含 XWayland 应用）都生效，nvim 里也一样。
`hl.bind` 做不到这件事——绑定只能触发 dispatcher，不能把一个键伪装成另一个键。

取值：`caps:escape`（当前，Esc 键保持原样）· `caps:swapescape`（对调）· `caps:none`（只废掉）。
完整列表在 `/usr/share/X11/xkb/rules/base.lst` 里搜 `caps:`。

> 想要「轻按 Esc、按住 Ctrl」那种双功能：XKB 做不到，需要 `keyd` 或
> `interception-tools` 这类在 evdev 层工作的工具。

### 鼠标行为三连（第 6 / 6b 节）

```lua
cursor.hide_on_key_press = true   -- 打字时隐藏光标，动鼠标才回来
cursor.no_warps          = true   -- 切焦点时指针不瞬移
input.follow_mouse       = 2      -- 悬停不抢键盘焦点，点击才切
input.mouse_refocus      = false  -- 指针不动、脚下窗口换了时不重新派发焦点
```

这四项是**互相咬合**的，不是四个独立开关：

`no_warps` 是为 `hide_on_key_press` 服务的——光标「重新显形」的条件正是「指针发生
移动」，而 Hyprland 默认切焦点会把指针 warp 过去，于是每次切窗口光标都闪一下。
第 2 节的 `focus_dir` 每按一次连发三个 dispatch，闪烁被放大三倍。关掉 warp 就消失了。

关掉 warp 之后，如果还停在 `follow_mouse = 1`，手碰一下鼠标就会把焦点抢回指针
所在的窗口——所以必须同时改成 2。

### window swallowing：官方默认开着，本配置未改

`config/misc.lua` 里这两行是官方默认值，本配置沿用：

```lua
enable_swallow = true,
swallow_regex  = "(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)",
```

效果是**从终端启动 GUI 时，那个终端窗口会被隐藏**，GUI 关掉再放回来。第一次遇到时
极易误判成「程序把 shell 占住了」，然后徒劳地去试 `nohup` / `&` / `disown`——
它的判据是**进程祖先链**，跟作业控制毫无关系，那三个都改不了父子关系。

单次绕开：`setsid -f CMD`。完整判据、根因与四种方案的实测对比见
[07](07-troubleshooting.md) 坑 9。

### 抽屉架（rack）：第二套工作平面

> 2026-08-26 改造。此前是**单个**无名 special workspace（`special:special`），语义是
> 「临时藏一两个窗口」。现在是一组命名 special workspace 组成的**第二套工作环境**。

本配置有两套平面：

- **工作平面** —— 普通工作区（正数 id），正事在这儿
- **抽屉架** —— `special:rack1` / `special:rack2` / …，另一批程序（聊天、媒体、下载器）
  住这儿。每一格都是满屏桌面，整架可一键收起

#### 键位：模态复用，零新增

`ALT+S` 从「开抽屉」变成「切平面」，其余导航键含义随所在平面变化：

| 键 | 工作平面 | 抽屉架 |
|---|---|---|
| `ALT+S` | 进抽屉架（回上次那格） | 收起，回工作平面 |
| `ALT+[` `]` · `CTRL+2` `3` | 工作桌面 ←→ | 抽屉格 ←→（**回绕**） |
| `CTRL+1` `4` | 工作桌面头/尾 | 抽屉格头/尾 |
| `ALT+T` | 新建工作桌面 | 新建一格抽屉 |
| `ALT+SHIFT+[` `]` | 带窗口切工作桌面 | 带窗口切抽屉格 |
| `ALT+SHIFT+T` | 带窗口去新工作桌面 | 带窗口去新抽屉格 |
| `ALT+SHIFT+S` | 把窗口丢进抽屉架 | 把窗口捞回工作平面 |

这是本配置**唯一**的模态。能接受是因为抽屉架浮出来是满屏的
（`dwindle.special_scale_factor` 默认 `1.0`），「我在哪个平面」一眼可见。
`ALT+S` 同时就是老板键。

实现上是 `mykeys.lua` 第 1b 节的 `two_planes(work, in_rack)` 包装器，
全部模态判断只有**一个来源**：`rack.current_slot()` 返回 `nil` 就是在工作平面。

抽屉格切换**回绕**而工作桌面不回绕：抽屉架常态只有两格，回绕让 `ALT+]` 直接变成
两格来回切，比走到头卡住好用。

#### 为什么用 special 而不是「多开几个普通工作区」

- **收起来自动回原处。** special 是「盖在」当前工作桌面上的，收起即复位。走普通
  工作区就得自己维护「进来之前在哪个桌面」，而本配置是纯动态工作区，那个桌面随时
  可能被销毁 —— 变量必然失效，是个 bug 温床。
- **隔离是免费的。** `edge_ws()` 的 `w.id > 0` 过滤（见下文）已经把负数 id 的 special
  挡在外面，`CTRL+1/4` 永远不会误入抽屉架。
- **视觉上无差别。** 满屏，不是缩小的浮动面板。

格数**动态**，同工作平面哲学：`ALT+T` 加一格，搬空自动消失
（`misc.close_special_on_empty` 默认 `true`）。副作用：新开一格却不往里放东西就离开，
这一格会当场蒸发 —— 与「空工作区不赖着」是同一个规则，不是 bug。

#### `ALT+SHIFT+S`：一个键管两个方向

官方只绑了「送进去」，没绑「取出来」，用起来像只进不出的黑洞。这里做成双向，
按当时状态决定方向：

1. 焦点窗口在抽屉架里 → 捞回底下的工作桌面
2. 抽屉架浮着但焦点没进去 → 捞出当前格最后一个
3. 其余 → 把当前窗口丢进抽屉架的目标格

分支 1 落点是 `monitor.active_workspace`（**当前**工作桌面，不是窗口原来那个），
实测切到 ws3 再捞，窗口落在 ws3。

分支 2 曾经是必需兜底（旧坑 3）。2026-08 在 Hyprland 0.56.2 上复验，**焦点现在会
跟进 special**（`kitty@2` → `v2rayN@special:rack1`），所以分支 1 通常就接住了。
分支 2 保留作兜底：留着零成本，删了则焦点万一没进去时这个键会反过来「把窗口塞进去」。

#### 实测出来的 API 约束

stub `/usr/share/hypr/stubs/hl.meta.lua` 里这些函数全是 `fun(...)`，没有任何类型
信息，只能试。**两条最坑的都是「不认识的参数直接忽略，不报错」**：

1. **`toggle_special` 收裸字符串，且不带 `special:` 前缀。**

   ```lua
   hl.dsp.workspace.toggle_special("rack2")            -- ✅
   hl.dsp.workspace.toggle_special({ name = "rack2" }) -- ❌ 静默退回 special:special
   ```

   `{workspace=}` / `{special=}` / `{"rack2"}` 同样静默失效。

2. **`window.move` 正相反：要 table，`workspace` 要全名。**

   ```lua
   hl.dsp.window.move({ workspace = "special:rack2" })  -- ✅
   ```

   同一节里两个 API 前缀要求相反，最容易写错。

3. **「藏窗口」的参数叫 `follow = false`，不叫 `silent`。**
   默认送窗口进 special 会把那一格拉出来显示并带走焦点。实测
   `silent = true` / `silent = 1` / `focus = false` / `quiet = true` **全部静默失效**
   （照样弹出来），只有 `follow = false` 管用。原生 dispatcher 叫
   `movetoworkspacesilent`，名字对不上，别照着猜。

4. **`hl.get_workspaces()` 会返回 special 工作区。** 实测
   `[2:2 3:3 -99:special:special 4:4 5:5]`。枚举抽屉格直接遍历它即可。
   （本文档旧版和 `mykeys.lua` 旧注释都写反了，见下文「纯动态工作区」一节。）

5. **从一格直接切到另一格是一次 `toggle_special` 调用**，不必先关再开。

6. **抽屉格 id 不稳定。** 搬空后销毁，再放东西是全新 id（实测 `-99` → `-98`）。
   所以代码一切认名字（`^special:rack(%d+)$`），绝不认 id。

7. **抽屉架收起时 `monitor.active_special_workspace` 是 `nil`**，哪怕格里有窗口。
   查内容要用 `hl.get_workspace("special:rackN")`，它不受开合影响。

另外 `monitor.active_workspace` 在抽屉架浮出时**仍然是底下那个正常工作桌面**，
与焦点在哪无关 —— 这正是「窗口捞出来放哪儿」的答案。

#### 调试出口 `RACK`

`hyprctl eval` 是另一个 chunk，够不到 `mykeys.lua` 里的 local，所以引擎在文件末尾
挂了一个全局引用：

```bash
hyprctl eval 'RACK.toggle_plane()'
hyprctl eval 'local f=io.open("/tmp/r","w") f:write(table.concat(RACK.slots(),",")) f:close()'
```

`hyprctl eval` 拿不到返回值也没有 `print`，**要看结果只能自己写文件**。
这是验收时唯一能测到「真正跑着的那份代码」的办法 —— 照抄一遍逻辑去 eval，验的是
副本不是本体。（`hl.dsp.send_shortcut` 试过，参数形式没试出来，走不通。）

---

## 纯动态工作区

**核心思路**：工作区是临时对象——非 persistent 的工作区在最后一个窗口关闭后自动消失。
于是「新建桌面」＝跳到一个空工作区，「删除桌面」＝把它搬空。不需要预先决定有几个桌面。

| 键 | 行为 |
|---|---|
| `ALT+T` | 在**最右边**追加一个新桌面 |
| `ALT+SHIFT+T` | 带着当前窗口去新桌面 |
| `ALT+[` / `ALT+]` | 在实际存在的桌面之间左右走 |
| `CTRL+2` / `CTRL+3` | 同上，纯左手版（见下） |
| `CTRL+1` / `CTRL+4` | 直接跳到**第一个 / 最后一个**桌面（见下） |
| `SUPER+CTRL+1..9` | 跳到本显示器上**第 N 个已存在**的桌面（按位置，不是按编号） |

### 为什么不用官方的 `emptym`

`emptym` = 「本显示器上编号最小的空工作区」，它会**往回找**：你在 2 号按一下，它跳到
空着的 1 号去——方向是反的。改用 `maxid + 1` 后语义变成「在末尾开一个新的」，桌面
永远从左往右长，`ALT+]` 就能顺着走回来，跟直觉一致。

```lua
local function next_ws()
    local maxid = 0
    for _, w in ipairs(hl.get_workspaces()) do
        if w.id > maxid then maxid = w.id end
    end
    return tostring(maxid + 1)
end
```

这里不用像 `edge_ws()` 那样过滤 special。注意**理由不是**「`hl.get_workspaces()` 不返回
special」—— 它**确实会**返回（本文档 2026-08-26 之前写反了）。真正的理由是 special 的
id 是负数，**永远当不上 max**。取 min 的 `edge_ws()` 就没这个便宜可占，必须显式写
`w.id > 0`。

编号会随着开关桌面出现空洞（剩 1、3 时新建的是 4 而不是 2），这无所谓——本配置
**从不按绝对编号跳转**，位置跳转用的是 `m~N`。

### `CTRL+2` / `CTRL+3`：纯左手切屏

`[` 和 `]` 在右手区、CTRL 在左下角，切屏得动两只手。`CTRL+2/3` 全在左手：小指压 CTRL，
食指/中指够 2 和 3，右手可以一直放在鼠标上。两套并存，看哪只手空着就用哪套。

⚠️ 代价（和 `CTRL+W` 同一类）：合成器截获后应用收不到，被占掉两个用途——
Chrome 系浏览器的「切到第 2/3 个标签页」、VS Code / Zed 的「聚焦第 2/3 个编辑器分栏」。
kitty 的切标签是 `CTRL+SHIFT+数字`，不受影响。
真被咬到就把那两行改成 `CONTROL + ALT + 2/3`，零冲突且仍是纯左手。

### `CTRL+1` / `CTRL+4`：跳到头 / 跳到尾

和上面凑成一组：`1 2 3 4` 排成一行，**两端是「直接到头/到尾」，中间两个是「左右挪一格」**，
四个键一只左手全包。桌面多了以后连按 `CTRL+3` 走过去很烦，`CTRL+4` 一步到位。

⚠️ **不能写成绝对编号 `1` 和 `4`。** 纯动态工作区的编号会留洞——剩 1、3、7 是常态，
按绝对编号跳会凭空创建那个编号的工作区（这正是官方 `SUPER+ALT+数字` 被注释掉的原因）。
所以按下时实时扫一遍现存工作区取 min / max id：

```lua
local function edge_ws(want_max)
    local mon  = hl.get_active_monitor()
    local best = nil
    for _, w in ipairs(hl.get_workspaces()) do
        local same_mon = (mon == nil) or (w.monitor == nil) or (w.monitor.name == mon.name)
        if w.id > 0 and not w.special and same_mon then
            if best == nil
                or (want_max and w.id > best)
                or (not want_max and w.id < best) then
                best = w.id
            end
        end
    end
    return tostring(best or 1)
end
```

两个过滤条件都不能省：

- **`w.id > 0 and not w.special`** —— 抽屉架那些 special 工作区 id 是负数（`-99` 起）。
  不过滤的话 min 永远是抽屉格，`CTRL+1` 会一头扎进抽屉架。上面 `next_ws()` 只取 max
  所以不需要这条，别照抄那份就以为够了。
  ★ 这条同时是**两个平面互不干扰的保证**，不只是防呆 —— 见上文「抽屉架」。
- **同显示器** —— 与 `m-1/m+1`「本显示器内相对」保持一致。单屏时这条不起作用，接副屏才有区别。

不用官方 `m~N` token 的理由：`m~1` 确实等于「第一个」，但「最后一个」得先知道总数，
还是要扫一遍，不如两端统一用 id，读起来对称。

代价同 `CTRL+2/3`：浏览器的「切到第 1 / 第 4 个标签页」会被吃掉，`CTRL+1` 尤其常用。
介意就改成 `CONTROL + ALT + 1/4`。

---

## 关于官方文件被改动

纯动态工作区没法只靠 `mykeys.lua` 实现，因为要**取消**官方已经定义的东西。
五个文件的改动：

| 文件 | 改了什么 | 为什么 |
|---|---|---|
| `config/workspaces.lua` | 删掉全部 `hl.workspace_rule(... persistent = true)` | persistent 会让空工作区赖着不走，等于退回写死 N 个桌面 |
| `config/binds.lua` | 注释掉 `SUPER+ALT+数字`（绝对编号跳转）那个循环 | 按绝对编号跳会**凭空创建**该编号的工作区，与动态策略直接冲突 |
| `config/variables.lua` | `NUM_WPM` 3 → 9 | 它不再决定「有几个桌面」，只决定生成多少个**按位置跳转**的键位。绑满 9 个没代价：位置不存在时按下即空操作 |
| `config/windowrules.lua` | 加企业微信幽灵窗规则 | 见 `docs/09-wine-apps.md`（`initial_title` 而非 `title`，坑 14） |
| `config/misc.lua` | 关掉 Hyprland 内置壁纸与 logo，底色改成壁纸主色 | 见下节「开机时先闪一张陌生壁纸」 |

**pacman 升级把它们覆盖回去了怎么办**：

```bash
cd ~/.config/hypr/config
for f in binds variables workspaces windowrules misc; do
    patch -p0 --forward "$f.lua" < /路径/config/hypr/patches/$f.lua.patch
done
hyprctl reload
```

patch 是拿 `/etc/skel/.config/hypr/config/` 的原版做的基准（已核对一致），
所以升级后只要 skel 那份没大改，patch 就能直接打上。冲突了就手动照上表改五处，都很小。

---

## 开机时先闪一张陌生壁纸

**现象**：每次重启，桌面先出现一张暗色三角碎片的壁纸（`/usr/share/hypr/wall1.png`），
约 1.5 秒后才跳到自己设的那张。

**根因：noctalia 不是「设置」壁纸，是「盖」壁纸。**

这是最反直觉的一点。系统里**没有任何壁纸守护进程**——没有 swww、没有 hyprpaper、
没有 swaybg，`ps` 里只有 noctalia 一个。noctalia 是在 wlr-layer-shell 的 background 层
自己画一张图，底下压着的**始终**是 Hyprland 内置的默认壁纸，从来没有被换掉，只是被遮住。

于是两层的时间差就暴露出来了（实测某次开机）：

```
14:05:06.867  Hyprland 主进程启动   → 立刻画 wall*.png        ← 闪的就是这张
14:05:07.599  noctalia EGL 初始化
14:05:08.279  initServices 耗时 808ms（插件 git fetch 等）
14:05:08.337  [wallpaper] creating on DP-1, path=…/a1-紫调少女.png  ← 才盖上
```

空档长度**是浮动的**，取决于 noctalia 冷启动快慢（同机另一次只花 269ms）。
时间线可以直接从 `~/.cache/noctalia/noctalia.log` 的 `[wallpaper] creating` 行读出来。

同一个根因还有第二个表现：**noctalia 崩溃或重启时，那张内置壁纸会露出来**。
（排查 wine 时用 `pkill -f` 误杀过 noctalia，当时「顶栏和壁纸一起消失」就是这个，见坑 14。）

**解法**——`config/misc.lua`，关掉内置层，把空档改成纯色：

```lua
misc = {
    force_default_wallpaper = 0,      -- 默认 -1 = 从 wall0/1/2.png 里随机一张
    disable_hyprland_logo = true,
    background_color = "rgb(1a1b26)", -- 默认 #111111
}
```

底色取的是**当前壁纸的实际主色**，不是拍脑袋定的：

```bash
magick 壁纸.png -colors 5 -format '%c' histogram:info: | sort -rn | head -1
# 8224430: (26,27,38) #1A1B26   ← 占绝大多数像素
```

同色以后空档期在视觉上基本消失。换壁纸换了色系的话，这个值要跟着重取一遍。

**验证**（`set: true` 才算真生效，`set: false` 是在报默认值）：

```bash
hyprctl reload
for o in misc:force_default_wallpaper misc:disable_hyprland_logo misc:background_color; do
    printf '%-36s' "$o"; hyprctl getoption $o | head -2 | tr '\n' ' '; echo
done
# background_color 回的是十进制 ARGB：4279900966 = 0xFF1A1B26
```

⚠ 两个别走的方向：

- **别去 noctalia 里找「开机壁纸」选项**——它管不到 Hyprland 起来到自己起来之间那段，
  那是合成器的地盘。
- **别装 swww/hyprpaper 来「提前铺好」**——那只会多一个和 noctalia 抢 background 层的
  进程，闪烁变成两次。真正该做的是把底层那张关掉。

---

## 已知的应用层冲突

Wayland 下这些键**应用完全收不到**：

| 键 | 会吃掉 |
|---|---|
| `CTRL+ALT+L` | JetBrains 系 IDE 的**格式化代码** |
| `CTRL+ALT+H` | JetBrains 的调用层次 |
| `ALT+Enter` | JetBrains 的意图操作/快速修复；Wine 游戏、模拟器的全屏切换 |
| `CTRL+1` ~ `CTRL+4` | 浏览器切到第 1~4 个标签页、VS Code 切编辑器分栏 |
| `ALT+Space` | Windows / 传统 GTK 应用的窗口菜单（Wine 里会感觉到） |
| `ALT+W` | 带菜单栏应用的「Window」菜单助记键（影响很小） |

**如果这台机器上要用 IDEA / PyCharm / CLion，前两个基本等于废掉。**
规避：把 `mykeys.lua` 里的 `CONTROL + ALT` 批量换成 `SUPER + ALT`（目前只占了一个 `C` 键）。

## 被摘掉的官方键位

`mykeys.lua` 第 1 节的七个 `hl.unbind`：

- `SUPER+←/→/↑/↓` —— 原方向切焦点，已由 `CTRL+ALT+HJKL` 接管
- `SUPER+S` / `SUPER+SHIFT+S` —— 抽屉，已换成 `ALT+S` / `ALT+SHIFT+S`（抽屉架，见上文。
  官方那两个键指向无名的 `special:special`，本配置已完全不用这个名字）
- `SUPER+Space` —— 启动器，已换成 `ALT+Space`

想留着当备用就把对应 `hl.unbind` 注释掉——但记住 `hl.bind` 是**叠加**不是覆盖，
不 unbind 就是两套键位并存，不是二选一。

## 兼容性前提

- **Hyprland ≥ 0.56 且用 Lua 配置。** `hl.bind` / `hl.dsp.*` 是 0.56+ 的新 API。
  若目标机是传统 `hyprland.conf`（`bind = SUPER, F, fullscreen, 0` 那种），本文件
  一行都跑不了，需整体翻译。`install.sh` 会检查并中止。
- **noctalia**：`ALT+9`（顶栏开合）和 `ALT+Space`（启动器）走 `noctalia msg` IPC。
- **UWSM**：分屏终端用 `uwsm app -- ` 前缀（与官方 `binds.lua` 一致）。

## 不要带到虚拟机之外的东西

如果这套配置曾在 VMware 虚拟机里调过，检查这两处官方文件有没有留下 VM 专用改动
（**本包内没有**，是干净的）：

| 文件 | VM 上常见改动 | 带到真机的后果 |
|---|---|---|
| `config/environment.lua` | `hl.env("LIBGL_ALWAYS_SOFTWARE", "1")` | GPU 加速全废 |
| `config/monitors.lua` | `scale = "auto"` → `"1"` | 高分屏显示成蚂蚁字 |
