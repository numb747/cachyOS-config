# 10 · 屏幕取字（OCR）

> `Super+Shift+O` 框选取字 · `Super+Alt+O` 整屏取字 · 识别结果直接进剪贴板。
> 2026-08-31 新增，替代 normcap。

---

## 1. 为什么换掉 normcap

normcap 的三个毛病，根因各不相同：

| 症状 | 根因 |
|---|---|
| 字符粘连、大量漏识别 | 底层是 **Tesseract**，传统 OCR，对屏幕小号无衬线中文本来就差。**调参救不回来** |
| 中英混排时英文基本靠猜 | 本机 `/usr/share/tessdata/` 只有 `chi_sim`/`chi_tra`/`osd`，**连 `eng` 都没装** |
| 每次都有延迟 | 每次触发都起进程、加载模型、跑完退出 |

换成 **RapidOCR**（PP-OCRv6 + onnxruntime），并把模型加载抽进常驻服务，三个一起解决。

评估过但没选的方案：

- **Umi-OCR** —— 功能最接近 Snipaste 的开箱体验，但 Linux 版是 PaddleOCR-json 打包，
  几百 MB，且自带的截图功能在 Wayland 下失灵，仍得靠 grim 喂图。等于本方案的重型版本。
- **本地 VLM**（Qwen3-VL 之类）—— 质量天花板，能吃复杂排版和手写，但要显卡且延迟秒级。
  可以将来作为「疑难截图」的补充热键，不适合日常高频。
- **云 API**（腾讯云/百度）—— 质量高、本地零负担，但截图内容要外传。
- **给 tesseract 补 `eng` 语言包** —— 只能解决三个毛病里的一个，粘连和延迟照旧。

---

## 2. 键位

沿用 `config/binds.lua` 定下的截图家族分工：**`SHIFT` = 框选，`ALT` = 整屏**。
截图是 `P`、录屏是 `R`，取字是这家子的第三个成员，用 `O`。

| 键 | 动作 |
|---|---|
| `Super+Shift+O` | 框选一块区域取字 |
| `Super+Alt+O` | 取当前聚焦显示器的整屏 |

绑定写在 `config/hypr/mykeys.lua` **第 15 节**，属 **hypr** 模块（不是 ocr 模块）。

`O` 键在所有修饰键组合下都没被占用（`hyprctl binds` 核实过），纯新增，不需要 `hl.unbind`。

> **为什么这一节用 SUPER 而不是 ALT。** `mykeys.lua` 其余「动作类」键位全在 ALT 上，
> 这里是**有意的例外**：取字属于截图家族，而那一家的修饰键分工是官方 `binds.lua`
> 定的另一套。跟着截图/录屏走，手指记忆是「同一个位置换个字母」，比归队到 ALT 省脑子。

---

## 3. 三个部件怎么咬合

```
按键 ──► ocr-grab（客户端，短命进程）
             │  slurp 选区 → grim 截图 → 落临时文件
             │  curl POST ──────────┐
             │                      ▼
             │              127.0.0.1:8265  ← ocrd.socket（systemd 持有）
             │                      │  首次连接触发激活
             │                      ▼
             │              ocrd.service ──► ocr-server（常驻，模型在内存）
             │                      │  空闲 600s 自己 exit(0)
             │  ◄── 纯文本 ─────────┘
             ▼
        wl-copy 进剪贴板 + notify-send 弹预览
```

| 文件 | 职责 |
|---|---|
| `bin/ocr-grab` | 截图、发请求、写剪贴板、发通知。**不碰 OCR 本身** |
| `bin/ocr-server` | 加载一次模型，之后每个请求只做推理 + 文本后处理 |
| `config/systemd/user/ocrd.socket` | 监听 `127.0.0.1:8265`，**进程死了它还在** |
| `config/systemd/user/ocrd.service` | 被 socket 激活，没有 `[Install]` |

### 为什么用 socket activation 而不是开机常驻

RapidOCR + onnxruntime 常驻要 400~600 MB 内存。socket activation 让我们两头都占：

- systemd 持有监听 socket，**服务本身可以随便死**
- 服务空闲 600 秒自己 `exit(0)`，内存还给系统
- 下次按键时 connect 会被 systemd 接住并重新拉起服务，客户端只是感觉慢了一下

调 `IDLE_TIMEOUT`（在 `ocr-server` 顶部）就能在「省内存」和「永远零冷启动」之间移动。
设成很大的数就等于开机常驻。

### 两个必须这么写的地方

**① `.socket` 里必须 `Accept=no`。** 写成 `Accept=yes` 的话 systemd 会为**每条连接**
单独 fork 一个进程，模型就要每次重新加载——常驻服务的意义直接归零。`Accept=no` 是把
整个监听 socket 交给一个进程自己 accept 循环。

**② `ocr-server` 里必须 `protocol_version = "HTTP/1.0"`。** 用 HTTP/1.1 会启用
keep-alive，`handle_request()` 循环会卡在一条空闲连接上，于是「空闲超时自退」这件事
**永远不会触发**——服务会一直占着那 500 MB 不放。这个 bug 很隐蔽：功能全对，只有内存
在那儿赖着。

### 一个已知的竞态（已缓解）

服务决定退出、但还没走完 `SystemExit` 的那一瞬间，如果正好来了请求，理论上会丢一次。
窗口极小，但真会发生。`ocr-grab` 的缓解办法是：**连接失败时 `sleep 0.5` 自动重试一次**，
第二次就能被 systemd 重新拉起的新进程接住。

这也是为什么截图要**先落临时文件再 POST**，而不是 `grim | curl` 管道直连——
管道方案重试时没法重发，`slurp` 早就退出了，选区已经没了，只能让用户再框一次。

---

## 4. 实测数据（2026-08-31，本机 24 核 znver4）

| 场景 | 耗时 |
|---|---|
| 冷启动（服务未跑，含模型加载 + 推理） | **0.79 s** |
| 热路径，框选一块 620×150 的区域 | **0.33 s** |
| 整屏 2560×1440 | **1.92 s** |

识别质量（14 px 小字，正是 normcap 最吃力的区间）：**字符零错误，不粘连、不漏字**。

---

## 5. 两条反直觉的调参结论

### ⚠ 别在送进 OCR 之前放大图片

「小字放大能提高召回」听起来很合理，实测是**反的**：

| 字号 | 原图逐行命中 | 2× 放大后 |
|---|---|---|
| 12 | 3/4 | **2/4** ↓ |
| 14 | **4/4** | 3/4 ↓ |

**根因在 `/etc/rapidocr/config.yaml` 的 Det 段**：

```yaml
limit_side_len: 736
limit_type: min
```

检测模型**内部**就会把短边不足 736 px 的图放大到 736。在外面再放一次 = 连做两次插值，
伪影叠加。`ocr-server` 里那段注释就是为了防止以后又有人「优化」出这个想法。

### ⚠ `intra_op_num_threads` 默认值（-1）在多核机器上最慢

| 线程数 | 中位耗时 | 准确率 |
|---|---|---|
| `-1`（自动，配置默认） | 265 ms | 4/4 |
| 1 | 363 ms | 4/4 |
| 2 | 225 ms | 4/4 |
| **4** | **151 ms** | 4/4 |
| 8 | 143 ms | 4/4 |

24 核上开满反而慢——小图的线程调度开销盖过并行收益。`ocr-server` 取 **4**：和 8 只差
8 ms（噪声级别），但省一半 CPU。这一项**不是**改 `/etc/rapidocr/config.yaml`，而是在
`ocr-server` 里用 `params={"EngineConfig.onnxruntime.intra_op_num_threads": THREADS}`
传进去——改系统配置文件会被包升级覆盖。

---

## 6. 文本后处理

OCR 按**视觉行**返回，需要两步整理才是人想要的文本。两步都在 `ocr-server` 里。

### 智能合并换行

一段中文正文在网页上被容器宽度折成 5 行，OCR 就返回 5 个字符串。直接 `\n` 连起来粘到
聊天框是一堆断行；无脑全合并又会毁掉代码和列表。所以**只在确实是被折行的中文段落处合并**，
三个条件同时满足才合：

1. 前一行末尾和后一行开头**都是中文** —— 英文/代码一律保留换行
2. 前一行末尾**不是**句号问号之类的收尾标点 —— 那是作者主动结束段落
3. 前一行的右边界**顶到了本次结果的最右侧** —— 说明它是写满了才换行

第 3 条是关键。少了它，「标题 + 正文」会被粘成一行。

### 中英文之间补空格

PP-OCR 的中文识别模型**对空格不敏感**（训练语料里中文本来就不带空格），
`与 English 混排` 会识别成 `与English混排`。后处理按 pangu 那套排版规范补回去。

**只在「中日韩文字」和「拉丁字母/数字」直接相邻时补**，不动其它任何位置。
不想要就把 `ocr-server` 里的 `PANGU` 置 `False`。

> **为什么不把规则扩展到 `~` `(` 这些符号。** 试过就知道会坏事：
> `配置在~/.config` 确实少个空格想补，但同一条规则会把 `屏幕取字(OCR)` 变成
> `屏幕取字 (OCR)`——而后者原文本来就没空格、识别也完全正确。
> 为了一个空格去冒险改坏别处，不划算。

---

## 7. 已知限制

- **连续破折号会被合并**：`——`（两个 em dash）识别成一个 `—`。属视觉歧义，后处理救不了。
- **中文与 `~` `/` 之间的空格补不回来**（见上一节的取舍）。
- **整屏取字要 1.9 秒**，因为 2560×1440 像素多。日常用框选（0.33 s）。
- **每天第一次按键会等约 0.8 秒**（服务冷启动），这是空闲自退换来的。

---

## 8. 运行时依赖：一个装不上的 AUR 包

`python-rapidocr` **不能直接 `yay -S`**，上游 PKGBUILD 写了
`makedepends 'python-installer>=1.0.1'`，而 Arch 全仓库最新只有 **1.0.0**——
这个约束在任何地方都满足不了。

改过的 PKGBUILD 已归档在 **`aur/python-rapidocr/`**，装法、锁更新的理由、
以及**怎么复核这个 AUR 包没被投毒**（2026-08-31 做过一次，与 PyPI 上游 wheel
逐文件比对：90 个文件哈希全部一致）都写在 **`aur/README.md`**。

三件事要记住：

1. **装完必须 `IgnorePkg`** —— 否则自动更新会拿官方 PKGBUILD 重建，必然再撞同一个错。
2. **`IgnorePkg` 写在 `/etc/pacman.conf`，不在本包管辖范围**，`sync.sh` 收不回来，
   换机器要手动加。
3. **它会连带拉进 `python-opencv` 全套**（含 `vtk` 371 MB），合计约 **936 MB** 磁盘。
   Arch 官方没打 headless 版的 opencv，省不掉。

---

## 9. 排查

```bash
# 服务状态。socket 应当 active(listening)；service 不在跑是【正常的】（空闲自退了）
systemctl --user status ocrd.socket ocrd.service

# 看日志。「模型就绪」「空闲 600s,退出」这两行是正常生命周期
journalctl --user -u ocrd -n 30

# 绕开键位直接测，能分辨是识别的问题还是截图/剪贴板链路的问题
grim -g "$(slurp)" /tmp/x.png
curl -s -w '\n%{http_code}\n' --data-binary @/tmp/x.png http://127.0.0.1:8265/ocr

# 手动跑服务看完整报错（不走 systemd 时它自己 bind 8265）
systemctl --user stop ocrd.socket && ~/.local/bin/ocr-server
```

HTTP 返回码的含义（`ocr-grab` 会把它们翻译成不同的通知，别只看「失败」两个字）：

| 码 | 意思 |
|---|---|
| 200 | 有文字，已进剪贴板 |
| **204** | 图是好的，**但里面没有文字**——不是故障 |
| 400 | 请求体是空的 |
| 500 | 图片数据解不开。服务不会因此崩溃 |
| 000 | 连不上服务，看 `systemctl --user status ocrd.socket` |

### 装完没反应？

**先确认那两个激活步骤跑过了。** `install.sh` 的 `put` 只负责把 `.socket`/`.service`
拷进 `~/.config/systemd/user/`，不 `daemon-reload` 的话 systemd 根本不知道它们存在：

```bash
systemctl --user daemon-reload
systemctl --user enable --now ocrd.socket
```

`mod_ocr` 里已经带了这两句，手动拷文件时才需要自己补。这是本仓库**唯一**一个需要
「激活」而不只是「拷文件」的模块。

---

## 10. 调参入口一览

| 想改什么 | 改哪 |
|---|---|
| 空闲多久自动退出 | `ocr-server` 的 `IDLE_TIMEOUT`（秒） |
| 推理线程数 | `ocr-server` 的 `THREADS` |
| 关掉中英文补空格 | `ocr-server` 的 `PANGU = False` |
| 换行合并的收尾标点 | `ocr-server` 的 `CLOSING_PUNCT` |
| 端口 | `ocrd.socket` 的 `ListenStream` + `ocr-grab` 的 `ENDPOINT`（两处都要改） |
| 键位 | `config/hypr/mykeys.lua` 第 15 节 |
| 换更大/更准的模型 | `/etc/rapidocr/config.yaml` 的 `model_type` / `ocr_version` ⚠ 包升级会覆盖 |

> `/etc/rapidocr/config.yaml` 是 AUR 包 `package()` 里从 site-packages 移过去再软链
> 回来的，属于**包的文件**，`pacman -Syu` 重装该包时会被覆盖。所以凡是能在 `ocr-server`
> 里用 `params=` 传的，都别去改那个文件。
