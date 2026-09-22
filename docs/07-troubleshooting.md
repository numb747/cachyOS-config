# 07 · 踩坑与排错

这里全是**这套配置实际踩过并定位到根因**的坑，不是通用 FAQ。
每条都给了判据（怎么确认是这个问题），而不只是「试试这个」。

---

## 坑 1 — p10k 配置向导每次开 shell 都弹

**现象**

```
Does this look like a diamond (rotated square)?
Choice [ynq]:
```

**根因**

`cachyos-config.zsh` 无条件 source powerlevel10k。而 p10k 决定要不要弹向导的判据在
`/usr/share/zsh-theme-powerlevel10k/internal/p10k.zsh` 的 `_p9k_precmd_impl` 里：

```zsh
if [[ -z "${parameters[(I)POWERLEVEL9K_*~POWERLEVEL9K_(MODE|CONFIG_FILE|GITSTATUS_DIR)]}" ]]; then
    # → 弹向导
```

**关键洞察**：官方文档里的 `POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true`
**根本没有任何地方读它的值**。全树 grep 这个变量名，只在 README 和 `wizard.zsh` 的提示
文案里出现。它之所以「有效」，纯粹是因为「定义了一个 `POWERLEVEL9K_` 开头的变量」这个
事实本身让上面那个 `-z` 判断为假——写 `=false` 一样能关掉向导。

**修法**：不用那个开关，直接装一份真配置（含 20 个 `POWERLEVEL9K_*` 变量），顺手把坑 2
也解决了：

```bash
cp /usr/share/zsh-theme-powerlevel10k/config/p10k-robbyrussell.zsh ~/.p10k.zsh
```

`cachyos-config.zsh` 里的 `[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh` 会自动读它。

**这个坑会二次发作**：本包已纳管 `~/.p10k.zsh`，但文件被误删后症状一模一样，而且因为
「明明装过」容易误判成别的原因。诊断一步到位——`./sync.sh` 会直接报
`! 系统上不存在：~/.p10k.zsh`；修复用 `./install.sh term`（幂等，同模块其余 5 个文件
判定「已是最新，跳过」，只写这一个），别手 `cp`，那样 MANIFEST 校验对不上。
2026-08-26 实际发生过一次。

**为什么难复现**：向导挂在 precmd 上，`zsh -i -c 'cmd'` 跑完就退出，压根到不了第一个
提示符。必须真交互式 zsh + 真 pty，见文末「验证方法」。

---

## 坑 2 — 主题配置写了没用，提示符还是 p10k 样式

**现象**：`.zshrc` 里明明写了 `ZSH_THEME="robbyrussell"` 并手动 source 了主题文件，
`echo $ZSH_THEME` 也确实是 `robbyrussell`，渲染出来却是 powerline 风格。

**根因**：p10k 不是「设一次 `PROMPT` 就完事」，它在 **precmd 里重新赋值 `PROMPT`**。
`.zshrc` 里的静态赋值第一次渲染就被冲掉了。

**一次误诊**：查 `precmd_functions` 没看到 p9k 钩子，差点得出「p10k 没在跑」的错误结论。
实际是过滤用的正则 `^[a-z_]+$` 匹配不到含数字的 `_p9k_precmd`。

**决定性判据**——直接打印运行时的 `PROMPT` 本体：

```zsh
print -rn -- ${(V)PROMPT}                 # 输出里全是 _p9k_on_expand / _p9k__1 / _p9k_t[...]
print -l ${(k)functions} | grep -c p9k    # → 277
```

**修法**：顺着 p10k 走，别跟它对抗。主题配置全部放 `~/.p10k.zsh`，
把 `.zshrc` 里手动 source 主题的那几行**删掉**。副作用是好的：白拿 p10k 的异步
gitstatus 和 instant prompt。

> ⚠️ 别改回手动 source 主题的写法——会重新踩进这个坑。

---

## 坑 3 — `echo $SHELL` 显示的不是 zsh，`chsh` 说 "Shell not changed"

三件事全是误解：

### 3a. `chsh: Shell not changed.` 是**成功**信息

本机 `chsh` 来自 **util-linux**（`pacman -Qo /usr/bin/chsh` 可查），
`login-utils/chsh.c`：

```c
if (!nullshell && strcmp(oldshell, info.shell) == 0)
    errx(EXIT_SUCCESS, _("Shell not changed."));
```

`oldshell` 取自 passwd，且 **PAM 认证排在这个比较之前**。所以「先要密码 → 然后说
not changed」的完整含义是：认证通过了，一看你要设的就是当前值，无事可做。退出码
`EXIT_SUCCESS`。

### 3b. `$SHELL` 不能用来判断「我现在在哪个 shell」

它是**登录那一刻的快照**，greetd 只在登录时读一次 passwd：

```rust
format!("SHELL={}", user.shell.to_string_lossy()),
```

之后 `chsh` 改了 passwd，已经跑着的会话里那份环境变量仍然活着，并被所有子进程继承。

**正确判别**：

```bash
ps -p $$ -o comm=     # 当前进程真名，最可靠
echo $ZSH_VERSION     # 非空 = zsh
echo $SHELL           # ← 不能用来判断当前 shell
```

**不重登也想修正会话内的过期变量**：

```bash
systemctl --user set-environment SHELL=/usr/bin/zsh
dbus-update-activation-environment --systemd SHELL
```

（已在跑的 Hyprland 进程自身的 environ 改不了，下次登录自然消失。）

### 3c. 提示符字符能直接区分

| shell | 提示符 |
|---|---|
| zsh（robbyrussell 风格） | **`➜`** U+279C |
| fish（CachyOS 默认） | `❯` U+276F |

### 排除掉的社区传言

论坛常见说法是「CachyOS 在 bashrc 里 `exec fish`，所以 chsh 白改」。**本机不成立**，
逐项核过：`~/.bashrc` / `~/.bash_profile` / `/etc/profile` / `/etc/profile.d/*` /
`/etc/skel/*` 均无 `exec fish`；`cachyos-hello` / `cachyos-settings` 无 `chsh` /
`usermod -s` 调用；`/etc/shells` 含 zsh。

---

## 坑 4 — kitty `shell` 选项的引号

kitty 对 `shell` 的值走 `shlex_split` 再做 `$` 变量展开（`kitty/utils.py` 的
`resolved_shell`）：

```python
ans = list(map(expand, shlex_split(q)))
```

| 写法 | 结果 |
|---|---|
| `'tnoremap <Esc><Esc> <C-\><C-n>'` | ✅ 单引号内 `\` 原样保留 |
| `"tnoremap <Esc><Esc> <C-\\><C-n>"` | ⚠️ 双引号必须写两个反斜杠 |

**用单引号。** 值里若含 `$` 会被展开，也要注意。

验证解析结果：

```bash
kitty +runpy '
from kitty.config import load_config
from kitty.utils import resolved_shell
import os
print(resolved_shell(load_config(os.path.expanduser("~/.config/kitty/kitty.conf"))))'
```

---

## 坑 5 — toggleterm 取 `vim.o.shell` 的时机

`toggleterm.lua` 里 `opts = { shell = vim.o.shell }` 的值在**插件 spec 构造那一刻**
就被取走了。kitty 传的 `-c "set shell=..."` 要等 spec 构造**之后**才执行——那样
toggleterm 读到的是旧的 `$SHELL`。

**所以必须设在 `lua/config/options.lua`**（它在 lazy.nvim 启动前加载）：

```lua
vim.opt.shell = vim.fn.executable("zsh") == 1 and vim.fn.exepath("zsh") or vim.o.shell
```

一处设置，三处受益：`:terminal`、toggleterm（`Ctrl+/`）、`:!cmd` / `vim.fn.system`。

---

## 坑 6 — 只拷 noctalia 的 config.toml，配色不对

主题的真实来源是 `~/.local/state/noctalia/settings.toml`，不是
`~/.config/noctalia/config.toml`。两边的 `[theme]` 段重叠时前者生效。

**判据**：

```bash
noctalia config export full | grep -A6 '^\[theme'
```

打印出来的才是活配置。本机是 `source = "community"` +
`community_palette = "Tokyo Night Moon"`，而 `config.toml` 里写的是
`source = "wallpaper"`——那行已经不生效了。

细节见 [05](05-theme-ui.md#-配置分裂在两个文件里)。

---

## 坑 7 — Qt 应用配色不生效

`qt6ct.conf` 里发行版 skel 写的是**字面量** `$USER`：

```ini
color_scheme_path=/home/$USER/.config/qt6ct/colors/noctalia.conf
```

qt6ct 不做变量展开，这是个死路径。`install.sh` 会自动替换成真实 `$HOME`；手动改也行。

---

## 坑 8 — `hyprctl dispatch` 在 Lua 配置下**语法变了**（不是失效）

想手工验一条 dispatcher，照 Hyprland 传统文档敲：

```console
$ hyprctl dispatch movetoworkspacesilent "special:probe,address:0x5597..."
error: [string "return hl.dispatch(movetoworkspacesilent spec..."]:1: ')' expected near 'special'

 → Note: dispatch in lua is a shorthand for hl.dispatch(...), your syntax might need to be updated.
```

**参数被当成 Lua 代码解析了。** 报的是语法错误，很容易误以为是自己参数写错、引号没转义。

> **2026-08-27 更正**：早先这里写的是「这条路整个走不通」，**不对**。`dispatch` 没失效，
> 它只是变成了 `hl.dispatch(<你传的东西>)` 的简写——**传 Lua 表达式就能用**：
>
> ```bash
> hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'   # → ok，进程真的起来了
> ```
>
> 报错信息末尾那句 `your syntax might need to be updated` 已经把话说明白了。
> 分工：**`dispatch` 用来「执行一个动作」**（它只跑 dispatcher，写法短）；
> **`eval` 用来「调试和取值」**（能跑任意 Lua）。用 `dispatch` 在会话里拉起 GUI 进程
> 尤其顺手——由 Hyprland 来 exec，环境变量天然正确，比在别的终端里手动导
> `WAYLAND_DISPLAY` 可靠。

要跑任意 Lua（而不只是一条 dispatcher）时用 `hyprctl eval`：

```bash
hyprctl eval 'hl.dispatch(hl.dsp.window.move({ workspace = "special:probe", window = hl.get_window("address:0x5597...") }))'
```

⚠ `hyprctl eval` **拿不到返回值，也没有 `print`**。要看结果只能自己写文件：

```bash
hyprctl eval 'local f=io.open("/tmp/r","w") f:write(tostring(某表达式)) f:close()'; cat /tmp/r
```

另外 `hyprctl eval` 是**另一个 chunk**，够不到 `mykeys.lua` 里的 `local`。所以抽屉架
引擎在文件末尾挂了一个全局 `RACK` 专供验收（`hyprctl eval 'RACK.toggle_plane()'`）——
否则只能照抄逻辑去 eval，验的就是副本不是本体了。详见
[02](02-hyprland.md#调试出口-rack)。

### 附带：这类 Lua API「静默失效」的通病

`hl.dsp.*` 对**不认识的参数键直接忽略，不报错、不警告**。已知踩过的：

| 写法 | 实际发生 |
|---|---|
| `toggle_special({ name = "rack2" })` | 静默退回默认的 `special:special` |
| `window.move({ …, silent = true })` | `silent` 被忽略，那一格照样弹出来（正确的是 `follow = false`） |

stub `/usr/share/hypr/stubs/hl.meta.lua` 里这些全写成 `fun(...)`，**没有类型信息可查**。
遇到「代码看着对但行为不对」，先怀疑参数名，用 `hyprctl eval` 挨个试。

---

## 坑 9 — 从终端启动 GUI，终端窗口自己消失了（`nohup` / `&` 都挡不住）

**现象**

在 Alacritty 里跑 `java -jar app.jar`，GUI 弹出来的同时**终端窗口不见了**；关掉 GUI，
终端又原样回来。加 `nohup ... &` 毫无区别。

**判据**（两条都成立就是这个坑，不用再往下查）

```bash
hyprctl -j getoption misc:enable_swallow   # → "bool": true
hyprctl -j getoption misc:swallow_regex    # → 字符串里含你正在用的终端 class
```

**根因**

Hyprland 的 **window swallowing**。`config/hypr/config/misc.lua`（官方默认值，本配置沿用未改）：

```lua
misc = {
    enable_swallow = true,
    swallow_regex  = "(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)",
},
```

新窗口 map 时，Hyprland 取它的 PID 沿 PPID 链往上走，若某个**祖先进程**拥有一个 class
命中 `swallow_regex` 的窗口，就把那个终端窗口 unmap（**是隐藏不是关闭**），等新窗口
消失再放回来。设计意图是「终端只是启动器，别占着屏幕」。

**为什么 `nohup` 和 `&` 没用**——这是本坑最容易走弯路的地方：判据是**进程祖先链**，
与作业控制无关。`nohup` 只改 SIGHUP 处置，`&` 只改前后台，**两者都不改变父子进程关系**，
`java` 仍是那个 shell 的亲儿子，链完好，照吞不误。同理 `disown`、`</dev/null` 也都无效。

**修法：不改配置，单次绕过 —— 断开祖先链**

```bash
setsid -f java -jar app.jar >/dev/null 2>&1
```

`-f` 强制 fork，中间进程立刻退出，GUI 被 reparent 到 `systemd --user`，链断。
`-f` 不能省：`setsid` 只在自己是进程组长时才 fork，写脚本里（无作业控制）会不 fork，
链就还在。

⚠ **命令尾部的 `>/dev/null 2>&1 </dev/null &` 与断链无关，别当成必要条件**（2026-09-16）。
`&` 只改前后台、`</dev/null` 只改 stdin 指向，两者都不动父子关系 —— 和上面 `nohup`/`disown`
失效是同一个理由，见「为什么没用」那段。加上它们不会坏事，但少了它们也照样不被吞。
从**交互式 zsh** 里调（有作业控制）时，`setsid -f` 会立刻 fork 并立刻返回，提示符马上
回来，`&` 纯属多余；真正需要重定向的场合是 stdout 还想留着的脚本调用，那时用
`>/dev/null 2>&1 </dev/null` 防住后台进程写终端。

**Hyprland 并非「必然吞」**，两条永久路线都在这份配置里可及：

| 想做到 | 改哪 | 代价 |
|---|---|---|
| 某个应用永久豁免 | `misc.swallow_exception_regex`（匹配**被启动窗口的 title**） | 只对这个应用生效，其余照吞 |
| 整个功能关掉 | `misc.enable_swallow = false` | 全局改变行为，本配置刻意保持官方默认 |

⚠ 别自己改 `config/hypr/config/misc.lua` —— 那是 5 个 CachyOS 官方文件之一，动了就要多
维护一个 patch（见 [CLAUDE.md](../CLAUDE.md) 坑 4）。要改走 `mykeys.lua` 的 `hl.config`。

**候选方案实测**（2026-08-27，从 `/tmp` 下调用，shell pid 73965）：

| 方法 | 结果 PPID | cwd | 能否躲开 swallow |
|---|---|---|---|
| `setsid -f CMD` | 1383 = `systemd --user` | **保留调用者的 cwd** | ✅ 推荐 |
| `hyprctl dispatch 'hl.dsp.exec_cmd("CMD")'` | 1462 = `Hyprland` | 变成 `~`，**相对路径会失效** | ✅ 但要写绝对路径，且 Lua 引号嵌套烦（见坑 8） |
| `uwsm app -- CMD` | 73965 = **调用的那个 shell** | 保留 | ❌ **无效** |
| `systemd-run --user --scope CMD` | 73965 = **调用的那个 shell** | 保留 | ❌ **无效** |

⚠ 后两条容易想当然地以为有效。`uwsm app` 默认用的就是 `--scope`，而 **scope 单元是把
调用者的子进程「移进」cgroup，不改变父子关系**——PPID 仍是 shell，祖先链原封不动。
只有 service 单元（由 `systemd --user` 亲自 fork）才断链。

**如果哪天想永久豁免某个应用**（本次没做，配置保持原样）：`misc.swallow_exception_regex`。
注意两个字段语义不对称——`swallow_regex` 匹配**终端的 class**，
`swallow_exception_regex` 匹配**被启动窗口的 title**，不是 class。

---

## 坑 10 — noctalia 面板（剪贴板/启动器）打开不到 1 秒自己消失

**现象**

按 `SUPER+V`，剪贴板面板弹出来，还没看清就没了。反复按、面板反复闪。
**键盘焦点其实是好的**——按完立刻敲字母，字确实进了搜索框，然后连面板带字一起消失。

**⚠️ 根因没查清。** 下面全是实测记录，不是结论。读这条的时候请带着这个前提。

**先做的事：把指针挪进面板矩形，看还关不关**

```bash
# hl.dsp.cursor.move 只收 table，写成 (x, y) 会报 expected a table { x, y }
hyprctl dispatch 'hl.dsp.cursor.move({x = 1280, y = 720})'
```

犯病时这一下就能让面板常驻，是最快的验证入口，也正是 `bin/noct-panel` 的全部内容。

**实测记录（2026-09-22，同一个 noctalia 进程 PID 290934，全程没重启）**

| 时段 | 指针在面板矩形外 | 指针在矩形内 |
|---|---|---|
| 16:47 | **0.78~0.98 秒自关，6/6** | **常驻，6/6** |
| 17:21–17:29 日志回看 | 1.4~49 秒，无规律 | — |
| 17:40 后专门跑的 15 组矩阵（内/外 × 指针动/不动） | **全部活过 6 秒，15/15** | 同 |

用户手工复核过 16:47 那一组：鼠标放屏幕正中按 `SUPER+V` → 面板常驻、搜索可用；
甩到角落再按 → 约 1 秒消失；敲字进得去 → 键盘焦点没问题。

**所以能说的只有这些**

- 犯病时，「指针在不在面板矩形内」是决定性变量，这一条复现得很干净。
- 但它**只在某个状态下成立**。那个状态什么时候进、什么时候出，都不知道；
  这次它在没有任何人为动作的情况下自己消失了（中间唯一可疑的操作是装第 18 节
  键位时跑过一次 `hyprctl reload`，Hyprland 日志太短没留住时间戳，没能证实）。
- 因此**不能**说「这不是故障、是上游的既有行为」。上游
  `noctalia-dev/noctalia#2204` 确实在讨论面板自关，但那条不足以解释
  「同一进程前后两小时行为相反」。`settings.schema.*` 里确实没有关掉它的开关。

**曾经写在这里的两条错误结论**（都是拿时间相关性当因果，留着当反面教材）

- ~~「launcher 历史中位就是 1.0 秒，说明它一直这样」~~ —— 过度解读。
  「打开就敲字回车」本来也就 1 秒，同一份数据两种解释都成立，不构成证据。
- ~~「重启 noctalia 不能修，别白折腾」~~ —— 没有证据。当时「重启没修好」的那几次，
  指针恰好在矩形外；后来不犯病的那两小时也**没有**重启过。重启修不修得好，未知。

**解法**：`bin/noct-panel` + `mykeys.lua` 第 18 节，`SUPER+V` 改调它。
它不判断当前是不是坏状态——**坏状态下是解药，好状态下只是多挪一次指针**，无条件挪。

脚本三件事：开面板 → 从 `hyprctl layers` 读**面板实际几何**把指针移到中心 →
面板关掉后把指针**放回原处**（用户中途自己动过鼠标就不还原）。
几何是读出来的不是算出来的，所以 placement 改 attach/float、换分辨率、多显示器
都自动跟上。还原那一步不是礼貌，是维持第 6b 节那个「指针底下永远是焦点窗口」的
不变量——不还原的话，下一次真实鼠标微动会把焦点拽到面板原来所在的窗口上，
症状是「从剪贴板选了条目，`Ctrl+V` 却粘进了别的应用」。

**写这个脚本时量到的两个 noctalia 行为**（2026-09-23，都不是文档里写着的）

- **所有面板复用同一个 layer surface**。control-center 开着时按 `SUPER+V`，
  日志明明有 `opened "clipboard"`，`hyprctl layers` 里那个 `noctalia-panel` 的
  **address 一个字都没变**。所以「按 address 做前后差集找新面板」不成立——
  差集是空的，正好漏掉这个场景。判据要用「toggle 尘埃落定后还有没有面板」。
- **关闭有约 236ms 的动画**，期间 layer 还在（开只要约 43ms）。不等它就会把指针
  挪进一个正在消失的面板。

**⚠ 排除掉的方向**（2026-09-22 全部做过前后对照。注意这些是「不是**唯一**原因」，
在犯病状态下没有一个能单独解释症状，但不等于整条线索作废）

| 怀疑过的 | 实测结论 |
|---|---|
| 跑过 OCR 打坏的 | 不是。前后两次测试之间指针位置变了，把时间巧合当成了因果 |
| `config-reload` / 装包触发的 icon theme change → bar/dock reload | 不是。把 `system icon theme changed → [bar] reloading config → [dock] reloading config` 整条日志序列复现了一遍，面板照常 |
| 顶栏显示/隐藏态 | 不是。两种状态各测 5 次，都是 ~0.91 秒 |
| 键盘/快捷键路径、slurp 独占键盘 | 不是。绕开键盘直接 `noctalia msg panel-open clipboard` 同样复现 |
| 焦点被别的窗口抢走 | 不是。Hyprland 事件流（`.socket2.sock`）在 `openlayer` → `closelayer` 之间没有任何焦点/窗口事件 |

**诊断入口**：`~/.cache/noctalia/noctalia.log` 有 `[panel] panel manager: opened/closing "<id>"`，
两者时间差就是面板存活时长。⚠ 日志**不记录关闭原因**，只能靠对照实验定位。
做对照实验时**把指针位置当成一等变量记录下来**——它会在你没注意时被改（比如你正
在跟人说话），当噪音处理会让所有前后对照全部失效，本次就是这么错了两轮。

**⚠ 顺带三个重启 noctalia 时才会踩到的坑**（本次排查中实际踩了）：

- 从 **Hyprland 进程**的 `environ` 抄环境去启动 noctalia 会得到
  `fatal: failed to connect to Wayland display`——Hyprland 自己就是合成器，
  它的环境里**没有** `WAYLAND_DISPLAY`。正确做法是 CLAUDE.md 坑 8 那条：
  `hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'`，由 Hyprland 拉起，环境天然正确。
- 手动拉起的实例**顶栏不会自动隐藏**——隐藏逻辑是 `mykeys.lua` 第 9 节的
  `hl.on("hyprland.start")` 发 `bar-hide`，手动启动不触发该事件，要补一条
  `noctalia msg bar-hide`。
- 偶尔会起出「半残」实例：壁纸和顶栏画得出来、DBus 名字也注册了，但主循环卡在
  网络等待（`WCHAN=skb_wait_for_more_packets`，启动阶段要访问 `api.noctalia.dev` 等），
  症状是 `noctalia msg` 返回空、`notify-send` 超时。判据是**日志停止增长**，
  `kill -9` 重来即可。

---

## 常见症状 → 去哪查

| 症状 | 排查方向 |
|---|---|
| 快捷键全无反应 | `hyprctl binds -j \| jq length` 看总数（2026-09-16 实测 **124**，这个数会随加键位变，以 CLAUDE.md「现状」段为准）；**95 = `require("mykeys")` 没挂上**（自定义那部分全丢），**81 = 连 `binds.lua`/`variables.lua` 都还是 skel 原版**（`NUM_WPM` 不同，循环少展开 9 条）。后两个才是判据，别拿总数硬比 |
| `Super+Shift/Alt+R` 没反应、或录完打不开 | 先 `command -v wl-screenrec`（AUR 包，不在 packages.txt 的 pacman 行里）。文件损坏多半是被 `SIGTERM`/`SIGKILL` 杀的——必须 `SIGINT`，见 [05](05-theme-ui.md#录屏--wl-screenrec) |
| 双击图片/视频没反应，或还是用浏览器打开 | `xdg-mime query default image/png`；配置写坏的典型症状是 `mimeapps.list` 里出现一行挤了几十个类型的畸形 key，见 [05](05-theme-ui.md#默认打开方式图片--imv音视频--mpv) |
| `Alt+[` / `Ctrl+1` 跑去切抽屉格了 | 这是**模态**，说明抽屉架正浮着。`Alt+S` 收起即可。见 [02](02-hyprland.md#抽屉架rack第二套工作平面) |
| 窗口丢进抽屉架就找不着了 | `hyprctl clients -j \| jq -r '.[]\|select(.workspace.name\|test("special:rack"))\|"\(.workspace.name) \(.class)"'` 看它在哪一格；`Alt+S` 进去后用 `Alt+]` 翻格 |
| 从终端启动 GUI，终端窗口消失了 | 是 window swallowing，不是进程问题。`nohup`/`&`/`disown` 全都挡不住（判据是进程祖先链）。用 `setsid -f CMD`。见坑 9 |
| 部分键无反应 | 被应用抢了？不可能——Wayland 下是合成器优先。检查是不是自己写的键和官方叠加了（`hl.bind` 是叠加不是覆盖，要先 `hl.unbind`） |
| `ALT+9` / `ALT+Space` 无效 | noctalia 没跑。`pgrep noctalia`；`noctalia msg --help` 能否连上 |
| 顶栏不见了 | 是 `auto_hide = true`，鼠标移到屏幕顶边。或按 `ALT+9` |
| `SUPER+V` 的面板一闪就没（启动器同理） | 已由 `bin/noct-panel` 兜住（接在 `SUPER+V` 上）。手工验证：把指针挪进面板矩形，犯病时面板立刻常驻。⚠ 根因**没查清**，别信「这是上游既有行为、重启没用」那套旧说法，见坑 10 |
| `SUPER+V` 的剪贴板历史一重启就空 | 看日志有没有 `[secret-store] ... provider-unavailable`：没有 Secret Service 时它拒绝落盘、只留内存。解法是 `[storage]` 文件密钥，见 [05](05-theme-ui.md#剪贴板supervsuper-的历史靠-storage-文件密钥才能活过重启)。⚠ 改完**必须重启 noctalia 进程**，`config-reload` 不重新初始化存储 |
| 换壁纸/换主题每次都要输密码 | `greeter_sync` 在推给登录界面。noctalia 默认用 `run0` 提权，绕开了自带的 polkit policy——**看 journalctl 里真正被拒的 action id**（是 `systemd1.manage-units` 不是 `apply-appearance`）。要 `privilege_command = "pkexec"` + `/etc/polkit-1/rules.d/` 规则两步，见 [05](05-theme-ui.md#greeter-同步换壁纸主题为什么每次都要输密码) |
| 提示符全是豆腐块 | 缺 `ttf-meslo-nerd` |
| 提示符变成没见过的样子 / 弹配置向导 | `~/.p10k.zsh` 没了。`./sync.sh` 一眼看出，`./install.sh term` 修。见坑 1 |
| 终端打开不进 nvim | `kitty.conf` 的 `shell` 那行；或者是从 alacritty 开的（它本来就不进） |
| nvim 一堆红色 stack trace | 多半是 LSP 的 glob 问题，`mini.lua` 里有绕行补丁；或 Mason 缺运行时，见 [04](04-neovim.md#语言工具链mason) |
| Mason 一片红叉 | 缺 node/go/php/java 等运行时，不是配置问题。见 [04](04-neovim.md#语言工具链mason) |
| 每开 shell 刷一堆报错 | `.zshrc` 里有无条件的 `eval`/`source`。本包的写法全是探测存在才执行，被改过了才会这样 |
| 光标样式不对 | Bibata 没装，回退到 Adwaita，属正常。`yay -S bibata-cursor-theme` |
| 壁纸没上屏 | `settings.toml` 里显示器名写死为 `DP-1`，新机不同。在 noctalia 里重选一次壁纸 |
| 升级后快捷键行为变了 | pacman 覆盖了 `config/*.lua`。用 `config/hypr/patches/*.patch` 重打，见 [02](02-hyprland.md#关于官方文件被改动) |

---

## 验证方法（本次反复用到的三招）

### 1. 用真 pty 测交互式 shell

很多问题（p10k 向导、precmd 覆盖 PROMPT）**只在真终端里发生**。
`zsh -i -c 'cmd'` 跑完即退，到不了第一个提示符，复现不出来。

```bash
# 无 tty 会误报的假象：can't change option: zle / gitstatus failed to initialize
zsh -i -c 'echo hi'

# 正确：script 分配真 pty，且用真交互式 zsh（不带 -c）
printf 'exit\n' | script -qec "zsh -i" /dev/null
```

### 2. 对照实验确认根因

不要只验证「修好了」，要同时验证「不修就会坏」：

```bash
mkdir -p /tmp/zt-no /tmp/zt-yes      # 两份只差一行的 .zshrc
printf 'exit\n' | script -qec "ZDOTDIR=/tmp/zt-no  zsh -i" /dev/null | grep -c diamond   # 应 > 0
printf 'exit\n' | script -qec "ZDOTDIR=/tmp/zt-yes zsh -i" /dev/null | grep -c diamond   # 应 = 0
```

### 3. 检测终端里跑的到底是什么进程

```bash
nvim -c terminal -c 'lua vim.defer_fn(function()
  local pid = vim.b.terminal_job_pid
  print(io.open("/proc/"..pid.."/comm"):read("*l"))   -- → zsh
end, 3000)'
```

注意喂给 pty 的 stdin 若立刻 EOF，shell 会秒退、探测到 `nil`。
用 `sleep 20 | script ...` 把 stdin 撑住。

---

## 回滚

```bash
./uninstall.sh              # 交互确认后把所有文件回滚到最近一次 .bak-*
./uninstall.sh --list-baks  # 先看看有哪些备份
```

单项回滚：

| 目标 | 操作 |
|---|---|
| 只退 Hyprland 快捷键 | 删 `~/.config/hypr/mykeys.lua` 并从 `hyprland.lua` 摘掉 `require("mykeys")` |
| 官方 hypr 文件还原 | `cp /etc/skel/.config/hypr/config/*.lua ~/.config/hypr/config/` |
| 提示符换回 p10k 默认 | `rm ~/.p10k.zsh && p10k configure` |
| kitty 不再自动进 nvim | 删掉 `kitty.conf` 里 `shell nvim ...` 那一行 |
| 登录 shell | `chsh -s /bin/bash`（或别的） |

---

## 遗留 / 可继续调

1. **Mason 语言工具链未装齐** —— 见 [04](04-neovim.md#语言工具链mason)。
2. **`mykeys.lua` 第 4 节有一句过时注释**：写着「`NUM_WPM = 3`，默认只有三个工作区」，
   实际已改成纯动态工作区、`NUM_WPM = 9`。只是注释，不影响行为。
3. **rime 词库未打包** —— `~/.local/share/fcitx5/rime/` 属个人数据，换机时单独拷。

### 已结案

- **切桌面/切窗口时光标闪一下 + 切完窗口一两秒焦点自己跳回原窗口** —— 两个症状，
  一个根因。修法是**全部删掉**、回到 Hyprland 默认，只留 `hide_on_key_press = true`。

  完整机制见 [02](02-hyprland.md#鼠标行为第-6--6b-节)。要点是：当初为了「不闪」而
  上的 `no_warps = true` 把指针和焦点拆开了，反而造出了焦点被抢的洞；为了堵这个洞
  再上的 `follow_mouse = 2` 又锁死了 warp 的开关，绕成死循环。默认配置里根本没有
  这个洞——「切焦点时指针跟着 warp」正是让指针底下永远是焦点窗口、因而抢不走焦点的
  那个机制。闪烁是它的代价，接受即可。

  作废的候选方案（不要再试）：`follow_mouse = 1`、`inactive_timeout`、
  `follow_mouse = 3`、`follow_mouse_threshold`。前三个是在给一个错误的因果判断
  打补丁；最后一个更隐蔽——它和 `mouse_refocus`、`follow_mouse_shrink` 一样，
  读取点都在 `FOLLOWMOUSE == 1` 的分支里，在 `follow_mouse = 2` 下是空转配置。
