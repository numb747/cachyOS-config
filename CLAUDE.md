# ~/cachyOS-config —— 桌面配置的单一事实来源

> **新会话读这一份就够。** 本机（CachyOS + Hyprland）全部桌面配置的归档、文档与安装器。
> 本文件只放导航、规矩和会踩的坑；**细节和来龙去脉都在 `docs/`**，历史在 git 里。

> ⚠ **先确认你在哪台机器上。** 两份检出：**源机器** `/home/david/cachyOS-config`（下面都按它写）、
> **笔记本** `/home/monkey/cachyOS-config`（17 个文件永远显示「不一致」，`sync.sh --pull` 和裸
> `install.sh` 是**禁止操作**）。在笔记本上先读 `docs/11-multi-machine.md`。

```
~/cachyOS-config/        仓库根 = 配置包本体（github.com/numb747/cachyOS-config）
├── README.md / README.zh-CN.md   人读的总览，英文 + 中文，两份一起改
├── INSTALL.md           新机器从零到可用 + 验收清单
├── manifest.map         ★ 文件映射表：包内路径 ⇄ 系统路径，按 #@module 分模块（单一事实来源）
├── install.sh           包 → 系统（幂等、分模块、自动备份；--list / --dry-run）
├── sync.sh              系统 → 包（把线上改动收回来）
├── check.sh             只读体检：MANIFEST / manifest.map / hl.dsp 参数名 / 文档数字 / 凭据 / 语法
├── uninstall.sh         回滚
├── packages.txt         pacman 包清单（含 AUR 说明）
├── MANIFEST.txt         sha256，由 sync.sh 生成，只覆盖 git 入库文件
├── docs/                17 篇，见下表（配图 docs/img/，计划 docs/plans/）
├── config/ home/ state/ 配置文件本体
├── bin/                 装到 ~/.local/bin/ 的脚本（录屏、取字、剪贴板粘贴、白板、mmd、AI Chrome、cc-cost、ccx…）
├── claude/              装到 ~/.claude/ 的 Claude Code 工具（状态栏、Agent Teams 角色与日志钩子、skills、MCP 套餐）
├── share/               装到 ~/.local/share/（fcitx5 主题、自建 .desktop 与图标）
├── system/              一次性系统修复脚本（改 /etc，不走 manifest），见 docs/05
├── security/            每周安全体检 + ufw（`sudo ./setup.sh`，装到 /usr/local、/etc，不走 manifest），见 docs/16
├── aur/                 本地改过的 AUR 包与投毒复核方法，见 aur/README.md
└── wallpaper/           参考图 + ASCII 成品 + 生成脚本（出处在 tokyonight/_picks*.json）
```

脚本都靠 `BASH_SOURCE` 自定位，挪目录不用改脚本。但 `~/.claude.json` 的 `projects` 键按绝对路径
索引，**改仓库路径后要手动迁键名**，否则 Claude Code 当陌生目录（重弹信任框、丢 allowedTools）。

---

## 改配置的正确姿势

**改线上文件，不要改包里的文件。** 包是快照，线上是本体。

```bash
# 1. 改 ~/.config/... 下的真实配置，验证效果
# 2. 收回包里（hypr patch → 文档数字对账 → 最后生成 MANIFEST）
cd ~/cachyOS-config && ./sync.sh --pull
# 3. 把「为什么这么改」写进对应的 docs/ —— 最容易漏，也最值钱
# 4. 提交前 ./check.sh —— 有 ✗ 就别提交
```

- **`--pull` 会自动重写文档里的数字**（键位数、ASCII 成品数、docs 篇数与体积、`claude/` 文件数、nvim 插件数），
  别手改。表在 `sync.sh` 的 `docnums`；`./sync.sh --docs` 只报不改。改了文档措辞导致正则匹配不到时会报警。
- **MANIFEST 必须排在 `--pull` 的最后**，往里加任何会改文件的步骤都要加在它之前，否则刚生成就过期。
- **新增纳管文件：先 `git add` 再 `--pull`。** MANIFEST 跟着 `git ls-files` 走，未跟踪的文件它看不见且不报错。
- 其他：`./sync.sh`（只看漂移）· `--diff` · `--pack`（打 tar.gz）· `--manifest`（只重算校验）·
  `./install.sh --dry-run` · `./install.sh hypr nvim`（只装指定模块）。
- 下载软件按 pacman → 官方原生包 → yay（先审再装）的顺序，全局 `~/.claude/CLAUDE.md` 已有，完整清单见 `docs/00` 第 5 节。

---

## 文档索引

| 我想… | 看 |
|---|---|
| 装系统 / 下载软件该走哪条路 | `docs/00-install-os.md` |
| 各部分怎么咬合、设计原则 | `docs/01-architecture.md` |
| 快捷键、窗口行为、工作区、抽屉架、group | `docs/02-hyprland.md` |
| 终端 / zsh / 提示符 / 毛玻璃 / kitty 壁纸 | `docs/03-terminal.md` |
| nvim（molten、image.nvim、tabby…） | `docs/04-neovim.md` |
| 配色 / 顶栏 / 字体 / 壁纸 / 输入法 / 默认打开方式 / mmd-view | `docs/05-theme-ui.md` |
| 忘了某个键 | `docs/06-keymap-cheatsheet.md` |
| 出问题了 | `docs/07-troubleshooting.md` |
| Claude Code：状态栏、arch-map、提示缓存、`/compact` 技巧、AI Chrome、ccx 套餐、cc-cost、cc-shutdown、版本钉死与升级、贴图/看图 | `docs/08-claude-code.md`（缓存 10、技巧 11、AI Chrome 12、ccx 13、cc-cost 14、关机 15、版本与看图 16） |
| 企业微信 / winapp（已卸载，历史） | `docs/09-wine-apps.md` |
| 屏幕取字 RapidOCR | `docs/10-ocr.md` |
| 笔记本那份检出的例外 | `docs/11-multi-machine.md` |
| Waydroid（已卸载，历史） | `docs/12-waydroid.md` |
| 启动器 / 剪贴板（Walker + Elephant） | `docs/13-launcher.md` |
| tmux 键位、Agent Teams、并行判断、`Alt+a` 窗格总览 | `docs/14-tmux.md` |
| Discord 客户端（Equibop + system24） | `docs/15-discord.md` |
| 每周安全体检、ufw、出事怎么办 | `docs/16-security.md` |

---

## 十五条会踩的坑（改之前先知道）

1. **noctalia 主题的真实来源是 `~/.local/state/noctalia/settings.toml`**，不是 `~/.config/noctalia/config.toml`，
   两边重叠以 state 为准。查活配置用 `noctalia config export full`。
2. **配色文件是生成物**（kitty/alacritty/btop/gtk4/qt6ct/kdeglobals），由 noctalia 模板渲染，手改会被覆盖；入口是 noctalia。
3. **`hl.bind` 对同一键位是叠加不是覆盖**，替换官方键位先 `hl.unbind`。`hl.config` 是逐项合并，只写关心的项是安全的。
4. **hypr 有 5 个 CachyOS 官方文件被改过**（`binds`/`variables`/`workspaces`/`windowrules`/`misc`），`-Syu` 可能覆盖，
   用 `config/hypr/patches/*.patch` 重打。**别加第 6 个**：纯覆盖值一律写进 `mykeys.lua`（最后加载，后写的赢）。
   kitty 的 `background_blur` 在本机是死选项；模糊归 Hyprland、透明度归 kitty `background_opacity`（设 1 模糊消失）。
   blur 定为「糊透」（`passes=4, size=8, vibrancy=0.5, brightness=0.9`），**保留剪影/轻糊都试过退回，别再试**，见 `docs/03`。
5. **`vim.opt.shell` 必须设在 `lua/config/options.lua`**，晚了 toggleterm 取走旧值。
6. **fontconfig：`prepend` 不是插到队首**（要 `prepend_first`）；`<alias>/<prefer>` 总排在所有 `<match>` 前，顺序敏感用 `<match>`；
   看效果用 `fc-match -s`。见 `docs/05`。
7. **fcitx5 主题 `Optional|Color` 要写子小节 `Value=`**，`*TextSizeFactor` 是整数百分比；用 gdbus `GetConfig` 验证，别靠肉眼。
8. **`hl.dsp.*` 对不认识的参数键静默忽略**：`toggle_special` 收裸字符串、不带 `special:`；「不跟过去」叫 `follow = false`。
   「代码看着对但行为不对」先怀疑参数名。`hyprctl dispatch` 参数按 Lua 解析（`hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'`
   可用来在会话里拉起 GUI）；跑任意 Lua 用 `hyprctl eval`，没有返回值。见 `docs/02`、`docs/07` 坑 8。
9. **`noctalia msg config-reload` 不重新注册子系统**：改 `[shell.launcher.providers.*]`、`[storage]` 后必须重启进程
   （`hyprctl dispatch 'hl.dsp.exec_cmd("noctalia")'`）。`config export` 变了不等于行为变了。枚举合法键用 `noctalia config validate`。
10. **改默认打开方式别给 `xdg-mime default` 传多个类型**（挤成一个畸形 key、静默失效）。改 `.desktop` 一律新建文件名，
    别同名覆盖（全量遮蔽）；`Icon=` 要验证主题里真有。没钉的类型 Dolphin 和 `xdg-open` 各猜各的。见 `docs/05`。
11. **停 wl-screenrec 必须 `SIGINT`**（否则 mp4 缺 moov 打不开），等进程真退出；AMD 要 `--low-power=off`；绑键别加 `uwsm app --`。
12. **noctalia 的系统集成报错都指错方向**：换壁纸老要密码 → 默认 `run0` 绕开了包自带的 policy，要 `privilege_command = "pkexec"`
    + `/etc/polkit-1/rules.d/49-*.rules`（1.7.0 起 action 改名 `sync-appearance`，规则两个名字都认）；剪贴板重启就空 →
    没有 Secret Service，改 `[storage] key_source = "file"`（`storage.key` 不入包）。**先看 journal 里真正被拒的 action id。**
13. **顶部弹的东西先分清通知（`top_right`）还是 OSD（`top_center`）**，入口不同；换歌弹窗是 OSD `[osd.kinds] media`。
    键管什么查 `/usr/share/noctalia/assets/translations/en.json`。
14. **窗口规则在创建时求值，那一刻所有窗口 `title` 都是空的**，按标题抓窗口要用 `initial_title`。（来自已卸载的企业微信，经验通用；
    原文见 `docs/09`。）
15. **noctalia 是在 background 层「盖」壁纸，不是设置壁纸**，底下始终是 Hyprland 内置图：开机先闪约 1.5 秒、noctalia 一崩就露出来。
    解法在 `config/misc.lua`：`force_default_wallpaper = 0` + `disable_hyprland_logo` + `background_color` 取壁纸主色
    （当前按 a1 取的 `rgb(1a1b26)`，**换色系要重取**）。别装 swww。验证看 `hyprctl getoption` 的 `set: true`。

---

## 边界：不进这个包的东西

`~/.ssh/` · `~/.gnupg/` · `~/.claude/settings.json`（含明文 token；状态栏、Agent Teams 的键由 `install.sh` 用 jq 合并进去）·
`~/.claude/mcp/secrets.env`（ccx 套餐的密钥，见 `docs/08` 第 13 节）· `~/.claude-glm/`（ccglm）·
`~/.config/noctalia/storage.key`（剪贴板加密主密钥，新机器重新生成）· `~/.local/share/fcitx5/rime/`（个人词库）·
壁纸全库（包里只带 `11-w55gjr.png` 参考图和 `wallpaper/ascii/` 成品）· `~/.zsh_history`。

换机器时这些走安全渠道单独传。往包里加文件前先确认不含凭据：
`grep -rniE 'sk-[a-zA-Z0-9]{16,}|AIzaSy|auth[_-]?token|BEGIN .*PRIVATE KEY' .`

---

## 现状（2026-11-18）

- 源机器：CachyOS · Hyprland 0.57.2 · noctalia 5.5.0 · kitty 0.50.0 · nvim 0.12.6 · zsh 5.9.2 + p10k 1.20.18 · fcitx5 5.1.23
- Hyprland 绑定 **122** 条（自定义 37 条）；`hyprctl binds -j | jq length` 可验。自定义数只认**行首**的 `hl.bind(`。
  0.57 起 special 工作区 id 是 `nil`，比大小前先判空（这类错只在按键时触发，`configerrors` 查不出）。
- nvim **51 装 / 55 锁**（差的是 `disabled.lua` 主动关的）。molten 在普通 `.py` 里跑 Jupyter cell；image.nvim
  用 `processor = "magick_cli"`、`build = false`、`lazy = false`，且 snacks.image 必须关。见 `docs/04`。
- 模块（`./install.sh --list`）：
  - **hypr**：纯动态工作区、抽屉架 `ALT+S`（第二套工作平面，导航键在架内是模态的）、group `ALT+G`、
    截图/录屏/取字统一「`Shift` 框选、`Alt` 整屏」。见 `docs/02`。
  - **term**：kitty + zsh + p10k + tmux 免前缀 Alt 层（前缀 `C-q`），`Alt+a` 窗格总览（`bin/tmux-panes`，读
    `~/.claude/sessions/*.json`，队员靠屏幕正则）。外层 nvim 转发 `Alt+Shift+标点` 会丢 Shift。见 `docs/03`、`docs/14`。
  - **ui**：noctalia、fcitx5 tokyonight 主题、fontconfig、默认打开方式（`config/mimeapps.list`）。见 `docs/05`。
  - **cc**：Claude Code 状态栏、Agent Teams（4 个角色 + 团队日志钩子；限权限只用 `tools` 白名单；队员做完常驻要手动关）、
    arch-map 等 skills、ccx 套餐。17 个文件在 `claude/`。见 `docs/08`、`docs/14` 第 7 节。
  - **wall**：ASCII 壁纸成品 + `_ascii.py`、`theme-switch`/`theme-preview`。
  - **ocr**：RapidOCR 常驻服务（systemd socket 激活，空闲自退；必须 HTTP/1.0；别在送进 OCR 前放大图片）。
    `python-rapidocr` 要本地改 PKGBUILD 且 IgnorePkg 锁更新（`/etc/pacman.conf`，不在包管辖）。见 `docs/10`、`aur/README.md`。
  - **launcher**：Walker + Elephant（`ALT+Space`、`SUPER+V` 剪贴板）。elephant 本体和插件须同一次构建；两个插件是自己发布的
    AUR 补丁版，`depends=elephant=<同版本>` 会让 `-Syu` 拒绝升级 elephant——有意的，先更新插件。装新插件要重启 walker。见 `docs/13`。
  - **discord**：Equibop + system24。面板直角、头像/服务器图标圆是有意的；IrcColors 要开着。见 `docs/15`。
- 不是 install.sh 模块的：每周安全体检（`security/`，改了要重跑 `sudo ./setup.sh audit`，见 `docs/16`）；
  钥匙环开机解锁（`system/`）。
- 已撤掉、别再加回来：作战大屏 warboard、终端版 discordo、noctalia 启动器（及回退脚本 noct-panel）、
  看板/宠物 TUI ccw/ccs/ccp（网页版 `~/ccmon` 取代）、Waydroid、企业微信。
- 待办：Mason 语言工具链未装齐（缺运行时，见 `docs/04`）；切桌面时光标闪一下（见 `docs/07` 遗留项）。
