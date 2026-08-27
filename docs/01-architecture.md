# 01 · 架构与设计原则

先读这篇，后面六篇都是它的展开。

---

## 一张图看清分层

```
                    ┌─────────────────────────────────────────┐
   登录             │ greetd + noctalia-greeter               │
                    └──────────────────┬──────────────────────┘
                                       │ uwsm 启动会话
                    ┌──────────────────▼──────────────────────┐
   会话环境         │ ~/.config/uwsm/env                      │
                    │ QT_QPA_PLATFORMTHEME / 光标 / TERM      │
                    └──────────────────┬──────────────────────┘
                                       │
      ┌────────────────────────────────┼────────────────────────────────┐
      │                                │                                │
┌─────▼─────────────┐    ┌─────────────▼──────────┐    ┌───────────────▼────┐
│ Hyprland          │    │ noctalia (Quickshell)  │    │ 应用                │
│ 合成器 · 键位      │◄──►│ 顶栏 · 启动器 · 锁屏    │    │ kitty → nvim        │
│ config/*.lua 官方  │IPC │ 主题引擎 ★             │───►│ GTK / Qt / btop     │
│ mykeys.lua 个人    │    │ 生成各程序的配色文件     │模板 │ 配色由它写出来       │
└───────────────────┘    └────────────────────────┘    └────────────────────┘
```

★ 是这套配置里最容易搞错的一环：**颜色不是你写的，是 noctalia 生成的**。
`~/.config/kitty/themes/noctalia.conf`、`btop/themes/noctalia.theme`、
`gtk-4.0/noctalia.css`、`qt6ct/colors/noctalia.conf`、`kdeglobals` 全是产物。
改配色的正确入口是 noctalia，不是去编辑这些文件（下次它会覆盖回来）。见 [05](05-theme-ui.md)。

---

## 原则一：个性化与发行版文件分离

CachyOS 用 `cachyos-hypr-noctalia` / `cachyos-zsh-config` 这类包持续维护基线配置。
一旦直接改它们的文件，每次 `pacman -Syu` 都要面对 `.pacnew` 三方合并。所以：

```
~/.config/hypr/hyprland.lua   官方，唯一改动：末尾追加 require("mykeys")
~/.config/hypr/config/*.lua   官方 —— 但有 3 个例外，见下
~/.config/hypr/mykeys.lua     ← 全部键位个性化都在这一个文件

~/.zshrc                      第一行 source 发行版基线，之后只做叠加
~/.p10k.zsh                   提示符全部在这里，.zshrc 里一个字都不写
```

**例外**：`config/` 下的 `binds.lua` / `variables.lua` / `workspaces.lua` 为了实现
纯动态工作区被改了。这是有意识付出的代价，理由和补救办法见 [02](02-hyprland.md#关于官方文件被改动)。

## 原则二：可选依赖必须静默降级

`.zshrc` 里所有外部工具（zoxide、rvm、uv、hacktools、docker）都写成
「探测存在才启用」。目的：同一份配置扔到任何一台机器上都不会在每次开 shell 时刷报错。
反面教材就在 [07](07-troubleshooting.md) 的坑 1。

## 原则三：一处设置，多处受益

`nvim` 的内置终端 shell 只在 `lua/config/options.lua` 里设一次
（`vim.opt.shell`），`:terminal`、toggleterm、`:!cmd` 三个入口同时正确。
细节和「为什么不能在别处设」见 [04](04-neovim.md#内置终端为什么用-zsh-而不是-shell)。

## 原则四：修饰键有分工

| 修饰键 | 语义 | 例子 |
|---|---|---|
| `ALT` | **动作** | `ALT+Enter` 全屏、`ALT+W` 关窗、`ALT+T` 新桌面、`ALT+\` 分屏 |
| `CTRL+ALT` | **导航** | `CTRL+ALT+HJKL` 切焦点 |
| `+SHIFT` | 「**带着窗口一起**」 | `CTRL+ALT+SHIFT+HJKL` 搬窗口、`ALT+SHIFT+T` 带窗口去新桌面 |
| `SUPER` | 官方保留的第二套入口 | `SUPER+Q` 关窗、`SUPER+F` 全屏 |

记住这四行，116 条绑定基本不用查表。

截图和录屏是这套分工在 `SUPER` 那一路的延伸：**`SHIFT` = 框选，`ALT` = 整屏**，
`P`（截图）和 `R`（录屏）两套修饰键含义完全一致，见 [06](06-keymap-cheatsheet.md)。

---

## 各模块之间的实际耦合

装一半会出问题的地方，列在这里：

| 如果只装… | 会缺什么 |
|---|---|
| 只装 `hypr` | `ALT+9`、`ALT+Space` 依赖 `noctalia msg` IPC。没有 noctalia 这两个键无效，其余正常 |
| 只装 `term` | `kitty.conf` 末行 `include themes/noctalia.conf`，那个文件由 noctalia 生成。**本包带了一份种子**，所以不会报错；但换壁纸/配色后由 noctalia 覆盖 |
| 只装 `ui` | 顶栏和配色对了，但键位是官方的 81 条 |
| 只装 `nvim` | 独立可用。唯一外部依赖是 zsh（内置终端），没有则回退到 `$SHELL` |
| 不装 `wall` | `settings.toml` 里的壁纸路径指向不存在的文件，noctalia 显示纯色背景，无报错 |

分屏终端键（`ALT+\`）用的是官方全局变量 `TERMINAL`（在 `config/variables.lua`，
默认 `kitty`）和 `uwsm app --` 前缀。不用 UWSM 的话把 `mykeys.lua` 第 5 节的
`launchPrefix` 改成 `""`。
