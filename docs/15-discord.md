# 15 · Discord 客户端：Equibop + system24 主题（tokyo night）

> 包内 `config/equibop/`，`./install.sh discord` 装到 `~/.config/equibop/`。
> 2026-10-15 在**笔记本**上配好后收进包 —— 这是第一个从笔记本这一侧进包的模块，
> 源机器上还没装过，见文末「两台机器」。
>
> 和 `docs/08` 第 9 节的「用手机 Discord 驱动 Claude Code」（claude-discord-sync）**没有关系**：
> 那个是 bot 守护进程，这里是人用的聊天客户端。

---

## 1 · 选型：为什么是 Equibop

| | 是什么 | 取舍 |
|---|---|---|
| **Equibop** ✔ | Discord 桌面版的独立外壳，**预装 Equicord**（Vencord 的分支，插件更多） | **cachyos 仓库里就有**，`pacman -S equibop`，不用 AUR、不用往官方客户端里注入 |
| 官方 Discord + Equicord 安装器 | 往官方客户端打补丁 | 官方客户端一更新补丁就掉，要重新注入 |
| Vesktop | Vencord 的独立外壳 | 同类，但插件比 Equicord 少；本机没选它没有更深的理由 |

配置分三处，全在 `~/.config/equibop/`：

| 文件 | 管什么 | 入包 |
|---|---|---|
| `settings.json` | Equibop 外壳本身：托盘、标题栏、启动画面配色（已是 tokyo night 的 `#1a1b26` / `#a9b1d6`） | ✔ |
| `settings/settings.json` | Equicord：插件开关、**启用了哪个主题**、通知、云同步开关 | ✔ |
| `settings/quickCss.css` | 自定义 CSS（现在是空的，留着占位，以后往这写就会跟着同步） | ✔ |
| `themes/system24-tokyo-night.theme.css` | 主题文件，见第 2 节 | ✔ |
| `sessionData/` | **登录态**（token 在里面） | ✘ 永不入包，换机器重新登录 |
| `MessageLoggerData/`、`state.json`、`Crashpad/` | 运行时数据 | ✘ |

★ 两份 `settings.json` 都核过：只有开关和界面选项，没有 token、没有用户 ID、没有本机路径，
`cloud.settingsSync` 是 `false`。仓库 `.gitignore` 有一条兜底的 `settings.json`
（防 `~/.claude/settings.json` 误入库），为这两个文件**逐个路径**加了 `!` 例外，没有放宽通配。

---

## 2 · 主题：system24，tokyo night 配色

[refact0r/system24](https://github.com/refact0r/system24) —— TUI 风格的 Discord 主题：
等宽字体、直角方框、面板边框上嵌标题（像终端分屏的窗格名）、频道开头用 ASCII 艺术字、加载动画也是 ASCII。
仓库里自带十个配色，用的是官方的 `theme/flavors/system24-tokyo-night.theme.css`，和桌面其余部分（kitty / nvim / noctalia）同一套色。

**相对上游原版只改了两个开关**（`curl` 上游那份 `diff` 一下就能看到）：

| 变量 | 上游 | 本包 | 为什么 |
|---|---|---|---|
| `--animations` | `on` | `off` | 终端没有过渡动画，关掉更像 TUI |
| `--remove-pfp-decor` | `off` | `on` | 头像装饰框（Nitro 那些花边）和方框风格冲突 |

其余保持作者默认：`DM Mono` 300 字重、直角（`--unrounding: on`）、方头像（`--round-pfp: off`）、
面板标签（`--panel-labels: on`）、ASCII 标题与加载动画、小号用户面板。

### 调整过程（为什么最后是作者默认）

当天来回试过，留个记录免得以后再绕一圈：

1. 一开始误装成同一作者的 **midnight**（圆角、非等宽）—— 不是想要的。想要的是 system24 那种 TUI 感。
2. 换 system24 后先**关了面板标签、头像改圆**，又试了 **`--unrounding: off`（全部圆角）**。
   结论：圆角一开就不像 TUI 了，改回直角。
3. 关掉面板标签、用圆头像以后，**整体变回「暗色版普通 Discord」**。system24 的终端感
   主要就来自「直角方框 + 边框上的标签」这两样，所以面板标签和方头像都恢复了作者默认。
4. 在此基础上再往 TUI 推：关动画、去头像装饰、开 **IrcColors** 插件（第 3 节）。

想改就直接编辑主题文件 `body { … }` 里的变量（每行后面有作者的英文注释），
或者在 Equibop 设置 → Themes 里点主题旁的编辑按钮。

---

## 3 · 插件与账号设置

- **IrcColors**（Equicord 插件，已开）：按用户名哈希给每个人一个固定颜色，IRC 客户端那种效果。
  其余开着的都是 Equicord 默认就开的 API / 修复类插件。
- **消息「紧凑」显示**（设置 → 外观 → 消息显示 → 紧凑）：一行一条 `[时间] 名字: 内容`，
  和 system24 配起来最像终端聊天。⚠ 这是 **Discord 账号**的设置，不在 Equicord 的 settings.json 里，
  **不在本包管辖**；应该会随账号同步到别的设备（没实测），没跟过去就手动点一下。

---

## 4 · 装 / 迁移

```bash
sudo pacman -S --needed equibop   # cachyos 仓库
./install.sh discord              # 先完全退出 Equibop（含托盘），否则模块直接报错退出
```

⚠ **装之前必须退出 Equibop。** Equicord 在内存里持有设置，改动时整份写回 `settings/settings.json`，
运行中覆盖的文件可能被它冲掉。`mod_discord` 开头会 `pgrep -x equibop`，在跑就拒绝安装。

**Windows** 上没有 install.sh，手动复制：
- Equibop：`config/equibop/` 整个对应到 `%APPDATA%\equibop\`。
- 官方 Discord + Equicord：只要 `settings/` 和 `themes/` 两个目录，放到 `%APPDATA%\Equicord\` 下；
  外层 `settings.json` 是 Equibop 外壳专用的，不用拷。

Equicord 自带的「设置 → 备份与恢复」能导出插件设置，但**不含 `themes/` 下的主题文件**，
所以迁移以本包为准。

---

## 5 · 会踩的坑

1. **主题本体是运行时从网上拉的。** 主题文件第一行是
   `@import url('https://refact0r.github.io/system24/build/system24.css')`，
   DM Mono 也是从 Google Fonts `@import`。本包只存「开关 + 配色」，样式规则本身**跟着上游 main 走、没有钉版本**：
   - 好处：Discord 改版把类名（`.wrapper__44b0c` 这种带哈希的）换掉、主题局部失效时，作者修完这边自动生效。
   - 坏处：上游改了样式也会**静默**生效；离线或 GitHub Pages 抽风时只剩配色变量，布局退回 Discord 原样。
   - 真要钉死：把 `build/system24.css` 下载进 `themes/`、`@import` 改成本地文件（代价是以后要自己跟进修复）。
2. **`sync.sh` 会经常报 `settings/settings.json` 不一致。** Equicord 自动更新会给新插件补默认条目，
   还会写时间戳（`cloud.settingsSyncVersion`）。先 `./sync.sh --diff` 看是不是这类噪音，再决定收不收。
3. **想加的选项先查主题文件里有没有现成变量。** 例如全局圆角就是 `--unrounding` 一个开关管所有面板、按钮、
   服务器图标（`src/unrounding.css`），不需要自己写 CSS 覆盖。

---

## 6 · 评价（2026-10-15）

- **system24 值得用**：变量化做得好，所有改动都是改开关，不用碰选择器；和桌面 tokyo night 一套色，
  `--panel-labels` + 直角组合出来的终端感是别的 Discord 主题没有的。
- **短板**：DM Mono 300 字重偏细（主观判断，没做过对比），长时间看小字嫌累就把 `font-weight` 改成 400；
  依赖远程 `@import`（坑 1），本质上是「本地配置 + 在线主题」，不是完全离线可复现的。
- **不建议**：把面板标签关掉又想要 TUI 感 —— 第 2 节试过，标签一关就不像了。

---

## 两台机器

这个模块是**笔记本先有**、源机器还没装的（和 `docs/11` 里其余配置的方向相反）。
源机器 `git pull` 后：

- `./sync.sh` 会把这 4 个文件报成「系统上不存在」—— 只是警告，`--pull` 也不会因此写坏包。
- 想用就 `sudo pacman -S equibop && ./install.sh discord`；装完两边内容一致，以后哪台改了就从哪台收。
- 不想用就不装，那几条警告留着无害。
