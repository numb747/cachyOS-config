# 03 · 终端：kitty / alacritty / zsh / powerlevel10k

对应文件：`config/kitty/`、`config/alacritty/`、`home/.zshrc`、`home/.p10k.zsh`

---

## kitty —— 打开终端直接进 nvim

```conf
font_family                 Adwaita Mono
font_size                   12.5
modify_font                 cell_height 108%
symbol_map U+E0A0-U+E0A3,U+E700-U+E8EF,…  MesloLGS Nerd Font Mono

background_opacity          0.6
cursor_trail                1
window_padding_width        25

shell nvim -c terminal -c startinsert -c 'tnoremap <Esc><Esc> <C-\><C-n>'

include themes/noctalia.conf
```

### 字体：Adwaita Mono + Meslo 补图标

`Adwaita Mono`（`adwaita-fonts` 包，Iosevka 派生）字身窄、字重轻、字怀干净，比 Meslo /
Noto Sans Mono 那种等宽「办公体」清秀，配 tokyonight 的低对比配色更耐看。

代价是**它不带 Nerd Font 图标**，所以要用 `symbol_map` 把私用区码位单独映射给
`MesloLGS Nerd Font Mono`——不然 shell 里 nvim 那个图标全是豆腐块。两个字体包都得装。

字号 12.5 不是随手取的：默认 11pt 偏小，因为 noctalia 的 `ui_scale = 1.20` **只放大了
桌面 UI，kitty 没跟上**（108 DPI，2560×1440 / 27"，scale 1）。按比例该到 13.2，但那样
字太胖，取 12.5 只往上抬一档，剩下的靠 `cell_height 108%` 加行距补——
**优雅靠行距不靠字号**：窄字形 + 宽行距，正文成行更透气，字号还能压得住。

### `shell` 那行是核心

**开终端 = 开 nvim，且光标已经在内置终端里等着打字。**
（旧机 wezterm `default_prog` 的等价物。）三个 `-c` 分别是：

| 参数 | 作用 |
|---|---|
| `-c terminal` | 开内置终端 |
| `-c startinsert` | 直接进插入模式，可以立刻打字 |
| `-c 'tnoremap <Esc><Esc> <C-\><C-n>'` | 双击 Esc 退回普通模式 |

### ⚠️ 必须用单引号

kitty 对 `shell` 的值走 `shlex_split` 再做 `$` 变量展开（`kitty/utils.py` 的
`resolved_shell`）。**单引号内的 `\` 原样保留**；换成双引号就得写成 `<C-\\><C-n>`。
这一条踩过一次，写错了表现为 nvim 启动报映射错误。

### 想开纯 shell 窗口

```bash
kitty zsh        # 命令行给了程序就会覆盖 shell 那一行
```

或者进 nvim 后 `:q` 退出——因为内置终端跑的就是 zsh，`:q` 之后终端窗口还在。

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

**所有外部依赖一律写成「探测存在才启用」**，目录/命令不存在时整段静默跳过。
这样同一份 `.zshrc` 扔到任何机器都不会在每次开 shell 时刷报错。
hacktools 的路径也从硬编码的 `/home/david/` 改成了相对 `$HOME`，换用户名不用回来改。

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
