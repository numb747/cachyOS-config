# 13 · 应用启动器：Walker + Elephant（2026-10-09 替换 noctalia 自带启动器）

> `ALT+Space` 打开、`SUPER+.` 选 emoji、`SUPER+V` 剪贴板、顶栏最左那个按钮，四个入口现在都是 **Walker**。
> noctalia 自带的启动器和剪贴板面板没有卸载（它们是 noctalia 的一部分，卸不掉），只是不再有入口指向它们。
> 这一篇讲为什么换、换成了什么、配置在哪、踩过哪些坑。

## 为什么换

noctalia 自带启动器 bug 多，而且修不动。最典型的就是 [07 坑 10](07-troubleshooting.md)：
面板打开不到 1 秒自己关掉，根因始终没查清，只能靠 `bin/noct-panel` 挪指针兜住。
那次排查卡在一点上：**noctalia 所有面板共用同一个 layer surface**（启动器、剪贴板、
控制中心都画在这一个上面），开关、焦点、指针判断走的是它内部同一套逻辑，
从外面只能绕，没法修。功能上也有硬限制，比如
「已开窗口排在应用前面」上游 [#2470](https://github.com/noctalia-dev/noctalia/issues/2470)
已 closed as not planned（见 [05](05-theme-ui.md#启动器provider-模型已被-walker-取代)）。

想要的是：应用 + 已开窗口混在一起搜，加上 `g 空格 关键词 回车` 这种网页搜索前缀。

### 候选对比

| | 结论 |
|---|---|
| **Walker + Elephant** | ✅ 选它。独立进程、独立 layer surface，跟 noctalia 的面板系统完全无关；GTK4 + CSS 主题能直接吃 noctalia 生成的 `noctalia.css`，**换壁纸启动器跟着变色**，零维护；websearch 原生支持按引擎配前缀 |
| Vicinae（仿 Raycast） | 最精致，但 Qt + 带一个跑扩展的 Node 运行时，偏重；配色体系接不上 noctalia 的壁纸取色；「g 空格」这种用法文档里没查到原生支持 |
| fuzzel / rofi | 轻，但本质是 dmenu，窗口切换和网页搜索都得自己写脚本拼 |

**一条特别对症的**：Walker 的 layer 默认**四边锚定铺满整屏**（`[shell] anchor_* = true`），
中间那个框只是画在上面的内容。所以**指针在屏幕任何位置都落在 Walker 自己的 surface 里**，
坑 10 那种「指针在面板矩形外」的状态在结构上就不存在；点框外关闭是它自己判断点击位置
主动关的（`click_to_close`）。另外开了 `force_keyboard_focus = true`（独占键盘），
不给合成器挪焦点的余地。

## 架构：前端 + 后端

```
 ALT+Space ──► walker（GTK4 前端，常驻）  ◄─ 本地 socket ─►  elephant（数据后端，常驻）
               输入框 / 列表 / CSS 主题                      ├ desktopapplications
               只管画和交互                                  ├ windows      (wlr-foreign-toplevel)
                                                              ├ websearch    (g␣ b␣ gh␣ aw␣)
                                                              ├ symbols      (emoji / 符号)
                                                              ├ clipboard    (剪贴板历史, SUPER+V)
                                                              └ providerlist (; 前缀列出全部)
```

- **Walker** 只负责窗口、输入、渲染。不知道系统里有哪些应用和窗口。
- **Elephant** 预先索引好数据，收到查询返回结果；回车后的动作（启动应用、切窗口、开浏览器）
  也由它执行。每个能力是一个独立插件（`/usr/lib/elephant/*.so`）。
- 类比：Walker 之于 Elephant ≈ 编辑器之于 LSP。

两者都以 **systemd 用户服务**常驻（`~/.config/systemd/user/{elephant,walker}.service`，
`WantedBy/PartOf=graphical-session.target`）。`ALT+Space` 执行的 `walker` 只是叫醒常驻实例显示窗口，
再按一次关闭（`close_when_open`）。

没用 `elephant service enable` 自动生成的那份 unit：它缺 `PartOf`，退出 Hyprland 时不跟着停。

**启动应用不会被 elephant 连坐**：elephant 启动时自动探测到 uwsm（日志
`runprefix autodetect=uwsm-app --`），之后都用 `uwsm-app -- <Exec>` 起应用，
应用在独立的 systemd scope 里，`systemctl --user restart elephant` 不会把它们杀掉。

## 安装（全是 AUR 源码包）

```bash
yay -S aur/walker elephant elephant-desktopapplications elephant-windows \
       elephant-websearch elephant-providerlist elephant-symbols elephant-clipboard
# 然后用本地补丁版覆盖两个插件（剪贴板搜索规则见下方「剪贴板」，应用排序见坑 7）：
cd ~/cachyOS-config/aur/elephant-clipboard && makepkg -si
cd ~/cachyOS-config/aur/elephant-desktopapplications && makepkg -si
```

- **`aur/walker` 要写前缀**：CachyOS 仓库里也有 `walker`，版本落后（2026-10-09 时仓库 2.17.1，
  AUR 2.17.2 是前一天刚发的上游最新），不写 `aur/` yay 会优先装仓库那个。
- 两个 PKGBUILD 的维护者都是上游作者 benz（`hello@benz.dev`），源码直接从 GitHub tag 拉，
  不用自己打包。
- ★ **elephant 本体和所有插件必须同一次、用同一个 Go 工具链编出来。** 插件是
  `go build -buildmode=plugin` 产出的 `.so`，Go plugin 要求与宿主二进制的工具链和依赖版本
  **完全一致**，否则加载失败。所以：**别装 `elephant-bin`**（预编译本体 + 本地编译插件 = 必挂），
  **也别单独升级某一个插件**。以后升级让 yay 一次把 elephant 全家重编。
- Walker 和 Elephant 的版本号各走各的（walker 2.17.x 配 elephant 2.22.x 是对的），不用对齐数字。
- 首次安装时本机缺 `gtk4-layer-shell`（运行时）和 `gobject-introspection`（仅编译时，
  装成了 `--asdeps`，`pacman -Qdtq` 能清）。

然后 `./install.sh launcher` 拷配置并 `enable --now` 两个服务。

## 配置文件（想调什么改哪里）

| 文件 | 管什么 |
|---|---|
| `~/.config/walker/config.toml` | 只写和内置默认不同的项（Walker 把它**合并**到 `/etc/xdg/walker/config.toml` 上）：主题、独占键盘、无前缀时查哪些 provider、占位提示 |
| `~/.config/walker/themes/noctalia/style.css` | 主题 CSS，`@import` noctalia 生成的 `~/.config/gtk-4.0/noctalia.css` |
| `~/.config/walker/themes/noctalia/layout.xml` | 拷自默认布局：放大尺寸（框宽 1000，列表宽 960、最高 580）；**框贴上方、高度随结果伸缩**（输入框位置固定，没结果时缩成「输入框 + 一行提示」，不会留一个大空框） |
| `~/.config/elephant/websearch.toml` | 搜索引擎和前缀 |
| `~/.config/elephant/desktopapplications.toml` | 窗口优先：应用有窗口时回车聚焦它、排序让位给窗口；屏蔽 Waydroid 的同名副本（见坑 7） |
| `~/.config/elephant/windows.toml` | `show_workspaces = false`（工作区条目混在结果里只是噪音） |
| `~/.config/elephant/clipboard.toml` | 剪贴板：条数、不做 OCR、置顶排前、编辑器、选中后调 `clip-paste`（见下方「剪贴板」） |
| `~/.local/bin/clip-paste` | 剪贴板选中后的「复制 + 自动粘贴」 |

### 网页搜索前缀

| 敲 | 去 |
|---|---|
| `g 关键词` | Google（同时是 default 引擎：什么都没匹配上时直接回车也是谷歌） |
| `b 关键词` | 百度 |
| `gh 关键词` | GitHub 仓库搜索 |
| `aw 关键词` | Arch Wiki |

⚠ **前缀必须带尾随空格**（`prefix = "g "`）。源码里是裸的 `strings.HasPrefix`，
写成 `"g"` 的话搜 `gimp` 也会被当成 Google 搜索。激活时整段前缀会被切掉，只把后面的词交给引擎。
加引擎就在 `websearch.toml` 里再加一个 `[[entries]]`，改完 `systemctl --user restart elephant`。

### 其他前缀（Walker 内置默认，没改）

`.` 符号/emoji · `$` 只搜窗口 · `;` 列出所有 provider。
`=` 计算器、`>` 执行命令、`/` 文件、`:` 剪贴板、`!` 待办、`%` 书签这几个前缀是 Walker 内置默认，
但**对应插件没装，敲了没反应**。计算器是 2026-10-09 装过又按用户要求卸掉的（不需要）。

### 无前缀时查什么

```toml
[providers]
default = ["desktopapplications", "windows", "websearch"]
empty   = ["desktopapplications"]
```

- 敲字后应用、窗口、网页搜索一起出。和 noctalia 不同，这里**窗口和应用按同一个分数排序**
  （noctalia 那边应用永远在窗口前面，#2470）。但光靠这个，窗口其实常常排不过自己的应用，
  得另外配，见坑 7。
- 窗口条目副标题是窗口 class（`firefox`、`kitty`），应用条目副标题是 .desktop 的 Comment。
- 刚打开还没打字时**只列应用**，原因见下面坑 1。

### 配色跟着壁纸走

`style.css` 开头 `@import url("../../../gtk-4.0/noctalia.css")`，用的颜色名
（`@window_bg_color` `@window_fg_color` `@accent_color` `@card_bg_color` `@popover_bg_color`）
全是 noctalia gtk4 模板生成的。Walker **每次弹出都会重新 `load_from_file` 读 CSS**（`main.rs` 里
`setup_css` 在每次显示时调用），`@import` 也随之重解析——换壁纸后**下一次打开**就是新配色，
不用重启服务。

⚠ `@import` 必须写**相对路径**（以 style.css 所在目录为基准）。写成
`file:///home/david/...` 到笔记本（用户名 monkey）上就断，而且断了不报错，只是退回默认配色。

### 改完怎么生效

| 改了什么 | 怎么生效 |
|---|---|
| `style.css` | 下次打开自动生效 |
| `config.toml`、`layout.xml` | `systemctl --user restart walker`（只在启动时读） |
| `~/.config/elephant/*.toml` | `systemctl --user restart elephant` |

## 想加功能：可选插件一览

每个功能是一个 AUR 包，装了就能用（装完 `systemctl --user restart elephant`；
要它参与无前缀搜索就加进 `config.toml` 的 `providers.default`，否则靠前缀触发）。
⚠ 记住同次构建那条：新加插件时 yay 会顺带检查 elephant 本体版本，版本不一致就一起重编。

| 包 | 干什么 | 前缀 | 本机 |
|---|---|---|---|
| desktopapplications | 应用 | 无 | ✅ |
| windows | 已开窗口，回车跳过去 | `$` | ✅ |
| websearch | 网页搜索 | `g␣` `b␣` `gh␣` `aw␣` | ✅ |
| symbols | emoji / 符号，选中复制 | `.` | ✅（`SUPER+.`） |
| providerlist | 列出所有功能 | `;` | ✅ |
| calc | 计算器 / 单位换算 | `=` | ❌ 用户不要 |
| clipboard | 剪贴板历史 | `:` | ✅（`SUPER+V`，见下方「剪贴板」） |
| files | 文件搜索（fd 索引 $HOME） | `/` | ❌ |
| runner | 执行任意命令 | `>` | ❌ |
| bookmarks | 浏览器书签 | `%` | ❌ |
| todo | 带计时提醒的待办 | `!` | ❌ |
| snippets | 文本片段 | 自定义 | ❌ |
| menus | 自定义菜单（Lua/TOML 写，比如把常用脚本做成一个菜单） | 自定义 | ❌ |
| unicode | 全 Unicode 字符搜索 | 自定义 | ❌ |
| archlinuxpkgs | 搜索/安装/卸载 pacman 和 AUR 包 | 自定义 | ❌ |
| bluetooth / wireplumber / playerctl | 蓝牙 / 音频设备 / 媒体控制 | 自定义 | ❌ noctalia 顶栏已有 |
| 1password / bitwarden | 密码管理器 | 自定义 | ❌ |

## 入口接线

| 入口 | 在哪 |
|---|---|
| `ALT+Space` → `walker` | `config/hypr/mykeys.lua` 第 12 节 |
| `SUPER+.` → `walker -m symbols` | 同上；第 1 节 `hl.unbind("SUPER + period")` 摘掉官方的 `launcher /emo` |
| `SUPER+V` → `walker -m clipboard` | `config/hypr/mykeys.lua` 第 18 节（原来调 `bin/noct-panel clipboard`） |
| 顶栏最左按钮 | `config/noctalia/config.toml` 的 `[widget.launcher.actions] left = "exec walker"`——图标还是 noctalia 的 launcher 组件，只覆盖左键动作（noctalia v5 每个组件都能这么改，见[官方文档 Widget Actions](https://docs.noctalia.dev/noctalia/bar/actions/)） |

emoji 选中后是**复制到剪贴板**（elephant-symbols 默认 `command = "wl-copy"`），再 `Ctrl+V` 粘。
搜索语言是英文（`smile`、`heart`）；想用中文搜（「笑」）在 `~/.config/elephant/symbols.toml`
写 `locale = "zh"`，但它**只认一种语言**，换成中文后英文关键词就搜不到了。

## 剪贴板

2026-10-09 起 `SUPER+V` 也从 noctalia 面板换成了 Walker（`elephant-clipboard` 插件），
原因同启动器：noctalia 面板「一闪就关」（[07 坑 10](07-troubleshooting.md)），之前靠
`bin/noct-panel` 挪指针兜着。

| 操作 | 键 |
|---|---|
| 粘贴（复制 + 自动粘进当前窗口） | `Enter` |
| 删除这条 / 清空 | `Ctrl+D` / `Ctrl+Shift+D` |
| 置顶 / 取消置顶（置顶的排最上面） | `Ctrl+P` |
| 编辑后再用（图片进 satty，文本进默认编辑器） | `Ctrl+O` |
| 只看图片 / 只看文本 / 只看置顶 / 全部 | `Ctrl+I` 循环 |
| 暂停 / 恢复记录（复制密码前按） | `Ctrl+Shift+P` |

**搜索规则（本地补丁）**：不分大小写的子串匹配，空格分隔多个词表示都要包含，结果按时间从新到旧。
上游原版是模糊匹配且「位置越靠后扣分越多」，长段落中间的词根本搜不到（搜 `苦杏仁` 0 条）。
补丁和重装方法在 `aur/elephant-clipboard/`，说明见 [aur/README.md](../aur/README.md)。
⚠ elephant 每次升级后要回来重打，否则搜索静默退回原版。

配置 `~/.config/elephant/clipboard.toml`：`max_items = 300`（和原 noctalia 设置对齐）、
`ocr = false`（它的 OCR 是 tesseract，中文差，用户明确不要；屏幕取字另有 RapidOCR，见 [10](10-ocr.md)）、
`pinned_on_top = true`、`image_editor_cmd = "satty -f %FILE%"`、`command = "$HOME/.local/bin/clip-paste"`。

### 自动粘贴：`bin/clip-paste`

noctalia 原来是 `clipboard_auto_paste = "auto"`（选中即粘贴），elephant 默认只复制。
`clip-paste` 补上这一步：`wl-copy "$@"` → 等 0.15 秒让 Walker 关掉、焦点回到原窗口 →
看当前窗口类名，终端发 `Ctrl+Shift+V`、其他发 `Ctrl+V`。

- 必须透传 `"$@"`：elephant 复制文件列表时会在命令后追加 `-t 'text/uri-list'`。
- 用 `$HOME/.local/bin/...` 绝对路径：elephant 是 systemd 用户服务，PATH 里没有 `~/.local/bin`。
- 终端类名单抄自 `config/windowrules.lua` 的 `terminals`，加了新终端两边一起改。
- ★ 按键走 **Hyprland 的 `send_shortcut`**，不是 wtype，理由见坑 5。

2026-10-09 端到端实测（开目标窗口 → `walker -m clipboard` → 回车 → 截图）：
kitty 里粘贴成功（Ctrl+Shift+V），zenity 输入框里粘贴成功（Ctrl+V），中文正常。

### 和 noctalia 剪贴板的取舍

| | noctalia（原来） | elephant（现在） |
|---|---|---|
| 面板自关 bug | 有，靠 noct-panel 兜 | 结构上没有 |
| 预览 | 有 | 有（右侧大预览，图片直接显示） |
| 编辑后再用 / 暂停记录 / 按类型筛选 | 无 | 有 |
| 自动粘贴 | 原生 | 靠 `clip-paste` 补 |
| 存储 | **加密**（`[storage]` 文件密钥） | ⚠ **明文**：`~/.cache/elephant/clipboard.gob`（0600）+ `clipboardimages/*.png` |
| 源程序关掉后还能粘 | 有（`keep_from_closed_apps`） | 无 |

**noctalia 的剪贴板服务没关**（`[shell] clipboard_enabled` 仍是 true），只是没有键位指向它的面板。
留着是为了「源程序关掉后还能粘」这一条，代价是它也在后台加密存一份历史。
不要这个功能的话，在 noctalia 设置里关掉 Clipboard 即可。

⚠ 换过来时**历史不迁移**：elephant 从安装那一刻开始记，noctalia 那份加密历史读不过来。

## 调试

```bash
# 绕过 Walker 直接问后端（provider;查询;条数;精确匹配）
elephant query --json "desktopapplications,windows,websearch;g 天气;8;false" \
  | jq -r 'select(.item) | "\(.item.provider)\t\(.item.score)\t\(.item.text)"'

journalctl --user -u elephant -f      # 后端日志：插件加载、启动命令
journalctl --user -u walker -f        # 前端日志
elephant listproviders                # 已加载的插件
elephant generate doc <provider>      # 某插件全部配置项（和默认值）
```

## 坑

### 坑 1：企业微信的幽灵窗口会在窗口列表里显示成空白行

> 2026-10-09 wine 版企业微信已卸载（[09](09-wine-apps.md)），这个坑的来源没了。
> `empty = ["desktopapplications"]` 暂保持原样，以后别的程序冒出无标题窗口还是同一套绕法。

企业微信（wine）有几个**无标题**的幽灵窗口，Hyprland 里被规则停放在
`special:wine_ghosts`。Elephant 的 windows 插件走的是
`wlr-foreign-toplevel` 协议，**看不到工作区**，也**没有任何过滤选项**（只有 `delay` /
`show_workspaces` / `show_empty_workspaces`），于是原样列出来：图标是个通用图标，标题空白，
副标题 `wxwork.exe`。

绕法：`empty = ["desktopapplications"]`，空查询时不查窗口。敲字后它们标题为空，
只有敲 `wx…` 匹配到副标题才会冒出来，日常碰不到。
真要根治得给 elephant 的 `internal/providers/windows/setup.go` 加一句「标题为空就跳过」，
那就成了要自己维护的补丁，目前不值得。

### 坑 2：Hyprland 的 layer 毛玻璃对 Walker 不生效（原因未查）

本想像终端那样给框底下加模糊。试过 `hl.layer_rule({ match = { namespace = "walker" }, blur = true })`，
带/不带 `ignore_alpha`、规则加载后**重启 walker 服务**再测（layer 规则在 surface 创建时求值，
常驻服务的 surface 是旧的，所以必须重启），grim 截图里框底下的终端文字**始终清晰**，没有被模糊。

排除过的方向：不是合成器把 layer 变透明了——底色写死 `#ff0000` 截出来是纯 `(255,0,0)`。

于是放弃模糊，框底色改为**完全不透明**（`background: @window_bg_color`）。
没有模糊的半透明很难看：0.88 时底下文字清楚可见，0.98 都还看得见残影。
以后想再试，记得「改规则 → `hyprctl reload` → `systemctl --user restart walker` → 再截图」这个顺序。

### 坑 3：应用名是英文

本机 `LANG=en_US.UTF-8`，所以 .desktop 取的是 `Name=` 而不是 `Name[zh_CN]=`。
中文名的应用照样能搜到，因为
elephant 也匹配 Comment / Keywords（当初 wine 版企业微信的 Comment 写了「企业通讯」，搜「企业」就能出来）。
想全切中文：`~/.config/elephant/desktopapplications.toml` 写 `locale = "zh_CN"`。
⚠ 拼音搜中文名**不支持**（noctalia 那边也不支持，换启动器不涉及这条）。

### 坑 4：装了新的 elephant 插件后，Walker 一打开那个模式就崩

2026-10-09 装 `elephant-clipboard` 后第一次按 `SUPER+V`，walker 直接 core dump：

```
thread 'main' panicked at src/renderers/mod.rs:22:36:
failed to get item layout: clipboard
```

Walker 常驻服务**启动时**按「当时 elephant 已加载的插件」给每类条目建渲染模板；之后才装的插件
没有模板，一出结果就 panic（而且是 non-unwinding panic，整个进程 abort）。systemd 会自动拉起，
所以第二次按就正常了，看起来像「偶发崩溃」。

**规矩：装了新插件，`systemctl --user restart elephant walker` 两个一起重启。**
`install.sh launcher` 已经在末尾做了这步。

### 坑 6：空结果时中间一个大空框

默认布局把框写死 570 高、垂直居中。没有结果时列表和预览都隐藏，只剩一行居中的提示，
看起来就是一大块空白。改成 Raycast 的做法：`BoxWrapper` 用 `valign=start` + `margin-top=260`，
删掉 `height-request`，框随内容伸缩，输入框始终在同一位置。
空结果提示也按模式分开写（`[placeholders]`），剪贴板是「没有匹配的内容」而不是「历史是空的」。

### 坑 5：wtype 发的 Ctrl+Shift+V 在 kitty 里粘不进去

自动粘贴最初用 wtype（virtual-keyboard 协议）。实测：`wtype 'abc'` 打字正常，
但 `wtype -M ctrl -M shift v -m shift -m ctrl` 在 kitty 里**什么都粘不进去**，截图里 kitty
光标还变成了空心（它认为自己失焦了）。换成 Hyprland 自己投递
`hyprctl dispatch 'hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "V" })'` 立刻正常，
之后继续打字也不受影响（社区报过 send_shortcut「只发按下不发松开」，本机没复现）。
所以 **不需要装 wtype**；以后也别为了「更通用」换回去。

⚠ 测这个别用「kitty 里跑 `cat > 文件`、看文件内容」：终端行缓冲在收到回车前不交给 cat，
而回车本身又可能被别的东西吃掉，文件为空不代表没粘上。**用截图判断。**

### 坑 7：同一个应用，窗口开着却排在「启动新实例」后面

2026-10-09 现象：LocalSend 开着，搜 `local` 出来三条同名 LocalSend，第一条是开新实例，窗口排第三。
三条分别是：Waydroid 导出的**安卓版** LocalSend、原生 `localsend.desktop`、windows 插件给的窗口。
名字一样，模糊匹配分完全相同（140），拉开差距的全是**历史分**：

- desktopapplications 默认 `history = true`，启动过的应用加分（`localsend.desktop` +20，安卓版 +2）；
- windows 插件**没有历史机制**，窗口永远只有裸匹配分。

所以「用过的应用」必然压过「开着的窗口」。上游有现成的对策 `score_open_windows`
（有窗口的应用分数减半，默认就是 true），但源码里 `hasWindow` 只在 `window_integration = true`
时才计算——**不开 window_integration，score_open_windows 完全不生效**，文档里那句
「Requires window_integration」就是这个意思。

`desktopapplications.toml` 的做法：

1. `window_integration = true`：「有窗口就压分」生效，窗口排到前面；顺带应用条目回车也是聚焦已有窗口。
   **真要开新实例按 `Ctrl+Return`**（Walker 内置的 `new_instance` 动作）。
2. `blacklist` 掉同名副本，否则它们没有窗口、不会减半，照样压着窗口：
   Waydroid 安卓版 LocalSend。（当初还屏蔽了 `~/.wine` 里 Windows 版 Firefox 的两个开始菜单快捷方式，
   和原生窗口同分 192=192、谁先随机；2026-10-09 wine 整套卸载，那条 blacklist 一并删了。）
   blacklist 是正则，匹配**去掉 .desktop 的文件名**（子目录里的也只看文件名），要加 `^…$`。

#### 减半太粗：无关条目夹进窗口和应用中间 → 本地补丁

上面两步做完，窗口确实第一了，但搜 `local` 第二条变成了 **LibreOffice Calc**：

| 条目 | 分 | |
|---|---|---|
| LocalSend 窗口 | 140 | |
| LibreOffice Calc | 123 | 模糊匹配 **L**ibre**O**ffice **Cal**c，三处都在词首，加成很高 |
| Hardware Locality lstopo | 122 | |
| WeCom | 97 | 匹配的是 Exec 路径 `/home/david/.local/bin/…` |
| LocalSend 应用 | 72 | 144 减半 |

减半只保证「应用在自己窗口之下」，不管中间夹进多少别的。减半是上游写死的
（`query.go` 里 `score / 2`），配置调不了。

补丁（`aur/elephant-desktopapplications/`，fork 的 `desktopapps-window-first` 分支）：
**有窗口的应用分数 = 它窗口的分数 − 1**，窗口分用和 windows 插件完全相同的算法
（标题、app_id 取高者，`max(分 − 起始位置, 10)`），多个窗口取最高的。这样应用紧贴在自己窗口下面。
窗口分不超过 `min_score`（30，窗口基本没匹配上）时不动应用的分。

实测（隔离实例对比，2026-10-09）：

| 搜 | 原版 第 2 条 | 补丁版 第 2 条 |
|---|---|---|
| `local` | LibreOffice Calc 123 | LocalSend 应用 139 |
| `fire` | Firefox 58（与 LibreOffice Impress 56 只差 2） | Firefox 113 |
| `excal` | LibreOffice Calc 75 | Excalidraw 139 |
| `libre`（无窗口） | 不变 | 不变 |

WeCom / Excalidraw 因 Exec 路径含 `.local` 被搜出来是另一回事：`only_search_title = true` 能去掉，
但会连 Comment 一起不搜（搜「企业」就出不来 WeCom，见坑 3），没开。

还剩的、有意没修的：

- **Waydroid 应用的窗口识别不出来**。elephant 判断「这个应用有没有窗口」只拿窗口 app_id 去比
  `StartupWMClass` / `Icon` / `Exec` 第一个词，而 Waydroid 窗口的 app_id 是
  `waydroid.<包名>`，恰好等于 .desktop 文件名——上游没比这一项。要修得改
  `internal/providers/desktopapplications/activate.go` 的 `appHasWindow`，又多一个要维护的补丁，
  用户决定先不做。影响：搜 `wecom` 时安卓 WeCom 的窗口排在 WeCom 应用条目后面。
- **补丁版被升级冲掉时会退回「减半」**：窗口仍第一，只是无关条目又会夹进来。到时候按
  `aur/README.md` 重打。（打补丁前还有一个「历史分累加到能翻盘」的理论风险，
  补丁版直接用窗口分覆盖应用分，这条不存在了。）

## 回退到 noctalia 启动器

三处改回去即可，noctalia 那边的 `[shell.launcher]` 配置一直保留着没删：

1. `mykeys.lua` 第 12 节：`hl.bind("ALT + Space", hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher"))`；
   删掉 `SUPER + period` 的 unbind 和 bind；第 18 节 `SUPER+V` 换回 `$HOME/.local/bin/noct-panel clipboard`
2. `config.toml` 删掉 `[widget.launcher.actions]`
3. `systemctl --user disable --now walker elephant`
