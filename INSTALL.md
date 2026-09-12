# 全新机器安装流程

从刚装完系统到完全复现，大约 20 分钟（不含下载时间）。

---

## 前提

| 项 | 要求 | 怎么确认 |
|---|---|---|
| 发行版 | CachyOS（或 Arch 系） | `cat /etc/os-release` |
| 桌面 | **Hyprland ≥ 0.56，Lua 配置** | `ls ~/.config/hypr/hyprland.lua` 存在 |
| 基线包 | `cachyos-hypr-noctalia` | `pacman -Q cachyos-hypr-noctalia` |

> **传统 `hyprland.conf` 用不了本包的键位模块。** `hl.bind` / `hl.dsp.*` 是 0.56+ 的
> Lua API，`bind = SUPER, F, fullscreen, 0` 那种写法需要整体翻译。`install.sh` 会
> 检查并中止 hypr 模块，其余模块仍可正常安装。
>
> 装 CachyOS 时在桌面环境里选 **Hyprland** 就自带以上全部。

---

## 步骤

### 1. 装包

```bash
sudo pacman -Syu
sudo pacman -S --needed $(grep -vE '^\s*(#|$)' packages.txt | tr '\n' ' ')
```

`packages.txt` 末尾的「可选」段落是注释掉的，按需自己装。

**屏幕取字（ocr 模块）的运行时要单独处理** —— `python-rapidocr` 在 AUR，
而且**不能直接 `yay -S`**（上游 PKGBUILD 的 `makedepends` 写了
`python-installer>=1.0.1`，Arch 全仓库最新只有 1.0.0，必然报
`could not find all required packages`）。改好的 PKGBUILD 已经在包里：

```bash
sudo pacman -S --needed python-onnxruntime-cpu
cd aur/python-rapidocr && makepkg -si && cd ../..

# 装完锁更新：否则下次 -Syu 会拿官方 PKGBUILD 重建，再撞同一个错
sudo sed -i 's/^#IgnorePkg\s*=\s*$/IgnorePkg   = python-rapidocr/' /etc/pacman.conf
```

⚠ 它会连带拉进 opencv 全套（含 vtk 371 MB），共约 936 MB 磁盘。
不需要屏幕取字就跳过这段，其余模块不受影响（只是按 `Super+Shift+O` 会提示服务连不上）。
缘由、投毒复核方法见 `aur/README.md`，用法见 `docs/10-ocr.md`。

### 2. 改登录 shell（需要密码，脚本不代劳）

```bash
chsh -s "$(command -v zsh)"
```

> `chsh: Shell not changed.` **是成功信息**，不是报错——说明当前已经是 zsh 了。
> 原因见 [docs/07 坑 3](docs/07-troubleshooting.md#坑-3--echo-shell-显示的不是-zshchsh-说-shell-not-changed)。

### 3. 先看一眼会做什么（可选但推荐）

```bash
./install.sh --dry-run
```

不动任何文件，只打印每一步。确认没有意外后再真跑。

### 4. 装

```bash
./install.sh              # 全部
./install.sh hypr nvim    # 或者只装指定模块，--list 看有哪些
```

每个被覆盖的已有文件都会先备份成 `<名字>.bak-YYYYmmdd-HHMMSS`。
脚本是幂等的，重复执行结果一致。

### 5. 注销，重新登录 Hyprland

`~/.config/uwsm/env` 和登录 shell 都**只在登录那一刻读一次**，`source` 一下不够。

### 6. 首次进 nvim

```bash
nvim        # 等 lazy 把 46 个插件装完再操作
```

语言 LSP / formatter 要在 `:Mason` 里另装，前置运行时见
[docs/04](docs/04-neovim.md#语言工具链mason)。

### 7. 两件 `install.sh` 不会代劳的 noctalia 收尾

`install.sh` 只写 `$HOME`，所以下面第二条它碰不了；第一条是密钥，按规矩不入包。

**① 生成剪贴板加密主密钥**（不生成的话，剪贴板历史每次重启清零）：

```bash
umask 077
head -c 32 /dev/urandom | xxd -p -c 64 > ~/.config/noctalia/storage.key
kill -TERM $(pgrep -x noctalia); setsid -f noctalia -d    # ★ 必须重启进程，config-reload 不够
```

包里的 `config.toml` 已含 `[storage]` 段指向这个路径，只差文件本身。
原理与验收见 [docs/05](docs/05-theme-ui.md#剪贴板supervsuper-的历史靠-storage-文件密钥才能活过重启)。

**② 建 polkit 规则**（不建的话，每次换壁纸/主题都要输密码）——**这步要 sudo**：

```bash
sudo tee /etc/polkit-1/rules.d/49-noctalia-greeter.rules >/dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.noctalia.greeter.apply-appearance" &&
        subject.isInGroup("wheel") && subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF
```

仅当装了 `noctalia-greeter` 且开着 `greeter_sync` 才需要。
原理见 [docs/05](docs/05-theme-ui.md#greeter-同步换壁纸主题为什么每次都要输密码)。

---

## 验收清单

逐条过一遍，全对就算装好了。

### 终端

- [ ] 打开终端 → **直接进 nvim**，光标在内置终端里，可以立刻打字
- [ ] `Esc Esc` → 回到 nvim 普通模式
- [ ] `:q` 退出 → 是 zsh，提示符是绿色 `➜`（不是 fish 的 `❯`）
- [ ] 提示符里的图标正常显示，**不是豆腐块**（豆腐块 = 缺 `ttf-meslo-nerd`）
- [ ] 开 shell 时**没有任何报错刷屏**
- [ ] 背景半透明，能看到壁纸

```bash
ps -p $$ -o comm=      # → zsh   （别用 echo $SHELL 判断，见坑 3）
```

### Hyprland

```bash
hyprctl binds -j | jq length     # → 116   （95 = mykeys 没挂上）
```

- [ ] `Ctrl+Alt+H/J/K/L` 切焦点
- [ ] `Alt+Enter` 真全屏（盖住顶栏）；在全屏状态下按 `Ctrl+Alt+L` 仍能按方向切窗口
- [ ] `Alt+W` 关窗口
- [ ] `Alt+T` 新建桌面，**追加在最右边**；`Alt+[` / `Alt+]` 能走回来
- [ ] `Alt+\` 在下方开新终端；`Ctrl+Alt+\` 在右侧
- [ ] `Alt+S` 进抽屉架（满屏从上方降下），再按收起并回到原来那个桌面
- [ ] 抽屉架里 `Alt+T` 加一格 → `Alt+[` / `Alt+]` 在两格间来回（**模态**：这几个键在
      抽屉架里切的是抽屉格，不是工作桌面）
- [ ] `Alt+Shift+S` 双向：工作桌面上按＝窗口**原地消失**藏进抽屉架（抽屉架不弹出）；
      在抽屉架里按＝捞回**当前**工作桌面
- [ ] 回工作桌面按 `Ctrl+1` / `Ctrl+4`，**不会**跳进抽屉格
- [ ] `CapsLock` 当 Esc 用（在 nvim 里试最直观）
- [ ] 打字时鼠标光标自动隐藏，动一下鼠标才回来

### 截图 / 录屏 / 取字 / 默认打开方式

- [ ] `Print` 框选截图 → satty 弹出标注，**同时** `~/Pictures/` 里落了一份原图
      （关掉 satty 不看也应该有文件）
- [ ] `Super+Shift+R` 框选 → 弹「录制中」通知 → 再按同一个键 → 弹「已保存」，
      `~/Videos/screenrec-*.mp4` 出现，且路径已在剪贴板里（`Super+V` 可验）
- [ ] 录出来的 mp4 **能播且有声音**——这条是在验 SIGINT 收尾正确、moov atom 完整：

```bash
f=$(ls -t ~/Videos/screenrec-*.mp4 | head -1)
ffprobe -v error -show_entries format=duration -of csv=p=0 "$f"   # 读得出时长 = 没损坏
ffmpeg -i "$f" -af volumedetect -f null - 2>&1 | grep max_volume  # -91 dB = 当时没声音
```

- [ ] `Super+Shift+O` 框选一段中文 → 弹「已复制 N 字」通知，`Super+V` 能看到识别结果
      （**第一次按会等约 1 秒**，服务在加载模型；之后都是 0.3 秒左右，不是卡住了）
- [ ] `Super+Shift+O` 按下后直接 `Esc` → **不该有任何通知**，也不留临时文件
- [ ] 框一块**没有文字**的区域（比如纯色壁纸）→ 提示「没识别到文字」，不是「识别失败」
- [ ] 服务的生命周期正常——socket 常在、service 用完会自己退：

```bash
systemctl --user status ocrd.socket    # 应当 active (listening)
systemctl --user status ocrd.service   # 刚用完是 active，闲置 10 分钟后应变成 inactive
journalctl --user -u ocrd -n 5         # 能看到「模型就绪」「空闲 600s,退出」
```

- [ ] 双击图片 → imv 打开，**方向键能翻同目录的其他图**（标题栏显示 `[3/12]` 这样的计数）
- [ ] 双击视频 → mpv 打开；确认走的是硬解，不是软解：

```bash
mpv --vo=gpu --no-audio --frames=90 --msg-level=vd=v <某个视频> 2>&1 | grep -i 'hardware'
# 应看到  Using hardware decoding (vulkan).   —— AMD 上是 vulkan 先命中，不是 vaapi
```

- [ ] dolphin 里右键图片 →「打开方式」能看到 **imv**（看不到就是 desktop 数据库没刷，
      跑 `update-desktop-database ~/.local/share/applications`）

### 顶栏与主题

- [ ] 鼠标移到屏幕顶边，noctalia 顶栏浮出（默认自动隐藏）
- [ ] `Alt+9` 手动开合顶栏
- [ ] `Alt+Space` 打开应用启动器
- [ ] 终端 / btop / dolphin 的配色是同一套 Tokyo Night 冷蓝紫调

```bash
noctalia config export full | grep -A3 '^\[theme'
# 应看到  source = "community"   community_palette = "Tokyo Night Moon"
```

- [ ] 壁纸已上屏（没上就在 noctalia 设置里重选一次，见下面「已知差异」）

剪贴板历史能活过重启（步骤 7 的 ①）：

```bash
# 复制点东西后，磁盘上应出现加密文件；重启 noctalia 后日志应有 loaded encrypted
ls -la ~/.local/state/noctalia/clipboard/          # index.enc + entries/*.enc，0600
grep 'loaded encrypted clipboard history' ~/.cache/noctalia/noctalia.log
```

- [ ] `SUPER+V` 面板里能看到历史，且重启后还在

换壁纸不再要密码（步骤 7 的 ②，仅装了 noctalia-greeter 时）：

```bash
pkcheck --action-id org.noctalia.greeter.apply-appearance --process $$   # → polkit.result=yes
```

- [ ] 换一次壁纸，全程无密码弹窗

### nvim

- [ ] `:Lazy` 显示 46 installed（47 锁 − 1 个 `bufferline.nvim` 被 disable，属预期）
- [ ] `Ctrl+/` 开出居中的浮动终端，里面是 zsh
- [ ] `<leader>e`（空格 e）打开 mini.files
- [ ] 打开一个 GBK 编码的中文文件不乱码

### 输入法

- [ ] `Ctrl+Space`（或你在 fcitx5 里设的键）能切到 rime 中文
- [ ] 在 GTK 应用（firefox）和 Qt 应用（dolphin）里都能打中文
- [ ] 候选框是深色圆角、蓝色选中胶囊（不是白底方框）——白底说明主题没生效，
      跑 `gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller
      --method org.fcitx.Fcitx.Controller1.GetConfig "fcitx://config/addon/classicui"`
      看 `Theme` 是不是 `tokyonight`
- [ ] 候选词里的序号和汉字都可见（序号消失 = `LabelTextSizeFactor` 被写成了小数，见 docs/05）

### 字体

- [ ] 汉字没落到韩文字形上：

  ```bash
  fc-match -s "sans-serif:lang=zh-cn" | grep -iE 'CJK|Sarasa' | head -1
  # 期望 Sarasa Gothic SC 或 Noto Sans CJK SC；出现 CJK KR 就是没生效
  ```

  注意**必须带 `-s`**。不带的 `fc-match` 返回 Latin 字体是正常的，不代表出错。

- [ ] 终端里图标不是豆腐块（缺 `ttf-meslo-nerd`）

### Claude Code 工具（cc 模块）

只在这台机器装了 `claude` CLI 才有意义；没装的话 `install.sh cc` 会 warn 但仍把脚本铺开。

- [ ] `python3 ~/.claude/test-cc.py` 打印「全部通过」（纯函数、秒回、不消耗 API）
- [ ] `ccs` 能列出当前会话；一个都没开的话先起一个 `claude` 再看
- [ ] `ccp` 能进宠物界面，`q` 退出后终端不留残影
- [ ] **状态栏**：随便开个 `claude`，底部有一行 `[Opus 5·high] 目录 │ ███░░░ 33% …`

      没有的话查 `jq '.statusLine' ~/.claude/settings.json`。这一段**不在包里**
      （settings.json 含明文 token），是 `install.sh` 用 jq 合并进去的；
      没装 jq 时它只 warn 不动手，得自己加，片段见 [docs/08](docs/08-claude-code.md#3--状态栏为什么要-installsh-特殊处理)。

- [ ] token 还在：`jq -r '.env.ANTHROPIC_AUTH_TOKEN' ~/.claude/settings.json`
      —— 合并只加键不动其它，但值得确认一次。改前的备份在 `settings.json.bak-<时间戳>`

⚠ `ccw/ccs/ccp` 三个 alias 定义在 **term 模块**的 `.zshrc` 里。只装 term 不装 cc，
alias 会指向不存在的文件。

### 企业微信（wine 模块）

`install.sh wine` 只铺 `winapp` 工具链和配置，**不装企业微信本体**——prefix 有 2 GB+、
安装包 600 MB，都不入包。装法见 [docs/09](docs/09-wine-apps.md#4--新机器装企业微信)：

```bash
winapp create wecom
winapp install wecom <官网下载的 WeCom_x.x.x.exe>   # 图形界面，点「立即安装」
```

- [ ] 启动器里**只有一个**「企业微信」条目
      —— 多出来的是 wine 的 `winemenubuilder` 生成的裸条目，它**打不出中文**也不进沙箱，
      按 [docs/09 坑 6](docs/09-wine-apps.md#坑-6-winemenubuilder-会污染启动器和文件关联) 清掉
- [ ] 能扫码登录、收发消息
- [ ] **能在聊天框打中文**（fcitx5 → XIM → wine，坑 7 那条链路）
- [ ] 能发文件、收文件
- [ ] 屏幕上**没有空白窗口遮挡**主界面（幽灵窗规则生效了）
- [ ] 沙箱边界正确 —— 敏感目录必须全是「挡住」：

```bash
winapp check wecom     # 用完全相同的 bwrap 参数跑 ls，不靠口头保证
```

⚠ 从终端 `winapp run` 起的实例，命令一结束就会被 `--die-with-parent` 带走，
**这不是崩溃**（坑 3）。调试用 `setsid --fork winapp run wecom`，日常用启动器。

---

## 换机器时的已知差异

| 差异 | 表现 | 处理 |
|---|---|---|
| **用户名不同** | `settings.toml` 里的壁纸路径 | `install.sh` 自动改写成新 `$HOME` |
| **显示器输出名不同** | `settings.toml` 写死 `DP-1`，壁纸不上屏 | 在 noctalia 设置里重选一次壁纸 |
| **多显示器** | `config/variables.lua` 里 `MONITOR2/3` 是空串 | 用 `hyprctl monitors` 查到输出名后填进去 |
| **高分屏 / HiDPI** | `config/monitors.lua` 是 `scale = "auto"` | 通常够用；不行就填具体倍数 |
| **没装 Bibata 光标** | 光标是 Adwaita 样式 | `yay -S bibata-cursor-theme`，或无视 |
| **要用 JetBrains IDE** | `Ctrl+Alt+L/H`、`Alt+Enter` 被合成器吃掉 | 把 `mykeys.lua` 的 `CONTROL + ALT` 批量换成 `SUPER + ALT` |

---

## 需要另外单独传的东西（本包**不含**）

| 东西 | 说明 |
|---|---|
| `~/.ssh/` | SSH 密钥与 `known_hosts`。用安全渠道传，别打进压缩包 |
| `~/.gnupg/` | 同上 |
| `~/.claude/settings.json` | 含明文 API token。⚠ 只有**这一个文件**不含在内；`~/.claude/` 下的工具脚本由 cc 模块正常纳管，`install.sh` 会把 `statusLine` 段合并进你自己的 settings.json |
| `~/.local/share/fcitx5/rime/` | rime 个人词库与方案 |
| `~/Pictures/Wallpapers/` 全库 | 167 MB。本包只带当前那一张 + 4 张 ASCII 成品 + 重新拉取的脚本 |
| `~/mywork/tools/env.sh`、`~/hacktools/` | `.zshrc` 会探测它们；不存在就整段静默跳过，不影响 |
| `~/.config/noctalia/storage.key` | 剪贴板历史的加密主密钥。**不必传**——新机器按步骤 7 重新生成即可，代价只是旧剪贴板历史读不出来（`~/.local/state/noctalia/clipboard/` 那堆 `.enc` 换了密钥就解不开，文件不会被删，换回原密钥仍可恢复）。真要连历史一起迁就用安全渠道单独传，别打进压缩包 |

---

## 卸载

```bash
./uninstall.sh --list-baks     # 先看有哪些备份
./uninstall.sh                 # 交互确认后回滚
```

优先「回滚到最近一次备份」，没有备份的（本包新建的文件）才删除。
官方 `hypr/config/*.lua` 会尝试从 `/etc/skel` 还原成发行版原版。
