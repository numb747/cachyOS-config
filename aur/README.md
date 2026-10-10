# aur/ —— 需要本地改过才能装的 AUR 包

这里放的**不是**要装到 `$HOME` 的配置文件，所以不走 `manifest.map`，`install.sh`
也不碰它。它是「重装这台机器时，为了让某个 AUR 包装得上，必须留在手边的东西」。

目前只剩一个：`python-rapidocr`（装不上）。

> 原先还有 `elephant-clipboard`、`elephant-desktopapplications` 两份本地补丁版 PKGBUILD，
> 2026-10-09 已作为**新包名发布到 AUR**（维护者是自己，AUR 账号 couldLover），本地这两份随之删除。
> 下面两节保留「为什么要改」和维护流程，装法改成直接 `yay`。

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

## 两个 AUR 包的共同约定（2026-10-09 发布）

| AUR 包 | 替代 | 补丁来源（github.com/numb747/elephant 的分支） |
|---|---|---|
| [`elephant-clipboard-substring`](https://aur.archlinux.org/packages/elephant-clipboard-substring) | `elephant-clipboard` | `clipboard-substring-search` |
| [`elephant-desktopapplications-windowfirst`](https://aur.archlinux.org/packages/elephant-desktopapplications-windowfirst) | `elephant-desktopapplications` | `desktopapps-window-first` |

- **新包名 + `provides`/`conflicts`**，不是上传同名包：AUR 规则只允许「带补丁的变体」用不同名字发布。
  `provides=elephant-xxx=${pkgver}`，所以 `pacman -Q elephant-clipboard` 查得到补丁版，
  依赖原名的东西也满足；装它会提示和原版冲突、替换掉原版。
- **装法**：和 elephant 本体、其他插件放在**同一条** yay 命令里（Go plugin ABI，见 `docs/13-launcher.md`）：

  ```bash
  yay -S aur/walker elephant elephant-windows elephant-websearch elephant-providerlist \
         elephant-symbols elephant-clipboard-substring elephant-desktopapplications-windowfirst
  systemctl --user restart elephant walker      # 装了新插件两个都要重启，见 docs/13 坑 4
  ```

- **打包仓库**：本机 `~/linuxProjects/aur-<包名>/`（和 card-forge / jm-boom 放在一起），
  `origin` 是 `ssh://aur@aur.archlinux.org/<包名>.git`。里面只入库 `PKGBUILD`、`.SRCINFO`、`.patch`。
  补丁的 fork 本地克隆是 `~/Projects/elephant`（`origin` = fork，`upstream` = abenz1267/elephant；笔记本上没有这份克隆）。

### ⚠ elephant 升级时会发生什么：被版本依赖卡住，而不是悄悄坏掉

本地版是**同名** `pkgrel=1.1`，上游一升级就被未打补丁的版本替换——退化但不坏。
换成新包名后，上游所有 `elephant-*` 一起升到新版时，这两个包**不会**被替换，留在旧版本上；
而 Go plugin 要求和本体同一次构建，放任不管就是**加载失败**——剪贴板、应用搜索直接没了。

所以两个 PKGBUILD 都写死了 **`depends=("elephant=${pkgver}")`**（2026-10-09，`2.22.1-2` 起）。
效果：上游发新版时 `yay -Syu` 会报 `installing elephant (X.Y.Z) breaks dependency 'elephant=2.22.1'`
**拒绝升级 elephant**，直到这两个包更新到同版本。宁可卡住，也不要静默坏掉。
⚠ 代价：卡住期间整次 `-Syu` 会报错（可以先 `--ignore elephant` 把别的升了）；
装了这两个包的其他 AUR 用户也一样被卡，所以上游发版后要尽快跟。
`=2.22.1` 不带 pkgrel，上游只 bump pkgrel 重编时不会卡（`pacman -T 'elephant=2.22.1'` 验证过）——
但那种情况本体是重新编的，插件理论上也该跟着重编：`yay -S` 这两个即可。

排查加载失败：`journalctl --user -u elephant` 里看对应 provider 有没有 `providers loaded=`。

维护流程（在有 fork 克隆的那台机器上）：

```bash
cd ~/Projects/elephant && git fetch upstream --tags
git rebase --onto vX.Y.Z v2.22.1 clipboard-substring-search   # 冲突 = 上游改了这段，手工处理
git push -f origin clipboard-substring-search
git diff vX.Y.Z clipboard-substring-search -- internal/providers/clipboard \
  > ~/linuxProjects/aur-elephant-clipboard-substring/clipboard-substring-search.patch
# desktopapplications 同理：分支 desktopapps-window-first，路径 internal/providers/desktopapplications

cd ~/linuxProjects/aur-elephant-clipboard-substring
sed -i 's/^pkgver=.*/pkgver=X.Y.Z/; s/^pkgrel=.*/pkgrel=1/' PKGBUILD
updpkgsums && makepkg -f && makepkg --printsrcinfo > .SRCINFO
git commit -am "Update to X.Y.Z" && git push
```

补丁打不上时 `prepare()` 直接失败，不会装出半成品。**没有锁 IgnorePkg**，理由同前：锁住插件而本体照常升级，一样加载失败。

---

## elephant-clipboard-substring —— 剪贴板（launcher 模块，`SUPER+V`）的搜索补丁

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

### 自检（看补丁是否还在）

```bash
elephant query --json "clipboard;a;300;false" | jq -s '[.[]|select(.item)]|length'   # 原版几乎总是 0
```

---

## elephant-desktopapplications-windowfirst —— 启动器里「应用紧贴自己的窗口」的排序补丁

### 为什么要改

开了 `window_integration` 后，有窗口的应用上游是**分数减半**，只保证排在自己的窗口之下，
中间会夹进无关条目（搜 `local`：LocalSend 窗口 140 → LibreOffice Calc 123 → … → LocalSend 应用 72）。
补丁（`desktopapps-window-first.patch`，只动 `internal/providers/desktopapplications/` 的
`query.go` 一处 + `activate.go` 抽出判定函数、加一个算窗口分的函数）：**应用分 = 它窗口的分 − 1**，
窗口分的算法照抄 windows 插件。详细对比表在 `docs/13-launcher.md` 坑 7。

### 2026-10-10 追加的两处修复（⚠ AUR 还没发布）

① **blacklist 对启动后新建/重写的 .desktop 也生效**：上游只在启动扫描目录时查，
Waydroid 每次会话启动都会删掉重建自己导出的 .desktop，屏蔽就失效了（被屏蔽的安卓版 LocalSend
带着历史分排回第一）。② 认窗口时加上「**app_id = .desktop 文件名**」：Waydroid（`waydroid.<包名>`）、
`org.kde.ark` / `org.kde.dolphin` 这类应用之前认不出自己的窗口。同时窗口分改成和 windows 插件逐步一致
（先挑原始分最高的字段再减起始位置）。详见 `docs/13-launcher.md` 坑 7。

代码在 fork `desktopapps-window-first` 分支的 6a63b9e（已推到 GitHub）。**AUR 上的 `elephant-desktopapplications-windowfirst`
还停在不含这两处的版本**——源机器没有 AUR 的 SSH 密钥，发布要在笔记本上按上面的维护流程做：
笔记本没有 fork 克隆，补丁直接从 GitHub 取（这个分支只动 `internal/providers/desktopapplications/`）：

```bash
curl -L https://github.com/numb747/elephant/compare/v2.22.1...desktopapps-window-first.diff \
  > ~/linuxProjects/aur-elephant-desktopapplications-windowfirst/desktopapps-window-first.patch
# 然后 bump pkgrel → updpkgsums → makepkg -f → .SRCINFO → commit/push
```

源机器 2026-10-10 装的是同一补丁本地 `makepkg` 的**原名包** `elephant-desktopapplications 2.22.1-1.2`
（那份本地 PKGBUILD 已随 `aur/` 本地版一起删掉）。AUR 发布后在源机器上
`yay -S elephant-desktopapplications-windowfirst` 换过去即可（`conflicts` 原名，会提示替换）。

### 自检

追加修复在不在：开过 Waydroid 之后（.desktop 被重建过）搜 `local` 不出安卓版 LocalSend。

窗口开着时，补丁在 → 应用分恰好比窗口少 1；原版 → 约一半：

```bash
elephant query --json "desktopapplications,windows;localsend;4;false" | jq -c 'select(.item)|.item|[.score,.provider]'
```
