# aur/ —— 需要本地改过才能装的 AUR 包

这里放的**不是**要装到 `$HOME` 的配置文件，所以不走 `manifest.map`，`install.sh`
也不碰它。它是「重装这台机器时，为了让某个 AUR 包装得上，必须留在手边的东西」。

目前有两个：`python-rapidocr`（装不上）和 `elephant-clipboard`（行为要改）。

---

## python-rapidocr —— 屏幕取字（ocr 模块）的运行时

### 为什么不能直接 `yay -S python-rapidocr`

上游 PKGBUILD 写的是：

```bash
makedepends=('python-build' 'python-installer>=1.0.1' 'python-setuptools')
```

而 Arch 全仓库最新的 `python-installer` 只有 **1.0.0** —— 这个约束在任何地方都
满足不了，yay 会直接停在：

```
-> No AUR package found for python-installer>=1.0.1 (required by: python-rapidocr)
-> could not find all required packages: python-installer >=1.0.1
```

它只是构建期用来把 wheel 解包进 `pkgdir` 的工具（见 `package()` 里的
`python -m installer`），1.0.0 完全够用。本目录这份 PKGBUILD 就只放宽了这一行，
`depends`、`source`、`b2sums` 一字未动，校验和照常验证。

### 装法

```bash
sudo pacman -S --needed python-onnxruntime-cpu       # 推理运行时，官方仓库
cd ~/cachyOS-config/aur/python-rapidocr && makepkg -si
```

`makepkg` 的 `check()` 会跑一次 `python -m rapidocr.main check`，模型或运行时有
问题会当场构建失败，不会装出一个坏包。

### 装完必须锁更新

```bash
sudo sed -i 's/^#IgnorePkg\s*=\s*$/IgnorePkg   = python-rapidocr/' /etc/pacman.conf
```

两个理由：

1. **自动更新必然失败** —— yay 会拿官方 PKGBUILD 重建，再撞上同一个版本约束。
2. **它是低关注度 AUR 包**（提交于 2025-11-30，1 票），平时没多少人盯着看。
   AUR 出过投毒事件（2025-07 的 `librewolf-fix-bin` 等三个包被植入 CHAOS RAT），
   升级前应该重做一遍下面的复核。

⚠ `/etc/pacman.conf` 在 `$HOME` 之外，**不归本包管辖**，`sync.sh` 收不回来。
换机器时这一步要手动做。

### 怎么复核这个包没被投毒

2026-08-31 做过一次，全部通过。复核方法（升级时重做一遍）：

```bash
# ① 打包层：AUR 仓库该只有 3 个文件，且没有 .install（装包时以 root 执行）
git -C <aur-repo> ls-files          # 期望：.SRCINFO / PKGBUILD / pyproject.toml.patch
ls <aur-repo>/*.install             # 期望：不存在

# ② 安装产物不该越界
pacman -Qlq python-rapidocr | grep -ivE "site-packages|/etc/rapidocr|/usr/bin/rapidocr"
pacman -Qlq python-rapidocr | grep -iE "systemd|autostart|cron|hooks"   # 期望：空

# ③ 代码层（最强的一条）：和 PyPI 上游 wheel 逐文件比 SHA256。
#    PyPI 那份是 RapidAI 自己 CI 发布的，与 AUR 维护者无关，两边一致即说明没被换。
#    2026-08-31 结果：90 个文件全部一致、0 不一致；3 个 .onnx 模型也一致。
#    只有 _version.py 和 models/.gitkeep 「缺失」，都能在 PKGBUILD 里找到原因
#    （版本号被 patch 写死故不生成；.gitkeep 被 prepare() 显式删掉）。

# ④ 行为层：运行时不该外联
#    静态扫描：exec / os.system / subprocess / pickle.loads / base64.b64decode
#              / socket.socket / urlopen —— 全部应为 0
#    源码里出现的 URL 应当只有 modelscope.cn/models/RapidAI/RapidOCR 和 Apache 许可证
```

**已知但无害的一处**：源码里有 9 个真·内置 `eval()`，全在
`inference_engine/pytorch/` 下（从 PaddleOCR 移植的网络定义，拿层名字符串转类）。
本机没装 pytorch、配置里三个阶段都是 `onnxruntime`，实测 `import rapidocr` 后加载的
pytorch 模块数为 **0** —— 是执行不到的死代码，且与上游 wheel 逐字节一致，
不是打包者塞进去的。

原理、调参和键位见 `docs/10-ocr.md`。

---

## elephant-clipboard —— 剪贴板（launcher 模块，`SUPER+V`）的搜索补丁

### 为什么要改

上游的剪贴板搜索用的是 fzf 模糊匹配，并且 `score = fzf 分数 - 匹配起始位置`，低于 30 分丢弃。
对应用名这种短文本没问题，对剪贴板（一大段文字）是错的：**匹配位置越靠后越搜不到**。
2026-10-09 在本机 48 条历史上实测：

| 搜索词 | 原版命中 | 补丁后 |
|---|---|---|
| `a` | 0 | 27 |
| `苦杏仁`（在段落中间） | 0 | 2 |
| `工作量` | 2 | 7 |
| `鉴别` | 1 | 4 |

补丁（`clipboard-substring-search.patch`，只动 `internal/providers/clipboard/clipboard.go` 一处）：
**不分大小写的子串匹配；空格分隔多个词时每个词都要出现（AND）；结果一律按时间从新到旧排**
（置顶的仍在最上，`pinned_on_top`）。上游 master（2026-10-09）这段代码没变。

### 装法

```bash
cd ~/cachyOS-config/aur/elephant-clipboard && makepkg -si
systemctl --user restart elephant walker      # 两个都要重启，见 docs/13 坑 4
```

★ **必须和已装的 elephant 本体同版本**（Go plugin ABI，见 docs/13）。PKGBUILD 的 `pkgver` 要和
`pacman -Q elephant` 一致，不一致就改 `pkgver` 和 tarball 的 sha256 再编。

### 补丁的源头：自己的 fork

改动以 commit 形式存在 **github.com/numb747/elephant** 的 `clipboard-substring-search` 分支上
（2026-10-09 fork，基于 `v2.22.1`，没有给上游开 PR）。本地克隆在 `~/Projects/elephant`，
`origin` 是 fork（走 `github-numb747` 这个 SSH 别名），`upstream` 是 abenz1267/elephant。
本目录的 `.patch` 就是从这个分支导出的。

上游发新版时，在 fork 里把补丁挪到新 tag 上，再重新导出：

```bash
cd ~/Projects/elephant && git fetch upstream --tags
git rebase --onto vX.Y.Z v2.22.1 clipboard-substring-search   # 冲突了说明上游改了这段，手工处理
git push -f origin clipboard-substring-search
git diff vX.Y.Z clipboard-substring-search -- internal/providers/clipboard \
  > ~/cachyOS-config/aur/elephant-clipboard/clipboard-substring-search.patch
# 然后改 PKGBUILD 的 pkgver、两个 sha256，makepkg -si
```

### 升级时会发生什么

`pkgrel=1.1` 比上游 `2.22.1-1` 新，所以同版本下 yay 不会覆盖它。
但上游一发新版（所有 elephant-* 一起升），yay 会用**未打补丁**的版本替换——**不会坏，只是搜索退回原来那样**。
所以每次 elephant 升级后回来做一遍：改 `pkgver` / sha256 → `makepkg -si` → 重启两个服务。
补丁打不上（上游改了这段）时 `prepare()` 会直接失败，不会装出半成品。

自检（看补丁是否还在）：

```bash
elephant query --json "clipboard;a;300;false" | jq -s '[.[]|select(.item)]|length'   # 原版几乎总是 0
```

**没有锁 IgnorePkg**：锁住它而 elephant 本体照常升级，插件就会因 ABI 不一致加载失败，剪贴板直接没了。
宁可退化，不要坏掉。
