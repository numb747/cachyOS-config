# ~/cachyOS-config —— 桌面配置的单一事实来源

> **新会话读这一份就够。** 这里是本机（CachyOS + Hyprland）全部桌面配置的归档、文档与
> 安装器。要改配置、要迁到别的机器、要查「当初为什么这么设」，都从这里开始。

```
~/cachyOS-config/                   ← 仓库根 = 配置包本体（github.com/numb747/cachyOS-config）
├── CLAUDE.md                 ← 你在这（本文件是给 AI 会话的导航）
├── README.md                 人读的总览（GitHub 首页渲染的就是它）
├── INSTALL.md                新机器从零到可用 + 验收清单
├── LICENSE                   MIT + 第三方内容（壁纸/LazyVim）归属声明
├── manifest.map              ★ 文件映射表：包内路径 ⇄ 系统路径（单一事实来源）
├── install.sh                包 → 系统（幂等、分模块、自动备份）
├── sync.sh                   系统 → 包（把线上改动收回来）
├── uninstall.sh              回滚
├── packages.txt              pacman 包清单
├── MANIFEST.txt              sha256 校验（由 sync.sh 生成，只覆盖入库文件）
├── docs/                     11 篇，见下表（配图在 docs/img/）
├── config/ home/ state/      配置文件本体
├── bin/                      装到 ~/.local/bin/ 的脚本（hypr-screenrec 录屏、winapp wine 沙箱、ocr-* 屏幕取字）
├── claude/                   装到 ~/.claude/ 的 Claude Code 工具（看板/宠物 TUI/状态栏）
├── share/                    装到 ~/.local/share/ 的东西（fcitx5 主题、imv 的 desktop 条目）
├── aur/                      改过才能装的 AUR 包（PKGBUILD 归档，不装到 $HOME，不走 manifest）
├── wallpaper/                参考壁纸 + ASCII 成品 + 壁纸库生成脚本
└── .snapshots/               sync.sh --pack 的 tar.gz 产物（不入 git）
```

> 2026-08-27 起**没有 `cachyos-desktop-config/` 这层中间目录了**，仓库根就是包本身。
> 三个脚本都靠 `BASH_SOURCE` 自定位，扁平化对它们透明；唯一改过的是 `sync.sh --pack`
> （原逻辑是「打包上一级里的那个包目录」，扁平后会把 `.git` 和 `$HOME` 同级内容一起卷进去）。
>
> 2026-08-28 目录由 `~/ccconfig` **改名为 `~/cachyOS-config`**，与远程仓库名对齐。
> 同样靠 `BASH_SOURCE` 自定位，脚本零改动。改名时要跟着动的只有四处硬编码：
> `bin/winapp` 的沙箱抽查清单、`config/winapp/wecom.conf` 注释、`README.md` 的 clone 示例、
> 本文件——**`config/hypr/patches/*.patch` 里的绝对路径不用管**，`sync.sh --pull` 会重生成。
> 另外 `~/.claude.json` 的 `projects` 键是按绝对路径索引的，改名后需手动迁移键名，
> 否则 Claude Code 把新路径当陌生目录（重弹信任对话框、丢 `allowedTools`）。

---

## 改配置的正确姿势

**改线上文件，不要改包里的文件。** 包是快照，线上是本体。

```bash
# 1. 正常改 ~/.config/... 下的真实配置，验证效果
# 2. 收回包里（自动重生成 MANIFEST 和 hypr patch）
cd ~/cachyOS-config && ./sync.sh --pull
# 3. 把「为什么这么改」写进对应的 docs/ —— 这一步最容易漏，也最值钱
```

其他常用：

```bash
./sync.sh              # 只看哪些文件漂移了（默认，不写任何东西）
./sync.sh --diff       # 逐个打印差异
./sync.sh --pack       # pull 之后再打 tar.gz，准备拷去别的机器
./install.sh --dry-run # 装之前先看会做什么
./install.sh hypr nvim # 只装指定模块（--list 看全部）
```

**新增一个要纳管的配置文件**：只改 `manifest.map` 一行，三个脚本自动跟上。

---

## 文档索引 —— 按你要解决的问题找

| 我想… | 看 |
|---|---|
| 装系统本身（Ventoy / 镜像 / CachyOS 取舍 / 动态壁纸） | `docs/00-install-os.md` |
| 搞懂各部分怎么咬合、有哪些设计原则 | `docs/01-architecture.md` |
| 改快捷键、窗口行为、工作区 | `docs/02-hyprland.md` |
| 改终端 / zsh / 提示符 | `docs/03-terminal.md` |
| 改 nvim | `docs/04-neovim.md` |
| 改配色 / 顶栏 / 字体 / 壁纸 / 输入法 | `docs/05-theme-ui.md` |
| 忘了某个键是什么 | `docs/06-keymap-cheatsheet.md` |
| 出问题了 | `docs/07-troubleshooting.md` |
| 改 Claude Code 的看板 / 宠物 TUI / 上下文状态栏 | `docs/08-claude-code.md` |
| 在 wine 里跑 Windows 程序 / 企业微信 / 沙箱边界 | `docs/09-wine-apps.md` |
| 屏幕取字（OCR）/ 换掉 normcap 的缘由 / RapidOCR 调参 | `docs/10-ocr.md` |

---

## 十五条会踩的坑（改之前先知道）

1. **noctalia 的主题真实来源是 `~/.local/state/noctalia/settings.toml`**，不是
   `~/.config/noctalia/config.toml`。两边 `[theme]` 段重叠时以 state 那份为准。
   查活配置一律用 `noctalia config export full`，别读配置文件。

2. **配色文件是生成物，手改会被覆盖。** kitty/alacritty/btop/gtk4/qt6ct/kdeglobals 的
   noctalia 配色由模板引擎渲染（`[theme.templates] builtin_ids`）。改配色的入口是
   noctalia 本身。

3. **`hl.bind` 对同一键位是叠加不是覆盖。** 要替换官方键位必须先 `hl.unbind(...)`，
   否则两套并存。`hl.config` 则是逐项合并，只写自己关心的项是安全的。

4. **hypr 有 5 个 CachyOS 官方文件被改过**（`config/` 下的 `binds` / `variables` /
   `workspaces` 为纯动态工作区，`windowrules` 为企业微信幽灵窗，`misc` 为关掉内置壁纸）。
   `pacman -Syu` 可能覆盖回去，用 `config/hypr/patches/*.patch` 重打，
   基准是 `/etc/skel/.config/hypr/config/`。（此前文档记的「3 个」是漏了后两个。）
   **别急着加第 6 个**：只有「要撤销官方已定义的东西」才必须动原版，纯覆盖值一律写进
   `mykeys.lua`（`require("mykeys")` 排在所有 `config.*` 之后，后写的赢），
   多动一个原版就多一份升级后要重打的 patch。终端毛玻璃（`decoration.blur`）就是这么
   处理的 —— `decorations.lua` 至今仍是逐字节原版，见 `docs/02-hyprland.md`。
   ⚠ 顺带两条 blur 的坑，都在 `docs/03-terminal.md`：**kitty 的 `background_blur`
   在本机是死选项**（要 KDE blur 扩展协议，Hyprland 不实现）；模糊归 Hyprland、
   透明度归 kitty 的 `background_opacity`，后者设成 1 模糊会整个消失。
   blur 参数走**「糊透 + 微压暗」**（`passes=4, size=8, vibrancy=0.5, brightness=0.9`），
   刻意做成**换壁纸不用重调**的通用值：认不出原图 = 永远不会有亮块压在代码上，
   氛围靠 `vibrancy` 留色调而非透出图案。⚠ **别再试「降 passes 保留剪影」**——
   2026-08-28 试过 `passes=1, size=13`，对稀疏 ASCII 壁纸好看，换实心插画立刻
   「一张脸压在文字上」。保留结构的方案没法通用。见 `docs/03-terminal.md`。

5. **`vim.opt.shell` 必须设在 `lua/config/options.lua`。** 设晚了 toggleterm 在 spec
   构造那一刻就取走了旧值。

6. **fontconfig：`prepend` 不是插到队首**，是插到「匹配到的那一项之前」；要顶到第一位
   得用 `prepend_first`。且 `<alias>/<prefer>` 无论写在哪都会排到所有 `<match>` 之前，
   顺序敏感时一律用 `<match>`。判断渲染效果看 `fc-match -s`，单结果的 `fc-match` 会骗人。
   详见 `docs/05-theme-ui.md`。

7. **fcitx5 主题里 `Optional|Color` 必须写成子小节 `Value=`**，直接 `Key=#rrggbb`
   静默失效；`*TextSizeFactor` 是**整数百分比**，写 `0.88` 会变成 0（文字消失）。
   改完用 `gdbus ... GetConfig "fcitx://config/addon/classicui/theme/tokyonight"`
   看生效值验证，别靠肉眼。

8. **`hl.dsp.*` 对不认识的参数键静默忽略**，不报错不警告，stub 里全是 `fun(...)`
   查不到类型。已知：`toggle_special` 收**裸字符串且不带 `special:` 前缀**
   （传 table 会静默退回默认工作区）；「不跟过去」的参数叫 **`follow = false`
   而不是 `silent`**。「代码看着对但行为不对」先怀疑参数名。
   另外 `hyprctl dispatch` 在这套 Lua 配置下**只是语法变了，不是失效**（2026-08-27 更正）：
   参数会被当 Lua 解析，所以**传 Lua 表达式就能用**——
   `hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'` 是有效的，拿它在会话里拉起 GUI 进程
   比手动导 `WAYLAND_DISPLAY` 可靠。要跑任意 Lua（而非一条 dispatcher）才用 `hyprctl eval`，
   且 eval 没有返回值/`print`，看结果要自己写文件。详见 `docs/07-troubleshooting.md` 坑 8。

9. **`noctalia msg config-reload` 只重读文件，不重新注册子系统。** 已知踩过两次：
   `[shell.launcher.providers.*]`（provider 不重载）和 `[storage]`（存储不重新初始化，
   2026-08-27）。两次都表现为 `noctalia config export` 显示配置已生效、但行为纹丝不动，
   极易误判成配置写错又去改配置。**改完这类段一律重启进程**
   （`kill $(pgrep -x noctalia); setsid -f noctalia -d`，或
   `hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'`）。
   启动器另外还有个限制：provider 有且只有 `global` / `prefix`
   两个键，**没有** weight/priority/order——「让已开窗口排在应用前面」上游
   [#2470](https://github.com/noctalia-dev/noctalia/issues/2470) 已 closed as not planned，
   别重新调研。用 `noctalia config validate` 当探针枚举合法键名。详见 `docs/05-theme-ui.md`。

10. **改默认打开方式别用 `xdg-mime default app.desktop type1 type2 …`。** 一次传多个类型
    会把它们挤成**一个畸形 key** 写进 `mimeapps.list`（`image/png image/jpeg …=x.desktop`），
    规范要求每行一条，整行静默失效且不报错。要从 `.desktop` 的 `MimeType=` 拆行生成——
    注意 **zsh 不做默认分词**，多行字符串喂 `printf` 只输出一次。
    改 `.desktop` 条目一律**新建文件名**，不要同名覆盖 `/usr/share/applications/` 里的：
    同名是**全量遮蔽**而非字段合并，上游升级新增格式支持时你这份不会同步。
    `Icon=` 还得验证在当前主题里真的存在（imv 上游写的 `multimedia-photo-viewer`
    在 Adwaita 和 breeze 里都没有，菜单里就是空白）。详见 `docs/05-theme-ui.md`。

11. **停 wl-screenrec 必须 `SIGINT`，不能 `SIGTERM`/`SIGKILL`。** 它靠 Ctrl-C 那条路径
    flush 编码器并写 mp4 的 moov atom，杀错信号得到的是播放器打不开的废文件，
    且发完信号要等进程真正退出才算完。AMD 上还要显式 `--low-power=off`
    （Mesa VAAPI 没有 low-power 编码入口）。绑键时**不能**加 `uwsm app --` 前缀，
    否则进程进了另一个 cgroup，`bin/hypr-screenrec` 的 pidfile 就追不上、停不下来。

12. **noctalia 的两处系统集成，报错都指向错误的方向**（2026-08-27，详见 `docs/05-theme-ui.md`）：

    - **换壁纸/主题老要密码**：`greeter_sync` 默认用 `run0` 提权，请求的 action 是
      `org.freedesktop.systemd1.manage-units`，**绕开了** `noctalia-greeter` 包自带的
      `org.noctalia.greeter.apply-appearance` policy。照那个 policy 写 polkit 规则**完全无效**，
      而 `manage-units` 又不能安全放行（run0 的 unit 名随机，放行 = 全局 root 免密）。
      解法：`privilege_command = "pkexec"` 掰回来 + `/etc/polkit-1/rules.d/49-*.rules` 放行。
      **通则：先看 journalctl 里真正被拒的 action id，别照着 policy 文件猜。**
    - **剪贴板历史重启就空**：不是「不支持持久化」，是它**坚持加密后才落盘**、
      主密钥默认取自 Secret Service，而本机没有 provider（日志
      `[secret-store] ... provider-unavailable`），于是降级成仅本会话。
      解法：`[storage] key_source = "file"`，绕开整个 Secret Service，不装 keyring 不改 PAM。
      ⚠ `storage.key` **不入包**（见下方边界），新机器要重新生成，代价是旧历史读不出来。

13. **「弹在顶部的东西」先分清是通知还是 OSD，两个子系统入口完全不同**（2026-08-27，
    详见 `docs/05-theme-ui.md`）。换歌时顶部那个「正在播放」是 **OSD**
    （`[osd.kinds] media`），不是通知，拿 `[notification.filter.*]` 治它**永远无效**。
    **位置就是判据**：本包 OSD 在 `top_center`、通知在 `top_right`。
    `[osd.kinds]` 是**全局**的，noctalia 没有按播放器/按应用关 OSD 的选项。
    通用手法两条，配套用：
    - **有哪些合法键** → `noctalia config validate <file>`，未知键报 `unknown setting`
      但仍返回 valid，拿临时 toml 塞满候选键一次枚举完（坑 9 已用过这招）。
    - **某个键管什么** → `/usr/share/noctalia/assets/translations/en.json`，
      `settings.schema.shell.*` / `settings.notifications.*` 里有 label + description，
      比 `strings` 二进制和官网都可靠（官方文档站该页目前 404）。
    ⚠ 验收别看 `noctalia config export`——那是坑 9 的陷阱，`export` 变了不等于行为变了。
    不过坑 9 是**按配置段**而非全局：`[osd.kinds]` 实测吃 `config-reload`（2026-08-27
    换歌验证过），已知必须重启的只有 `[shell.launcher.providers.*]` 和 `[storage]`。

14. **wine 窗口规则要用 `initial_title`，不是 `title`**（2026-08-27，详见 `docs/09-wine-apps.md`）。
    窗口规则在**创建时**求值，那一刻**所有**窗口的 `title` 都是空的——拿 `title = "^$"`
    去抓国产软件那些空白幽灵窗，会把主窗口一起误伤（当初表现为「整个企业微信点不动、
    鼠标点击全部落空」，往 CEF/GPU/Windows 版本方向查了很久）。`initial_title` 记录
    创建那一刻的标题，才是稳定判据。同段还有三条各自能吃掉半天的：
    - **bwrap 别加 `--unshare-ipc`**：它切断 X11 的 MIT-SHM 共享内存，程序调
      `X_ShmPutImage` 收到 BadValue 直接崩，日志里只有一行 X Error，看不出和沙箱有关。
    - **`--die-with-parent` + 终端启动**：shell 一退出应用就被带走，看着像"随机崩溃"，
      而从桌面启动器起（父进程是 systemd）却一切正常，极易误判。调试用 `setsid --fork`。
    - **杀 wine 进程别用 `pkill -f`**：模式会匹配到正在执行它的 shell 自己（退出码 144），
      排查期间还误杀过 noctalia 导致顶栏和壁纸一起消失。按 `/proc/<pid>/cmdline` 精确匹配。
    ⚠ 还有一条反直觉的：日志里成片的 GPU 报错（`vulkan` 枚举失败、`amdgpu_get_auth failed`、
    `egl dri2 screen` 创建失败）**是噪音**，强制软件渲染并不能解决任何问题。
    `docs/09` 第 6 节专门列了排除掉的错误方向，别再往那查。

15. **noctalia 不是「设置」壁纸，是在 background 层「盖」壁纸**（2026-08-27，
    详见 `docs/02-hyprland.md`「开机时先闪一张陌生壁纸」）。系统里**没有任何壁纸守护进程**
    （无 swww / hyprpaper / swaybg），底下压着的**始终**是 Hyprland 内置的
    `/usr/share/hypr/wall*.png`，从没被换掉。两个表现同一个根因：开机时先闪 ~1.5 秒
    那张陌生壁纸（noctalia 冷启动的空档，长度浮动）；**noctalia 一崩就露出来**
    （坑 14 里 `pkill -f` 误杀后「顶栏和壁纸一起消失」就是它）。
    解法在 `config/misc.lua`：`force_default_wallpaper = 0` + `disable_hyprland_logo = true`
    + `background_color` 取壁纸主色（`magick … -colors 5 … histogram:info:` 采样，
    当前 `rgb(1a1b26)`；**换壁纸换色系要重取**）。
    ⚠ 别去 noctalia 里找「开机壁纸」选项（管不到合成器起来那段），
    也别装 swww 来「提前铺好」（多一个抢 background 层的进程，闪两次）。
    时间线直接读 `~/.cache/noctalia/noctalia.log` 的 `[wallpaper] creating` 行。
    验证一律看 `hyprctl getoption` 的 **`set: true`**——`set: false` 是在报默认值。

---

## 边界：不进这个包的东西

`~/.ssh/` · `~/.gnupg/` · `~/.claude/settings.json`（含明文 token —— ⚠ 只排这**一个文件**，
`~/.claude/` 下的工具脚本由 cc 模块正常纳管，见 `docs/08`）·
`~/.config/noctalia/storage.key`（剪贴板历史的加密主密钥 —— 引用它的
`config.toml` 正常入包，**密钥本身不入**；新机器按 `docs/05` 重新生成即可，
代价只是旧历史读不出来）·
`~/.local/share/fcitx5/rime/`（个人词库）· 壁纸全库（166 MB，只带一张参考图 + 拉取脚本）·
`~/.zsh_history` ·
`~/.local/share/wineprefixes/`（wine prefix，企业微信那个 2 GB+，含聊天记录与登录态；
新机器用 `winapp create/install` 重建，见 `docs/09`）·
`~/.cache/wecom-setup/*.exe`（企业微信安装包 600 MB，官网可重新下）。

换机器时这些走安全渠道单独传。**往包里加文件前先确认不含凭据**：

```bash
grep -rniE 'sk-[a-zA-Z0-9]{16,}|AIzaSy|auth[_-]?token|BEGIN .*PRIVATE KEY' .
```

---

## 现状（2026-09-11）

- 源机器：CachyOS · Hyprland 0.56+ · noctalia v5.0.0 · kitty 0.48.2 · nvim 0.12.5 ·
  zsh 5.9.2 + p10k 1.20.17
- Hyprland 绑定 **121** 条；`hyprctl binds -j | jq length` 可验
  （2026-08-26 加了 5 条截图/录屏键位，此前是 111；更早文档记的 109 是错的。
  2026-08-31 加了 2 条 OCR 键位：116 → 118。2026-09-03 加了 3 条 group 键位
  （先 2 条批量/整组操作，后又补了 `ALT+SHIFT+G` 踢出单个）：118 → 121）
- 截图/录屏/取字：`Print` 系 + `Super+Shift/Alt+P` 截图（落盘 + satty），
  `Super+Shift/Alt+R` 录屏（`bin/hypr-screenrec` 包 wl-screenrec，同键停止），
  `Super+Shift/Alt+O` 取字（见下方 ocr 模块）。
  三套共用一个分工：**`Shift` = 框选，`Alt` = 整屏**
- 默认打开方式：图片 → imv（17 类型）· 音视频 → mpv（122 类型），
  见 `config/mimeapps.list`，坑在 `docs/05-theme-ui.md`
- **抽屉架**（2026-08-26）：`ALT+S` 切换的是**第二套工作平面**，不是单个抽屉。
  一组 `special:rack1/rack2/…`，`ALT+[ ] · CTRL+1-4 · ALT+T` 在架内是**模态**的
  （切抽屉格而非工作桌面）。零新增键位。见 `docs/02-hyprland.md`
- **窗口分组 group**（2026-09-03 新增）：某场景窗口数堆到 5+ 触发接入，此前评估过
  判断「暂不需要」，触发条件成立才正式加。`ALT+G` 建组/拆组（整组解散）、
  `ALT+SHIFT+G` 只踢出当前这一个（其余保留）、`CTRL+ALT+SHIFT+G` 一键把当前工作区
  收进一组、`movefocus_cycles_groupfirst=true` 让已有 `CTRL+ALT+HJKL` 兼任组内切标签
  （零新增键位）。视觉配色是官方默认值，没改。
  ⚠ `hl.dsp.group.move_window` 参数格式实测没探明，「批量分组」和「踢出单个」都改走
  `HL.Group:add()` / `:remove()` 直接操作组对象绕开它——这对方法互相对称，
  比 `hl.dsp.*` 的 dispatcher 更底层、确定性更强，见 `docs/02-hyprland.md`
- nvim **45 装 / 46 锁**（差的 `bufferline.nvim` 是 `disabled.lua` 里主动关的，属预期）
- **molten**（2026-09-11 新增）：在普通 `.py` 里跑 Jupyter kernel、`# %%` 分 cell、
  输出内联显示，`<leader>m` 系键位。**不引入 .ipynb** —— buffer 是纯 Python 文件，
  basedpyright 原生满血，走 ipynb 得靠 otter.nvim 打补丁。异步（实测提交 6 秒的 cell
  2.6 ms 返回）、中断保留命名空间（实测），对爬虫/接口调试比 tty REPL 强一档。
  ★ 光装配置文件不够：要 `python-pynvim` + `python-ipykernel`（已入 packages.txt），
  且 **`~/.local/share/jupyter/runtime/` 不存在时 kernel 起不来而报错完全指错方向**
  （已在 `molten.lua` 的 init 里 mkdir 兜掉）。另有 4 个坑（`MoltenEvaluateRange` 是
  function 不是 command、不能懒加载、`python3_host_prog` 要防 venv 污染、
  输出窗口的 `q` 撞上本配置全局禁用的 `q`）全在 `docs/04-neovim.md`
- **snacks.image**（2026-09-11 新增）：在 mini.files 里按 `l` 打开 png 会满屏二进制
  ——根因是 nvim 里没有任何东西能渲染图片：没装 image.nvim，而 snacks 的 image 模块
  **默认关闭**（它的 defaults 表里压根没有顶层 `enabled` 键，取值 nil 即假），
  LazyVim 也不开它。`snacks.lua` 里加 `image = { enabled = true }` 解决。
  选它而不选 image.nvim 的**唯一理由**：image.nvim 要 `magick` **luarock**（当初就是
  被这个卡住才放弃的），snacks.image 只要 ImageMagick 的**命令行程序**，而
  `/usr/bin/magick` 早就为 ASCII 壁纸装好了 —— 所以 `imagemagick` 现在有两个消费者，
  不再是「不做 ASCII 壁纸就可以不装」的可选项。
  ⚠ 两个别抱错期待的地方：① **molten 的 plot 还是看不到**，molten 的 provider 只认
  `none`/`image.nvim`/`wezterm`，**不认 snacks**，两者是独立机制；② mini.files 的
  **preview 窗格仍不出图**（它是 readfile 进 scratch buffer，不走 `BufReadCmd`）。
  ⚠ 依赖终端的 kitty 图形协议：kitty/ghostty/wezterm 行，**alacritty 不行**（会静默
  不显示）；且运行时探测在 `--headless` 下必然报不支持，验证要在真终端 `:checkhealth snacks`。
  见 `docs/04-neovim.md`
- 输入法：fcitx5 5.1.21 + rime，自制 `tokyonight` 主题；中文字体走
  更纱黑体 → Noto CJK SC，`fonts.conf` 已修掉「汉字默认用韩文字形」的系统级默认
- **cc 模块**（2026-08-26 新增，第 6 个）：Claude Code 的上下文占比状态栏 +
  多会话看板 `ccw`/`ccs` + 宠物 TUI `ccp`（**能就地把别的终端里那道选择题答掉**）。
  9 个文件在 `claude/`，见 `docs/08-claude-code.md`。
  ⚠ 两个坑：alias 在 **term** 模块的 `.zshrc` 里而脚本在 **cc**，只装一个会得到空 alias；
  状态栏靠 `install.sh` 用 jq 把 `statusLine` 合并进本机 settings.json（那份含 token、不入包）。
  ⚠ 代答依赖 transcript 的内部格式 + 实测出的按键序列，**Claude Code 升级后可能失效**，
  重新摸用 `python3 ~/.claude/probe_multiq.py`
- **noctalia 系统集成**（2026-08-27 新增，见坑 12 与 `docs/05-theme-ui.md`）：
  换壁纸/主题的 greeter 同步已免密（`privilege_command = "pkexec"` +
  `/etc/polkit-1/rules.d/49-noctalia-greeter.rules`，⚠ 后者是系统文件、**不在本包管辖**，
  新机器要手动建）；`SUPER+V` 剪贴板历史已能活过重启
  （`[storage] key_source = "file"`，密钥 `~/.config/noctalia/storage.key` 不入包）。
  两者都**没有**装 keyring、**没有**改 PAM、**没有**动任何系统包。
  另关掉了换歌时的「正在播放」OSD（`[osd.kinds] media = false`，坑 13）——
  那是 OSD 不是通知，全局生效，media widget 不受影响
- **wine 模块**（2026-08-27 新增，第 7 个）：`bin/winapp` —— 每个 Windows 程序一套
  独立 wine prefix + bubblewrap 沙箱的工具链。目前只有企业微信一个实例
  （**公有云版没有 Linux 客户端**：官网 `platform=linux` 返回的就是 Windows exe，
  `/server` 页那个 Linux 包是私有部署版 `weworklocal_*`，公有云账号登不上；
  也不存在员工聊天网页版）。跑在 **wine-staging 11.16 + 官方最新 5.0.10.6015** 上——
  和社区经验相反，不需要 deepin-wine 那套补丁。
  沙箱白名单只放行 XDG 文档目录，`~/hacktools`、`~/myTestAndSecurity`、`~/Projects`、
  `~/.ssh` 等一律不可见，用 **`winapp check wecom`** 实测边界（它用完全相同的 bwrap
  参数跑 `ls`，不靠口头保证）。坑见坑 14 与 `docs/09-wine-apps.md`
- **ocr 模块**（2026-08-31 新增，第 8 个）：屏幕取字 `Super+Shift/Alt+O`，
  **替代 normcap** —— 后者底层是 Tesseract，对屏幕小号中文粘连、漏字，且本机
  tessdata 连 `eng` 都没装、每次按键还要重新加载模型。现在是 RapidOCR（PP-OCRv6
  + onnxruntime），模型加载抽进 **systemd socket 激活**的常驻服务，空闲 10 分钟
  自退把 500 MB 内存还回去。实测：框选 **0.33 s**、冷启动 0.79 s、整屏 1.9 s，
  14 px 小字**字符零错误**。
  ★ 这是仓库里**第一个带 systemd 单元的模块** —— `put` 只拷文件，`mod_ocr` 里
  必须另有 `daemon-reload` + `enable --now ocrd.socket`，否则装了也没反应。
  ⚠ 三条反直觉的，全在 `docs/10-ocr.md`：
  **① 别在送进 OCR 前放大图片**（`limit_side_len: 736 / limit_type: min` 决定了检测
  模型内部就会放大，外面再放一次 = 两次插值，实测字号 14 从 4/4 掉到 3/4）；
  **② `intra_op_num_threads` 默认 -1 在 24 核上最慢**（265 ms），限到 4 只要 151 ms；
  **③ 服务必须用 HTTP/1.0** —— keep-alive 会让「空闲自退」永远不触发，症状是功能全对
  但内存一直赖着。
  ⚠ 运行时依赖 `python-rapidocr`（AUR）**不能直接 yay 装**：上游 PKGBUILD 写了
  `makedepends python-installer>=1.0.1`，而 Arch 全仓库最新只有 1.0.0。改过的
  PKGBUILD 归档在 **`aur/python-rapidocr/`**，连同「怎么复核这个 AUR 包没被投毒」
  的方法（2026-08-31 与 PyPI 上游 wheel 逐文件比对：90 个文件哈希全一致）写在
  `aur/README.md`。装完**必须** `IgnorePkg` 锁更新，但那写在 `/etc/pacman.conf`、
  **不在本包管辖**，换机器要手动加。它还会连带拉进 opencv 全套（含 vtk 371 MB），
  共约 936 MB
- **MANIFEST 只覆盖入库文件**（2026-09-11 修）：`sync.sh` 原来用裸 `find`，把
  `.gitignore` 挡掉的东西全收了进来——305 条里 **163 条是 `.git/` 内部对象**，
  还有 `secret-age.key`、`__pycache__`、两个 2.7 MB 的 `.snapshots/*.tar.gz`。
  后果是每次 commit 都改写 `.git/`、MANIFEST 生成完立刻过期，而 git 对象在别的
  机器上必然不同、`sha256sum -c` 在新机器上一定失败，正好废掉它唯一的用途
  （上次提交时 `docs/05-theme-ui.md` 的哈希就已经是陈旧的，没人发现）。
  改成跟着 `git ls-files` 走，现在 138 条、与 git 索引完全一致。
  ⚠ 别改回 `find`：`.gitignore` 以后新增条目会自动跟上，不用维护排除清单。
  非 git 环境（解压的 tar.gz）有 `find + prune` 的 fallback 分支。
- 待办：Mason 语言工具链未装齐（缺运行时，非配置问题，见 `docs/04`）；
  切桌面时光标闪一下（候选方案列在 `docs/07` 遗留项）；
  企业微信的 CEF 子进程 `WXWorkWeb.exe` 偶发 `int3` 崩溃（只影响内嵌网页组件如
  「文档」「审批」，主程序收发消息不受影响，`win81` 已缓解）
