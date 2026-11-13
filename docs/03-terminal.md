# 03 · 终端：kitty / alacritty / zsh / powerlevel10k

> tmux 单独一篇：[14-tmux.md](14-tmux.md)。

对应文件：`config/kitty/`、`config/alacritty/`、`home/.zshrc`、`home/.p10k.zsh`

---

## kitty —— 打开终端直接进 nvim

```conf
font_family                 Adwaita Mono
font_size                   13.5
modify_font                 cell_height 108%
symbol_map U+E0A0-U+E0A3,U+E700-U+E8EF,…  MesloLGS Nerd Font

background_opacity          0.6
dynamic_background_opacity  yes
cursor_trail                1
window_padding_width        25 25 12 25   # 下边 12，见下文「kitty 标签栏」

shell nvim -c terminal -c startinsert -c 'tnoremap <Esc><Esc> <C-\><C-n>'

include themes/noctalia.conf
```

### 字体：Adwaita Mono + Meslo 补图标

`Adwaita Mono`（`adwaita-fonts` 包，Iosevka 派生）字身窄、字重轻、字怀干净，比 Meslo /
Noto Sans Mono 那种等宽「办公体」清秀，配 tokyonight 的低对比配色更耐看。

代价是**它不带 Nerd Font 图标**，所以要用 `symbol_map` 把私用区码位单独映射给
`MesloLGS Nerd Font`——不然 shell 里 nvim 那个图标全是豆腐块。两个字体包都得装。

**用普通版，不用 Mono 版**（2026-09-29 改）。两者正文字形完全一样，只差图标尺寸：
Mono 版把每个图标强制缩进一格宽，`󰲡` 这类「方框套数字」缩完里面的数字基本看不清；
普通版图标本身约 1.5～2 格宽，kitty 遇到「图标后面跟空格」会借用那一格画成两格宽
（kitty 文档 `narrow_symbols` 一节）。lualine、文件树、render-markdown 的图标都是
「图标 + 空格」写法，正好吃到这条规则；图标后紧跟文字时 kitty 退回一格，不会重叠。
`symbol_map` 只接管私用区码位，所以这个改动对正文零影响，只是全局图标变大。

字号 13.5 不是随手取的：默认 11pt 偏小，因为 noctalia 的 `ui_scale = 1.20` **只放大了
桌面 UI，kitty 没跟上**（108 DPI，2560×1440 / 27"，scale 1）。按比例该到 13.2。
最初嫌那样字太胖，只取 12.5 往上抬一档，其余靠 `cell_height 108%` 加行距补。
**2026-09-30 改成 13.5**：实际用下来 12.5 还是偏小。行距那条原则不变——
**优雅靠行距不靠字号**：窄字形 + 宽行距，正文成行更透气。

> 顺带试过**只放大 render-markdown 的标题图标**，结论是做不到、也不做了：
> kitty 不会把 Nerd Font 图标放大到填满行高，图标后面多加空格只会给它更多宽度，
> 高度并不会变。实测 `󰲡` 大约和大写字母一样高。唯一真能放大的办法是用 fontTools
> 自己做一份放大版图标字体，再单独 `symbol_map` 过去，但多养一个自造字体不值得。

### `shell` 那行是核心

**开终端 = 开 nvim，且光标已经在内置终端里等着打字。**
（旧机 wezterm `default_prog` 的等价物。）三个 `-c` 分别是：

| 参数 | 作用 |
|---|---|
| `-c terminal` | 开内置终端 |
| `-c startinsert` | 直接进插入模式，可以立刻打字 |
| `-c 'tnoremap <Esc><Esc> <C-\><C-n>'` | 双击 Esc 退回普通模式 |

### 单下 Esc 有 300ms 延迟 —— 已知、有意保留

映射了 `<Esc><Esc>`，nvim 收到单下 Esc 时分不清还有没有第二下，只能扣留一个
`timeoutlen`（LazyVim 设的 300ms）再放给程序。tmux 复制模式里按 Esc 取消选择时最明显。
tmux 自己的 `escape-time` 是 10ms，跟它无关。同样的 `<Esc><Esc>` 一共有**三份**
（这里、`autocmds.lua` 的 TermOpen、`toggleterm.lua`），buffer 级的也会造成等待，
想改的话三处都要动。

**2026-10-14 试过一版「看前台放行」，当天就撤回了**（`e636ab0` 及其 revert）：
做法是把三份 `<Esc><Esc>` 都换成一个全局的单键 `<Esc>`，按下时读 `/proc/<shell pid>/stat`
的 tpgid（终端前台进程组）：前台是 tmux / nvim 就立刻放行，其余照旧等第二下。
实测延迟确实没了，但**tmux 里双击 Esc 也回不了 nvim 普通模式**，而平时要靠它在 tmux 里
直接回普通模式、切 LazyVim 的 tab，只剩 `Ctrl+\ Ctrl+n` 太别扭。
**这个取舍没有两全的解**：nvim 要想不等，就只能在还不知道有没有第二下的时候先把第一下放出去，
这样第一下 Esc 就会漏给程序。tmux 里如果跑的是正在回答的 Claude，这一下就会把它打断。
所以选择保留延迟、保住双击。别再往「去掉延迟」这个方向试了，除非能接受上面的代价，
或者改用不以 Esc 开头的键来切模式。

### ⚠️ 必须用单引号

kitty 对 `shell` 的值走 `shlex_split` 再做 `$` 变量展开（`kitty/utils.py` 的
`resolved_shell`）。**单引号内的 `\` 原样保留**；换成双引号就得写成 `<C-\\><C-n>`。
这一条踩过一次，写错了表现为 nvim 启动报映射错误。

### 想开纯 shell 窗口

```bash
kitty zsh        # 命令行给了程序就会覆盖 shell 那一行
```

或者进 nvim 后 `:q` 退出——因为内置终端跑的就是 zsh，`:q` 之后终端窗口还在。

想要一个**小的浮动窗口**跑纯 zsh（像桌面挂件，拖到哪算哪）：Walker 里搜「浮动终端」，
见 [02](02-hyprland.md)「浮动终端」。

### 远程控制：开过又撤了（2026-10-15）

为了在当前 kitty 开新标签页跑终端版 Discord（discordo），一度开了
`allow_remote_control socket-only` + `listen_on unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}`。
kitty 标签页和 nvim 的 tab 是**两套**，新标签页整个盖住 nvim，不合用；discordo 后来也整套换成了
Equibop（见 `docs/15-discord.md`），远程控制随之撤掉。以后真要开，记住两点：用 `socket-only` 不用 `yes`
（后者让终端里打印的转义序列就能控制 kitty）；套接字放 `$XDG_RUNTIME_DIR`，别用 `unix:@名字`
（Linux 抽象套接字不受文件权限保护）。

### kitty 标签栏 = 底部药丸 / 页码点（2026-11-13）

kitty 自己有标签（`Ctrl+Shift+T` 开、`Ctrl+Shift+←/→` 或 `Ctrl+Tab` 切、`Ctrl+Shift+Q` 关、
`Ctrl+Shift+Alt+T` 起名），每个标签都跑一份 `shell` 那行，也就是**又一个独立的 nvim**，
和原来那个不共享 buffer。只有一个标签时标签栏不显示，所以平时看不到。

层级从外到内是：kitty 标签 → nvim tab（tabby，顶部）→ tmux 窗口（底部状态栏）→ tmux 窗格（顶部边框标题）。
标签栏用 `tab_bar_style custom` + `config/kitty/tab_bar.py` 自己画，居中贴窗口最底下。
有两种画法，改 `tab_bar.py` 里的 `STYLE` 一行切换：

- `"pill"`（当前）：照 tabby 的圆头药丸 + 序号，当前标签实心，其余不给背景块。
- `"dot"`：手机桌面那种页码点 `● ○ ○`。
- **两种都留着的原因**：药丸单看好看，但底部已有 tmux 窗口列表（同样是「序号 + 药丸」）和 lualine，
  顶部有 tmux 窗格标题和 tabby，kitty 这排长得像标签，就容易被认成又一排 tmux 标签，
  所以中途改成过点；用户想再看看药丸，就两种都保留。觉得认错了就切到 `dot`，改变形状比换位置管用。
- **为什么不显示标题**：每个 kitty 标签跑的都是同一条 nvim 命令，标题全一样。起过名的标签，点后面跟名字。
- **颜色**取 `draw_data` 里的 `active_tab_background` / `inactive_tab_foreground`，来自 noctalia 生成的
  `themes/noctalia.conf`，换壁纸自动跟上。背景用 0（默认色），所以标签栏和窗口一样透明。
- `tab_bar_margin_height 10 0`：外侧不留空的话，标签栏贴着窗口下沿，会被 Hyprland 的圆角裁掉一截。
- `window_padding_width 25 25 12 25`（下边从 25 改成 12）：25 时标签栏离 lualine 41px、离窗口下沿 14px，
  看着像掉在窗框上；12 时是 21/14。只有一个标签时，格子取整剩下的零头会补到四周，lualine 离下沿实测仍有 28px，
  和左右差不多，平时的样子没变。量间距的办法：`grim` 截底边，用 PIL 找 lualine 青色和药丸粉色所在的像素行。
- ⚠ **`tab_bar.py` 只在 kitty 进程启动时读一次**（`load_custom_draw_tab` 带 `@run_once`），改完要开新的 kitty 进程才看得到，
  `Ctrl+Shift+F5` 不够。从别的样式**第一次**切到 `custom` 时例外，因为那时才会第一次去读它。
- 试样式的办法：`kitty --class kt-tabtest --session <文件>`，开一个带三个标签的测试窗口，用 `grim` 截底边。
  关测试窗口时按 `hyprctl clients -j` 里拿到的 pid 去杀，**别用 `pkill -f`**，它会连执行这条命令的 shell 一起杀掉（又踩了一次）。

### 主题从哪来

末行 `include themes/noctalia.conf` 里那个文件是 **noctalia 生成的**，不是手写的。
本包带了一份种子避免首次启动 include 失败，但换壁纸/配色后会被 noctalia 覆盖。
改配色的正确入口见 [05](05-theme-ui.md)。

### 毛玻璃：模糊是 Hyprland 做的，kitty 只负责「变透明」

这是最容易找错地方的一处——**kitty 在 Wayland 下没有任何模糊能力**。分工是：

| 环节 | 谁做 | 在哪 |
|---|---|---|
| 窗口半透明（露出背后） | kitty | `config/kitty/kitty.conf` → `background_opacity 0.6` |
| 把露出来的东西糊掉 | Hyprland | `config/hypr/mykeys.lua` 第 13 节 → `decoration.blur` |
| 不让 Hyprland 抢透明度 | Hyprland | `config/hypr/config/windowrules.lua` 终端类 `opacity = "1.0 override"` |

kitty 输出的是一个带 alpha 通道的 surface，Hyprland 检测到 alpha 之后，对该窗口**背后
的合成结果**跑双 Kawase 模糊。所以把 `background_opacity` 改回 `1`，模糊会**整个消失**
——合成器无处可糊。反过来，光调 Hyprland 的 blur 而 kitty 不透明，也一样什么都看不到。

第三行那条 window rule 解释了另一个现象：Hyprland 全局设了
`active_opacity 0.95 / inactive_opacity 0.85`，但终端类被 `1.0 override` 豁免，透明度
完全交给 kitty 自己的 `0.6` ——**这就是 kitty 聚焦/失焦时不变明暗的原因**。想要终端也跟着
呼吸，删掉 windowrules 里那一行即可（注意它同时管 ghostty / konsole / alacritty 等）。

⚠️ **kitty 的 `background_blur` 选项在这台机器上是死的。** 它要求合成器实现 KDE 的
blur 扩展协议，而 Hyprland 不实现（走自己的 alpha 检测路径）。设了不报错、也不生效，
排查时很容易在这上面绕圈。

**调参入口在 `mykeys.lua` 第 13 节。** 为什么写在那儿而不是官方的 `decorations.lua`，
见 [02 · 关于官方文件被改动](02-hyprland.md#关于官方文件被改动)。

### 参数策略：糊透 + 微压暗（通用，换壁纸不用重调）

```lua
passes     = 4      -- 糊到认不出原图，这是可读性的保证
size       = 8      -- 只决定光晕摊开范围，6~10 差别很小
noise      = 0.025  -- 压深色大面积的色带 + 一点材质感
contrast   = 1.0    -- 保持中性，>1 会把糊剩的边缘重新拉出来
vibrancy   = 0.5    -- ★ 氛围感全靠它，默认 0.17 会把壁纸洗成灰
brightness = 0.90   -- 微压暗，任何壁纸都不会亮到影响读代码
```

核心取舍：**认不出原图 = 永远不会有一块亮东西压在代码上。**
氛围感不靠「透出图案」，靠 `vibrancy` 留住色调——让背景**有色但无形**。
代价是壁纸再好看也只贡献一团光晕，那是通用性换来的。

各值的完整理由写在 `mykeys.lua` 第 13 节逐行注释里。

### ⚠️ 别再试「保留剪影」那条路

2026-08-28 走过一次弯路，记下来免得重来：

嫌官方 `passes = 4` 糊得太死，去调 `passes = 1, size = 13, brightness = 1.1`
（降采样只做一次 + 大半径，让壁纸主体的剪影柔和透出来）。**对着当时那张稀疏的
ASCII art 壁纸确实好看**——人像剪影浮出来但认不出单个字符，很有玻璃压在图上的层次。

然后换成正常插画壁纸（实心、高对比、亮主体），立刻翻车：**一张脸清清楚楚压在文字上**，
亮块直接盖住整段代码。

结论：**保留结构的方案没法通用，只对「95% 是 flat 深底」的稀疏图成立。**
想要一组换壁纸不用管的值，就得糊透。这也是为什么 `contrast` 要保持 `1.0`——
往上调等于把糊剩的边缘重新拉出来，抵消糊透的努力。

顺带一条仍然成立的知识：**Kawase 模糊每加一 pass 就把画面降采样一半**，
`passes = 4` 等于降到 1/16。所以想让模糊「不那么糊」，要减的是 `passes` 不是 `size`
——只是在这套配置里我们**不想**要那个效果。

### 轻糊（43PR 风格）：试过，退回（2026-11-11）

想换个味道，学 [43PR/dotfiles](https://github.com/43PR/dotfiles) 的 `look.lua`
那种「几乎不糊」的效果。上面那条的教训（保留结构只对深底稀疏图成立）这次是**认的**，
所以配套换了壁纸：从壁纸库按「亮度低、去暗部后饱和度低、深色占比高、无亮块」打分，
再从 wallhaven anime 分类（主色黑、≥2560×1440）补了 18 张暗色单色二次元图，
放在 `~/Pictures/Wallpapers/mono-anime/`（不入包）。

**他的配方**拆开看是四件事，透明本身反而是最次要的：

| | 43PR | 本机 |
|---|---|---|
| 透明靠谁 | Hyprland 给所有窗口 `opacity 0.9 override`，全屏 1.0；kitty 不透明 | kitty `background_opacity 0.6`，Hyprland 对终端 `1.0 override` |
| 模糊 | `passes=1, size=5, vibrancy=0.2`，其余默认 | 糊透 |
| 底色 | 纯黑 `#000000` + 白字单色主题 | noctalia 按壁纸生成 |
| 壁纸 | 黑白、大片纯黑 | — |

**过程与结果：**

1. 照搬 `passes=1, size=5` → **重影**：Kawase 只跑 1 pass 时每个像素只从几个离散偏移点取样，
   锐利边缘被复制成几层错开的半透明副本；当时那张网点/抖动风格壁纸还起了棋盘格摩尔纹。
   **43PR 那边看不出来，是因为他窗口 opacity 0.9 只透 10%；本机 kitty 透 40%，缺陷全露出来。**
   只抄模糊参数、不抄透明度，前提就不成立了。
2. `grim` 并排比了 关 / 1·5 / 2·3 / 2·5 / 3·3：**2·3** 是「还认得出轮廓、又没有重影」的最轻一档。
3. 换成 2·3 后仍然**看着眼睛不舒服**，当天退回糊透。问题不在参数，在于**字后面有图案本身就累眼**
   ——这和「糊透 = 认不出原图 = 不会有东西压在代码上」是同一个道理，只是这次是从舒适度而非亮块撞上的。

结论：**本机这套「kitty 透 40%」的前提下，轻糊这条路不舒服，别再试。**
真想要 43PR 那个味道，得连透明度一起抄（kitty 不透明 + 窗口 0.9），那就不是「更透」了，
和当初「提高透明度」的出发点相反。

顺带记两条：
- 动态壁纸（noctalia 5.4.1 不支持视频，要另装 `mpvpaper`）讨论过没上。要上的话注意
  **壁纸一动，模糊每帧都得重算**，糊透（4 pass）在 Radeon 610M 上最贵；`mpvpaper --auto-pause`
  能在被全屏窗口挡住时暂停。
- kitty 加了 `dynamic_background_opacity yes`，留着：`Ctrl+Shift+A` 再按 `L` 更透 / `M` 更实 /
  `D` 回到配置值，只影响当前窗口、不写回配置。⚠ 这个选项**只在 kitty 进程启动时读**，
  在已有进程里 `Ctrl+Shift+N` 开的新窗口也不算，得从启动器/快捷键起一个全新进程。

### 调参方法：截图比对，别靠肉眼记忆

运行时试参数用 `hyprctl eval`（Lua 配置下 `hyprctl keyword` 不可用），`hyprctl reload` 还原：

```bash
hyprctl eval 'hl.config({ decoration = { blur = { size = 20, passes = 2 } } })'
grim /tmp/blur-test.png          # 立刻截一张
hyprctl reload                   # 还原
```

相邻两档的差别很微妙，隔几秒就记不准了，**一定要落盘截图并排看**。
上面那组值就是这么逐版比出来的（跨两张性质相反的壁纸，试了 size 1/6/8/10/12/13/16
× passes 1/2/4 共十轮）。

想量化「背景到底还剩多少色」而不是靠眼睛猜：

```bash
magick /tmp/shot.png -crop 600x400+700+400 -resize 1x1 -format "%[pixel:p{0,0}]" info:
```

取终端空白区一块，缩成 1 像素读均值，和 kitty 主题的 `background`（`#1f2335`）比。
差得太少说明壁纸没透出来，差太多说明会干扰文字。

验证生效一律看 `set: true`——`set: false` 是在报默认值，不是你设的：

```bash
hyprctl getoption decoration:blur:passes   # int: 1 · set: true
hyprctl getoption decoration:blur:xray     # bool: false · set: false ← 没设过
```

### 全屏时毛玻璃是浪费的

窗口铺满整屏时，「玻璃悬浮在壁纸上」的层次感不存在了，模糊只等于给终端加了个色调。
毛玻璃真正好看是在平铺/浮动状态下——`gaps_out` 露出的那圈壁纸和窗口内模糊后的延续
接得上，才有玻璃压在图上的感觉。本机终端常年全屏，所以这部分收益是拿不到的。

---

## alacritty —— 备用终端

保持 CachyOS 默认配置，只有两处个性化：`opacity = 0.8`、导入
`themes/noctalia.toml`（同样是 noctalia 生成的产物）。

留着它是因为**它不会自动进 nvim**——nvim 配置炸了的时候，这是不用记 `kitty zsh`
就能进系统的后路。

---

## zsh —— 基线 + 叠加

```
/usr/share/cachyos-zsh-config/cachyos-config.zsh    ← 发行版基线，不动
~/.zshrc                                            ← 只做叠加
~/.p10k.zsh                                         ← 提示符全在这
```

基线已经提供了 `zsh-syntax-highlighting` / `zsh-autosuggestions` /
`zsh-history-substring-search`，所以**不需要**再引入 oh-my-zsh 的等价插件。

### ⚠️ 绝对不要在 .zshrc 里 source 任何主题

powerlevel10k 在 `precmd` 里重新赋值 `PROMPT`，任何静态赋值都会被冲掉。
`ZSH_THEME=...` + 手动 `source robbyrussell.zsh-theme` 那种写法在这里是无效的——
表现为「配置看着对，提示符就是不变」。主题配置全部走 `~/.p10k.zsh`。

（这正是 [07](07-troubleshooting.md) 坑 2 的内容。）

### .zshrc 的分区

| 段 | 内容 |
|---|---|
| PATH | `~/.local/bin`，以及**探测存在**才加的 `~/.local/share/nvim/mason/bin` |
| 编辑器 | `EDITOR=vim` |
| Android SDK / 逆向工具 | 探测 `~/mywork/tools/env.sh` 存在才 source |
| hacktools | 探测 `$HACKTOOLS`（默认 `~/hacktools`）目录存在才定义别名 |
| AI sandbox | 探测 `docker` 命令存在才定义 |
| 可选工具链 | rvm / zoxide / uv，全部探测后才启用 |
| tmux 窗格状态 | 只在 `$TMUX_PANE` 存在时生效：`preexec`/`precmd` 把正在跑的命令、上一条的退出码/耗时写进 tmux 窗格选项，给 tmux 的 `Alt+a` 总览用（2026-10-13，见 [14](14-tmux.md) 第 9 节） |
| 古诗 | 探测 `fortune` 命令存在才定义 `zfortune`（2026-11-12，见下方「古诗」） |

**所有外部依赖一律写成「探测存在才启用」**，目录/命令不存在时整段静默跳过。
这样同一份 `.zshrc` 扔到任何机器都不会在每次开 shell 时刷报错。
hacktools 的路径也从硬编码的 `/home/david/` 改成了相对 `$HOME`，换用户名不用回来改。

### 古诗（2026-11-12）

敲 `zfortune` 随机读一首（alias，`fortune ~/.local/share/fortune/poems`）。
程序是 pacman 的 `fortune-mod`，诗库取自
[ruanyf/fortunes](https://github.com/ruanyf/fortunes)（作者本人仓库，纯文本，简体）：

| 文件 | 内容 | 条数 |
|---|---|---|
| `tang300` | 唐诗三百首 | 313 |
| `song100` | **宋诗**一百首（不是宋词） | 101 |

同仓库的 `chinese`（2 万多条格言）**故意没放进来**，会把诗淹掉。

诗库**不入包**，换机器重新拉：

```bash
git clone --depth 1 https://github.com/ruanyf/fortunes.git /tmp/ruanyf-fortunes
mkdir -p ~/.local/share/fortune/poems
cp /tmp/ruanyf-fortunes/data/{tang300,song100} ~/.local/share/fortune/poems/
cd ~/.local/share/fortune/poems && strfile tang300 && strfile song100
```

用户**只要手动敲命令随机读**：开终端自动弹诗、回想测验、搜索、收藏这些
当天做过又撤掉了，嫌冗余，别再加回来。

颜色码是数据文件自带的（题目绿、作者黄），跟着终端配色走。

### p10k

`~/.p10k.zsh` 是 `/usr/share/zsh-theme-powerlevel10k/config/p10k-robbyrussell.zsh`
的**逐字节副本**（已核对 `diff` 无差异）。所以：

- 想换风格：从同目录换一个（`p10k-lean.zsh` / `p10k-classic.zsh` / `p10k-pure.zsh`
  / `p10k-rainbow.zsh` / `p10k-lean-8colors.zsh`）复制过来即可
- 想细调：`p10k configure` 走向导，它会重写这个文件
- 图标依赖 `ttf-meslo-nerd`，缺字体表现为一堆豆腐块

#### ⚠️ 这个文件是 load-bearing 的，删了不会回退到 robbyrussell

基线第 101 行是**条件加载**（`[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh`），文件不在
就整行跳过，环境里一个 `POWERLEVEL9K_*` 都没有 → 走向导 / 裸默认。
**p10k 没有「回退到某个预设」的行为。** 判据和完整分析见 [07](07-troubleshooting.md) 坑 1。

这里只补一条那边没写的：这个坑不只发生在「新机器没装」，也发生在**文件后来被删掉**。
2026-08-26 就踩过一次，症状是提示符变成谁也没见过的样子，当时误判成「shell 配置被改坏了」。
先跑 `./sync.sh` 看一眼——它会直接报 `! 系统上不存在：~/.p10k.zsh`，比猜快得多。

#### 为什么不直接用 oh-my-zsh 原版 robbyrussell

卡在基线的加载顺序上：

```
行  10   export ZSH="/usr/share/oh-my-zsh"
行  28   source $ZSH/oh-my-zsh.sh              ← oh-my-zsh 在这里加载主题
行  88   source .../powerlevel10k.zsh-theme    ← p10k 在后面，接管 PROMPT
行 101   [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
```

行 88 无条件执行，p10k 在 `precmd` 里每次重绘都重新赋值 `PROMPT`，行 28 设的静态
`PROMPT` 必然被冲掉。要真用原版就得删基线的行 88——那是发行版文件，`pacman -Syu
cachyos-zsh-config` 会覆盖回来，每次升级重打。**为了一个外观完全一样的结果去和发行版
对着干，不划算。**

顺带：基线**没有设 `ZSH_THEME`**（`grep -c '^ZSH_THEME'` = 0，运行时也是空），所以行 28
的 oh-my-zsh 根本没加载任何主题。不存在「先加载再被冲掉」的重复劳动。

#### 开销实测（2026-08-26）

| | 耗时 |
|---|---|
| 空 `zsh -f` 基准 | 0.7 ms |
| `+ source ~/.p10k.zsh` | 1.1 ms（**净 +0.4 ms**） |
| `+ source oh-my-zsh.sh` | 24.3 ms（净 +23.5 ms） |
| `zsh -f -i`（完全不读 rc） | 1 ms |
| `zsh -i`（基线 + `.zshrc` + p10k 全套） | **140 ms** |

**这个配置文件本身是 0.4 ms，可以当零**——5 KB 纯变量赋值。没有它反而更慢（多一段
`_p9k_can_configure` 判断）。140 ms 是发行版选 p10k 这个决定的代价，与本配置无关。

常驻开销：p10k 给**每个交互式 shell 单独 fork 一个 `gitstatusd`**，各约 5.2 MB RSS，
随父 shell 退出而退出（不泄漏）。开 4 个终端 ≈ 21 MB。

这是取舍不是浪费：oh-my-zsh 原版 `git_prompt_info` 是每画一次提示符 fork 一次 `git`，
大仓库里会卡；p10k 用常驻 daemon + 异步渲染换掉这个延迟，**拿内存换每次回车的手感**。
另有 `~/.cache/p10k-instant-prompt-$USER.zsh`（14 KB）先用缓存画提示符、后台再补真实
内容，所以那 140 ms 感觉不到。

### 登录 shell

```bash
chsh -s "$(command -v zsh)"     # 然后重新登录
getent passwd "$USER"           # 末段应是 /bin/zsh 或 /usr/bin/zsh
```

`install.sh` 会检查并提示，但**不会**替你改——改登录 shell 要密码，属于该由你亲手做的事。

---

## 三个终端相关的环境变量

在 `~/.config/uwsm/env`（会话级，登录时读一次）：

```sh
export TERM=xterm-kitty
export QT_QPA_PLATFORM="wayland;xcb"
export QT_QPA_PLATFORMTHEME="qt6ct"
```

改了要**注销重进**才生效，`source` 一下是不够的——它是给整个会话（含 Hyprland
自己拉起的进程）用的。

---

## Dolphin 里「打开终端」用 Konsole（只改 Dolphin）

全局默认终端是 kitty（`~/.config/kdeglobals` 的 `[General] TerminalApplication=kitty`），
但 kitty 一打开就进 nvim，在 Dolphin 里按 Shift+F4「在此打开终端」时不顺手，所以 Dolphin 单独用 Konsole。

KIO 的 `KTerminalLauncherJob` 读的是 `KSharedConfig::openConfig()`，也就是**应用自己的配置
叠在 kdeglobals 上面**，所以同名键写进 `dolphinrc` 就只覆盖 Dolphin：

```sh
kwriteconfig6 --file dolphinrc --group General --key TerminalApplication konsole
kwriteconfig6 --file dolphinrc --group General --key TerminalService org.kde.konsole.desktop
```

- `TerminalService` 优先于 `TerminalApplication`，两个都写，免得以后 kdeglobals 里冒出一个 `TerminalService` 把它盖掉。
- **别改 kdeglobals**：那是 noctalia 模板生成的产物，手改会被覆盖；而且它对所有 KDE 程序生效。
- Dolphin 启动时读一次配置，改完要**完全退出 Dolphin 再开**才生效。
- F4 的内嵌终端面板本来就是 Konsole 组件（konsolepart），跟这个设置无关。
- `dolphinrc` 没进 `manifest.map`：里面大半是 Dolphin 运行时写的视图状态，入包只会天天漂移。新机器上跑一遍上面两条命令即可。

### 面板里的字被撑开、像全角字符

Konsole 没有自己的 profile 时用「系统等宽字体」，这个值由 qt6ct 给；`qt6ct.conf` 没设字体，
等宽字体就落到了 **Noto Sans**（比例字体，`fixedPitch: False`，`i` 4px、`W` 15px）。
Konsole 按最宽的字母给每格定宽，窄字母两边全是空，看着像全角。

修法只动 Konsole，不碰 qt6ct 的全局字体：`~/.local/share/konsole/david.profile`
（已入包，term 模块）把字体钉成 Adwaita Mono 12，再让 konsolerc 默认用它：

```sh
kwriteconfig6 --file konsolerc --group 'Desktop Entry' --key DefaultProfile david.profile
```

内嵌面板（konsolepart）也读 konsolerc 的 DefaultProfile，所以同样要**重启 Dolphin** 才生效。
查 Qt 实际拿到哪个字体：PySide6 里 `QFontInfo(QFontDatabase.systemFont(QFontDatabase.FixedFont))`。
