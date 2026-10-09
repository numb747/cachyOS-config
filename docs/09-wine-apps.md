# 09 · wine 应用（已移除）

> **2026-10-09 起本机不再用 wine。** 企业微信改为只用 Waydroid 里的安卓版（`docs/12`），
> wine 版连同整套工具链一起卸载。本篇只留一份「拆了什么、丢了什么、怎么找回来」的记录。
> 原文（282 行：为什么必须 wine、为什么不用 deepin-wine、winapp 沙箱设计、8 条坑、
> 排除掉的错误方向）在 git 历史里：
>
> ```bash
> git show 8892a3a:docs/09-wine-apps.md
> ```

## 1 · 拆掉了什么

| 位置 | 内容 |
|---|---|
| `manifest.map` / `install.sh` | 整个 `wine` 模块（`mod_wine`、`--list` 里那一项） |
| 包内 | `bin/winapp`、`config/winapp/wecom.conf`、`share/applications/wecom.desktop`、`share/icons/wecom.png` |
| `packages.txt` | `wine-staging` `wine-mono` `wine-gecko` `winetricks`（`bubblewrap` 也从清单拿掉了，系统包本身没卸——glycin 等系统包依赖它） |
| `config/hypr/config/windowrules.lua` | `wecom-ghost-windows`、`wecom-ghost-overlay-hide` 两条幽灵窗规则 |
| `~/.config/elephant/desktopapplications.toml` | 屏蔽 `~/.wine` 里 Windows 版 Firefox 快捷方式的那条 blacklist |
| 线上（不入包的） | `~/.local/share/wineprefixes/wecom/`（3.7 GB，含本地聊天记录）、`~/.wine/`（里面装过一个 Windows 版 Firefox）、`~/.cache/wecom-setup/`（两个安装包 1.1 GB）、winemenubuilder 生成的 `wine-*.desktop` / `.menu` / `.directory` 和图标 |

## 2 · 丢了什么

**企业微信视频通话。** Waydroid 的摄像头因 minigbm 的 YUV 缓冲 bug 不可用（`docs/12` 第 7 节，
当时决定不修），此前视频通话全靠 wine 版。卸载时已确认不再需要。

## 3 · 还通用的经验

这几条不依赖 wine，换别的 XWayland 程序照样会踩，原文第 5 节有完整排查过程：

- **Hyprland 窗口规则抓「创建时无标题的窗口」要用 `initial_title`，不能用 `title`。**
  规则在窗口创建时求值，那一刻所有窗口的 `title` 都是空的，`title = "^$"` 会把主窗口一起误伤。
- **bwrap 别加 `--unshare-ipc`**：切断 X11 的 MIT-SHM，程序调 `X_ShmPutImage` 直接崩。
- **`--die-with-parent` + 从终端启动** = shell 一退应用就死，像随机崩溃；调试用 `setsid --fork`。
- **杀进程别用 `pkill -f`**：模式会匹配到执行它的 shell 自己，曾因此误杀 noctalia。

## 4 · 想装回来

`git show 8892a3a:<路径>` 取回上面第 1 节列的包内文件，`sudo pacman -S wine-staging wine-mono wine-gecko winetricks`，
再照原文第 4 节 `winapp create wecom` → `winapp install wecom <WeCom_x.x.x.exe>`。
