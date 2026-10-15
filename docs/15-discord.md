# 15 · Discord 客户端：Equibop + system24 主题（tokyo night）

> 包内 `config/equibop/`，`./install.sh discord` 装到 `~/.config/equibop/`。
> 2026-10-15 两台机器**同一天各配了一套**：笔记本先收进包（往 TUI 推），源机器另配了一套（圆头像 + 圆服务器图标）。
> 2026-10-16 合并时定为**源机器那套**，笔记本 pull 后跟过去，见第 2 节和文末「两台机器」。
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
| `themes/system24-*.theme.css`（另 3 个，`@author local`） | 自写的 system24 补丁主题，见第 2 节末 | ✔ |
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

**相对上游原版改了三处**（`curl` 上游 `theme/flavors/system24-tokyo-night.theme.css` 来 `diff` 一下就能看到）：

| 变量 | 上游 | 本包 | 为什么 |
|---|---|---|---|
| `--font` / `--code-font` | `DM Mono` | `Adwaita Mono` | 和终端同款（kitty / nvim）；中文按 fontconfig 回落到更纱黑体。DM Mono 不是本机字体，是主题从 Google Fonts 在线拉的 |
| `font-weight` | `300` | `400` | Adwaita Mono 只有 Regular / Bold，写 300 也落到 Regular，改成 400 免得误以为是细体 |
| `--round-pfp` | `off` | `on` | 圆头像，**有意的**（见下） |

外加启用一个自写的补丁主题 **「system24 · 圆形服务器图标」**（`system24-round-server-icons.theme.css`）：
system24 的 `--unrounding: on` 连服务器图标的 SVG 遮罩也 `display: none` 掉了（变方块），这个文件把遮罩还回去，
恢复 Discord 原生的圆形图标（悬停 / 选中变圆角方形）。

其余保持作者默认：直角面板（`--unrounding: on`）、面板标签（`--panel-labels: on`）、动画开、
头像装饰保留、ASCII 标题与加载动画、小号用户面板。升级上游时用新文件覆盖后把上表几行再改一遍。

### 风格取舍：面板直角，头像和服务器图标圆

两台机器当天各自调过一遍，走了相反的方向，2026-10-16 合并时**用户选了源机器这套**：

- **笔记本那套（已弃）**：作者默认 + 关动画 + 去头像装饰 + 开 IrcColors，一路往 TUI 推。
  理由是「关掉面板标签、用圆头像以后，整体变回暗色版普通 Discord」。
- **源机器这套（现用）**：面板保持 system24 的直角方框和边框标签（终端感的主体），
  但**头像和服务器图标故意是圆的** —— 用户明确说「对我是故意圆角的」。
  动画、头像装饰保留作者默认，IrcColors 不开，字体换终端同款。

⚠ 别把「圆头像」当成笔记本那次试过的「整体变回普通 Discord」：那次是**同时关了面板标签**，
这套面板标签是开着的。也**别**为了圆图标去开全局 `--unrounding: off`——那会把所有面板、按钮一起变圆，
所以才单写了补丁主题只管图标。

更早的弯路：一开始误装成同一作者的 **midnight**（圆角面板、非等宽）—— 不是想要的，想要的是 system24 的 TUI 感。

### 另外两个自写主题（备选，默认不开）

和「圆形服务器图标」同样是 `@author local`，文件在包里，`enabledThemes` 里没开：

- **侧栏悬停展开**（`system24-collapse-sidebar.theme.css`）：服务器栏 + 频道栏 + 用户面板平时收成一条窄边，
  鼠标移上去才展开。⚠ 要压的是 `.guilds` 和 `.sidebarList` 两个子元素，压外层 `.sidebar` 没用（Discord 左侧是 subgrid）。
- **隐藏服务器栏**（`system24-hide-server-list.theme.css`）：去掉最左那列服务器图标，切服务器改用 `Ctrl+K`。

想开就在 Equibop 设置 → Themes 里勾上；想改主题变量就编辑 `body { … }` 里那几行（每行后面有作者的英文注释），
或者在 Themes 里点主题旁的编辑按钮。改完照「改配置的正确姿势」收回包里。

---

## 3 · 插件与账号设置

- 开着的都是 Equicord 默认就开的 API / 修复类插件，没有额外装插件。
- **IrcColors**（**没开**）：按用户名哈希给每个人一个固定颜色，IRC 客户端那种效果。笔记本那套开过，
  合并时随源机器这套关掉了；想要就在设置 → Plugins 里搜它。
- 首次启动向导的选择：stable 分支；**不**开机自启（XDG autostart 在这套 Hyprland 下不一定生效，
  要自启改走 `mykeys.lua`）；**不**开 Rich Presence（arRPC 会把正在玩的游戏/程序公开给好友，还多一个常驻进程）；
  **开**最小化到托盘（noctalia 顶栏有 `tray`，关窗后照常收通知）。
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
   `@import url('https://refact0r.github.io/system24/build/system24.css')`
   （它还会顺带 `@import` midnight 和 Google Fonts 的 DM Mono，后者本包用不上）。代理（TUN）没开时会退回
   Discord 原生外观，不是主题坏了。本包只存「开关 + 配色」，样式规则本身**跟着上游 main 走、没有钉版本**：
   - 好处：Discord 改版把类名（`.wrapper__44b0c` 这种带哈希的）换掉、主题局部失效时，作者修完这边自动生效。
   - 坏处：上游改了样式也会**静默**生效；离线或 GitHub Pages 抽风时只剩配色变量，布局退回 Discord 原样。
   - 真要钉死：把 `build/system24.css` 下载进 `themes/`、`@import` 改成本地文件（代价是以后要自己跟进修复）。
2. **`sync.sh` 会经常报 `settings/settings.json` 不一致。** Equicord 自动更新会给新插件补默认条目，
   还会写时间戳（`cloud.settingsSyncVersion`）。先 `./sync.sh --diff` 看是不是这类噪音，再决定收不收。
3. **想加的选项先查主题文件里有没有现成变量。** 例如全局圆角就是 `--unrounding` 一个开关管所有面板、按钮、
   服务器图标（`src/unrounding.css`）。变量粒度不够时（只想要圆图标、面板保持直角）才写补丁主题，
   单独一个 `.theme.css` 文件，别往 `quickCss.css` 里塞 —— 主题列表里能单独开关，也一眼看得出是自写的。
4. **补丁主题里的类名带哈希**（`.svg_cc5dd2` 这种），Discord 改版会换掉，表现是补丁静默失效（比如图标又变方）。
   重新在 DevTools（`Ctrl+Shift+I`）里找新类名改掉即可。

---

## 6 · 评价（2026-10-15）

- **system24 值得用**：变量化做得好，所有改动都是改开关，不用碰选择器；和桌面 tokyo night 一套色，
  `--panel-labels` + 直角组合出来的终端感是别的 Discord 主题没有的。
- **短板**：依赖远程 `@import`（坑 1），本质上是「本地配置 + 在线主题」，不是完全离线可复现的；
  变量管不到的细节（如只圆图标）得写带哈希类名的补丁 CSS（坑 4），Discord 改版要跟着修。
- **不建议**：把面板标签关掉又想要 TUI 感 —— 笔记本试过，标签一关就不像了。

---

## 两台机器

两边都装了 Equibop，**8 个文件应逐字节相同**，没有本机路径和分辨率相关的值。

- 源机器（`/home/david`）照常改线上 → `./sync.sh --pull`。
- 笔记本**禁止 `--pull`**（`docs/11`），改了 Discord 配置就逐文件 `cp ~/.config/equibop/... config/equibop/...`
  → `git add` → `./sync.sh --manifest`。
- 2026-10-16 合并后笔记本那边要跟过去：先**完全退出 Equibop（含托盘）**，`git pull` 后跑 `./install.sh discord`，
  再开 Equibop 看头像和服务器图标是不是圆的。不退出的话 Equicord 会把内存里的旧设置写回 `settings/settings.json`。
