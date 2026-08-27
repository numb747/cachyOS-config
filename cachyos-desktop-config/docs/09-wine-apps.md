# 09 · wine 应用（winapp 与企业微信）

在 wine 里跑 Windows 程序的工具链：**每个应用一套独立 prefix + bubblewrap 沙箱**。
由 `install.sh wine` 安装，`manifest.map` 的 `#@module wine` 段是路径的单一事实来源。

目前只有企业微信一个实例。全部实测于 **2026-08-27**，wine-staging 11.16、企业微信 5.0.10.6015。
第 5 节那些坑每一条都真实浪费过时间，改之前先看。

---

## 1 · 为什么必须是 wine

三条都是实测，不是听说：

1. **企业微信公有云版没有 Linux 客户端。** 官网下载接口
   `work.weixin.qq.com/wework_admin/commdownload?platform=linux` 返回的是
   `WeCom_5.0.10.6015.exe`——腾讯自己拿 Windows exe 兜底。
2. **官网那个 Linux 包是私有部署版。** `work.weixin.qq.com/server` 页确实提供
   deb/rpm/AppImage，但文件名是 `weworklocal_3.5.0.2224.x86_64.*`——`weworklocal`
   只能连自建服务器，公有云账号登不上去。
3. **不存在员工聊天网页版。** `work.weixin.qq.com` 上能扫码登录的只是**管理后台**
   （管通讯录、建应用），收发不了消息。搜索结果里那些「企业微信网页版登录入口」
   全是标题党。

## 2 · 为什么是上游 wine 而不是 deepin-wine

AUR 有 `com.qq.weixin.work.deepin`（星火商店重打包），成功率确实更高——它的补丁就是
为腾讯系写的。没选它的理由：

| | 上游 wine-staging | deepin-wine |
|---|---|---|
| wine 版本 | 11.16，`extra` 官方仓库，跟随滚动 | wine 8 + wine 10 两个 deepin 分支**并存** |
| 企业微信版本 | 5.0.10.6015，腾讯官方 CDN 直取 | 5.0.0.6008，第三方**重打包** |
| 体积 | 官方仓库包 | ~1.5 GB 第三方二进制 |
| 沙箱友好度 | 高，WINEPREFIX 自包含 | 低，依赖 `/opt` 下多个组件 |
| 出问题时 | 可控，能看 wine 日志自己调 | 黑盒，改别人的 `run.sh` |

**结论：最新版企业微信在原版 wine-staging 上跑得通**，不需要 deepin 那套补丁。
这一点和社区经验相反——网上的成功报告集中在 4.x 时代，5.x 反而没人试。

## 3 · winapp 工具链

```
winapp create  <名字>              建 prefix，按配置设好 Windows 版本与运行库
winapp install <名字> <安装器.exe>  在该 prefix 里跑安装器（不沙箱，装东西要能写）
winapp run     <名字> [exe]        启动（默认沙箱）
winapp stop    <名字>              停掉该应用的所有实例
winapp check   <名字>              ★ 用相同的沙箱参数跑 ls，看它到底能访问什么
winapp shell   <名字> <命令...>     在 prefix 环境里执行任意命令，如 winapp shell wecom winecfg
winapp list                        列出所有应用及其 prefix 大小
winapp remove  <名字>              删掉 prefix（配置保留）
```

每应用一份配置 `~/.config/winapp/<名字>.conf`，`create` 时自动生成模板。

**刻意不共用 prefix。** 不同应用要各自的 Windows 版本、DLL override 和 winetricks 组件，
塞进同一个 prefix 会互相污染——一个应用装坏了会连累其他所有应用。wine 本体是 pacman
装的系统级组件，那一层本来就是共用的，"复用"应该复用在工具链而不是 prefix。

### 沙箱边界

`--tmpfs $HOME` 先把整个家目录抹掉，再按**白名单**bind 回来。白名单而非黑名单：
以后新增的敏感目录默认就是不可见的，不用记得去补黑名单。

- **放行**：XDG 文档目录（`Desktop Documents Downloads Music Pictures Videos Public Templates`）、
  该应用自己的 prefix、fontconfig（只读）
- **自动挡住**：`~/.ssh` `~/.gnupg` `~/.claude` `~/ccconfig` `~/Projects` `~/go`
  **`~/hacktools` `~/myTestAndSecurity`** 以及所有其他点目录

别口头相信，用 `winapp check wecom` 实测——它用**完全相同**的 bwrap 参数跑 `ls`：

```
$ winapp check wecom
· wecom 在沙箱里能看到的家目录内容：
    .cache  .config  .local  Desktop  Documents  Downloads  Music  Pictures  Public  Templates  Videos
· 抽查几个敏感位置：
    ✓ 挡住  ~/.ssh      ✓ 挡住  ~/ccconfig    ✓ 挡住  ~/hacktools
    ✓ 挡住  ~/.claude   ✓ 挡住  ~/Projects    ✓ 挡住  ~/myTestAndSecurity
```

`.config`/`.local`/`.cache` 出现在列表里是**挂载点的必经路径**，不是泄漏：宿主
`~/.config` 有 44 项，沙箱里只有 `fontconfig` 一项；`.local/share` 里只有 `wineprefixes`。

## 4 · 新机器装企业微信

prefix 有 2 GB+（含聊天记录与登录态），安装包 600 MB，都**不入包**。

```bash
# 1. 拿官方最新版下载直链（公有云版，不是 /server 页那个私有部署版）
curl -sIL 'https://work.weixin.qq.com/wework_admin/commdownload?platform=win' \
  | sed -n 's/^location: //Ip' | tail -1
# → https://dldir1.qq.com/wework/work_weixin/WeCom_5.0.10.6015.exe

# 2. 下载后建环境并安装
winapp create wecom
winapp install wecom ~/Downloads/WeCom_5.0.10.6015.exe   # 图形安装界面，点「立即安装」

# 3. 启动（或直接用启动器里的「企业微信」条目）
winapp run wecom
```

安装界面里**不要勾「开机自动启动企业微信」**——它会绕过 wrapper 裸启动，沙箱和输入法
环境全都白搭。

`wecom.conf` 里两项值得注意：`WIN_VERSION=win81`（社区经验：win10 下 CEF 有兼容问题）、
`VDESKTOP=""`（**刻意留空**，理由见坑 4）。

---

## 5 · 坑

### 坑 1 ★ 窗口规则要用 `initial_title`，不能用 `title`

企业微信除主窗口外还会创建几个空白窗口（一个约 986x28 的细条、一个和主窗口差不多大的
纯白窗、两个 0x0 的隐藏窗）。它们都浮动，而 Hyprland 里**浮动窗恒在平铺窗之上**，
于是那个白窗正好把主界面整个罩住。

想当然的写法是拿 `title = "^$"` 抓它们。**这是错的**：窗口规则在**创建时**求值，
而那一刻**所有**窗口的 `title` 都还是空的，主窗口会被一起误伤。当初给它们加
`no_focus`，结果是整个企业微信窗口点不动、鼠标点击全部落空，往 CEF / GPU / Windows
版本方向查了很久才发现是自己的规则干的。

`initial_title` 记录的是**创建那一刻**的标题，主窗口从一开始就是「企业微信」，
幽灵窗从一开始就是空——这才是稳定判据：

```lua
hl.window_rule({
    name  = "wecom-ghost-windows",
    match = { class = "^(wxwork\\.exe)$", initial_title = "^$", xwayland = true },
    workspace = "special:wine_ghosts silent",
})
```

★ 不要再加 `float = true` 收窄条件：那个 986x28 的细条在**创建瞬间**还不是浮动的，
加上就漏网了。`initial_title` 本身已经足够精确。

规则里除 `workspace` 外还带了 `move = {"-9999","-9999"}` 和 `decorate = false`：
`opacity` 只作用于窗口**内容**，Hyprland 画的**边框**照样可见，那圈边框本身就是
肉眼看到的"白框"。挪出屏幕比调透明度可靠。

### 遗留：28px 细条治不了，别再花时间（2026-08-27 结论）

主窗口顶部那条 `<主窗口宽度>x28` 的空白细条**无法用窗口规则处理**，已确认无解：

- 它的位置和宽度**完全跟随主窗口**，Hyprland 显示它但不独立管理其几何，
  `workspace` / `move` / `decorate` 规则**全部落空**（同一条规则对旁边那个
  1022x686 的大白框却完全有效，对比很明显）
- ★ **不要试图关掉它**：实测 `hl.dsp.window.close({window="address:0x…"})`
  精确关闭这个细条，会**连带关闭整个企业微信**（7 个进程全部退出）。
  它不是独立的装饰窗，而是主窗口的附属物
- `winecfg` 的 `Decorated=N`（`HKEY_CURRENT_USER\Software\Wine\X11 Driver`）
  **无效**，试过了，细条照旧，已回退不留

结论：**接受它**。它不遮挡主界面内容、不影响任何功能，纯属观感问题。

### 坑 2 ★ bwrap 不能加 `--unshare-ipc`

X11 的 **MIT-SHM** 扩展靠 System V 共享内存传图像。隔离 IPC namespace 后 X server
和客户端共享不了内存段，程序一调 `X_ShmPutImage` 就收到 `BadValue` 并**崩溃退出**：

```
X Error of failed request:  BadValue
  Major opcode of failed request:  130 (MIT-SHM)
  Minor opcode of failed request:  3 (X_ShmPutImage)
```

挡住 SysV IPC 的那点收益不值这个代价。`--unshare-pid`/`--unshare-uts` 保留没问题。

这个 bug 一度被虚拟桌面掩盖着（那条渲染路径绕开 MIT-SHM），撤掉虚拟桌面才暴露，
表现为"偶尔启动崩溃"。

### 坑 3 ★ `--die-with-parent` + 终端启动 = 命令一结束应用就死

`--die-with-parent` 盯的是**父进程**。从终端 `winapp run` 后，shell 一退出 bwrap
就跟着走，看起来像"应用莫名其妙崩溃"。**桌面启动器不受影响**（父进程是 systemd），
所以同一份配置从启动器起就好好的、从终端起就活不过几秒，极易误判。

调试时用 `setsid --fork winapp run wecom`，强制交给 init 收养。

### 坑 4 ★ 不要用虚拟桌面（`explorer /desktop`）治幽灵窗

`VDESKTOP` 这个功能在 `winapp` 里保留着，但**企业微信刻意不用**。它确实能把幽灵窗
收编进一个容器，代价却是：

- 多一层容器窗口，画布尺寸要和窗口尺寸手工对齐，对不上就裁切或留黑边
- 实测偶发启动崩溃
- 容器里的桌面图标**双击不响应**（wine explorer 桌面的固有行为）——曾经因此
  误判成"企业微信点不动"，实际程序本身一直是好的

★ 最坑的是**残留**：虚拟桌面的 explorer 进程如果没被清干净，会留下一个孤儿窗常驻在
屏幕上。我们追查了很久的"大白屏"，最后发现是自己上一轮的残骸，不是企业微信的问题。

幽灵窗用坑 1 的窗口规则治，干净得多。

### 坑 5 沙箱实例用 `wineserver -k` 杀不掉

沙箱带 `--unshare-pid`，wineserver 活在自己的 PID namespace 里，外面那句
`wineserver -k` 根本够不着它。必须直接杀 bwrap，靠 `--die-with-parent` 让里面的
wine 跟着退出。`winapp stop` 已经这么做了。

★ 定位进程要按 `/proc/<pid>/cmdline` 精确匹配，**不能用 `pkill -f`**——后者会把正在
执行这段逻辑的 shell 自己也匹配进去（命令行里含同样的字符串），当场自杀（表现为
退出码 144）。这个坑在排查期间还误杀过 noctalia，导致顶栏和壁纸一起消失。

### 坑 6 winemenubuilder 会污染启动器和文件关联

wine 默认把 Windows 的开始菜单项和文件关联翻译成 `.desktop` 塞进
`~/.local/share/applications/`。实测装完企业微信后多出：一个**不带输入法环境、
也不进沙箱**的「企业微信」条目、一个「卸载企业微信」、以及 6 个 `wine-extension-*`
（把 `.chm`/`.reg`/`.vbs` 等扩展名的默认打开方式抢走）。

那个裸条目最坑：它能正常启动、界面也对，**就是打不出中文**（没有 `XMODIFIERS`），
而且完全不经过沙箱。用户很容易点到它然后以为配置没生效。

`winapp` 已用 `WINEDLLOVERRIDES=winemenubuilder.exe=d` 全程禁掉它。已经被污染过的话：

```bash
rm -rf ~/.local/share/applications/wine/ ~/.local/share/applications/wine-extension-*.desktop
update-desktop-database ~/.local/share/applications
```

### 坑 7 中文输入要 `XMODIFIERS`，但**不要**设 `GTK_IM_MODULE`/`QT_IM_MODULE`

wine 跑在 XWayland 上，走 XIM 才能用 fcitx5，所以 `XMODIFIERS=@im=fcitx` 必须有。
但**只在 wrapper 里注入，不要写进 `~/.config/uwsm/env`**：设成全局会让所有 XWayland
应用改走 XIM，而 `GTK_IM_MODULE`/`QT_IM_MODULE` 更会把原生 Wayland 应用从
text-input-v3 拉回旧模块，是倒退。

### 坑 8 wine 不走 fontconfig，字体要真的放进 prefix

wine 不读系统 fontconfig，得把字体文件软链进 `$WINEPREFIX/drive_c/windows/Fonts/`，
再往注册表 `FontSubstitutes` 写替换关系——企业微信这类国产软件把 `SimSun`/`微软雅黑`
硬编码在界面里，装不到就画方块。`winapp` 的 `CJK=1` 已自动处理（软链而非复制，
系统字体升级后 prefix 自动跟上）。

---

## 6 · 排除掉的错误方向（别再往这查）

排查"企业微信点不动"时走过的弯路，**这些都不是原因**：

| 曾经怀疑 | 实测结论 |
|---|---|
| **GPU / 软件渲染** | 日志里 `vulkan` 枚举失败、`amdgpu_get_auth failed`、`egl dri2 screen` 创建失败很唬人，但强制软件渲染（`LIBGL_ALWAYS_SOFTWARE=1`）**并不能**消除幽灵窗，反而让主窗口更小（580x394 vs 672x801）。**那些 GPU 报错是噪音。** |
| **Windows 版本（win10 vs win81）** | `win81` 确实有效果，但它治的是 CEF 子进程 `WXWorkWeb.exe` 的偶发 `int3` 崩溃，**跟点不动无关**。主界面是原生 Win32 控件，不经过 CEF。 |
| **窗口尺寸与虚拟桌面画布不一致** | 看着像坐标错位，其实不是——安装器阶段两者同样不一致（1265x705 对 1100x750）却能正常点击。 |
| **bwrap 沙箱** | 裸跑同样点不动，与沙箱无关。 |

真正的原因是坑 1（自己的窗口规则误伤）和坑 4（虚拟桌面的桌面图标本来就不响应双击）。

**教训**：`err:` 开头的日志不等于病根。先确认"哪个窗口/哪个进程"，再查"为什么"——
当初如果早点用 `hyprctl clients -j` 把窗口逐个列出来看 `initialTitle`，能省下大半时间。

---

## 7 · 验收

```bash
winapp list                  # prefix 在不在、多大
winapp check wecom           # ★ 沙箱边界，敏感目录必须全是「挡住」
```

启动后逐项确认：

1. 扫码登录
2. 收发中文消息 —— **fcitx5 能在聊天框打中文**（坑 7 那条链路）
3. 发文件：文件选择器里能看到 `~/Downloads`，**看不到** `~/hacktools`、`~/Projects`
4. 收文件：能落盘并打开
5. 屏幕上**没有空白窗口遮挡**（坑 1 的规则生效了）

窗口状态可以直接查，`漏网 0` 才算干净：

```bash
hyprctl clients -j | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if 'wxwork' in (c.get('class') or '').lower():
        print(c.get('initialTitle') or '(幽灵)', c.get('size'), (c.get('workspace') or {}).get('name'))
"
```

正常输出：主窗口在当前工作区，幽灵窗全部在 `special:wine_ghosts`。
