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

## 常见症状 → 去哪查

| 症状 | 排查方向 |
|---|---|
| 快捷键全无反应 | `hyprctl binds -j \| jq length`；116 = 正常，95 = `require("mykeys")` 没挂上，81 = 连 `binds.lua`/`variables.lua` 都还是 skel 原版（`NUM_WPM` 不同，循环少展开 9 条） |
| `Super+Shift/Alt+R` 没反应、或录完打不开 | 先 `command -v wl-screenrec`（AUR 包，不在 packages.txt 的 pacman 行里）。文件损坏多半是被 `SIGTERM`/`SIGKILL` 杀的——必须 `SIGINT`，见 [05](05-theme-ui.md#录屏--wl-screenrec) |
| 双击图片/视频没反应，或还是用浏览器打开 | `xdg-mime query default image/png`；配置写坏的典型症状是 `mimeapps.list` 里出现一行挤了几十个类型的畸形 key，见 [05](05-theme-ui.md#默认打开方式图片--imv音视频--mpv) |
| `Alt+[` / `Ctrl+1` 跑去切抽屉格了 | 这是**模态**，说明抽屉架正浮着。`Alt+S` 收起即可。见 [02](02-hyprland.md#抽屉架rack第二套工作平面) |
| 窗口丢进抽屉架就找不着了 | `hyprctl clients -j \| jq -r '.[]\|select(.workspace.name\|test("special:rack"))\|"\(.workspace.name) \(.class)"'` 看它在哪一格；`Alt+S` 进去后用 `Alt+]` 翻格 |
| 从终端启动 GUI，终端窗口消失了 | 是 window swallowing，不是进程问题。`nohup`/`&`/`disown` 全都挡不住（判据是进程祖先链）。用 `setsid -f CMD`。见坑 9 |
| 部分键无反应 | 被应用抢了？不可能——Wayland 下是合成器优先。检查是不是自己写的键和官方叠加了（`hl.bind` 是叠加不是覆盖，要先 `hl.unbind`） |
| `ALT+9` / `ALT+Space` 无效 | noctalia 没跑。`pgrep noctalia`；`noctalia msg --help` 能否连上 |
| 顶栏不见了 | 是 `auto_hide = true`，鼠标移到屏幕顶边。或按 `ALT+9` |
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

1. **切桌面时光标闪一下**。已试过 `no_warps`（治好了切窗口的闪）、`follow_mouse = 2`、
   `mouse_refocus = false`。下一步候选，按代价从小到大：
   - `follow_mouse = 1` + `mouse_refocus = false`
     （`mouse_refocus` 疑似只在 `follow_mouse = 1` 下生效，当前可能是空转）
   - `cursor:inactive_timeout = 1`（治标：闪出来后 1 秒自动消失）
   - `follow_mouse = 3`（代价太大：点击也不切键盘焦点，鼠标基本失去意义）
2. **Mason 语言工具链未装齐** —— 见 [04](04-neovim.md#语言工具链mason)。
3. **`mykeys.lua` 第 4 节有一句过时注释**：写着「`NUM_WPM = 3`，默认只有三个工作区」，
   实际已改成纯动态工作区、`NUM_WPM = 9`。只是注释，不影响行为。
4. **rime 词库未打包** —— `~/.local/share/fcitx5/rime/` 属个人数据，换机时单独拷。
