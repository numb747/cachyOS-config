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

**用单引号。** 值里若含 `$` 会被展开，也要注意。写错了表现为 nvim 启动报映射错误。

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

`vim.opt.shell` 必须设在 `lua/config/options.lua`（lazy.nvim 启动前加载），设晚了 toggleterm 在 spec 构造时就取走了旧的 `$SHELL`。
原理与写法见 [04](04-neovim.md#内置终端为什么用-zsh-而不是-shell)。

---

## 坑 6 — 只拷 noctalia 的 config.toml，配色不对

主题真实来源是 `~/.local/state/noctalia/settings.toml`（`[theme]` 段重叠时它生效），活配置一律看
`noctalia config export full`。见 [05](05-theme-ui.md#-配置分裂在两个文件里)。

---

## 坑 7 — Qt 应用配色不生效

`qt6ct.conf` 里 skel 写的是字面量 `$USER`，qt6ct 不展开、是死路径；`install.sh` 会自动替换。
见 [05](05-theme-ui.md#qt6ctconf-里的-user-陷阱)。

---

## 坑 8 — `hyprctl dispatch` 在 Lua 配置下**语法变了**（不是失效）

想手工验一条 dispatcher，照 Hyprland 传统文档敲：

```console
$ hyprctl dispatch movetoworkspacesilent "special:probe,address:0x5597..."
error: [string "return hl.dispatch(movetoworkspacesilent spec..."]:1: ')' expected near 'special'

 → Note: dispatch in lua is a shorthand for hl.dispatch(...), your syntax might need to be updated.
```

**参数被当成 Lua 代码解析了。** 报的是语法错误，很容易误以为是自己参数写错、引号没转义。

`dispatch` 没失效，它只是变成了 `hl.dispatch(<你传的东西>)` 的简写——**传 Lua 表达式就能用**（报错末尾那句
`your syntax might need to be updated` 说的就是这个）：

```bash
hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'   # → ok，进程真的起来了
```

分工：**`dispatch` 用来「执行一个动作」**（只跑 dispatcher，写法短）；**`eval` 用来「调试和取值」**（能跑任意 Lua）：

```bash
hyprctl eval 'hl.dispatch(hl.dsp.window.move({ workspace = "special:probe", window = hl.get_window("address:0x5597...") }))'
```

用 `dispatch` 在会话里拉起 GUI 进程尤其顺手——由 Hyprland 来 exec，环境变量天然正确，比在别的终端里手动导
`WAYLAND_DISPLAY` 可靠。

`hyprctl eval` 拿不到返回值、没有 `print`、够不到 `mykeys.lua` 的 `local`（看结果要自己写文件、验收走全局 `RACK`），
以及 `hl.dsp.*` 对不认识的参数键**静默忽略**（`toggle_special` 收裸字符串、「不跟过去」叫 `follow = false` 不叫 `silent`），
都写在 [02](02-hyprland.md#实测出来的-api-约束) 与 [02 · 调试出口](02-hyprland.md#调试出口-rack)。

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

**现象**：面板弹出来不到 1 秒就没了，键盘焦点其实是好的（敲的字进了搜索框，然后连面板带字一起消失）。
**⚠ 根因没查清**，只在某个说不清何时进出的状态下犯病，别信「上游既有行为、重启没用」那类说法。

2026-10-09 起启动器（`ALT+Space`）和剪贴板（`SUPER+V`）都改用 Walker 绕开了（独立进程、铺满整屏，
结构上不存在「指针在面板外」），见 [13](13-launcher.md)；回退脚本 `bin/noct-panel` 也已删。
其他 noctalia 面板（控制中心等）仍可能撞上，仍然有效的两条：

- **犯病时，指针在不在面板矩形内是决定性变量**：把指针挪进去面板就常驻。手工验证
  `hyprctl dispatch 'hl.dsp.cursor.move({x = 1280, y = 720})'`（只收 table，写成 `(x, y)` 会报错）。
- **所有面板复用同一个 layer surface**：换面板时 `hyprctl layers` 里 `noctalia-panel` 的 address 不变，
  按 address 做前后差集找不到新面板。

诊断入口：`~/.cache/noctalia/noctalia.log` 的 `[panel] panel manager: opened/closing "<id>"`（不记关闭原因）；
做对照实验要把指针位置当一等变量记下来。

**重启 noctalia 时的三个坑**：

- 别从 Hyprland 进程的 `environ` 抄环境启动（它里面没有 `WAYLAND_DISPLAY`，报 `failed to connect to Wayland display`），
  用 `hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'`，见坑 8。
- 手动拉起的实例顶栏不会自动隐藏（隐藏靠 `mykeys.lua` 第 9 节的 `hl.on("hyprland.start")`），补一条 `noctalia msg bar-hide`。
- 偶尔起出「半残」实例：壁纸顶栏画得出来，但主循环卡在启动阶段的网络等待，`noctalia msg` 返回空、`notify-send` 超时。
  判据是**日志停止增长**，`kill -9` 重来。

实测记录、排除掉的方向与 `bin/noct-panel` 的实现见 `git show f23564b:docs/07-troubleshooting.md`。

---

## 坑 11 — 升级后程序报 `cannot open shared object file`（`-Syu` 是完整升级也会中）

**现象**（2026-11-20）：早上 `yay -Syu` 后 chrome-devtools MCP 显示 `CONNECTION_CLOSED`。手动跑
`~/.local/bin/chrome-ai-mcp`，看到的是 node 本身起不来：
`node: error while loading shared libraries: libsimdjson.so.36`。

**根因不在本机，是仓库没对齐**：`cachyos-extra-znver4` 先发了 simdjson 5.2.0（库从 `.so.36` 变成 `.so.37`，旧文件被删）。
重编的 `nodejs 26.13.1-3` 只进了通用 `cachyos` 仓库，`cachyos-znver4` 里还是链着 `.so.36` 的 `-2`。
**pacman 对同名包取 `pacman.conf` 里第一个有这个包的仓库，不比较各仓库版本**，znver4 排在最前，所以 `-Syu` 拿不到 `-3`。

**修法**：

```bash
pacman -Si nodejs | grep -E '^(Repository|Version)'   # 看各仓库版本
sudo pacman -S cachyos/nodejs                         # 指定仓库装重编过的那个
```

装之前可以确认一下新包链的是新库：`pacman -Sp cachyos/nodejs` 拿到下载地址，下载后
`bsdtar -xOf 包 usr/bin/node >/tmp/node && readelf -d /tmp/node | grep NEEDED`。之后 `-Syu` 碰到本机版本比 znver4 仓库新，
会提示 `local is newer` 并跳过，**不会降回去**；等 znver4 仓库追上版本，就会恢复正常更新。

**自动检查：`system/pacman-libcheck/`**。pacman 钩子，每次装/升级完包，查「这次的包 + 依赖它们的包」里的 ELF 文件，
有缺库就在升级输出最后标红报出来，并列出各仓库版本。**只报不修**，钩子永远 `exit 0`，不影响 pacman 本身。

```bash
cd ~/cachyOS-config/system/pacman-libcheck
sudo ./setup.sh            # 装：/usr/local/libexec/pacman-libcheck + /etc/pacman.d/hooks/zz-pacman-libcheck.hook
sudo ./setup.sh --remove   # 卸
./pacman-libcheck --files /usr/bin/node    # 手动查某个文件
printf 'glibc\n' | ./pacman-libcheck       # 相当于全盘扫（glibc 被所有包依赖），约 5 秒
```

判定的取舍：

- **只报「换了版本号」的缺**：缺 `libfoo.so.36`、系统里有 `libfoo.so.37` 才报。第一版只要找不到库就报，
  全盘扫出几十个包：openmpi 的 CUDA 插件缺 `libcuda`、gstreamer/Qt 插件缺可选依赖、jdk 的 `libjvm.so` 是运行时才加载的……
  这些在本机都是常态，真问题反而被淹掉。
- 不在 `ldconfig -p` 缓存里的，再去 RPATH/RUNPATH 和文件所在目录找（`/opt` 下 Electron 之类自带库的程序）。
- `readelf` 并行跑时，每批输出必须写到各自的临时文件。共用一个管道会互相插队，解析出 `wood.jpg 缺 libxxx` 这种乱码。
- 忽略名单 `IGNORE` 目前只有 `/opt/android-ndk/`，它自带 Android 和交叉编译的整套工具链，那些库本来就不从本机找。
- 有问题的包不在仓库里（AUR/本地包）时，提示的修法是重新编译；重编前照 `aur/README.md` 审一遍。

**以后某个 MCP 或命令突然起不来**：先手动跑它的入口脚本看 stderr，别先怀疑浏览器、端口这些外围。

---

## 坑 12 — mesa 26.3.1：GTK/Flutter 应用原生 Wayland 拿不到 EGL config（已降回 26.2.6 并锁住）

**现象**（2026-11-20 `mesa 26.2.6 → 26.3.1` 后）：一批 GTK 应用同时坏——

| 应用 | 表现 | 终端报错 |
|---|---|---|
| LocalSend（Flutter/GTK3） | 点了没窗口 | `Failed to create OpenGL context: No available configurations for the given pixel format` |
| RustDesk 界面（Flutter/GTK3） | 窗口纯白 | `Failed to initialize GLArea: No available configurations for the given pixel format` |
| Satty（GTK4） | 工具栏正常、画布只写一行 `No EGL configuration available` | 无 |

RustDesk 只坏界面：`rustdesk.service` 照常跑、照常注册到自建服务器，别往网络/服务上查。

**根因**（上游已定位）：26.3.1 回补了 `mesa: don't advertise APIs that are not built`（MR 46169）。Arch/CachyOS 的 mesa
不编 GLES1，于是 EGL config 里不再带 ES1 位；而 `EGL_RENDERABLE_TYPE` 按规范默认就是 `EGL_OPENGL_ES_BIT`（ES1），
GTK3/GTK4 调 `eglChooseConfig` 时不写这一项 → 一个 config 都匹配不上。所有「GTK + OpenGL + 原生 Wayland」都中
（Godot、Ghostty、FlClash 等也报了）。`eglinfo -B` 正常，所以别以为是驱动整体坏了。

- mesa：<https://gitlab.freedesktop.org/mesa/mesa/-/issues/16934>（regression 标签）
- GTK：<https://gitlab.gnome.org/GNOME/gtk/-/issues/8566>
- CachyOS（RustDesk 正是这个）：<https://github.com/CachyOS/CachyOS-PKGBUILDS/issues/2156>

**现在的做法：整体降回 26.2.6 + IgnorePkg 锁住**，不给单个应用打补丁。当天上午先给 LocalSend、Satty 各做了
`GDK_BACKEND=x11` 绕法（commit 657b5d7、c68cb9c），下午 RustDesk 又中招，判断「一个个打补丁」打不完，已全部撤掉。

```bash
# 8 个包必须同版本一起降（缓存里有），装的时候会校验签名
C=/var/cache/pacman/pkg; V=3:26.2.6-1-x86_64_v4.pkg.tar.zst
sudo pacman -U $C/{mesa,lib32-mesa,opencl-mesa,lib32-opencl-mesa,vulkan-radeon,lib32-vulkan-radeon,vulkan-mesa-implicit-layers,lib32-vulkan-mesa-implicit-layers}-$V
# /etc/pacman.conf（原文件备份在 pacman.conf.bak-20261120）：
IgnorePkg   = python-rapidocr mesa lib32-mesa opencl-mesa lib32-opencl-mesa vulkan-radeon lib32-vulkan-radeon vulkan-mesa-implicit-layers lib32-vulkan-mesa-implicit-layers
```

当时没有别的包依赖新 mesa（同批升级里没有 llvm），所以能单独降。降完不用重启电脑，重开受影响的应用就行；
Hyprland 自己内存里还是旧映射，下次登录自然换上。CachyOS 右上角的「建议重启」是动了核心包就弹的固定提示。

**解锁时机**：上面任一上游 issue 修好并进了仓库（`pacman -Si mesa` 看版本，比如 26.3.2+ 的更新说明提到 EGL/GLES1，
或 Arch 打开 gles1）。先**不动系统**验证新版本：把新包解到临时目录，只让一个应用用它——

```bash
mkdir /tmp/newmesa && cd /tmp/newmesa && bsdtar -xf <新 mesa 包> usr/lib usr/share/glvnd
O=/tmp/newmesa/usr/lib
LD_LIBRARY_PATH=$O __EGL_VENDOR_LIBRARY_FILENAMES=/tmp/newmesa/usr/share/glvnd/egl_vendor.d/50_mesa.json \
  GBM_BACKENDS_PATH=$O/gbm LIBGL_DRIVERS_PATH=$O/dri localsend
```

（当天就是用这招拿旧包反过来确认的根因。）没有 `No available configurations` 了，就把 `IgnorePkg` 里这 8 个删掉再 `-Syu`。

**万一以后又不能降**（缓存被清、或别的包依赖新 mesa）：单个应用用 `GDK_BACKEND=x11` 能起来，具体做法在 657b5d7 / c68cb9c。

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
| `ALT+9` 无效 | noctalia 没跑。`pgrep noctalia`；`noctalia msg --help` 能否连上 |
| `ALT+Space` 无效 / 弹出来是空的 | Walker 走的是两个用户服务：`systemctl --user status walker elephant`。空列表多半是 elephant 没起或插件加载失败（`journalctl --user -u elephant`，Go plugin 版本不一致会在这里报），见 [13](13-launcher.md) |
| 顶栏不见了 | 是 `auto_hide = true`，鼠标移到屏幕顶边。或按 `ALT+9` |
| noctalia 面板（控制中心等）一闪就没 | 2026-10-09 起启动器和 `SUPER+V` 都走 Walker，不再经过 noctalia 面板。其他面板撞上时把指针挪进面板矩形，犯病时面板立刻常驻。⚠ 根因**没查清**，见坑 10 |
| `SUPER+V` 的剪贴板历史一重启就空 | 看日志有没有 `[secret-store] ... provider-unavailable`：没有 Secret Service 时它拒绝落盘、只留内存。解法是 `[storage]` 文件密钥，见 [05](05-theme-ui.md#剪贴板supervsuper-的历史靠-storage-文件密钥才能活过重启)。⚠ 改完**必须重启 noctalia 进程**，`config-reload` 不重新初始化存储 |
| 换壁纸/换主题每次都要输密码 | `greeter_sync` 在推给登录界面。noctalia 默认用 `run0` 提权，绕开了自带的 polkit policy——**看 journalctl 里真正被拒的 action id**（是 `systemd1.manage-units` 不是 `apply-appearance`）。要 `privilege_command = "pkexec"` + `/etc/polkit-1/rules.d/` 规则两步。**两步都做了还弹**：多半是升级后 action 改名、规则失配（1.7.0 起叫 `sync-appearance`），见 [05](05-theme-ui.md#greeter-同步换壁纸主题为什么每次都要输密码) |
| 提示符全是豆腐块 | 缺 `ttf-meslo-nerd` |
| 提示符变成没见过的样子 / 弹配置向导 | `~/.p10k.zsh` 没了。`./sync.sh` 一眼看出，`./install.sh term` 修。见坑 1 |
| 终端打开不进 nvim | `kitty.conf` 的 `shell` 那行；或者是从 alacritty 开的（它本来就不进） |
| nvim 一堆红色 stack trace | 多半是 LSP 的 glob 问题，`mini.lua` 里有绕行补丁；或 Mason 缺运行时，见 [04](04-neovim.md#语言工具链mason) |
| Mason 一片红叉 | 缺 node/go/php/java 等运行时，不是配置问题。见 [04](04-neovim.md#语言工具链mason) |
| 每开 shell 刷一堆报错 | `.zshrc` 里有无条件的 `eval`/`source`。本包的写法全是探测存在才执行，被改过了才会这样 |
| 光标样式不对 | Bibata 没装，回退到 Adwaita，属正常。`yay -S bibata-cursor-theme` |
| 壁纸没上屏 | `settings.toml` 里显示器名写死为 `DP-1`，新机不同。在 noctalia 里重选一次壁纸 |
| 升级后某程序起不来：`error while loading shared libraries` | 多半是仓库重编没跟上：某个库换了版本号，依赖它的包还没重编。`pacman -Si <包>` 看别的仓库有没有新版，有就 `sudo pacman -S 仓库名/包名`。升级时 pacman-libcheck 钩子会当场报出来，见坑 11 |
| 某个应用点了没窗口，终端里报 `Failed to create OpenGL context: No available configurations`；或窗口里写着 `No EGL configuration available` | mesa 26.3.1 的回归，本机已降回 26.2.6 并 IgnorePkg 锁住。`pacman -Q mesa` 看是不是被升上去了，见坑 12 |
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
