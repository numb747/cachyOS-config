# 14 · tmux：温习、3.x 新东西、遥控 Claude Code、Agent Teams 分屏

> 配置文件只有一个 `~/.tmux.conf`（包内 `home/.tmux.conf`，**term 模块**）。
> 这一篇一半是温习老功能，一半是 3.6–3.8 新加的东西。第 5 节是「用 tmux 给 Claude Code
> 打字、回车、等它答完、读答案」，第 7 节是「一个队长 claude 指挥几个队员 claude、
> 每个队员一个 tmux 窗格」。这两节的结论**全部实测过**（2026-10-11，tmux 3.8 +
> Claude Code 2.1.296）。

---

## 0 · 本机现状

- **tmux 3.8**（2026-10-10 随 `pacman -Syu` 升上来的）。
- 终端链是 **kitty → nvim `:terminal` → zsh → tmux**（kitty 的 `shell` 直接起 nvim，见
  [03](03-terminal.md#kitty--打开终端直接进-nvim)）。所以 tmux 的「外层终端」其实是 nvim，
  `tmux list-clients -F '#{client_termtype}'` 报的是 `libvterm(0.3)` —— 那就是 nvim 的终端库。
- 前缀键没改，还是 `C-b`。下文 `前缀 x` 都指「先按 `C-b` 松开，再按 `x`」。

### 「复制不出来」是怎么回事（2026-10-11）

升到 3.8 之后在 tmux 里选多行，按 `v` 开始选、按 `y` 复制，什么都没进剪贴板。两个原因叠在一起：

1. **没有配置文件，tmux 自己猜成了 vi 键位** —— 它看 `$EDITOR`/`$VISUAL` 里有没有 `vi`，
   本机 `EDITOR=vim`，于是 `mode-keys vi`。
2. **vi 键位的默认绑定和 vim 习惯不一样**：`v` 是**切换块选择**（不是开始选择），
   **`y` 根本没绑定**。开始选择是 `空格`，复制是 `Enter`。

剪贴板那条路本身是通的：`set-clipboard external`（默认）发 OSC52 → nvim 的终端转给 kitty →
Wayland 剪贴板，`tmux load-buffer -w` 实测能进 `wl-paste`。现在的配置额外加了
`copy-command 'wl-copy'`，复制时**同时**用 wl-copy 直接写，不依赖 nvim 那一层转发。

---

## 1 · 三层结构：session / window / pane

| 层 | 类比 | 常用键 |
|---|---|---|
| **session**（会话） | 一个工作区，可以脱离终端独立活着 | `前缀 d` 脱离 · `tmux a` 接回 · `前缀 s` 列表 · `前缀 $` 改名 |
| **window**（窗口） | 浏览器的 tab，底栏一格一个 | `前缀 c` 新建 · `前缀 n/p` 下/上一个 · `前缀 0-9` 直达 · `前缀 ,` 改名 · `前缀 &` 关 |
| **pane**（窗格） | tab 里切出来的分屏 | `前缀 %` 左右分 · `前缀 "` 上下分 · `前缀 方向键` 切 · `前缀 x` 关 · `前缀 z` 放大/还原 |

session 能脱离终端活着，这是 tmux 最根本的用处：关掉 kitty、断了 ssh，里面的程序照跑，
`tmux a` 回来一切原样。**长任务（编译、下载、Claude 跑大活）放进 tmux 就不怕手滑关窗口。**

### 找 tab、找东西

| 想做什么 | 键 |
|---|---|
| 树状浏览所有会话/窗口/窗格（带预览，可直接跳） | `前缀 w`（窗口视角）· `前缀 s`（会话视角） |
| 按名字/内容找窗口 | `前缀 f`，输入关键字 —— 会搜窗口名、标题，**也搜窗格里的文字** |
| 3.8 新：快速切换器 | `前缀 Tab`（窗口）· `前缀 Shift-Tab`（会话），底部弹一个浮动窗格选 |
| 显示窗格编号再按号跳 | `前缀 q` |
| 上一个窗口（来回切） | `前缀 l` |

在 `前缀 w` / `前缀 s` 的树里：`x` 关掉选中项、`t` 标记多个再批量操作、`/` 搜索、`Enter` 跳过去。

### 窗格的整理

| 键 | 干什么 |
|---|---|
| `前缀 空格` | 轮换预设布局（平铺、主窗格+侧栏…） |
| `前缀 { / }` | 和上/下一个窗格换位置 |
| `前缀 !` | 把当前窗格拆出去成为独立窗口 |
| `前缀 Ctrl+方向键` | 调大小（也可以直接用鼠标拖边框） |
| `前缀 T` | 3.8 新：给窗格起标题 |
| `:join-pane -s 2` | 把 2 号窗口并进来成为一个窗格（`!` 的反操作） |
| `:setw synchronize-panes on` | **同一窗口所有窗格同步输入**，一次给几台机器敲同样的命令 |

---

## 2 · 鼠标（3.8 起默认就开）

3.8 把 `mouse` 的默认值改成了 `on`，配置里写一遍只是为了换旧版本也一致。现在鼠标能干的：

| 动作 | 效果 |
|---|---|
| 点窗格 / 点底栏窗口名 | 切过去 |
| 拖窗格边框 | 调大小 |
| 滚轮 | 进复制模式往上翻历史（全屏程序如 nvim/less 里则交给程序自己） |
| 左键拖选 | 选中，**松开即复制并退出复制模式** —— 高亮瞬间消失是正常的，内容已经进剪贴板 |
| 右键窗格 | 窗格菜单：复制当前词/行、搜索、拆分、交换、放大、浮动… |
| 右键底栏 | 窗口菜单：交换、改名、关闭、新建 |
| **Ctrl + 拖** | 3.8 新：**画一个浮动窗格**（见下节） |
| **Alt + 拖** | 3.8 新：移动窗格 |
| 滚轮在底栏上 | 切换窗口 |

⚠ 外层终端（kitty）自己的选择被 tmux 抢了。kitty 里一般按住 `Shift` 拖可以绕过程序的鼠标捕获，
但本机中间还隔着一层 nvim，效果不稳定，而且分屏时会把相邻窗格的内容和边框一起选上。
**统一用 tmux 自己的复制**（下节）最省事。

---

## 3 · 复制粘贴

### 键盘（能跨屏、能翻历史）

```
前缀 [        进复制模式
  移动         h j k l / w b / Ctrl-u Ctrl-d / g G / 搜索 / ? n N
  v           开始选择（本配置改的；默认是 空格）
  V           整行选择
  Ctrl-v      切换块（矩形）选择（本配置改的；默认是 v）
  y           复制并退出（本配置加的；默认是 Enter，Enter 也还能用）
  q           不复制直接退出
前缀 ]        粘贴最近一次复制
前缀 =        从历史里挑一段粘贴（tmux 保存了每次复制的 buffer）
```

复制的东西同时进三个地方：tmux 自己的 buffer（`前缀 =` 能看到历史）、OSC52、`wl-copy`。
所以在 tmux 外面（浏览器、微信）直接 `Ctrl-v` 就有。

3.7 起复制模式可以显示**行号**：`:set copy-mode-line-numbers relative`，
跟 nvim 的相对行号一个意思，`10j` 这种跳法就不用数了。

### ⚠ 别在 tmux 里连按两下 Esc

kitty 起 nvim 时带了 `tnoremap <Esc><Esc> <C-\><C-n>`（[03](03-terminal.md)），
**两下 Esc 会被外层 nvim 吃掉**，切进 nvim 的普通模式，tmux 根本收不到。
复制模式里取消选择按**一下** `Esc` 就行；按多了发现「终端不动了」，按 `i` 回到 nvim 的终端模式。
同理，单独一下 `Esc` 也会被 nvim 扣留一个 `timeoutlen` 才放行（它在等第二下），有一点延迟是正常的。

---

## 4 · 3.6–3.8 的新东西（挑有意思的）

以下命令和键位都在本机 3.8 上用 `tmux list-commands` / `list-keys` 核对过存在；
具体行为以 `man tmux` 为准。

### 浮动窗格（3.7 引入，3.8 补全）

这是这几版最大的变化：窗格不再只能「切」，还能**浮在上面**，像 Hyprland 的浮动窗口。

| 怎么来 | |
|---|---|
| `前缀 *` | 新建一个浮动窗格 |
| **Ctrl + 鼠标拖** | 拖多大就多大 |
| `前缀 >` 窗格菜单 → Float | 把现有的平铺窗格浮起来（Tile 是放回去） |
| `前缀 g` 进入 move 键表 | 然后 `1-4` 贴到四角、方向键贴到四边、`0` 铺满、`Alt+1-4` 缩成四分之一贴角 |
| Alt + 鼠标拖 | 挪位置 |

命令行版：`tmux new-pane -x 80 -y 20 'btop'`。适合临时看一眼的东西 ——
`btop`、`lazygit`、一个计算器 —— 不打乱已有的分屏布局。

**模态窗格**（`new-pane -O`）：一个窗口只能有一个，`-C` 点外面就关、`-D` 按 Esc/Ctrl-c 就关、
`-K` 把**所有**按键（包括前缀）都给它。拿来做「弹出式」工具很合适：

```tmux
# 前缀 G：弹一个 lazygit，退出即关
bind G new-pane -O -D -x 90% -y 85% -c "#{pane_current_path}" lazygit
```

（上面这行**没有**写进本包的配置，想要自己加。）

### popup（3.2 就有，3.6/3.7 修了一堆）

和浮动窗格看着像，区别是 **popup 不是窗格**：不能分屏、不能留着、关了就没了。

```bash
tmux display-popup -E -w 80% -h 80% 'htop'      # -E：命令退出时自动关
tmux display-popup -E -d '#{pane_current_path}' 'zsh'   # 临时开个 shell，用完 exit
```

### 其他

| 功能 | 怎么用 |
|---|---|
| 内置亮/暗主题 | `theme` 选项，默认 `detect`（跟终端走）；想要老配色 `set -g theme terminal` |
| 滚动条 | `set -g pane-scrollbars on`（3.8 起会自动隐藏，`pane-scrollbars-timeout` 控制） |
| 鼠标悬停即聚焦 | `set -g focus-follows-mouse on` |
| 拖已有选区调整它 | 3.8 起复制模式里直接拖选区边缘 |
| 选择进行中不会因为滚到底而退出复制模式 | 3.8 修的，以前很烦 |
| 历史行带时间戳 | `capture-pane -I`：每行进入历史的时间 |
| 进度条 | 程序发 OSC 9;4，tmux 可以转发给外层终端 |

### 事件与钩子（3.8 重写过）

3.8 把钩子建在了内部事件上，能做的事一下多了很多：

- **`wait-for` 可以等事件**：`wait-for -E` 阻塞到某个钩子/事件发生。
- **格式监视器** `set-hook -B`：每秒求值一个格式，**变了**（或配 `-T` 时**为真**）就跑钩子。
  比如「某窗格屏幕上出现了 xxx 就提醒我」不用再写 while 循环。
- **OSC 133**：shell 如果发 OSC 133 标记（命令开始/结束/提示符），tmux 会触发
  `pane-command-started` / `pane-command-finished` / `pane-shell-prompt` 钩子 ——
  「长命令跑完弹个通知」可以直接挂在这上面。⚠ 本机 zsh + p10k **默认不发** OSC 133，
  要用得先在 `.zshrc` 里开（还没做）。

老的监视选项照样好用，不依赖这些新东西：

```tmux
setw monitor-activity on     # 这个窗口有新输出 → 底栏标记
setw monitor-silence 30      # 这个窗口 30 秒没动静 → 底栏标记（「编译跑完了」）
```

---

## 5 · 拿 tmux 遥控 Claude Code

> 想要的是「一个大脑 claude 指挥几个小 claude」？那用 Claude Code 内置的 Agent Teams，
> 见第 7 节，不用自己拿下面这些命令搭。这一节适合「让脚本/别的程序遥控 claude」。

思路很直接：Claude Code 是个终端程序，tmux 能往任意窗格里**打字**（`send-keys`）、能**读屏幕**
（`capture-pane`）、能**等信号**（`wait-for`）。三样凑齐就是一个遥控器。

和 [08](08-claude-code.md) 的 `ccp` 代答是同一个思路换了通道：`ccp` 走 **nvim RPC `chansend`**
把按键送进 nvim 的 terminal buffer；在 tmux 里跑的 claude，用 `tmux send-keys` 就够了，
不用找 socket。08 第 4 节那张**选择题按键序列表和「逐键发、间隔 ~0.2s」的结论照样适用**。

### 实测过的配方（2026-10-11 · tmux 3.8 · Claude Code 2.1.296 · haiku）

```bash
# 1. 起一个后台会话跑 claude（-x/-y 给个尺寸，否则后台会话是 80×24）
tmux new -d -s cc -x 160 -y 50 -c ~/some/project claude

# 2. 发一句话，停一下，再单独发回车
tmux send -t cc -l '帮我看看 README 有没有错别字'
sleep 1; tmux send -t cc Enter

# 3. 读屏幕（-S - 从历史最开头抓，-J 把折行拼回去）
tmux capture-pane -p -J -S - -t cc | tail -40
```

**多行消息**：走 buffer + 括号粘贴，Claude 的输入框会把它当成一次粘贴，换行不会触发提交：

```bash
printf '第一行\n第二行\n第三行' | tmux load-buffer -b msg -
tmux paste-buffer -p -d -b msg -t cc      # -p 括号粘贴，-d 用完删掉这个 buffer
tmux send -t cc Enter                     # 单独再发一个回车提交
```

> 实测 `send-keys -l $'a\nb'`（字面量带换行）也**没有**提前提交 —— Claude 把快速连续的输入
> 当成了粘贴。但这是靠时序碰巧对的，多行一律走 `paste-buffer -p` 才稳。
>
> ⚠ **文字和回车要分开发**（2026-10-11 更正）。第一次实测 `tmux send -t cc '文字' Enter`
> 一条命令能提交，同一天再测就不行了：回车紧跟在文字后面，被 Claude 当成粘贴的一部分，
> 变成了**换行**，消息停在输入框里。`-l` 发文字、`sleep 1`、再单独发 `Enter` 才稳。
> 刚关掉信任框或者刚弹过提示框时更容易出这个问题。

**等它答完**：别去屏幕上找「忙碌」的字样（见下面的坑），用 Claude Code 自己的 **Stop 钩子**发信号：

```json
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "tmux wait-for -S cc-done" }
] } ] } }
```

把上面存成一个文件，`claude --settings 那个文件` 启动（不用动全局 settings.json），然后：

```bash
tmux send -t cc -l '跑一下测试'; sleep 1; tmux send -t cc Enter
tmux wait-for cc-done          # 阻塞到 Claude 这一轮说完
tmux capture-pane -p -J -S -30 -t cc
```

实测发出到 `wait-for` 返回 7 秒，正好是那一轮的耗时。
多个会话就用不同的信号名（比如 `cc-done-$TMUX_PANE`，钩子进程继承了 claude 的环境，能拿到这个变量）。

**其他按键**：

| 想做什么 | 发什么 | 实测 |
|---|---|---|
| 打断正在进行的回答 | `Escape` | ✓ 刚发出就打断的话，**那条消息会被退回输入框**，没有提交记录 |
| 清空输入框 | `C-u`（会提示 `Ctrl+Y` 找回）或 `C-c` | ✓ |
| 切权限模式 | `BTab`（Shift+Tab） | 底栏写着 `shift+tab to cycle` |

### 几个坑

- **新目录会先弹「是否信任此文件夹」**，光标默认在 `No, exit` 上。要么先手动进一次，
  要么发 `Down` 再 `Enter`。⚠ 这个框**认数字键且按下即提交**（08 里记过），别乱发数字。
  **家目录不会被记住信任**，每次在 `~` 下起都会问。
- **别靠读屏判断忙/闲。** 忙碌时那一行是 `✶ Choreographing…` 这种**随机动词 + 转圈符号**，
  每次都不一样，也没有固定的 `esc to interrupt` 字样（老版本有，现在没了）。
  判断「说完了」用上面的 Stop 钩子；非要读屏，就看输入框那行 `❯ ` 后面是不是空的、上方有没有
  `✻ … for Ns · done` 这种收尾行，但这些都是 UI 细节，**Claude Code 升级就可能变**。
- 后台会话默认 80×24，Claude 的回答会折成很多短行，`capture-pane` 时加 `-J`，起会话时给 `-x -y`。
- 历史行数默认只有 2000，本配置调到了 50000，长回答才抓得全。

### 能拼出来的玩法

- **排队**：写个循环，从一个文件里一行一行取任务，`send` → `wait-for` → `capture-pane` 存档 → 下一条。
- **监工**：另开一个窗格跑 `ccw`（08 的看板），或者用 3.8 的 `set-hook -B` 监视 claude 窗格，
  出现权限提示框时底栏标红。
- **多开对比**：同一个问题 `send` 给三个窗格里不同模型/不同目录的 claude，`setw synchronize-panes on`
  也行，最后 `capture-pane` 并排比。
- **pipe-pane 录像**：`tmux pipe-pane -o -t cc 'cat >> ~/cc.log'`，窗格的全部输出持续写进文件
  （带转义序列，看的时候 `less -R`）。

---

## 6 · 其他零碎但好用的

```bash
tmux new -s 名字                     # 起一个有名字的会话
tmux a -t 名字                       # 接回指定会话
tmux ls                              # 列会话
tmux kill-session -t 名字
tmux capture-pane -p -S - > out.txt  # 把当前窗格全部历史存成文件
tmux source ~/.tmux.conf             # 改完配置不用重启
tmux list-keys | less                # 所有键位（含 3.8 新加的）
```

- `前缀 :` 进命令行，所有 `tmux xxx` 命令都能在这里直接敲（去掉 `tmux` 前缀）。
- `前缀 ?` 列出所有键位；3.7 起各模式里 `C-h` 是该模式的帮助。
- `前缀 Ctrl-z` 挂起客户端（回到外层 shell），`fg` 回来。
- 分屏想继承当前目录：`bind '"' split-window -c "#{pane_current_path}"`（以及 `%`），本配置**没加**。

---

## 7 · Agent Teams：一个队长 claude + 几个队员 claude，每人一个 tmux 窗格

需求是：只跟一个「大脑」claude 说话，由它分派给开发、review、查文档几个小 claude；
哪个小 claude 不对劲，能直接在 tmux 里点进去看、插话。这正是 Claude Code 内置的
**Agent Teams**（实验功能）加上它的 **tmux 分屏显示**，不用自己拿第 5 节那些命令搭。

### 和第 5 节自己搭的区别

| | 内置 Agent Teams（用这个） | 第 5 节自己用 tmux 命令搭 |
|---|---|---|
| 谁创建、管理队员 | Claude Code 自己 | 自己写的 `send-keys` / `wait-for` |
| 队员之间怎么通信 | 内置信箱 + 共享任务列表 | 没有，只能读屏 |
| 结果怎么回到队长 | 队员做完自动带着结果通知队长 | 读屏，很脆 |
| 权限提示 | 汇总到队长那里批 | 卡在各自窗格里没人批 |

tmux 在这里只当**显示器**：`teammateMode` 设成 `auto` 之后，Claude Code 自己调 tmux 给每个队员切窗格。

### 本机怎么开的（cc 模块）

- `~/.claude/settings.json` 合并了三样（`install.sh cc` 的 `cc_teams` 做，只加键、不碰 token）：
  `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"`、`teammateMode = "auto"`、团队日志的 4 个钩子。
- 三个角色定义在 `~/.claude/agents/`（包内 `claude/agents/`）：

  | 角色 | 模型 | 工具 | 干什么 |
  |---|---|---|---|
  | `developer` | 跟队长 | 全部 | 写代码、跑测试 |
  | `reviewer` | sonnet | 只读 + Bash（看 diff、跑测试）+ 消息/任务 | 审查，只审不改 |
  | `docs-reader` | sonnet | 只读 + WebFetch/WebSearch + 消息/任务 | 查项目文档和官方文档，给出处 |

用的时候：**先开 tmux，在 tmux 里启动 `claude`**，然后跟它说：

> 建一个 agent team：developer 类型的队员叫 dev，reviewer 类型的叫 rev，docs-reader 类型的叫 doc。
> 任务是……dev 写完让 rev 审，有疑问问 doc。

### 队长必须在 tmux 里启动吗

- **`auto`（本机设置）**：在 tmux 里启动 → 分屏；不在 tmux 里 → 退回「不分屏」模式
  （所有队员在队长终端里，用面板上下键切换着看）。**要分屏就得在 tmux 里启动。**
- **`tmux`（强制）**：不在 tmux 里也会分屏 —— 实测它**另起一个独立的 tmux 服务器**
  （socket 是 `/tmp/tmux-$UID/claude-swarm-<队长 pid>`，会话名 `claude-swarm`），队员都在那里面。
  要看得另开一个终端 `tmux -L claude-swarm-<pid> attach`，队长退出时那个服务器一起关。
  能用，但不如直接在 tmux 里启动顺手。

### 怎么看队员在干什么

| 想看什么 | 怎么看 |
|---|---|
| 某个队员的完整过程 | 它的窗格：收到的消息（`ctrl+o` 展开）、调的工具、回答，全在里面 |
| 跟某个队员直接说话 | 点进它的窗格打字，不经过队长（实测有效） |
| 谁在忙、忙了多久 | 队长窗格底部的面板：`● main` / `◯ dev  任务名  1m 3s` |
| 屏幕太挤 | `前缀 z` 放大当前窗格；`前缀 w` 树状列表带预览；窗格标题就是任务名 |
| **队员之间说了什么** | **团队日志**（下面），队长看不到这部分 |

### 团队日志：队员之间的对话队长看不到

队员 A 直接发给队员 B 的消息**只出现在 A、B 两个人的窗格里**，队长只收到发给它的消息和
队员做完时的汇报；信箱文件（`~/.claude/teams/<团队>/inboxes/`）会话结束就删。所以挂了钩子，
每条消息、每次空闲、每个任务建立/完成都记一行到 `~/.claude/team-logs/<日期>.jsonl`：

```bash
~/.claude/team-log.sh        # 今天的日志，人读格式
~/.claude/team-log.sh -f     # 跟随 —— 开个 tmux 窗格放着，就是一个「团队频道」
~/.claude/team-log.sh -r     # 原始 JSON
```

实测长这样（两个 haiku 队员，doc 读 README 给 rev，rev 审 calc.py）：

```
13:20:53  ✉ doc → rev  这个项目是一个极简演示程序：输入两个数字，输出它们的和（README.md:2…
13:21:15  ✉ rev → doc  审查结论：有阻塞问题。calc.py:2 的 add 写成了 a - b，和需求相反 ⏎ - 阻塞 …
13:21:37  ✉ rev → team-lead  审查结论：有阻塞问题。calc.py:2 的 add 实现为 a - b …
13:21:43  ⏸ rev 空闲
```

钩子字段文档没写全，实测（2.1.296）：队员发的 `SendMessage` 带 `agent_type`（角色名）但**没有队员名**，
发送方要从 `tool_response.routing.sender` 取；队长发的没有 `agent_type`；`TeammateIdle` 带
`teammate_name` / `team_name`。所以脚本把 stdin **原样**存下、只加时间戳，显示时再挑字段。
⚠ 钩子调用带 `--hook` 参数，不靠「stdin 是不是终端」判断 —— 从脚本里手动查看时 stdin 也不是终端，
第一版就这么误判过（手动查看被当成了钩子调用，什么都不显示）。
⚠ 钩子脚本**永远 exit 0**：`TeammateIdle` / `TaskCompleted` 的 exit 2 意思是「不许停 / 不许完成」，
日志写失败绝不能变成卡住队员。

### 实测踩到的

- **队长的地址是 `team-lead`**，不是 `lead`。队员按自己的理解发给 `lead` 会被退回
  （`Not sent — no agent named 'lead' is reachable`），它会自己改，但白跑一轮。已写进三个角色定义。
- **队员之间会互相客套**（「收到」「好的，我等 rev 的结论」），每条消息都让对方再跑一轮、花一份钱。
  角色定义里加了「不发纯确认消息」。
- ⚠ 官方文档说：开启团队功能后，Claude 平时委派工作时**给 subagent 起了名字，那个 subagent 也会变成队员**，
  也就是没要团队也可能冒出团队。嫌这样就把 settings.json 里的开关改成 `"0"`（改完立即生效，不用重启）。没实测。
- 小模型当队长时**不一定会建任务列表**（`~/.claude/tasks/<团队>/` 是空的），但不影响消息和汇报。
- 中途可能弹提示框（这次是 auto mode 计费说明）卡住队长，要按回车。有人看着的时候无所谓，无人值守时注意。
- 关掉 tmux 会话后，队长和队员进程过一两秒自己退出，没有留下孤儿进程。
  ⚠ 查残留进程别用 `pgrep -f` 加 `kill` —— 模式会匹配到执行它的那个 shell 自己（退出码 144，
  和 `CLAUDE.md` 坑 14 一模一样，这次又踩了一次）。用 `pgrep -x 2.1.296` / `pgrep -x claude`
  再读 `/proc/<pid>/cmdline` 确认。

### 两种显示方式怎么选

`auto` 已经替你选好了，这里记一下差别，免得以后疑惑：

| | 不分屏（in-process） | tmux 分屏 |
|---|---|---|
| 看队员 | 面板里上下键选、回车看，一次一个 | 同时看所有人，点进去直接打字 |
| 环境 | 任何终端 | 要 tmux |
| 角色定义的正文 | **追加**在默认系统提示后面 | **替换**默认系统提示 —— 所以本包的三份写得比较完整 |
| `disallowedTools` | 生效 | **不生效** —— 所以本包限制权限一律用 `tools` 白名单 |
| 队员进程 | 在队长进程里，队长退出全没 | 各自独立进程 |

---

## 改配置

照 [CLAUDE.md](../CLAUDE.md) 的姿势：改 `~/.tmux.conf`，`tmux source ~/.tmux.conf` 验证，
再收回 `home/.tmux.conf`。它在 **term 模块**，和 `kitty.conf` / `.zshrc` 一起装；
笔记本上 `install.sh term` 是禁止操作（[11](11-multi-machine.md)），但这个文件两台机器没有差异，
单独 `cp` 就行。
