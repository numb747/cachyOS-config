# 05 · 主题与 UI：noctalia 顶栏、配色联动、字体、壁纸、输入法

对应文件：`config/noctalia/`、`state/noctalia/`、`config/gtk-*`、`config/qt6ct/`、
`config/btop/`、`config/kdeglobals`、`config/fcitx5/`、`config/fontconfig/`、
`share/fcitx5/themes/`、`wallpaper/`

---

## 先搞清楚：桌面顶部那条 bar 是 **Noctalia**，不是 waybar

`noctalia` 包，用 Quickshell 写的 Wayland shell。系统上**没有** `~/.config/waybar`——
找 bar 配置时第一反应去翻 waybar / eww / ags，全都不存在，会白绕一圈。

它由 `~/.config/hypr/config/autostart.lua` 里的 `hl.exec_cmd("noctalia")` 拉起。

常用命令：

```bash
noctalia config export full     # 打印【全部】键含默认值 —— 这是唯一可靠的查询方式
noctalia config validate        # 校验
noctalia msg config-reload      # 热重载
noctalia msg --help             # 列出全部 IPC 命令（bar / dock / 媒体 / 亮度 / 面板…）
```

`config.toml` **只存非默认项**，直接读文件是看不到有哪些可选项的。所以想知道某个东西
能不能配、叫什么名字，一律用 `noctalia config export full` 而不是读配置文件。

---

## ★ 配置分裂在两个文件里

这是这套配置最容易踩的一个坑：

| 文件 | 管什么 | 谁在写 |
|---|---|---|
| `~/.config/noctalia/config.toml` | 顶栏布局、widget、shell 行为、截图/会话动作 | 手写 |
| `~/.local/state/noctalia/settings.toml` | **主题来源、调色板、壁纸路径、锁屏部件** | noctalia 设置界面 |

两边的 `[theme]` 段**重叠**，实测以 `settings.toml` 为准：

```toml
# ~/.config/noctalia/config.toml  —— 【这一段】被 state 覆盖，不生效
[theme]
source = "wallpaper"

# ~/.local/state/noctalia/settings.toml  —— 实际生效
[theme]
source = "community"
community_palette = "Tokyo Night Moon"
mode = "dark"
```

`noctalia config export full` 打印出来的是 `source = "community"`，以它为准。

⚠ **只有重叠的 `[theme]` 段是这样，别推广成「config.toml 整个文件已过时」。**
`[shell]`（含 `greeter_sync`、clipboard 各项）、`[storage]`、`[bar.*]`、`[widget.*]`
都只在 config.toml 里，全部正常生效——2026-08-27 的 greeter 免密和剪贴板持久化两处
改动都写在这个文件里并实测生效。判断某个键到底生效没有，一律 `noctalia config export full`。

**后果**：只把 `~/.config/noctalia/config.toml` 拷到新机器，顶栏布局对了，但**配色
完全不对**。所以本包额外带了 `state/` 目录（含 `settings.toml` 和
`community-palettes/Tokyo%20Night%20Moon.json`）。

`install.sh` 的 `ui` 模块会自动把 `settings.toml` 里的 `/home/david` 路径改写成新机的
`$HOME`。但里面的显示器名 **`DP-1` 是写死的**——新机输出名不同的话壁纸不会自动上屏，
在 noctalia 设置里重选一次壁纸即可。

---

## 配色是怎么传导到每个程序的

noctalia 有一套模板引擎，把当前调色板渲染成各程序的配置文件：

```toml
# config.toml
[theme.templates]
builtin_ids = [ "btop", "gtk3", "gtk4", "kcolorscheme", "kitty", "qt", "alacritty" ]
```

于是这七个文件是**产物**，不是手写的：

| 产物 | 被谁引用 |
|---|---|
| `~/.config/kitty/themes/noctalia.conf` | `kitty.conf` 末行 `include` |
| `~/.config/alacritty/themes/noctalia.toml` | `alacritty.toml` 的 `[general] import` |
| `~/.config/btop/themes/noctalia.theme` | `btop.conf` 的 `color_theme = "noctalia"` |
| `~/.config/gtk-4.0/noctalia.css` | `gtk-4.0/gtk.css` 的 `@import` |
| `~/.config/qt6ct/colors/noctalia.conf` | `qt6ct.conf` 的 `color_scheme_path` |
| `~/.config/kdeglobals` | KDE 系应用（dolphin 等）直接读 |
| GTK3 | 走 `gtk-3.0/settings.ini` 的 `adw-gtk3` 主题 |

> **改配色的正确入口是 noctalia，不是编辑上面这些文件。** 手改了下次换壁纸/换调色板
> 就被覆盖回去。本包带这些产物只是为了避免新机首次启动时 `include` 一个不存在的文件。

`~/.local/state/noctalia/community-templates/` 下还有 ~45 个社区模板没启用
（neovim、lazygit、vscode、rofi、yazi、zellij、obsidian、firefox…）。想让某个程序也
跟着换色，把它的 id 加进 `builtin_ids` 即可。

### `qt6ct.conf` 里的 `$USER` 陷阱

发行版 skel 里这行写的是字面量：

```ini
color_scheme_path=/home/$USER/.config/qt6ct/colors/noctalia.conf
```

qt6ct **不做变量展开**，所以在用户名不是 `$USER` 这四个字母的机器上这是个死路径，
表现为 Qt 应用配色不生效。`install.sh` 会自动替换成真实 `$HOME`。

### LibreOffice：必须显式钉 VCL 后端

LibreOffice 靠自动探测选绘制后端，而 **Hyprland 不在它的已知桌面列表里**，探测会退到
`gen`——X11 裸绘制，主题完全不跟随（上表 GTK3 那行的 `adw-gtk3` 白写了），输入法还得走
XIM。所以在 `~/.config/uwsm/env` 里钉死：

```sh
export SAL_USE_VCLPLUGIN=gtk3
```

选 `gtk3` 而不是别的：它跟随 `adw-gtk3`，且 Wayland 下最稳。**不用 `qt6` / `kf6`**——
Wayland 下有已知滚动卡顿（[tdf#152911](https://bugs.documentfoundation.org/show_bug.cgi?id=152911)）。

本机可用后端列表：

```bash
ls /usr/lib/libreoffice/program/libvclplug_*.so
# → gen · gtk3 · gtk4 · kf6 · qt6
```

⚠️ **`uwsm/env` 是会话级的，登录时才读一次**（见 [03](03-terminal.md)）。改完必须重新登录，
在已开的终端里 `echo $SAL_USE_VCLPLUGIN` 是空的属正常，不代表没配上。

---

## 顶栏布局

```
┌────────────────────────────────────────────────────────────────────────┐
│ 启动器 时钟   [温度 GPU温度 内存]  │ 工作区  当前窗口 │  媒体  托盘 通知 网络 音量 电源 │
└────────────────────────────────────────────────────────────────────────┘
   start ─────────────────────────    center ──────────    end ──────────────────────
```

| 键 | 值 | 效果 |
|---|---|---|
| `auto_hide` + `smart_auto_hide` | false / false | 2026-09-09 起关闭：两者都自带"指针到达顶边即 reveal"的命中条，鼠标划过顶部点标签页之类操作很容易被误触发弹出。改成纯 IPC 手动控制（见下） |
| `reserve_space` | false | 不为它预留布局空间，窗口可以顶到屏幕最上沿 |
| `thickness` / `scale` | 35 / 1.10 | 栏高与栏内元素缩放 |
| `radius_bottom_*` / `concave_edge_corners` | 12 / true | 下方两角圆角，边缘内凹 |
| `[accessibility] ui_scale` | 1.20 | 整个 noctalia UI（面板、启动器、设置）放大 20% |

`group:g1` 是一个 capsule 分组，把「温度 / GPU 温度 / 内存」三个 sysmon 装进同一个
胶囊里（`fill = "on_secondary"`），视觉上是一块而不是三块。工作区和托盘也各自开了
capsule。多数 widget 设了 `color = "secondary"`，电源键是 `error`（红）。

时钟格式 `{:%H:%M %A %m/%d/%y}`。

`ALT+9` 手动开合顶栏（走 `noctalia msg bar-toggle`，见 [02](02-hyprland.md)）。
其他相关 IPC：`bar-hide` / `bar-show` / `bar-reserve-toggle` / `bar-auto-hide-set`。

顶栏默认收着，只在切工作区时用 `bar-show` 弹出 1.5 秒后 `bar-hide` 自动收回——
逻辑在 `~/.config/hypr/mykeys.lua` 第 9 节（`hl.on("workspace.active", ...)` +
`hl.timer`），不是 noctalia 自带能力，也不放官方 `config/*.lua` 里，理由同
[02](02-hyprland.md) 的 mykeys.lua 设计。

### 截图 → satty

```toml
[shell.screenshot]
pipe_to_command = true
pipe_command = "satty -f -"
save_to_file = true        # ← 2026-08-26 由 false 改成 true
copy_to_clipboard = false
```

截图管道进 satty 标注工具，**同时**落盘到 `~/Pictures`。
剪贴板里的图片也走 satty（`clipboard_image_action_command`）。

★ `save_to_file` 原本是 `false`，意味着截图**只**存在于 satty 的窗口里——
不在 satty 里手动保存，关掉窗口图就没了，且事后无迹可寻。
改成 `true` 后两条路径并存：satty 照常弹出供标注，不标注也不丢图。
`copy_to_clipboard` 保持 `false`——满屏截图直接塞进剪贴板容易误粘，
需要复制时在 satty 里按一下更可控。

### 录屏 → wl-screenrec

截图是 noctalia 内建的（`noctalia msg screenshot-*`），**录屏不是**——
noctalia 的 IPC 命令表里没有任何 record 命令，所以这块是自己搭的：
`~/.local/bin/hypr-screenrec` 包一层 wl-screenrec，键位见 [06](06-keymap-cheatsheet.md)。

选 wl-screenrec 而不是 OBS / wf-recorder：它是 wlroots 原生，帧从合成器经
DMA-BUF 直接进 VAAPI 编码器，全程不过 CPU。实测 2560×1440@60 录制时只占 **2.4%** CPU。

三个必须知道的坑：

**1. 停止必须用 SIGINT，不能用 SIGTERM。** wl-screenrec 靠 Ctrl-C 那条路径 flush
编码器并写 mp4 的 moov atom，杀错信号会得到一个没有索引、播放器直接打不开的文件。
脚本发完 `kill -INT` 还要轮询等进程真正退出（最多 5 s）才报「已保存」，
否则通知弹出时文件还没写完。验收就看 `ffprobe` 能否读出 duration。

**2. AMD 上要显式 `--low-power=off`。** Mesa VAAPI 没有 low-power 编码入口，
不关掉的话每次启动先失败一次再回退，白等一下还刷两行
`No usable encoding entrypoint found for profile` 报错。

**3. 带 transform（旋转）的显示器上不工作。** 同样是 Mesa VAAPI 的限制。
本机 DP-1 `transform: 0` 不受影响；真要录旋转屏只能换 OBS。

其余设计取舍：`--bitrate` 单位是**字节/秒**（上游默认 `5 MB` 即 40 Mbps，对 1440p 偏高），
脚本里定 `2 MB` ≈ 16 Mbps。音频录默认 sink 的 monitor 源，每次启动时
`pactl get-default-sink` 动态解析，换声卡不用改脚本。全屏模式取当前**聚焦**的显示器
而不是「唯一那块」，接第二块屏直接可用。

★ 绑定时**不能**加 `uwsm app --` 前缀（`binds.lua` 里其他 GUI 程序都加了）——
uwsm 会把录屏进程放进另一个 cgroup，脚本的 pidfile 就追不上，变成停不下来。

### 电源菜单

浮动居中，五个动作按数字键触发：`1` 锁屏 · `2` 注销 · `3` 锁屏并挂起 ·
`4` 重启 · `5` 关机。后三个有 3 秒倒计时可以反悔，关机标了 `destructive`（红）。

---

## OSD ≠ 通知：换歌时顶部弹的东西治不了，多半是找错了子系统（2026-08-27）

**症状**：pear-desktop（YouTube Music）每换一首歌，屏幕顶部就弹一次「正在播放」，
不想要。直觉是「给这个应用关通知」，于是去翻 `[notification.filter.*]` ——
**那条路对它完全不生效**，因为它根本不是通知。

### 两个子系统，长得像，入口完全不同

| | 通知 | OSD |
|---|---|---|
| 来源 | D-Bus `org.freedesktop.Notifications` | noctalia 内部事件 |
| 本包默认位置 | `top_right` | `top_center` |
| 关闭入口 | `[notification.filter.*]` | `[osd.kinds]` |

**位置就是最快的判据**：弹在正中间靠上 = OSD，靠右上角 = 通知。

### 判定链（三条独立证据，别只信一条）

```bash
# 1. 应用侧压根没开通知插件
python3 -c "import json,os;print(json.load(open(os.path.expanduser(
  '~/.config/YouTube Music/config.json')))['plugins']['notifications'])"
# → {'enabled': False, ...}

# 2. 挂 D-Bus 实测：换歌期间 Notify 调用数为 0
dbus-monitor --session "interface='org.freedesktop.Notifications',member='Notify'"

# 3. ★ 最直接的一条：翻译文件里写死了这个 OSD 干什么的
python3 -c "import json;d=json.load(open(
  '/usr/share/noctalia/assets/translations/en.json'));
print(d['settings']['schema']['shell']['osd-kinds-media'])"
# → {'label': 'Now Playing',
#    'description': 'Show an OSD popup when a new track starts playing'}
```

第 3 条值得单独记：**`/usr/share/noctalia/assets/translations/en.json` 是查
「某个配置键到底管什么」的权威来源**，比二进制 `strings` 和官方文档站都靠谱
（`docs.noctalia.dev/v5/services/notifications/` 目前 404）。配合坑 9 里那招
`noctalia config validate` 枚举合法键名，一个查「有哪些键」、一个查「键是干嘛的」。

### 解法

```toml
# ~/.config/noctalia/config.toml
[osd.kinds]
media = false
```

**这是全局开关**，关的是所有播放器的换歌弹窗；noctalia **没有**按播放器关 OSD 的选项。
bar 上的 media widget 和播放控制不受影响。

真要只针对单个播放器，只有 `[shell.mpris] blacklist = [...]`，但那会把它从 media
widget 里一并摘掉，通常不是想要的。

`[osd.kinds]` 下同结构的还有：`bluetooth` · `brightness` · `caffeine` · `dnd` ·
`keyboard_backlight` · `keyboard_layout` · `lock_keys` · `nightlight` ·
`power_profile` · `privacy` · `volume` · `volume_input` · `volume_output` · `wifi`。

⚠ **验收要看眼睛，不能看 `config export`** —— 见坑 9：`config-reload` 只重读文件，
`export` 显示 `media = false` 不等于行为真的变了。实际换一首歌确认；还弹就
`kill $(pgrep -x noctalia); setsid -f noctalia -d` 重启进程再看。

**本例实测结论（2026-08-27）**：`[osd.kinds]` **吃 `config-reload`**，换歌验证已不再弹，
不用重启进程。即坑 9 那个「reload 不够」的毛病是**按配置段**而非全局的——
已知需要重启的只有 `[shell.launcher.providers.*]` 和 `[storage]` 两段。
新段别默认往坏处想，先 reload 试，不行再重启。

### 顺带：通知过滤器的完整字段（真需要按应用屏蔽通知时用）

字段名同样是 `noctalia config validate` 探出来的（未知键会报 `unknown setting`
但仍返回 valid），标签取自 `translations/en.json` 的 `settings.notifications.filter`：

```toml
[notification]
filter_order = [ "discord" ]      # 按序求值，第一条匹配的赢

    [notification.filter.discord]
    enabled = true
    match = "discord"             # App：app name / desktop entry / category，不分大小写、子串
    match_content = ""            # Content Regex：匹配 summary 或 body
    allowed_urgencies = []        # 非空时只放行 low/normal/critical 中列出的
    show_toast = false            # ← 屏蔽弹窗就是这个
    play_sound = false
    save_history = true           # 仍留在控制中心历史
    bypass_dnd = false            # 反向用法：让重要 app 穿透勿扰
    allow_permanent = false
    override_duration = 5
```

GUI 在 `noctalia msg settings-open notifications` → Filters → Add。

另外两个**不对症**的东西，别再试：☕ caffeine 是空闲抑制器（防息屏），跟通知无关；
🔔 DND 是全局的，且**不持久化**（`state.toml` 里无记录，重启回 off）。
要永久静音全部通知用 `[notification] enable_daemon = false`（连历史都不留），
或写一条 catch-all 过滤器（`match = ""` + `match_content = ".*"` + `save_history = true`）。

---

## 启动器：provider 模型（已被 Walker 取代）

> ⚠ **2026-10-09 起 `ALT+Space` / `SUPER+.` / 顶栏启动器按钮都改走 Walker**，
> 见 [13-launcher.md](13-launcher.md)。本节是 noctalia 自带启动器的记录，
> `[shell.launcher]` 配置也还留在 `config.toml` 里，留着是为了要回退时有据可查。

`ALT+Space` 拉起的启动器不是单一列表，是若干 **provider** 的聚合。合法 id 只有六个：

```
applications · windows · emoji · wallpaper · session · calculator
```

每个 provider 有且只有两个可配项，写在 `~/.config/noctalia/config.toml`：

```toml
[shell.launcher]

    # 无前缀搜索里也列出已打开的窗口，方便直接跳过去而不是再开一个
    [shell.launcher.providers.windows]
    global = true

    # 很少用启动器算数，把计算器从无前缀搜索里摘掉，免得抢第一行；/calc 仍可用
    [shell.launcher.providers.calculator]
    global = false
```

| 键 | 含义 |
|---|---|
| `global` | 是否参与**无前缀**搜索。false = 只能靠前缀触发 |
| `prefix` | 触发前缀，和 `provider_prefix`（默认 `/`）拼接。留空 = 用内置默认 |

内置默认前缀：`/win` · `/emo` · `/wall` · `/session` · `/calc`。
`applications` 没有前缀设置项——它是 default provider，无前缀时永远参与。

选中窗口回车时 noctalia 发的是 `hyprctl dispatch focuswindow address:0x…`，
Hyprland 会自动把视图切到该窗口所在工作区，跨显示器还会先 `focusmonitor`。

### 三条限制（2026-08-26 实测，别再重新调研）

1. **`noctalia msg config-reload` 不会重载 launcher 的 provider 注册。**
   改完 `[shell.launcher.providers.*]` 必须重启 noctalia 进程才生效：

   ```bash
   kill $(pgrep -x noctalia); setsid -f noctalia -d
   ```

   它由 Hyprland 的 `autostart.lua` 直接拉起，不是 systemd unit，没法 `systemctl restart`。

2. **没有跨 provider 的排序权重。** 探过 `weight` / `priority` / `order` / `enabled`，
   `noctalia config validate` 一律报 `unknown setting`。应用永远排在窗口前面。
   上游 [issue #2470](https://github.com/noctalia-dev/noctalia/issues/2470) 提的正是
   「输 firefox 时已开的窗口应该排在启动项前面」，**已 closed as not planned**，
   不用等了。想让某类结果靠后，唯一手段是把它的 `global` 关掉、退回前缀触发。

3. **窗口和应用没有徽章区分**，只能看副标题：

   | 副标题长这样 | 是 |
   |---|---|
   | `An open source cross-platform alternative to AirDrop` | 应用（.desktop 的 Comment） |
   | `localsend` | 窗口（窗口 class，永远是单个小写词） |

   `show_app_origin_indicator` 那个开关只给应用打 System/Flatpak/Nix 来源标，和窗口无关。

另外模糊匹配是**子序列**匹配，很松：搜 `localsend` 会把标题为
`GitHub - noctalia-dev/noctalia: A sleek, customizable…` 的 firefox 窗口也捞出来
（能挑出 l-o-c-a-l-s-e-n-d）。噪声比预期多，属预期行为不是 bug。

### 排查手法

活配置一律用 `noctalia config export full`（读的是合并后的生效值），
`noctalia config validate <file>` 会对不认识的键报 `unknown setting`、
对不存在的 provider 报 `provider is nonexistent`——拿它当探针可以枚举出合法键名。

---

## 剪贴板：`SUPER+V` 的历史靠 `[storage]` 文件密钥才能活过重启

> ⚠ **2026-10-09 起 `SUPER+V` 打开的是 Walker 的剪贴板（elephant-clipboard）**，见
> [13-launcher.md](13-launcher.md#剪贴板)。noctalia 的剪贴板服务**仍在后台运行**，
> 只为保留「源程序关掉后内容还能粘贴」（`keep_from_closed_apps`），本节的加密存储配置也还在生效。

先认清是谁在干活：**这个剪贴板是 noctalia 自己的 `ClipboardService`**，走 Wayland 的
`ext_data_control_manager_v1` 协议。既不是 Hyprland 的（合成器根本没有剪贴板历史这个功能），
也**不是 cliphist**（本机没装，别去找 `~/.cache/cliphist/db`）。

### 症状与根因（2026-08-27）

历史每次重启清零。根因不是「它不支持持久化」，恰恰相反——它**坚持加密后才落盘**，
主密钥默认从 Secret Service 取，而本机没跑任何 provider（gnome-keyring / kwallet 都没启用），
于是每次启动都报：

```
[WRN] [secret-store] operation=lookup scope=storage status=unavailable
      category=provider-unavailable default-collection=unknown
```

设计上它宁可丢也不明文存，所以降级成「仅本会话可用」。

### 解法：文件密钥，绕开整个 Secret Service

noctalia 官方为声明式配置（NixOS/agenix 那类）留了出口，正好拿来用——**不装 keyring、
不改 PAM、不需要 sudo**：

```toml
# ~/.config/noctalia/config.toml
[storage]
key_source = "file"
key_file = "/home/david/.config/noctalia/storage.key"
```

密钥是 64 位小写十六进制（32 随机字节）：

```bash
umask 077
head -c 32 /dev/urandom | xxd -p -c 64 > ~/.config/noctalia/storage.key   # 权限必须 0600
```

### ★ 改完必须重启进程，`config-reload` 不算

这一条最坑：`noctalia msg config-reload` **不会重新初始化存储子系统**。
`noctalia config export` 会显示 `[storage]` 已生效，但磁盘上死活不出现文件——
很容易误判成配置写错了又去改配置。没有官方 restart 命令：

```bash
kill -TERM $(pgrep -x noctalia)
hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'   # 用 hyprctl 拉起，会话环境才正确
```

（和[启动器 provider 那条限制](#三条限制2026-08-26-实测别再重新调研)同源：
`config-reload` 只重读文件，不重新注册子系统。）

### 验收

| 检查 | 期望 |
|---|---|
| 目录 | `~/.local/state/noctalia/clipboard/` 出现，`0700` |
| 文件 | `index.enc` + `entries/*.enc`，均 `0600` |
| 确实加密 | `index.enc` 头 8 字节是 magic `NOCTALIAENC1`，其后为密文 |
| 无明文泄漏 | `grep -r '<刚复制的测试串>' ~/.local/state/noctalia/` 无结果 |
| **重启后读回** | 日志出现 `[INF] [clipboard] loaded encrypted clipboard history` |

失败的样子是重启后日志写 `clipboard history size=NN entries=1`（归零重来）。

### 注意事项

- ⚠ **`storage.key` 丢了 = 旧历史永久读不出来。** 换密钥不会重新加密，只是认证失败；
  加密文件本身会保留，换回原密钥即可恢复。它**不入包**（见 CLAUDE.md 的边界章节），
  新机器要重新生成——代价是旧历史读不出来，可接受。
- 本机**无全盘加密**（btrfs 裸盘），所以主密钥等于明文躺在盘上，只靠 `0600` 保护。
  接受这个取舍的理由：能读到该文件的人已经有本用户权限了，那他直接问 D-Bus 要
  keyring 里的东西也一样拿得到；真正的差别只在**离线磁盘攻击**这一个场景。
  真在意就该先上全盘加密，而不是纠结这一个文件。
- 相关配置项（都在 `[shell]`）：`clipboard_history_max_entries` 默认 **100**、
  范围 10–10000、**只算未 pin 的条目**；`clipboard_enabled`、`clipboard_auto_paste`
  （`off|auto|ctrl_v|ctrl_shift_v|shift_insert`）、`clipboard_keep_from_closed_apps`。
- noctalia 会自动检测**在它之后**才启动的 Secret Service provider（一旦有进程 claim
  `org.freedesktop.secrets` 就自动重开加密存储），所以哪天改用 keyring 也不用担心启动顺序竞态。

---

## greeter 同步：换壁纸/主题为什么每次都要输密码

`[shell.greeter_sync] auto_sync = true` 会在换壁纸或配色时，把结果推给 greetd 登录界面
（写 `/var/lib/noctalia-greeter/`，属主 `greeter:greeter` `0750`），这一步要提权。

### 根因：它默认用 `run0`，绕开了自带的 policy（2026-08-27）

`noctalia-greeter` 包装了 polkit policy `org.noctalia.greeter.apply-appearance`，
但 noctalia **默认挑 `run0`** 提权。run0 是靠起临时 systemd unit 干活的，请求的 action 是
`org.freedesktop.systemd1.manage-units`，**根本不经过那个 policy**：

```
polkitd: Operator of unix-session:3 FAILED to authenticate to gain authorization
  for action org.freedesktop.systemd1.manage-units [run0 noctalia-greeter-apply-appearance ...]
```

所以照着 `apply-appearance` 那个 action 写 polkit 规则是**完全无效**的。
而 `manage-units` 又没法安全放行——run0 的 unit 名是随机的 `run-uNNNN.service`，
无法按命令区分，放行它等于全局 root 免密。

**排错通则：先看 journalctl 里真正被拒的 action id，别照着 policy 文件猜。**

### 解法：两步，缺一不可

**① 掰回 pkexec**（包里的 `config/noctalia/config.toml` 已含此项）：

```toml
[shell.greeter_sync]
auto_sync = true
privilege_command = "pkexec"
```

官方对该键的说明：*Replace pkexec/run0 for greeter Sync Now；helper 路径和 staging 目录
会自动追加*。

**② 系统侧放行**——⚠ 这一步**不在本包管辖范围**（`install.sh` 只写 `$HOME`，不碰系统），
新机器要手动建 `/etc/polkit-1/rules.d/49-noctalia-greeter.rules`：

```javascript
polkit.addRule(function(action, subject) {
    if (action.id == "org.noctalia.greeter.apply-appearance" &&
        subject.isInGroup("wheel") && subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
```

`49-` 要排在 `50-default.rules` 前面；`/etc/` 优先级高于包自带的 `/usr/share/polkit-1/rules.d/`。
polkit 127 会自动重载，不用重启。

### 验收

```bash
pkcheck --action-id org.noctalia.greeter.apply-appearance --process $$   # → polkit.result=yes
noctalia msg greeter-sync                                                # 应无提示直接完成
```

journalctl 里应只剩 `pkexec: Executing command`，没有 polkitd 的 `FAILED to authenticate`。

### 边界与降级

- 规则带 `local && active`，**只有本地活跃会话免密**，SSH 进来换壁纸仍要密码（有意为之）。
- 若上游改了 action id 或键名，规则失配 → 退回弹窗（`polkit_agent = true` 开着，能正常弹），
  不会静默失败。
- 非活跃会话触发同步会走 timeout：文件 staged 下来并提示手动跑 `pkexec`，不会挂死。
- policy 里写的是 `auth_admin` 而非 `auth_admin_keep`，所以**不加规则的话每次都问、不缓存**。
- CachyOS 自带的 `/usr/share/polkit-1/rules.d/empower.rules` 是对 `empower` 组全 action 放行——
  别图省事往那个组里加人。

---

## 字体

| 用途 | 包 |
|---|---|
| **kitty 正文** | `adwaita-fonts`（Adwaita Mono，窄字形） |
| **图标（p10k / nvim）** | `ttf-meslo-nerd`（**必装**，缺了全是豆腐块） |
| **中文首选** | `ttf-sarasa-gothic`（更纱黑体，806 MB） |
| 中文兜底 | `noto-fonts-cjk` |
| Emoji | `noto-fonts-emoji` |
| 界面 | `cantarell-fonts`、`ttf-opensans` |
| 兜底 | `noto-fonts`、`ttf-dejavu`、`ttf-liberation`、`ttf-bitstream-vera` |

**kitty 是两个字体拼的**：正文 Adwaita Mono，Nerd Font 私用区码位用 `symbol_map`
单独映射给 MesloLGS Nerd Font（普通版，不是 Mono）。少装任何一个都会出问题——缺 adwaita 就回退到
fontconfig 的 `monospace`，缺 meslo 则图标变豆腐块。理由见
[03-terminal.md](03-terminal.md#字体adwaita-mono--meslo-补图标)。

alacritty 仍用 `monospace` 别名，由 fontconfig 自行解析，没有显式指定。

### `config/fontconfig/fonts.conf` —— 修汉字字形

**要解决的问题**：Arch/CachyOS 默认没有 CJK 语言排序配置，`/etc/fonts/conf.d/65-nonlatin.conf`
按字母序列出 Noto CJK 家族，`KR` 排在 `SC` 前面。结果是**汉字默认用韩文字形**
（`fc-match sans-serif:lang=zh-cn` → Noto Sans CJK KR），「直 / 骨 / 查 / 兌」等字
写法与简中习惯不同。这是「整体是 Tokyo Night，唯独中文看着别扭」的真实来源之一。

本包的 `fonts.conf` 分三层，全部用 `<match>` 写：

| 层 | 内容 | 为什么 |
|---|---|---|
| 一 | 钉住 Latin（Noto Sans/Serif/Mono）+ 其后接 CJK 链 | 英文数字观感完全不变，汉字逐字回退到中文字体 |
| 二 | `lang=zh-cn` 时把中文字体 `prepend_first` 到最前 | 单结果查询也能拿到中文字体 |
| 三 | `lang=ja/ko/zh-tw/zh-hk` 各自顶回区域字体 | 否则会被第一层钉住的简中字形抢走 |

**三个把人绊住的行为**（都实测过）：

1. **`mode="prepend"` 是插到「匹配到的那一项之前」，不是队首。**
   多条 `<match>` 叠加时要真正顶到第一位，必须用 `mode="prepend_first"`。
2. **`<alias>` + `<prefer>` 无论写在文件哪个位置，都会被排到所有 `<match>` 之前。**
   顺序敏感的场景一律用 `<match>`，不要混用。
3. **`fc-match X` 和 `fc-match -s X` 结果不同。**
   Pango / Qt 实际用的是排序后的 fontset，所以判断渲染效果**要看 `fc-match -s`**。
   本机 `fc-match sans-serif:lang=zh-cn` 至今仍返回 Latin 字体，看着像没生效，
   但 `-s` 的第一名是中文字体，实际渲染是对的。

验证（`install.sh ui` 会自动跑一次）：

```bash
for l in zh-cn ja ko zh-tw; do
    printf '%-6s -> ' "$l"; fc-match -s "sans-serif:lang=$l" | grep -iE 'CJK|Sarasa' | head -1
done
# 期望：zh-cn → Sarasa Gothic SC；ja → CJK JP；ko → CJK KR；zh-tw → CJK TC
```

### 关于更纱黑体：别指望它改变汉字长相

`ttf-sarasa-gothic` 排在中文链首位，但要明确它带来什么、不带来什么：

- **不会改变汉字字形**。更纱的中文部分**就是思源黑体**，与 Noto Sans CJK SC 同源。
  实测同样文字渲染成图对比，像素差异 **0.035%**，肉眼无差别。
- 真正的收益是 `Sarasa Mono SC` / `Sarasa Term SC` 的**严格 1:2 等宽**
  （终端里中英混排能对齐，Noto 做不到），以及更紧凑的字面和行高。
- 汉字「变好看」的功劳属于上面那节的 **KR → SC 修正**，与装不装更纱无关。

不装它整套配置照常工作，静默回退 Noto CJK SC。**要真正换汉字长相得换字族**，
比如 `Noto Serif CJK SC`（思源宋体，系统自带）。对比图：
![黑体 vs 宋体](img/font-compare.png)

## 光标

`gtk-3.0/settings.ini` 和 `uwsm/env` 里都写的 `Bibata-Modern-Ice`，但 **CachyOS 默认
不装这个包**（是 skel 里的一厢情愿）。不装就静默回退到 Adwaita 光标，没有任何报错，
只是样式不同。要一致就 `yay -S bibata-cursor-theme`。

## 默认打开方式：图片 → imv，音视频 → mpv

`config/mimeapps.list` 把 17 种图片类型钉给 imv、122 种音视频类型钉给 mpv，
两份清单都是从各自 `.desktop` 的 `MimeType=` 字段生成的，
覆盖范围正好等于程序真正支持的格式。

原始状态是：图片被 Chrome 接管、`svg`/`avif` 被 Firefox 接管，
而 `mp4`/`mkv`/`mov` **没有任何关联**（双击无响应）——本机原本既没有图片查看器
也没有视频播放器。

### 三个坑

**1. 不要用 `xdg-mime default app.desktop type1 type2 …` 一次传多个类型。**
它会把所有类型挤成**一个畸形的 key** 写进 `mimeapps.list`，形如
`image/png image/jpeg … image/qoi=imv-viewer.desktop`，而规范要求每行一条。
整行静默失效，`xdg-mime` 不报错。
正确做法是直接生成每行一条：读 `.desktop` 的 `MimeType=`，`tr ';' '\n'` 拆行后
`sed 's/$/=app.desktop/'`。注意 zsh **不做默认分词**，`printf '%s\n' $var` 对多行
字符串只会输出一次，要么 `${=var}` 要么全程走管道。

> 验证时容易被假象骗过：某个类型看起来「生效了」，其实是它本来就没有默认值，
> 新装的程序成了唯一声明该类型的应用，走 `mimeinfo.cache` 回退才对上的，
> 跟你写的配置无关。已有默认值的类型（比如被 Chrome 占着的 `image/png`）则纹丝不动。
> 用 `xdg-mime query default` 和 `gio mime` 两边交叉验证，后者还能看到候选列表。

**2. 图片绑的是 `imv-viewer.desktop`，不是系统的 `imv.desktop`。**
系统装了两个条目，`imv-dir.desktop` 的 `Exec` 是个包装脚本，单文件参数时执行
`imv -n "$1" "$(dirname "$1")"`——**加载整个目录并定位到点击的那张，可以左右翻页**；
直接绑 `imv.desktop` 就只有孤零零一张图。

但两个系统条目都带 `NoDisplay=true`（上游有意为之：imv 无参数启动没有意义，
不该出现在启动器里），代价是 dolphin 的「打开方式」列表里也看不到它。
所以包里自带一份 `share/applications/imv-viewer.desktop`——派生自 `imv-dir.desktop`、
去掉 `NoDisplay`、`Exec` 仍指向 `imv-dir` 以保留翻页。

★ **刻意用了新文件名，不是同名覆盖。** `~/.local/share/applications/` 优先级高于
`/usr/share/applications/`，同名是**全量遮蔽**而非字段合并——imv 升级新增格式支持时，
被遮蔽的那份不会同步，表现为「装了新版却打不开新格式」。独立命名则两边共存。
装完必须 `update-desktop-database`，否则新条目在「打开方式」里查不到
（`install.sh` 的 `mod_ui` 已代劳）。

**3. `.desktop` 里的 `Icon=` 要验证在当前主题里真的存在。**
imv 上游写的 `multimedia-photo-viewer` 在本机 Adwaita 和 breeze 里**都没有**，
菜单里会是空白占位。包里换成了 `image-x-generic`——两个主题都有且带 scalable SVG。
判断方法：`find /usr/share/icons/<主题> -name '<图标名>.*'`。

### mpv 默认不开硬解

`config/mpv/mpv.conf` 只有一行 `hwdec=auto-safe`。mpv 出厂默认是 `hwdec=no`（软解），
1440p/4K 会明显吃 CPU。开了之后本机实测走的是 **Vulkan**（RADV 的 Vulkan Video 解码），
不是 VAAPI——`auto-safe` 会按顺序试 vulkan → nvdec → vaapi，AMD 上 vulkan 先命中。
两者都是硬解，日志里 `Using hardware decoding (vulkan)` 即为生效。

## 本地 Excalidraw 白板（2026-10-09）

启动器里搜「Excalidraw」/「白板」点开即用，关掉窗口就停，不用时**零占用**。

Excalidraw 是纯前端应用：官方镜像 `excalidraw/excalidraw` 里只有 nginx 托管静态文件，
画布存在浏览器 localStorage。只有多人实时协作才需要另跑 `excalidraw-room`，一个人用不需要。

`bin/excalidraw` 做的事：

1. 容器不存在就 `docker run`（`--restart no`，开机不自启；只绑 `127.0.0.1:18766`），存在就 `docker start`
2. 等端口通了，用 `google-chrome-stable --app=… --user-data-dir=~/.local/share/excalidraw/chrome-profile` 开窗口
3. chrome 进程**阻塞到窗口关闭**，返回后 `docker stop`

用独立 profile 是这套设计的关键，一举两得：

- **独立 profile 才会阻塞。** 用日常 Chrome 的 profile，新窗口会交给已在运行的实例，
  命令立刻返回，脚本就不知道窗口什么时候关
- **画布数据位置固定**，不跟日常浏览器混在一起，清浏览器数据也不会误删

### 五个坑

**00. 必须带 `--password-store=basic`，否则每次开机后第一次打开都弹钥匙环密码。**
Chrome 每个 profile 都会向 Secret Service 要一把「Chrome Safe Storage」密钥，用来加密 cookie 和密码。
本机 gnome-keyring（2026-09-15 装上）登录时**不会自动解锁**，于是弹出
「An application wants access to the keyring "Default Keyring", but it is locked」。
输一次密码后，本次开机内都不再弹，所以表现为「有时候弹」。
Excalidraw 用不到 cookie 和密码，画布在 localStorage 里，Chrome 本来就不加密它。
所以直接不碰钥匙环，不损失任何东西。
验证方法（2026-10-09）：用 `dbus-monitor` 盯 `destination='org.freedesktop.secrets'`，
分别用新 profile 各启动一次。不加 flag 时有 `Unlock`×2、`GetSecrets`、`SearchItems`；加了以后**全为 0**。
⚠ 钥匙环已解锁时看弹窗没有意义：弹窗只在锁着时出现，得看 D-Bus 调用。

**0. `Exec=` 必须写绝对路径。** noctalia 启动器经 `systemd-run --user` 拉起程序，
而它的 PATH 里**没有 `~/.local/bin`**。写成 `Exec=excalidraw` 时，终端里跑一切正常，
在启动器里点了却毫无反应。只有 `~/.cache/noctalia/noctalia.log` 里留了一行
`Failed to find executable excalidraw`（2026-10-09 首版就踩了）。
所以写 `/home/david/...`，由 `install.sh` 的 `rewrite_home` 在换用户名时改写。
自测时要模拟启动器的环境：`systemd-run --user -E PATH=<noctalia 进程的 PATH> …`，在终端里直接跑不算数。

端口说明：宿主机上**只监听 `127.0.0.1:18766`**。`docker ps` 里看到的 `->80/tcp` 是
**容器内部** nginx 的端口，不占宿主机的 80 端口，`ss -tln` 里查不到 80。

**1. 端口别改。** localStorage 按「协议 + 主机 + 端口」隔离，换了端口旧图看起来就「没了」。
其实数据还在 profile 里，只是挂在旧 origin 下。重要的图另外导出成 `.excalidraw` 文件。

**2. 重复点图标不能把容器停掉。** 第二次启动时，同一 profile 的 chrome 会把请求交给已开的那个实例后
**立刻退出**。如果脚本照常往下走，就会把第一个窗口正在用的容器 `docker stop` 掉。
所以用 `flock` 把锁挂在第一次启动的那个进程上：拿不到锁就说明已经有窗口开着，
这时只开新窗口然后退出。容器由持锁的那个进程负责，它等到**所有**窗口都关了才停。
（2026-10-09 实测：先后开两个窗口，关掉一个容器还在跑，两个都关了才 `Exited`。）

**3. Wayland 下 `--class` 无效。** `--app` 窗口的 class 固定是 `chrome-127.0.0.1__-Default`，
`.desktop` 里的 `StartupWMClass` 就写这个，任务栏才能把窗口和图标对上。
图标是从镜像里抠出来的 `favicon.svg`，装进 `~/.local/share/icons/hicolor/` 之后要
`gtk-update-icon-cache`，因为那里已经有缓存文件（`mod_ui` 已代劳）。

升级镜像：`docker pull excalidraw/excalidraw && docker rm excalidraw`，下次点图标会用新镜像重建。
画布数据在 chrome profile 里，不在容器里，删容器不丢图。

## 手绘风 Mermaid 出图（2026-10-13）

用途：让 AI 给项目生成架构图、流程图，帮自己跟上迭代。选 Mermaid 而不是 Excalidraw/D2，原因有三：
它是 AI 写得最稳的图表语言；纯文本，能放进项目跟 git 一起 diff；GitHub/Obsidian 都能直接渲染。
想要 Excalidraw 那种手绘观感，Mermaid v11 起官方就有 `look: handDrawn`，底层同样是 rough.js。

```bash
mmd -i flow.mmd -o flow.png     # 用法同 mmdc，-c/-p/-b/-s 显式传了就覆盖默认
```

`bin/mmd` 自动补上的默认参数：`-c ~/.config/mermaid/config.json`（手绘 + 字体 + Tokyo Night 配色）、
`-p ~/.config/mermaid/puppeteer.json`（用系统 `google-chrome-stable`）、`-b '#1a1b26'`、`-s 2`。
`handDrawnSeed` 固定为 1：同一份源码每次画出来的抖动一样，重新生成不会产生无意义的 diff。
`flowchart.wrappingWidth` 从默认 200 调到 320：默认值下代码名会在连字符处被折断（`claude agents -` / `-json`），
320 刚好放得下一行中文说明或一个路径。config.json 不能写注释，原因记在这里。

**字体 = 英文 Excalifont + 中文小赖（Xiaolai）**，和 Excalidraw 自己的搭配一样。
`fontFamily: "Excalifont, Xiaolai"` 按字回退，英文落 Excalifont、汉字落小赖。
两款都装在 `~/.local/share/fonts/handwriting/`，**不入包**（小赖 22 MB），新机器照下面装：

```bash
d=~/.local/share/fonts/handwriting; mkdir -p $d && cd $d
# 小赖：上游 release 有完整 ttf
curl -fLO https://github.com/lxgw/kose-font/releases/download/v3.126/Xiaolai-Regular.ttf
# Excalifont：没有发布 ttf，Excalidraw 仓库里只有按字符范围切开的 7 个 woff2 分片，要合并
api=https://api.github.com/repos/excalidraw/excalidraw/contents/packages/excalidraw/fonts/Excalifont
raw=https://raw.githubusercontent.com/excalidraw/excalidraw/master/packages/excalidraw/fonts/Excalifont
t=$(mktemp -d); for n in $(curl -s $api | grep -o 'Excalifont-Regular-[0-9a-f]*\.woff2' | sort -u); do curl -sfL $raw/$n -o $t/$n; done
python - $t <<'EOF'
import glob, sys
from fontTools.ttLib import TTFont
from fontTools.merge import Merger
fs = []
for f in sorted(glob.glob(sys.argv[1] + "/*.woff2")):
    t = TTFont(f); t.flavor = None; t.save(f[:-6] + ".ttf"); fs.append(f[:-6] + ".ttf")
Merger().merge(fs).save("Excalifont-Regular.ttf")
EOF
fc-cache -f $d && fc-list | grep -iE 'excalifont|xiaolai'
# mermaid-cli：跳过 puppeteer 自带的 ~150 MB 浏览器，puppeteer.json 已指向系统 chrome
PUPPETEER_SKIP_DOWNLOAD=1 npm i -g --prefix ~/.local @mermaid-js/mermaid-cli
```

合并要 `python-fonttools` + `python-brotli`（读 woff2）。2026-10-13 合并结果为 561 个字符，大小写字母和数字齐全。

### 三个要知道的

**1. 装了小赖不会抢系统中文字体。** `fonts.conf` 用 `prepend_first` 钉死了更纱，
小赖不在任何规则里，只有被点名时才用。装完验过：`fc-match 'sans-serif:lang=zh-cn'` 仍是 Sarasa Gothic SC。

**2. 手绘线条只有部分图类型支持。** 流程图实测是手绘的；时序图的线框仍然是直线，
只有字体是手写的（2026-10-13，mermaid-cli 12.0.0）。这是上游的支持范围，不是配置问题。

**3. SVG 不嵌入字体，只记字体名。** 在没装这两款字体的机器上打开会退回默认字体。要发给别人就导出 PNG。

### 交互式看图：`mmd-view`（2026-10-13）

静态图读大项目不够用，所以另写了一个查看器。在 Dolphin 里**双击 `.mmd`** 就会打开；
对文件夹右键 →「打开方式」→「Mermaid 图查看器」，可以把整个目录的图列在侧栏里。
从启动器点开会弹出目录选择框。命令行用 `mmd-view [文件|目录]`。

| 操作 | 效果 |
|---|---|
| 滚轮 / 拖动 | 缩放 / 平移（改的是 viewBox，放多大文字都是矢量清晰的） |
| 单击节点 | 高亮直接上下游：上游绿、下游橙、其余变暗；节点旁浮出信息卡（见下） |
| 再点一次 | 展开整条调用链（传递闭包） |
| 双击节点 | 有 `@link` 就进入细节图，有 `@src` 就在 nvim 里跳到定义处（优先复用已开着的，见下） |
| `/` | 搜节点，回车逐个居中 |
| `n` | 写备注：选中节点时是这个节点的，没选中时是整张图的（顶栏「本图备注」按钮同） |
| `t` | 切字体：手写（Excalifont + 小赖，和 `mmd` 静态图一致）⇄ 等宽（Adwaita Mono + 更纱黑体，同 kitty 里的 LazyVim）；顶栏下拉框同，选择记在 localStorage |
| `d` | 横竖互换；顶栏下拉框三档「按文件方向 / 横向 / 竖向」，选择记在 localStorage，**只影响显示、不改 `.mmd`**（见下） |
| `e` | 导出当前看到的样子：复制到剪贴板 + 存成 `~/Pictures/mmd_<图名>_<时间>.png`（顶栏「导出」按钮同，见下） |
| `f` · `b` · `Esc` · `Alt+←` | 适应窗口 · 侧栏 · 取消高亮 · 回上一张图（回来时恢复离开时的缩放位置和选中的节点） |

**信息卡**（2026-10-13 改，原来固定在右下角）：贴着选中节点浮出，列上下游、源码 / 细节图按钮、已有备注。
- **放哪一侧**：在节点四周 8 个候选位置里挑「压住的东西最少」的，压住选中节点代价 ×50、高亮的上下游节点 ×1、边标签 ×0.5；
  一样好时偏好右侧。平移缩放、打字时**不换边**（只在原来那侧压住节点时才重选），否则卡片会乱跳。
- 节点移出视野卡片就收起，正在写备注时除外。**拖标题栏可以钉住**，钉住后标题栏出现 `↺` 回到节点旁；换图时清掉。
- 平时只列已有备注，按 `n` 或点按钮才展开输入框，`Esc` 收起。字号整体放大到 20px，长路径另起一行小字（可选中复制），不撑破卡片。
- **没保存的备注是草稿，不会丢**：按「文件 + 节点」记在内存里，切走节点、`.mmd` 被外面改了自动刷新都还在，
  光标位置也保留。如果编辑期间文件里的备注被别人（比如 AI）改了，会提示「保存会覆盖」，可以一键改用文件里的。

**等宽字体为什么要重画整张图**：mermaid 排版时按字体量字宽，只换 CSS 字体会让文字溢出框。所以切字体时先
`document.fonts.load` 把字体备好，再用新字体重新 `mermaid.initialize` 并重画。

**横向 / 竖向**（2026-10-13 加）：arch-map 出的图都是 `flowchart LR`，但有人习惯从上往下读，
所以方向做成查看器里的个人偏好，而不是写死在图里——同一份 `.mmd` 各看各的，git 里不会来回改方向。
实现是渲染前改写喂给 mermaid 的文本：找到 `flowchart` / `graph` 那一行（跳过 frontmatter 和 `%%` 行），
和想要的方向不一致时整张图**转置**：顶层和每个 subgraph 的 `direction` 一起横竖互换（`LR↔TB`、`RL↔BT`），
子图相对主轴的关系就不变。只换方向词、不增删行；选中的节点和备注草稿都保留，视图重新适应窗口。
只对流程图有效，时序图等其他类型下拉框变灰、按 `d` 只提示。`mmd` 出的静态图不受影响，仍按文件写的方向。

**第二轮优化**（2026-10-13，方案和讨论记录在 `docs/plans/2026-10-13-mmd-view.md`）。先测过性能：扫文件不到 2 ms、
首次打开 363 ms、重画 74 ms、平移每帧 0.03 ms，都没有瓶颈，所以这一轮只做了下面四件事：

- **防遥控**：原来伪造 `Host` 请求 `/api/files` 也返回 200，跨站 `text/plain` POST 到 `/api/note` 不触发预检、照常解析。
  也就是说，普通浏览器里打开的任何网页，扫到端口后都能往 `.mmd` 写 `%% @note`；而 `/arch-design` 会把备注当需求处理，
  这就成了往 AI 指令里注入内容的通道。现在所有请求只认 `Host: localhost/127.0.0.1:<端口>`（挡 DNS rebinding），
  `/api/*` 还必须带 `X-MMD-View: 1` 头（跨站请求带自定义头要先过 CORS 预检，服务不回 CORS 头，浏览器就拦下了），页面里统一走 `api()` 发请求。
  `/api/events` 例外：EventSource 加不了自定义头，它只读、没有副作用。实测伪造 Host、不带头、跨站 POST 都是 403。
- **单实例**：已经开着的窗口，只要它的目录包含这个文件（打开目录时要求是同一个目录），双击就交给它：
  页面跳过去（改 hash，`Alt+←` 照样能回来），窗口切到前台。实测转交 59 ms。实例登记在 `$XDG_RUNTIME_DIR/mmd-view/<端口>.json`
  （目录、端口、pid、窗口地址），服务退出时删除，进程已经死了的残留登记在查找时清掉。
  ⚠ **认窗口靠地址，不靠标题**：启动 Chrome 前后各取一次 `hyprctl clients`，多出来的那个 `chrome-localhost__-Default` 窗口就是。
  不同项目的图都叫 `00-overview.mmd`，按标题会认错（实测时桌面上就同时开着两个标题都是 `00-overview.mmd` 的窗口）。
  窗口刚关、服务还在 8 秒退出缓冲期里时，`/api/goto` 回 409，这次双击就新开一个窗口。
  连着双击两个文件时，第一个窗口的页面可能还没连上来，`/api/goto` 会等它最多 10 秒，免得白白多开一个。
  `--no-browser` 调试模式不参与登记和复用。
- **返回恢复**：离开一张图时按「文件 + 横/竖」记下视野、选中的节点、是否展开了整条链，回来时恢复，信息卡也重新弹出。
  横竖分开记，因为横竖一换，视野坐标就对不上了。只存在页面内存里，刷新页面就清空。
- **导出**：在浏览器里完成，不绕回 `mmd`：克隆当前 SVG → 画到 canvas → PNG。实测 foreignObject 不会污染画布，
  手写字体照常保留。**所见即所得**：范围是窗口里看得到的那块（按舞台四角换算成 SVG 坐标；不用 `view`，因为
  `preserveAspectRatio` 会在一个方向上多露出一截），高亮、变暗、黄点都保留；信息卡、顶栏是界面，不进图。
  高亮样式原来写在页面 CSS 里、还用了 `var()`，SVG 单独当图片渲染时这些都没有，所以单独放进 `<style id="hl-css">`，
  导出时把 `var()` 换成实际颜色再塞进 SVG，页面和导出共用这一份样式。
  分辨率是舞台的 2 倍（同 `mmd -s 2`），超过 Chrome 画布上限就自动降低倍数。只出 PNG：SVG 不嵌字体（见上面坑 3）。
  剪贴板和存文件各报各的结果，一边失败不影响另一边。

**备注**存成 `.mmd` 末尾的 `%% @note <节点id|*> <一行>`，一行一条，`Ctrl+Enter` 保存。有备注的节点右上角有个黄点。
它跟着 git 走，arch-map / arch-design 都会读：arch-map 只保留不删，arch-design 会把它当作反馈来改图，你确认后再清掉。

`.mmd` 改了会自动重画，并保留当前的缩放位置。有语法错误时**留着上一版图**，只在左下角报错，
所以可以一边让 AI 改、一边盯着看。

节点和源码的对应关系写成 Mermaid 注释，静态出图（`mmd`）不受影响：

```
%% @src  api  src/order.py def create_order   ← 路径相对 git 仓库根，后面是锚点
%% @link api  order-detail.mmd                ← 路径相对当前 .mmd
```

**锚点而不是行号**：锚点是定义那一行里的一段文字，打开时现场找行号。2026-10-13 实测，
代码顶部加一行 import，用行号写的 `@src` 就全部错位了，而且大多落在非空行上，看不出错。
旧写法 `路径:行号` 仍然认，但 arch-map 的 check.py 会把它当错误报出来。

**跳源码时复用已开着的 nvim**：每个 nvim 都会在 `$XDG_RUNTIME_DIR/nvim.<pid>.0` 自动开 socket。
mmd-view 逐个问 `getcwd()`，找工作目录在本项目里的那个，用 `--remote-expr luaeval(...)` 让它在一个
「普通文件、非浮动」的窗口里打开，不会占掉终端或浮动窗。然后顺着进程树找到它所在的终端窗口，
用 `hl.dsp.focus({ window = hl.get_window("address:…") })` 切到前台。nvim 在 tmux 里的话，先 `select-window` / `select-pane`，
再切 tmux 客户端所在的 kitty。找不到才新开 `kitty nvim`，它的工作目录就是项目根，下次就会被复用。
**挑哪个 nvim**（2026-10-13 定）：① 工作目录在本项目里的；② 没有的话，就用开在终端窗口里的那个 nvim，
不管它的工作目录在哪；③ 都没有才新开。用户的用法是平时只开一个 kitty，里面就是 `kitty.conf` 里 `shell nvim` 起的那个 LazyVim，
图上点代码就该在它里面打开。② 要求开在终端窗口里，是为了排除插件、脚本起的无头 nvim。
（曾误以为用户要 kitty 的 `--single-instance` 模式并改了 `TERMINAL = "kitty -1"` 和远程控制，当天就撤回了：
用户说的「单实例」是「只开一个 kitty 窗口」，用不上这两样。那次顺带实测到的两件事留作参考：单实例下 swallow
吞的仍是当前聚焦的窗口；新窗口用的是启动它那一刻的环境变量和目录。）
文件落在第一个「普通文件、非浮动」的窗口里。用户的三个 tab 按角色分（Claude Code / 代码 / shell），
只有「代码」tab 有普通文件窗口，所以会自然跳到那里，不会占掉终端。
同一档里有多个候选时，依次比：已经打开了这个文件 > 工作目录更深 > 所在窗口最近用过（`focusHistoryID`）。
本机 kitty 没开 `single_instance`，每个 kitty 都是独立进程，顺着进程树找到的窗口是唯一的。

**为什么 ② 可行：LSP 按文件路径找项目根，不看 nvim 的工作目录。** 实测在工作目录是 `~` 的 nvim 里打开
`~/ccmon/app.py`，pyright 的 root 是 `/home/david/ccmon`。对 `Board.build` 做 call hierarchy，
incoming 得到 `run`，outgoing 跨文件得到 `ccstatus.py` 里的 `refresh_from_files` / `group_agents` 等，
和架构地图里的那张流程图一致。于是跳过去之后：`gai` / `gao` 看调用方 / 被调用方（LazyVim snacks picker 自带），
`gd` / `gr` 看定义 / 引用，`<leader>ss` 看本文件符号，`<leader>fm` 在这个文件所在的目录里开 mini.files。
⚠ `<leader>e` 开的是 nvim 工作目录（`~`），跨项目时要用 `<leader>fm`。
⚠ 已知限制：nvim 在某个 kitty 的**后台标签页**里时，切到那个窗口后标签页不会跟着切，
因为切 kitty 标签页要开 kitty 远程控制（`allow_remote_control` + `listen_on`），本机没开。
⚠ `luaeval` 只收表达式，多行 Lua 要包成 `(function() … end)()`，不然报 `unexpected symbol near 'local'`。

**选中时只让轮廓发光**：手绘节点的 `.label-container` 里，第一条 path 是斜线填充，其余是轮廓。
早先给整个节点加 `drop-shadow`，每根斜线都跟着发光，压住文字（用户反馈「好看但影响视线」）。
现在选中时斜线淡到 25%，只给轮廓变色、发光。

结构：`bin/mmd-view` 是 Python 标准库写的小服务（只绑 127.0.0.1，端口随机），
页面在 `~/.local/share/mmd-view/viewer.html`，用的是 mermaid-cli 自带的那份 `mermaid.min.js`（12.1），
配置复用 `~/.config/mermaid/config.json`，所以和 `mmd` 出的静态图长得一样。
Chrome 用独立 profile `~/.local/share/mmd-view/chrome-profile`，要带 `--password-store=basic`，原因同 Excalidraw 坑 00。

**三个坑：**

**1. URL 用 `localhost`，不用 `127.0.0.1`。** `--app` 窗口的 class 由主机名决定，不含端口。
用 127.0.0.1 会和 Excalidraw 撞成同一个 `chrome-127.0.0.1__-Default`，任务栏图标会认错。
现在的 class 是 `chrome-localhost__-Default`（2026-10-13 用 `hyprctl clients` 实测）。

**2. 「窗口关了服务就退」靠 SSE 长连接判断，不靠心跳。** Chrome 会把后台窗口的定时器限流到一分钟一次，
靠心跳判断的话，图挂在别的桌面上服务就会误退。现在的做法是：页面一直开着一条 `/api/events` 连接（顺便用来推送刷新），
服务每 2 秒写一次 ping，写失败就说明窗口关了，再等 8 秒（给刷新页面留余量）就退出。
从没有页面连上来过的话，60 秒后退出。实测关窗约 12 秒后进程消失。
不用 Excalidraw 那种「chrome 阻塞到关窗」的办法，因为同一 profile 开第二个窗口时 chrome 会立刻返回。

**3. `.mmd` 系统默认识别成 `text/plain`**，直接关联的话会把所有纯文本都抢走。
所以用 `share/mime/packages/mermaid.xml` 自定义了 `text/vnd.mermaid`（继承 text/plain，文本编辑器照样能打开），
装完要 `update-mime-database ~/.local/share/mime`（`mod_ui` 已代劳）。
验证用 `kmimetypefinder x.mmd` 或 `gio info -a standard::content-type x.mmd`。
**别用 `xdg-mime query filetype`**：Hyprland 下它退回到 `file` 按内容猜，永远报 text/plain，和 Dolphin 实际看到的不一样。
desktop 条目**不能写 `NoDisplay=true`**，否则 Dolphin 的「打开方式」里没有它（imv 踩过的同一个坑）。
`MimeType` 里加了 `inode/directory` 只是为了出现在文件夹的「打开方式」里，默认打开文件夹的仍是 Dolphin。

## ADB 无线连接（2026-10-10）

手机打开「开发者选项 → 无线调试」，在启动器里搜「ADB」/「无线调试」点一下，就会连上，
通知里会显示连上了哪台设备。不用再去手机上抄 `IP:端口`，手动跑 `adb connect`。

为什么能省掉抄端口这一步：无线调试的**连接端口每次开关都会变**，但手机开着无线调试时
会用 mDNS 广播 `_adb-tls-connect._tcp` 服务，里面就带着当前的 IP 和端口。
`bin/adb-wifi` 用 `avahi-browse -rtpk` 读出所有广播，挨个 `adb connect`。
同一 IP 下端口已经变了的旧条目会留在 `adb devices` 里显示 offline，脚本会先 `adb disconnect` 掉。

**配对只需一次**（密钥记在手机的「已配对设备」里）。第一次用时，在手机上点「使用配对码配对设备」，
然后在终端跑 `adb-wifi pair`。配对端口也是脚本自动找的（`_adb-tls-pairing._tcp`），只需要输 6 位码。

### 两个坑

**1. 发行版的 adb 不支持 mdns。** android-tools 37.0.0（CachyOS 打的包）编译时没带 mdns，
`adb mdns check` / `adb mdns services` 都报 `mdns is not supported by this version of adb`，
设 `ADB_MDNS_OPENSCREEN=1` 也没用。所以按 Google 文档的写法，「配对过的设备会被自动连上」在这里不会生效，
只能另外用 avahi 发现设备。avahi-daemon 本来就在跑，本机也没有防火墙挡 5353/UDP（见 `docs/12`）。
如果以后换成 Google 官方的 platform-tools，可以改回 `adb mdns services`。

**2. adb server 会被启动器带走吗？不会。** 脚本有可能是第一个调 adb 的，这时 adb server 就由它 fork 出来。
elephant 用 `uwsm app` 拉起程序，默认放在 **scope** 里。脚本退出后 scope 里还剩 adb server，
scope 不会因此被停掉，server 也就保住了。如果以后把启动方式改成 service 类型
（`app2unit -t service` 之类），主进程一退出 systemd 就会把 server 一起杀掉，
表现是「通知显示连上了，转头 `adb devices` 是空的」。

## KDE Connect：和手机免确认互传（2026-10-13）

自己的手机和电脑之间互传文件、同步剪贴板，**两边都不用点确认**。
给同事传东西照旧用 LocalSend（每次要对方点接受，这正是想要的）。

- **电脑 → 手机**：Dolphin 里右键文件 →「发送到手机」（可多选）。走 `bin/send-to-phone`，
  发完弹通知；手机不在线也弹通知，不排队。手机收到的文件在「下载」目录。
- **手机 → 电脑**：任意 App 里「分享 → KDE Connect → 电脑」，直接落到 `~/Downloads`。
- **剪贴板**：电脑复制完，手机上直接能粘贴。反方向见下面坑 1。

配对只做一次（手机装 KDE Connect，同一 Wi-Fi 下双方确认）。之后这台设备一直被信任，
这层「契约」就是 LocalSend 没有的东西。

### 为什么是它

比过 LocalSend、Valent、Warpinator、Syncthing 等。LocalSend 1.15+ 其实有「仅收藏设备快速保存」，
能免掉接收确认，但发送端仍要选文件、选设备、点发送。**Valent**（GSConnect 作者写的 GTK 版，
协议和 KDE Connect 兼容）是给 GNOME 用户准备的，放在这台机器上全是短板：只有 AUR、要编译，
2026-10 时还是 alpha（最后一次发版 2025-11）；没有 Dolphin 集成；GTK 程序在非 GNOME 的
Wayland 下不在前台就读不到剪贴板。KDE Connect 在官方仓库，Dolphin 本来就拉进了大半 KF6，
剪贴板走 wlr data-control 协议，Hyprland 下后台也能同步。

### 插件只留 5 个

电脑端 `~/.config/kdeconnect/<设备ID>/config` 的 `[Plugins]` 段里，只开
`share`（互传）、`clipboard`、`sftp`（在 Dolphin 里浏览手机存储）、`ping`、`findmyphone`，
其余全部写 `false`。尤其是 `runcommand` / `remotecommands` / `mousepad` / `remotekeyboard` /
`lockdevice` 这几个，开着等于让手机能远程操作电脑。改完要重启 `kdeconnectd`
（`kill` 掉，任意一次 D-Bus 调用会把它重新拉起，比如 `kdeconnect-cli -l`），
并且**先关掉 `kdeconnect-app` 设置窗口**，否则它可能把旧状态写回去。
这份配置绑死设备 ID，**不入包**，新机器重新配对后照这段手工关。
手机端 App 里也有一份插件开关，同样只留对应的几个，不然手机一直推电池、信号、媒体包，
电脑全部丢弃，纯属白耗电。

### 四个坑

**1. 手机 → 电脑的剪贴板做不到全自动。** Android 10 起后台 App 读不到剪贴板，所有同类软件都一样。
只能在手机上手动推：KDE Connect 常驻通知里的「发送剪贴板」，或下拉快捷开关里的 KDE Connect 磁贴。

**2. 自启靠 uwsm，不用自己写 `exec-once`。** 包里带了 `/etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop`，
uwsm 会把它生成为 `app-org.kde.kdeconnect.daemon@autostart.service`。刚装完的那次会话里还没有这个 unit
（`daemon-reload` 之后才生成），当时的 `kdeconnectd` 是被 `kdeconnect-app` 经 D-Bus 顺带拉起的，
所以别拿「没开 App 时手机发不过来」当作故障，重新登录就好。

**3. servicemenu 的 Exec 必须写绝对路径，文件必须带可执行位。** Dolphin 的 PATH 里没有
`~/.local/bin`；KF6 不认没有可执行位的用户目录 servicemenu（同 `arch-map.desktop`）。
这两件事 `mod_ui` 都会处理（`rewrite_home` + `chmod +x`）。

**4. 手机端会被杀后台。** iQOO 这类国产 ROM 后台管理很激进，手机端要给 KDE Connect 开「允许后台高耗电」和自启动，
不然过一阵就「手机不在线」。

## Discord：Equibop + system24 主题

已独立成 `discord` 模块，全文在 `docs/15-discord.md`（选型、主题改了哪几处、自写补丁主题、两台机器怎么同步）。
这里只记和本篇相关的一点：主题字体换成了终端同款 `Adwaita Mono`，中文同样按本篇的 fontconfig 规则回落到更纱黑体。

---

## 已删掉的死配置

`~/.config/qt5ct/` 和 `~/.config/xsettingsd/` 在原机器上存在，但 `qt5ct` 和
`xsettingsd` 这两个程序**根本没装**——纯 skel 残留，改它们不产生任何效果。
本包没有收录，避免误导。

---

## 壁纸

当前壁纸：`~/Pictures/Wallpapers/tokyonight/D-ASCII/a1-紫调少女.png`
——即下面 `_ascii.py` 拿 `A-最搭/11-w55gjr.png`（紫调少女 · 黑底，纯黑底 + 淡紫人物
≈ `#bb9af7`，极简居中构图）生成的 ASCII 版本。主色 `#1A1B26`，占绝大多数像素。

> 真实生效路径以 `~/.local/state/noctalia/settings.toml` 的 `[wallpaper.monitors.*]`
> 为准（同 CLAUDE.md 坑 1：state 那份才是真的）。

⚠ **换壁纸时别忘了 `config/hypr/config/misc.lua` 的 `background_color`** ——
它取的是当前壁纸主色，用来消除开机时那 1.5 秒的内置壁纸闪烁。换了色系就要重新采样：

```bash
magick 新壁纸.png -colors 5 -format '%c' histogram:info: | sort -rn | head -1
```

**为什么需要它**（noctalia 是「盖」壁纸不是「设置」壁纸，底下压着 Hyprland 内置图）
见 `docs/02-hyprland.md`「开机时先闪一张陌生壁纸」与 CLAUDE.md 坑 15。

本包带了这一张（508 KB）+ 4 张 ASCII 成品（`wallpaper/ascii/`，2.1 MB，装到
`D-ASCII/`）。完整壁纸库 77 张 / 167 MB，太大，用脚本重新拉。

> ASCII 那 4 张是本包 `_ascii.py` 自己的产出，本来可以重生成——但**重生成依赖
> wallhaven 上的源图还在**，那个不可控，所以直接带成品兜底。

### 多主题一键切换（主题领导壁纸，非壁纸领导主题）

`bin/theme-switch`：按 `Super+Shift+T` 循环切换「精选主题」。每个主题 =
**人工精选的同调壁纸目录** + **官方社区调色板**（不是壁纸自动抽色）。

理念：让 noctalia 用`wallpaper` 抽色模式实时跟图换色是「壁纸领导主题」——但动漫平涂稿抽出来
往往偏成傻瓜色，很难保持 Rose Pine / Everforest 那种克制的高级灰调。所以反过来用
`community` 模式钉死调色板（色相克制、明度统一、作者精调），壁纸只负责视觉氛围。

| 主题 | 壁纸目录 | 调色板 | 匹配画面 |
|---|---|---|---|
| tokyonight | `~/Pictures/Wallpapers/tokyonight` | Tokyo Night Moon | 夜景、蓝紫调、雨夜霓虹 |
| rosepine | `.../rosepine` | Rose Pine Moon | 薰衣草紫天空、蓝调时刻、暖光室内 |
| everforest | `.../everforest` | Everforest（自定义 JSON） | 森林、苔藓、吉卜力乡村、治愈系 |
| dracula | `.../dracula` | Dracula（自定义 JSON） | 赛博朋克夜城、霓虹灯箱、紫粉青绿 |
| oxocarbon | `.../oxocarbon` | Oxocarbon | 冷白蓝灰、清冷克制 |

原理（每一步都是 IPC，改的是 `~/.local/state/noctalia/settings.toml`，即真相源）：

```bash
noctalia msg color-scheme-set community <名>   # 钉官方调色板
noctalia msg wallpaper-set <图>                # 设壁纸（持久到 default/monitors）
noctalia msg templates-apply                   # 渲染 gtk/kitty/btop/qt/alacritty
noctalia msg config-reload                     # 刷新 bar
noctalia msg greeter-sync                      # 锁屏配色同步
```

调色板是 `~/.local/state/noctalia/community-palettes/*.json`（`{dark,light}` 两档结构，
terminal.normal/bright 一套）。本包新加了 `Everforest.json`、`Dracula.json` 两个，
其余沿用社区自带。**自定义调色板照抄 `Rose Pine Moon.json` 的结构即可**，
关键 6 个 Material 键（mPrimary/mSecondary/mTertiary/mSurface/mSurfaceVariant/mOnSurface）
决定 bar 与 GTK 观感，terminal 段决定 kitty/btop。

加新主题三步：
1. `mkdir -p ~/Pictures/Wallpapers/<slug>/` 放精选壁纸（可带子目录，脚本递归取图，循环轮换）
2. 放 `.json` 到 `community-palettes/`（并在 `cachyOS-config/state/noctalia/community-palettes/` 同放一份供 install）
3. 在 `bin/theme-switch` 的 `THEMES` 数组加一行 `slug|Palette Name`，

⚠ **切主题会覆盖 `misc.lua` 的 `background_color` 的对齐值**——换了色系记得重新采样
（见上 `magick ... histogram` 命令），否则开机仍会闪一下内置壁纸。

## 壁纸库的生成管线

`wallpaper/tokyonight/` 下四个脚本：

| 脚本 | 作用 |
|---|---|
| `_fetch.py` / `_fetch2.py` | 按 Tokyo Night 调色板从 wallhaven 搜壁纸，结果存 `_picks*.json` |
| `_build.py` | 生成 `index.html` 预览页（带中文点评，按贴合度分 A/B/C/D 档） |
| `_ascii.py` | 把图片转成 Tokyo Night 配色的 ASCII art 壁纸（4K） |

`_fetch.py` 的筛选口径：以 Tokyo Night night/storm/moon 三个变体共通的 14 个色值
（`1a1b26` `24283b` `222436` `1f2335` `414868` `7aa2f7` `bb9af7` `7dcfff` `2ac3de`
`9ece6a` `c0caf5` `565f89` `f7768e` `9d7cd8`）为基准，用 wallhaven 支持的最接近的
5 个 seed 颜色去搜，再按色距重排。

`_fetch2.py` 修了第一版的一个偏差：**纯黑白图在 Lab 空间里离 `#1a1b26` 很近，会被误判成
"很搭"**，但它们只是暗，不是 Tokyo Night 的靛蓝紫调。所以加了两条惩罚——画面里没有
蓝紫色相（HSV hue 0.55–0.80）+22 分，整体彩度 < 12 再 +18 分。

重建：

```bash
cd ~/Pictures/Wallpapers/tokyonight
python _fetch.py && python _fetch2.py    # 拉图（需要网络）
python _build.py                          # 生成 index.html，浏览器打开挑
python _ascii.py                          # 重生成 D 档（约 4 秒）
```

分档目录：`A-最搭`（8 张）· `B-可选`（9）· `C-暗调单色`（8）· `D-ASCII`（12）·
`其他`（5）· `全部-软链`（37 个软链汇总）· `thumbs`（缩略图）。

> `全部-软链/` 是给 noctalia 壁纸面板用的——**它不递归扫子目录**，所以把好图平铺软链
> 到一层。面板目录指这里就能全看到；只想要最搭的就指 `A-最搭/`。

---

### `_ascii.py`：ASCII art 壁纸生成

依赖 **`imagemagick` + `librsvg`**（都在 `packages.txt`）。管线：

```
magick 裁切/降采样 → PPM → 字符映射 + Lab 调色板吸附 → SVG → rsvg-convert → PNG
```

每个字符在 SVG 里**显式指定 x 坐标**，不依赖字体 advance，网格必然对齐——这样换字体
也不会错位。默认 `MesloLGS Nerd Font Mono`、3840×2160、320 列。12 张约 4 秒。

底部 `JOBS` 是 kwargs 形式，加图就加一行：

```python
("A-最搭/27-vpe31p.jpg", "b1-霓虹房间", RAMP70, PALETTE,
 D(gamma=.72, boost=1.30, floor=.12, sig=4, cols=360, edge=.72,
   crop="2048x1152+3560+880")),
```

#### 四条调参经验（2026-08-26 试出来的，重装后别再踩一遍）

**1. `floor`（留白阈值）是观感的总开关。**
低于阈值的像素直接留空。`-auto-level` 会把纯黑背景抬起来，导致每个像素都够格分到一个
字符、满屏噪点（实测字符占屏能到 99%）。配合 `floor` 0.2–0.32 才干净。想更空就往上调，
想更满就往下。

**2. 颜色明度必须重映射到亮端**（`build_snap` 的 `lmin=46, lmax=94`）。
字符疏密已经负责表达结构了，颜色再跟着源像素一起变暗，暗部字符就几乎看不见、整张糊成
一团。正确做法是：**色相取自源像素，明度统一推到亮端**。

**3. 源图要选主体清楚、背景大片黑的。**
满构图的场景图转出来很吵。留白率高的（`a9-剪影极简` 0.7%、`a1-紫调少女` 2.7%）最耐看。

**4. 柔光插画必须开 `edge` 通道 —— 这条最容易白费时间。**
ASCII 只有"亮度"一个维度可用。白衣白发的人物站在浅色房间里，主体和背景挤在同一个亮度
带，**靠亮度根本分不开**：提列数（320→560）、拉阈值、加 unsharp 全部无效，而且越提越糊。
解法是改用 `-edge` 梯度幅值图驱动字符密度（`edge=0.72` 左右），轮廓和五官就画得出来了，
完全不依赖亮度差。再配合 `crop=` 裁紧构图，让主体占更多字符格。
`b1-霓虹房间` 就是这么救回来的。

反例对照：`a7-黑金属少女` 不需要 edge 通道，因为它本来就是纯黑底上一张白脸，亮度反差极大。

#### 关于 wallhaven 上的 ASCII art

**基本没有。** 用 10 组关键词（`ascii art` / `text art` / `terminal` / `dithering` /
`1bit` …）扫过，`ascii art` 只返回 7 条结果，人工看完 14 张候选只有 2 张能用
（`c1-点阵少女` `c2-网点少女`，已收在 `D-ASCII/`）。这个题材要自己生成，别浪费时间搜。

---

## 输入法：fcitx5 + rime

```
Default Layout = us
DefaultIM      = rime
```

`config/fcitx5/` 带了 `profile`（输入法组）、`config`（快捷键）、
`conf/notifications.conf` 和 `conf/classicui.conf`（外观）。
**rime 的词库和方案（`~/.local/share/fcitx5/rime/`）没有打包**——那是个人积累的数据，
且体积不定，换机时单独拷。

新机器上要让它在 Wayland 下正常工作，确认这些包都在：
`fcitx5` `fcitx5-rime` `fcitx5-gtk` `fcitx5-qt` `fcitx5-configtool`。
GTK/Qt 应用走对应的 im-module，Electron 应用靠 `ELECTRON_OZONE_PLATFORM_HINT=auto`
（已在 `uwsm/env`）。

### 候选框外观：`share/fcitx5/themes/tokyonight/`

装到 `~/.local/share/fcitx5/themes/tokyonight/`，由 `conf/classicui.conf` 的
`Theme=` / `DarkTheme=` 指向。默认主题在一整套 Tokyo Night 桌面里非常扎眼，
这个主题是为了消掉那个突兀感。

![预览](img/preview.png)

配色取 Tokyo Night，底色对齐 noctalia 的 `#1a1b26`（不是 Storm 的 `#24283b`）：

| 元素 | 色值 |
|---|---|
| 面板底 / 描边 | `#1a1b26` · `#414868` |
| 候选词 | `#c0caf5` |
| 序号 · 注释 | `#565f89`（压暗，减少干扰） |
| 选中胶囊 / 其描边 | `#3d59a1` · `#7aa2f7` |
| 选中项序号 | `#7dcfff` |
| 编码区高亮段 | `#7dcfff` on `#292e42` |

**PNG 是生成物，别直接改**。改 `.src/*.svg` 后跑 `.src/render.sh` 重建
（需要 `librsvg`）。`--preview` 参数会连 `docs/img/` 下的配图一起重生成。
9-patch 的 `Margin` 和 SVG 的圆角半径是配套的，改圆角要同步改 `theme.conf` 的 Margin。

#### theme.conf 的三个坑（fcitx5 5.1.21 实测）

1. **`Optional|Color` 类型的选项必须写成子小节 + `Value=`**，直接 `Key=#rrggbb`
   会被静默丢弃、既不报错也不生效。受影响的是这四个：
   ```ini
   [InputPanel/CandidateLabelColor]
   Value=#565f89
   ```
   （`CandidateLabelColor` / `HighlightCandidateLabelColor` /
   `CandidateCommentColor` / `HighlightCandidateCommentColor`。根因是
   fcitx5 把 `std::optional<T>` 序列化到 `config["Value"]` 子节点。）
2. **`LabelTextSizeFactor` / `CommentTextSizeFactor` 是整数百分比**
   （默认 100，范围 0–400）。写 `0.88` 会被解析成 `0`，序号和注释直接变零字号消失。
3. `[InputPanel]` **没有** `Spacing`（只 `[Menu]` 有）；
   `VerticalCandidateList` 在 5.1.21 的 classicui 里已不存在。

#### 验证与热重载（不用重启 fcitx5，也不用开 GUI）

```bash
# 改完配置让它立刻生效
gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
  --method org.fcitx.Fcitx.Controller1.ReloadAddonConfig "classicui"

# 看解析后的【生效值】+ 每个选项的类型描述 —— 判断「键名对不对 / 值有没有被吃掉」的唯一可靠手段
gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
  --method org.fcitx.Fcitx.Controller1.GetConfig \
  "fcitx://config/addon/classicui/theme/tokyonight"
```

注意 `/config/addon/classicui` 这个 dbus 对象路径**不存在**，只能走 `/controller`
的 `GetConfig`。`install.sh ui` 结尾会自动执行上面第一条。

### `conf/classicui.conf` —— 字体与两个必关的开关

```ini
Font="MesloLGS Nerd Font,Sarasa Gothic SC,Noto Sans CJK SC 13"
```

**逗号回退链**：Nerd Font 没有汉字字形，必须把中文字体显式列在后面，
Pango 会按顺序逐字回退。结果是拼音编码区和序号走 Meslo（跟终端同一个调子），
汉字走更纱 / Noto。字体在这个文件里，**不在 theme.conf 里**。

两个开关值得单独说：

- **`UseAccentColor=False`** —— 开着的话桌面强调色会覆盖主题的边框和选中色，
  正是「输入法看着不搭」的一大来源。
- **`UseDarkTheme=False`** + `Theme` 和 `DarkTheme` 都指向 `tokyonight` ——
  防止系统在明暗配色方案间切换时跳回默认主题。
