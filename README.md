# CachyOS + Hyprland 桌面配置包

一台已经调顺手的 CachyOS 机器的完整配置快照，目标是**在另一台机器上一条命令复现**。

> 快照时间：2026-08-26
> 来源机器：CachyOS · Hyprland 0.56+ · noctalia v5.0.0 · kitty 0.48.2 ·
> neovim 0.12.5（LazyVim，45 插件）· zsh 5.9.2 + powerlevel10k 1.20.17

> ⚠ **这是个人配置，不是通用发行版。** 它按一台特定机器的硬件与习惯调过：
> 单显示器 DP-1 2560×1440、AMD 显卡、中文输入法、特定键位肌肉记忆。
> 直接照搬到别的机器多半要改。`install.sh` 会覆盖 `$HOME` 下的配置文件
> （每个都先备份成 `.bak-时间戳`，且不需要 sudo、不碰系统目录），
> 但**请先 `--dry-run` 看一遍**再决定。出了问题用 `./uninstall.sh` 回滚。
>
> 授权与第三方内容（壁纸来自 wallhaven、nvim 部分来自 LazyVim）见 [LICENSE](../LICENSE)。

---

## 60 秒上手

```bash
git clone https://github.com/numb747/cachyOS-config.git cachyOS-config
cd cachyOS-config

sudo pacman -S --needed $(grep -vE '^\s*(#|$)' packages.txt | tr '\n' ' ')
./install.sh --dry-run    # 先看会动哪些文件
./install.sh              # 幂等；每个被覆盖的文件都会先备份成 .bak-时间戳
```

装到**别的用户名**下不用改任何东西：包里几处写死的绝对路径
（noctalia 的 `key_file`、壁纸 path、`wecom.desktop` 的 `Exec`）
由 `install.sh` 的 `rewrite_home` 自动改写到当前 `$HOME`。

装完注销重进 Hyprland。逐项确认见 [INSTALL.md](INSTALL.md) 的验收清单。

只想装其中一部分：

```bash
./install.sh hypr nvim        # 只装这两个模块
./install.sh --list           # 看有哪些模块
./install.sh --dry-run        # 只打印会做什么，不动文件
```

---

## 这个包里有什么

| 模块 | 内容 | 文档 |
|---|---|---|
| **hypr** | Hyprland 键位方案（35 条自定义绑定 → 共 118 条）、鼠标行为、纯动态工作区、抽屉架、录屏脚本 | [02](docs/02-hyprland.md) · [速查表](docs/06-keymap-cheatsheet.md) |
| **term** | kitty（启动即进 nvim）、alacritty、zsh、powerlevel10k | [03](docs/03-terminal.md) |
| **nvim** | LazyVim 定制：mini.files、toggleterm、lualine、tokyonight 透明 | [04](docs/04-neovim.md) |
| **ui** | noctalia 顶栏与主题联动、GTK/Qt/btop 配色、字体、光标、输入法、默认打开方式 | [05](docs/05-theme-ui.md) |
| **cc** | Claude Code：上下文占比状态栏、多会话看板（`ccw`/`ccs`）、宠物 TUI（`ccp`，能就地代答选择题） | [08](docs/08-claude-code.md) |
| **wall** | Tokyo Night 壁纸 + 配色，以及生成壁纸库的脚本 | [05](docs/05-theme-ui.md#壁纸) |
| **wine** | `winapp`：每个 Windows 程序一套独立 wine prefix + bubblewrap 沙箱；实例是企业微信 | [09](docs/09-wine-apps.md) |
| **ocr** | 屏幕取字 `Super+Shift/Alt+O`：RapidOCR 常驻服务替代 normcap，框选 0.33 秒进剪贴板 | [10](docs/10-ocr.md) |

还没装系统？先看 [docs/00-install-os.md](docs/00-install-os.md)（Ventoy 制盘、镜像、CachyOS 取舍）。
设计原则、模块之间怎么咬合，看 [docs/01-architecture.md](docs/01-architecture.md)。
装完出问题先翻 [docs/07-troubleshooting.md](docs/07-troubleshooting.md)——里面全是这套配置**实际踩过**的坑，不是通用 FAQ。

---

## 改了配置之后：把改动收回包里

包是快照，`~/.config/` 才是本体。**改线上文件，然后 `sync.sh` 收回来**，
不用手动记得拷了哪些：

```bash
./sync.sh              # 只看哪些文件漂移了（不写任何东西）
./sync.sh --diff       # 逐个打印差异
./sync.sh --pull       # 收进包里，并重新生成 MANIFEST 和 hypr patch
./sync.sh --pack       # pull 之后再打 tar.gz
```

要纳管一个新文件？只改 `manifest.map` 一行——`install.sh` / `uninstall.sh` / `sync.sh`
都读它，三个脚本自动跟上。

> 唯一的例外是 **hypr 模块**：`install.sh` 的 `mod_hypr` 是硬编码 `put` 的（为了在覆盖
> 五个官方文件前先打警告），不走 `put_module`。往 hypr 段加文件时，`install.sh` 里
> 必须**另外**补一行 `put`，否则 `sync.sh` 收得进来、`install.sh` 却装不出去。

有些文件包里存的是**模板**而非本机快照（比如 `qt6ct.conf` 里的 `/home/$USER`），
拉回来会把本机路径写死进包。这类文件在 `manifest.map` 里用 `#@nopull <包内路径>` 标注，
`--pull` / `--pack` 会跳过它们，`--check` 则照常显示不一致并标 `[nopull · 预期不一致]`。

---

## 目录结构

```
cachyOS-config/                  仓库根 = 包本身（没有中间层目录）
├── README.md              ← 你在这
├── CLAUDE.md              给 AI 会话的导航（坑清单 + 改配置的正确姿势）
├── LICENSE                MIT + 第三方内容（壁纸 / LazyVim）归属声明
├── INSTALL.md             全新机器从零到可用的完整流程 + 验收清单
├── manifest.map           ★ 文件映射表：包内路径 ⇄ 系统路径（三个脚本共用）
├── install.sh             包 → 系统（幂等 / 分模块 / --dry-run / 自动备份）
├── sync.sh                系统 → 包（把线上改动收回来）
├── uninstall.sh           还原
├── packages.txt           pacman 包清单
├── MANIFEST.txt           所有文件的 sha256（由 sync.sh 生成）
├── docs/                  11 篇说明，见上表
├── home/                  .zshrc  .p10k.zsh
├── bin/                   → ~/.local/bin/
│   ├── hypr-screenrec     录屏开关封装（wl-screenrec），Super+Shift/Alt+R 调它
│   ├── winapp             wine 应用的独立 prefix + bubblewrap 沙箱工具链
│   ├── ocr-server         屏幕取字的常驻识别服务（RapidOCR，systemd socket 激活）
│   └── ocr-grab           取字客户端：截图 → 识别 → 剪贴板，Super+Shift/Alt+O 调它
├── aur/                   改过才能装的 AUR 包（PKGBUILD 归档，不装到 $HOME）
├── claude/                → ~/.claude/（状态栏 / 会话看板 / 宠物 TUI）
├── config/                → ~/.config/
│   ├── hypr/              mykeys.lua + 5 个改过的官方文件 + 对应 .patch
│   ├── systemd/user/      ocrd.socket / ocrd.service（取字服务，需 enable 才生效）
│   ├── kitty/  alacritty/ 终端及其主题
│   ├── nvim/              整套 LazyVim 配置
│   ├── noctalia/          顶栏与 shell 行为
│   ├── gtk-4.0/ gtk-3.0/ qt6ct/ btop/ kdeglobals   主题产物
│   ├── uwsm/env           会话级环境变量
│   ├── mimeapps.list      默认打开方式：图片 → imv，音视频 → mpv
│   ├── mpv/mpv.conf       只有一行 hwdec=auto-safe（mpv 出厂是软解）
│   ├── fcitx5/            中文输入法（rime）+ 候选框外观 classicui.conf
│   └── fontconfig/        字体优先级（修掉汉字默认用韩文字形的系统默认）
├── share/                 → ~/.local/share/
│   ├── fcitx5/themes/     Tokyo Night 输入法主题（PNG 由 SVG 生成）
│   └── applications/      imv-viewer.desktop（自建条目，非覆盖系统的）
├── state/noctalia/        → ~/.local/state/noctalia/（★ 主题真正生效的地方）
├── wallpaper/             参考壁纸 + 4 张 ASCII 成品 + 壁纸库生成脚本
└── .snapshots/            sync.sh --pack 的 tar.gz 产物（不入 git）
```

---

## 三件需要先知道的事

**1. 主题的真实来源不是 `config.toml`。**
`~/.config/noctalia/config.toml` 里写着 `[theme] source = "wallpaper"`，但实际生效的是
`~/.local/state/noctalia/settings.toml` 里的 `source = "community"` +
`community_palette = "Tokyo Night Moon"`。只拷 `config.toml` 过去，配色是复现不出来的。
所以本包额外带了 `state/` 目录。判据：`noctalia config export full` 打印的才是活配置。

**2. 有五个 CachyOS 官方文件被改过。**
`~/.config/hypr/config/` 下的 `binds.lua` / `variables.lua` / `workspaces.lua`（纯动态
工作区）、`windowrules.lua`（企业微信幽灵窗）、`misc.lua`（关掉 Hyprland 内置壁纸，
消除开机时的壁纸闪烁）。`pacman -Syu` 升级 `cachyos-hypr-noctalia` 可能覆盖它们，
所以 `config/hypr/patches/` 里存了五个 patch，随时能重新打上。细节见 [docs/02](docs/02-hyprland.md#关于官方文件被改动)。

**3. 本包不含任何密钥。**
`~/.claude/settings.json`（内含明文 API token）、`~/.ssh/`、`~/.gnupg/`、shell 历史
都**没有**打进来。换机器时这些请单独用安全渠道传。

---

## 不在包里的东西（有意）

| 东西 | 为什么不带 |
|---|---|
| `~/.ssh/`、`~/.gnupg/`、`~/.claude/settings.json` | 含密钥，见上 |
| `~/Pictures/Wallpapers/` 全库（167 MB） | 太大；只带 1 张参考图 + 4 张 ASCII 成品 + 重新拉取的脚本 |
| `~/.zsh_history` | 个人痕迹，无复用价值 |
| `~/.bashrc`、wezterm、fish 片段 | 已弃用，登录 shell 是 zsh |
| `qt5ct/`、`xsettingsd/` | 配置文件在，但这两个程序本机没装，纯 skel 残留，是死配置 |
| nvim 的 `lazy/` 插件实体 | 由 `lazy-lock.json` 锁版本，首次启动自动装，带过去反而会冲突 |
