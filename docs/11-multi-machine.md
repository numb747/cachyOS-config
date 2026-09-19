# 11 · 多机差异 —— 同一个包跑在两台机器上

> **这一篇只在笔记本那份检出（`/home/monkey/cachyOS-config`）里成立。**
> 源机器（`/home/david/cachyOS-config`）照 `CLAUDE.md`「改配置的正确姿势」正常操作，
> 本篇的两个禁止操作、那张差异表、那些待办，**对源机器一条都不适用**。
>
> 2026-09-20 从 `CLAUDE.md` 拆出来。拆的原因：那段以「本机是笔记本」开头的警告
> 挂在 `CLAUDE.md` 最顶上，而 `CLAUDE.md` 是两台机器共用的同一份文件 ——
> 源机器上的会话一进来就被告知「禁止跑 `sync.sh --pull`」，
> 那恰恰是源机器上唯一正确的收配置姿势。

## 两台机器是什么

| | 源机器 | 笔记本 |
|---|---|---|
| 用户 / 路径 | `david` · `/home/david/cachyOS-config` | `monkey` · `/home/monkey/cachyOS-config` |
| 屏幕 | 2560×1440 · 27" 外接 `DP-1` · scale 1 | 1920×1080 · 15.5" 内置 `eDP-1` · scale 1.5 |
| 角色 | **包从这里打出来**，`sync.sh --pull` 在这里跑 | 消费端，照 `origin/main` 对齐 |

---

## 笔记本：6 个永远「不一致」的文件（2026-09-16 复核）

> **总原则：以远程仓库为准。** 笔记本的配置本来就是照着 `origin/main` 学的，那份是对的那份。
> 拉取远程后默认**全量对齐**，只有下面这 6 个文件例外——它们要么绑死在本机硬件上、
> 要么绑死在 `/home/monkey` 这个用户路径上，照搬远程会真的变坏。
> `./sync.sh` 会一直把它们报成「不一致」—— 这是**预期状态，不是待办**。

| 文件 | 笔记本（正确） | 包里（源机） | 为什么不能同步 |
|---|---|---|---|
| `~/.config/kitty/kitty.conf` | `font_size 10.0` | `12.5` | 笔记本 scale 1.5，合成器已替 kitty 放大过，再套源机那档补偿就是双重放大（只剩 119 列 × 27 行） |
| `~/.config/nvim/lua/plugins/no-neck-pain.lua` | `width = 90` | `120` | 侧边宽度是 `floor((columns - width) / 2)` 算的，跟 kitty 10.0 的 148 列配套 |
| `~/.local/state/noctalia/settings.toml` | 含 `eDP-1` 锁屏部件 + `/home/monkey` | 只有 `DP-1` + `/home/david` | 覆盖会丢掉笔记本屏的锁屏配置 |
| `~/.config/noctalia/config.toml` | 路径为 `/home/monkey` | `/home/david` | `install.sh` 的 `rewrite_home` 本来就会改写，装完必然不一致 |
| `~/.zshrc` | `difft` / `gittype` 收进已有的 `$HACKTOOLS` 守卫块 | 两条裸 alias 硬编码 `/home/david/hacktools/` | **`rewrite_home` 覆盖不到 `.zshrc`**（它只管 settings.toml / noctalia config.toml / wecom.desktop），只能手工改；顺手按 `CLAUDE.md` 自己的约定收进 `if [ -d "$HACKTOOLS" ]` 块里，目录不在就整段跳过 |
| `~/.config/qt6ct/qt6ct.conf` | 真实路径 | skel 原样 | `manifest.map` 已标 `#@nopull`，两台机器都会报不一致 |

> ★ **`config/hypr/config/misc.lua` 已于 2026-09-16 退出这张表。** 它之前在表里是因为
> `background_color` 要取当前壁纸的主色，而两台机器壁纸不同。现在笔记本壁纸也跟远程换成了
> `D-ASCII/a1-紫调少女.png`，主色一致（`rgb(1a1b26)`），文件逐字节相同。
> 换壁纸换色系时重新采样的命令见 `CLAUDE.md` 坑 15。

### 笔记本上的两个禁止操作

1. **不要跑 `./sync.sh --pull`。** 它会把上面这 6 项**反向写死进包**——笔记本字号、
   `eDP-1`、`/home/monkey` 硬路径全部进 git，推上去就污染源机器的配置。
   要往包里回收改动，只能挑**单个文件**手工来。
2. **不要跑不带参数的 `./install.sh`。** `mod_term` 会 put `kitty.conf` 和 `.zshrc`、
   `mod_nvim` 是**整目录 mv 走再替换**、`mod_ui` 的 `put_module ui` 含 `settings.toml`
   —— 三个模块各自会把上表对应项打回源机的值（有 `.bak-*` 备份，但等你发现字变大了
   才想起来就晚了）。**安全的是 `./install.sh hypr cc ocr wall`**；`term` / `nvim` / `ui`
   要装就先看 `./sync.sh --diff`，手工只搬新增的段。

> ★ **「`mod_nvim` 整目录 mv」这条对源机器同样成立**，只是后果不同：它会把
> `~/.config/nvim` 下的 lazy 插件目录等运行时产物一起搬进 `.bak-<时间戳>`。
> 从远程吃下几个 nvim 文件时，逐文件 `cp`（照 `install.sh` 的 `put` 约定先
> `cp -a` 出 `.bak-<时间戳>`）比跑整个模块干净。2026-09-20 源机器吃
> `util/term.lua` 那批就是这么做的。

### `MANIFEST.txt` 在笔记本上是过期的，别拿它验包

它只由 `./sync.sh --pull` 生成，而 `--pull` 在笔记本上是禁止操作（见上），所以**笔记本改了
包内文件后它不会更新**，`sha256sum -c` 必然一片 FAILED。这不是包损坏。

> 此前这里还记着一条「MANIFEST 把 `.git/` 卷了进去」的上游缺陷——**2026-09-11 的
> `8caafb7` 已经修掉**：`sync.sh` 从裸 `find` 改成跟着 `git ls-files` 走，现在只收入库文件。
> 所以不用再手工滤 `.git/` / `.snapshots/`，直接 `sha256sum -c` 即可（前提是 MANIFEST 是新的）。

---

## 笔记本已补齐的、以及还缺的

- `~/.config/noctalia/storage.key`（2026-08-27 生成，64 位 hex / 0600）——
  剪贴板历史落盘的主密钥，**不入包**。验收信号是日志里的
  `[clipboard] loaded encrypted clipboard history`，别看 `noctalia config export`（坑 9）。
- ⚠ **待办**：`/etc/polkit-1/rules.d/49-noctalia-greeter.rules` 还没建（要 sudo）。
  没有它 `privilege_command = "pkexec"` 只是换了个提权程序，换壁纸/主题**照样弹密码框**。
  内容见 `docs/05-theme-ui.md`；验收 `pkcheck --action-id
  org.noctalia.greeter.apply-appearance --process $$` 应从 `auth_admin` 变 `yes`。
- `wine` 模块**有意未装**（笔记本没装 wine）：`winapp` / `wecom.conf` / `wecom.desktop` /
  `wecom.png` 四个文件在 `./sync.sh` 里报「系统上不存在」，是预期。
  `packages.txt` 里缺的也正好是这 4 个包（`wine-staging` / `wine-mono` / `wine-gecko` /
  `winetricks`），其余全装了。
- ⚠ **待办**：`python-pynvim` + `python-ipykernel` 还没装（要 sudo，笔记本 sudo 需要密码）。
  这是 molten 的前置——配置文件 `plugins/molten.lua` 已经就位，但**不装这两个包
  `:MoltenInit` 起不来 kernel**。装法 `sudo pacman -S --needed python-pynvim python-ipykernel`，
  装完必须在 nvim 里 `:UpdateRemotePlugins` 再重启，否则 `:Molten*` 全是 E492（坑见 `docs/04`）。
- ★ **「Mason 语言工具链未装齐」那条待办对笔记本不成立**（`CLAUDE.md` 文末「现状」记的是源机器）。
  笔记本运行时齐全（node/npm/python3/go/rustc/cargo），Mason 已装 26 个
  （clangd / gopls / pyright / ruff / vtsls / lua-language-server / jdtls …）。
  别照着那条去「补装」。

### 壁纸库两台不一样大

`CLAUDE.md`「边界」一节记的 348 MB / 115 张是**源机器**的。笔记本只拉了一部分：
273 MB / 51 张（2026-09-16 数）。两边都靠 `wallpaper/tokyonight/_fetch.py` 重新拉，
包里只带两张成品（`11-w55gjr.png` 参考图 + `wallhaven-kxwp96.jpg`）。

---

## 两个脚本在笔记本上的实测表现（2026-09-16）

这两条不是「笔记本配置缺失」，是脚本本身的假设问题，**源机器上要按它的目录布局自行复核**。

- ⚠ **`theme-switch`（`SUPER+SHIFT+T`）在笔记本只有 1/5 能用**：它循环
  `tokyonight / rosepine / everforest / dracula / oxocarbon` 五个主题，每个要
  `~/Pictures/Wallpapers/<slug>/` 下有图。笔记本只有 `tokyonight/`（5 张），
  切到其余四个会打印「缺少壁纸目录」并 `exit 1` —— **不改任何状态，是安全失败**。
  想补就往对应目录丢图，`THEMES` 数组不用动。
  实测 `theme-switch tokyonight` 正常（它 `find` 不加 `-maxdepth`，递归取图）。
- ⚠ **`theme-preview`（`SUPER+I` / `SUPER+SHIFT+I`）在笔记本直接报错，不是装坏了**：
  它的 `list_images` 写的是 **`find ... -maxdepth 1`**，只认**主题目录根上那一层**的
  「片单图」；而笔记本 `tokyonight/` 根上只有 `_*.py` / `_picks*.json` / `index.html`，
  图全在 `A-最搭/` 和 `D-ASCII/` 两个子目录里，于是列出来是空集
  → `✗ 主题目录无片单图` → `exit 1`。
  ★ 这是**两个脚本对目录布局的假设不一致**：`theme-switch` 递归、`theme-preview`
  只看一层，而 `docs/05-theme-ui.md` 加新主题那三步写的是「可带子目录，脚本递归取图」——
  按文档的布局摆图，`theme-preview` 必然失效。
  两条路，**在笔记本上都别急着改脚本**（那是远程的东西，改了下次拉取要冲突）：
  往 `tokyonight/` 根上放几张想快速轮换的「片单」副本，或者确认源机器上
  该目录根到底是什么布局再决定以谁为准。

---

## 备份放在哪（2026-08-27 整理，笔记本）

家目录根上的旧备份已集中到 `~/.local/state/config-backups/`（0700，里面有明文 token），
那儿的 `README.txt` 记了内容清单。2026-08-26 的旧解包快照 `~/cccconfig/` 已删除
（逐文件核验过是本仓库的子集）。**现在笔记本只有 `~/cachyOS-config` 一份配置源。**

⚠ 但 `~/.config` / `~/.claude` 下那 17 个 `<文件名>.bak-时间戳` **原地保留、别归档**：
`uninstall.sh` 的 `latest_bak()` 是在**目标文件旁边**找它们的，挪走等于废掉回滚。
看回滚点用 `./uninstall.sh --list-baks`。
