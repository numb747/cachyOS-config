# 04 · Neovim（LazyVim）

对应目录：`config/nvim/` → `~/.config/nvim/`
基座 LazyVim，锁 47 个插件（`lazy-lock.json`），实装 46 个。

---

## 首次启动

```bash
nvim        # 自动 clone lazy.nvim，然后按 lazy-lock.json 装 47 个插件
```

等 lazy 界面跑完再操作。**不要**把旧机的 `~/.local/share/nvim/lazy/` 拷过来——
版本由 `lazy-lock.json` 锁定，拷实体反而容易和 git 状态冲突。

> 46 装 / 47 锁不是 bug：`bufferline.nvim` 在锁文件里，但被
> `lua/plugins/disabled.lua` 设成 `enabled = false`，属预期。

---

## 文件布局

```
init.lua                    只有一行：require("config.lazy")
lazyvim.json                启用了哪些 LazyVim extras（11 个语言）
lazy-lock.json              插件版本锁
stylua.toml                 Lua 格式化：2 空格 / 120 列
lua/config/
├── lazy.lua                lazy.nvim 引导 + LazyVim 挂载
├── options.lua             编码、swapfile、内置终端 shell、python provider
├── keymaps.lua             只有一条：禁用 q 录制宏
└── autocmds.lua            自动保存、终端双 Esc
lua/plugins/
├── colorscheme.lua         tokyonight，透明
├── disabled.lua            关掉 bufferline
├── image.lua               image.nvim：打开图片文件 + molten 出图，走 magick_cli 免 luarock
├── lualine.lua             状态栏
├── mini.lua                mini.files 文件管理器（替代 snacks explorer）
├── molten.lua              .py 里跑 Jupyter kernel，输出内联
├── no-neck-pain.lua        居中阅读模式
├── snacks.lua              关掉与 mini.files 冲突的部分，以及和 image.nvim 抢图片的 snacks.image
└── toggleterm.lua          浮动终端（本目录最大的一个定制）
```

---

## 关键定制

### 中文编码探测（options.lua）

```lua
opt.fileencoding  = "utf-8"                        -- 新文件
opt.fileencodings = "utf-8,gbk,gb2312,gb18030"     -- 打开时的探测顺序
```

打开 Windows 来的 GBK 文本不再是乱码。顺序不能反——`utf-8` 必须在最前，
否则合法的 UTF-8 会被 GBK 抢先「成功」解码成乱码。

### 内置终端为什么用 zsh 而不是 `$SHELL`

```lua
vim.opt.shell = vim.fn.executable("zsh") == 1 and vim.fn.exepath("zsh") or vim.o.shell
```

`$SHELL` 是登录那一刻的快照，可能是过期值（比如刚 `chsh` 完还没重新登录）。

**为什么必须设在 `options.lua`**：这个文件在 lazy.nvim 启动**之前**加载，而
`toggleterm.lua` 的 `opts = { shell = vim.o.shell }` 在 spec 构造那一刻就把值取走了。
设晚了就取到旧值。靠 kitty 的 `-c` 参数也来不及——那要等 spec 构造之后才执行。

一处设置，三处受益：`:terminal`、toggleterm（`Ctrl+/`）、`:!cmd` / `vim.fn.system`。

### 自动保存（autocmds.lua）

```lua
FocusLost    → silent! wa      -- 切走窗口就全部保存
InsertLeave  → silent! write   -- 退出插入模式就保存
```

配合 Hyprland 的 `follow_mouse = 2`（悬停不切焦点），`FocusLost` 只在真正点击别的
窗口时触发，不会因为鼠标划过就狂写盘。

代价：不适合编辑「必须显式保存才生效」的文件（如正在被守护进程监听的配置）。
临时关掉：`:autocmd! * <buffer>`。

### toggleterm —— 居中竖长条浮动终端

```
Ctrl+/          开/关浮动终端（normal 和 terminal 模式都能按）
<leader>th      水平终端      <leader>tv  垂直终端
<leader>tn      给终端命名     Ctrl+r（终端内）
<leader>tl      列出并切换终端  Ctrl+f（终端内）
<leader>tt      一次开 4 个终端
Esc Esc         从终端模式回普通模式
```

浮动窗口尺寸是函数算的，不是写死的：

```lua
width  = 宽屏取半屏并封顶 110 列；窄屏退让到 90% 避免溢出
height = 屏幕高度的 90%
```

宽度锁在 80~110 列的阅读舒适区，高度尽量拉满，不指定 `row`/`col` 时 toggleterm 会
自动居中。

### mini.files 取代 snacks explorer

```
<leader>e    打开（cwd）        <leader>E   打开（项目根）
<leader>fm   打开（当前文件所在目录）
l / L        进入 / 进入并关闭   h / H       返回 / 返回并关闭
=  或 Ctrl+s 同步（把改动写回文件系统）
gs / gv      水平/垂直分屏打开   Esc 或 q    关闭
```

mini.files 是「把目录当 buffer 编辑」的范式：**重命名文件 = 改那一行文字，然后按
`=` 同步**。删除、移动、新建同理，改完统一 `=` 提交。

`snacks.lua` 里把 `<leader>e` `<leader>E` `<leader>fe` `<leader>fE` `<c-/>` 全部设成
`false`，是为了让出键位——不然两个文件管理器会抢同一个键。

在这里按 `l` 打开图片能直接看到图（2026-09-11 起；当时靠 snacks.image，2026-09-12 起
改由 image.nvim 接管）；但右侧 **preview 窗格不出图**，原因见下面「image.nvim」一节。

#### mini.lua 里那段 `vim.glob.to_lpeg` 补丁

```lua
-- 修复 LSP server 发送无效 glob 模式 (如 **/*.{}) 导致 vim.glob.to_lpeg 崩溃
```

某些 LSP 会发出 `**/*.{}` 这种空花括号的 glob，Neovim 的 `vim.glob.to_lpeg` 解析
不了直接抛错，表现为打开某类文件时 nvim 弹一堆红色 stack trace。这段把空花括号
擦掉再交给原函数。属于上游 bug 的本地绕行——哪天 Neovim 修了可以删掉。

### molten —— 在 .py 里跑 Jupyter kernel，输出内联

2026-09-11 加入。做的是「Jupyter 那种交互」，但**不引入 .ipynb**：编辑的始终是普通
`.py` 文件，用 `# %%` 分隔 cell，输出以虚拟文本浮在 cell 下方，重跑就地覆盖。

```
<leader>mi   启动 kernel（每个 nvim session 一次）
<leader>mm   运行当前 cell 并跳到下一个   Shift+Enter 同功能
<leader>me   运行当前 cell（光标不动）    visual 模式下 = 运行选区
<leader>ml   运行当前行
<leader>mo   进入输出窗口 —— ★ 要复制输出就按它，窗口内 q / Esc 关掉
<leader>mc   中断执行（★ 保留所有变量）
<leader>mR   重启 kernel（清空所有变量）
<leader>mh   隐藏输出      <leader>md  删除该输出
<leader>ms   kernel 状态   ]x / [x     下一个 / 上一个 cell
```

#### 输出复制不了？那是虚拟文本

内联显示的输出是 `nvim_buf_set_extmark` 画上去的**虚拟文本**，不是 buffer 内容——
所以 `v` 选不中、`y` 复制不到、更不能编辑。这是 `molten_virt_text_output` 的固有代价，
换来的是「不污染文件、重跑就地覆盖」。

要复制就按 `<leader>mo` 进输出窗口：那是一个真正的 buffer（`filetype=molten_output`），
`v` / `V` / `y` / `/` 搜索全部正常，复制完 `q` 或 `Esc` 退出。

两个相关设置已经调过了：

- `molten_enter_output_behavior = "open_and_enter"` —— 默认值 `open_then_enter` 是
  「第一次按开窗、第二次按才进去」，想 yank 一段输出要按两次很别扭，改成一次直达。
- 没有开 `molten_copy_output`（执行完自动把输出塞进剪贴板）。它需要额外的 `pyperclip`
  包，而且会无差别覆盖剪贴板，不如按需进窗口复制。要开的话装 `python-pyperclip` 再
  `vim.g.molten_copy_output = true`。

#### 为什么不用 iron.nvim / vim-slime 那类 REPL

那类插件把代码喂进伪终端、再读回字符。molten 走的是 Jupyter 的 ZeroMQ 协议
（shell + iopub 双通道），换来三件 tty REPL 给不了的东西，都是实测过的：

| | tty REPL | molten |
|---|---|---|
| 执行 | 同步，占住那个终端 | **提交即返回：实测提交一个 6 秒的 cell，调用 2.6 ms 就返回** |
| 长任务期间 | 那个 REPL 不能再用 | 照常编辑 buffer、切窗口，还能排队执行别的 cell |
| 输出归属 | 一条流水账，靠自己认 | 每条输出带 msg_id，绑定到发起它的那段代码 |
| 中断 | Ctrl-C 送进 tty | 独立信道，**实测中断后命名空间完整保留**（变量还在） |

最后一条对爬虫特别值钱：一个请求挂住，`<leader>mc` 打断它，前面抓了 80 页的数据
和登录态全都不丢。

#### 为什么坚持 .py + `# %%` 而不是 .ipynb

**LSP。** buffer 就是一个普通 Python 文件，basedpyright 看到的是完整上下文，
补全 / 跳转 / hover / 重命名全部原生满血。走 `.ipynb` 得靠 otter.nvim 把 cell 抠出来
喂影子 buffer，是打补丁，跨 cell 引用经常失效。

附带三个好处：文件能直接 `python x.py` 跑；`git diff` 是纯代码而不是一坨 JSON；
「原型转成品」只是把 cell 边界改成函数边界，不用把代码从 notebook 里搬出来。

典型用法——**后写的定义覆盖前面的，不用回头改**（实测通过）：

```python
# %%
import pathlib
page = 1
def main():
    return fetch(page)

# %%
main()
▏ 2384766          ← 虚拟文本，重跑就地覆盖

# %% 结果不满意，就地改参数，不动上面的定义
page = 3
main()
▏ 1927451
```

#### cell 是怎么界定的 —— 它不是语言特性

`# %%` 在 Python 眼里就是**一条普通注释**，没有任何特殊含义。它之所以能分隔 cell，
完全是因为 `molten.lua` 里这两行搜索：

```lua
local s = vim.fn.search("^# %%", "bcnW")   -- 往上找最近的标记
local e = vim.fn.search("^# %%", "nW")     -- 往下找下一个
```

**是这个模式赋予它意义的。** molten 自己只认 line / visual / range 三种粒度，
没有 cell 概念。想换成 `#%%` / `# ---` / `# CELL`，改这两处正则即可。

因为匹配的是 `^# %%` **前缀**，后面跟什么都行 —— 所以 **cell 可以有名字**：

```python
# %% setup
# %% 抓列表页
# %% 解析 + 聚合
```

配套的视觉分隔（都在 `molten.lua` 里用 extmark 自己画的，没引入插件）：

- **标记行拉一条横线到行尾**，`# %% 抓列表页` 就变成一条带标题的分隔线。
  宽度用 `strdisplaywidth` 算，中文标题也不会算错。
- **光标所在的 cell 在 signcolumn 用 `▎` 标出来**，相当于 Jupyter 的选中态，
  一眼知道按 `<leader>mm` 会跑哪一段。

两个高亮组可以自己换色，`default = true` 意味着换 colorscheme 会自动跟着走：

```lua
vim.api.nvim_set_hl(0, "MoltenCellBorder",  { link = "Comment" })   -- 分隔线
vim.api.nvim_set_hl(0, "MoltenCellCurrent", { link = "Function" })  -- 当前 cell 竖线
```

实现上有三处是刻意的，改的时候别踩：

- 用 **extmark 而不是 `matchadd`**：extmark 挂在 buffer 上，分屏/换窗口都不用重设。
- `CursorMoved` 是高频事件，**不能每次都扫全文件**。所以 `draw_marks` 时把
  「这个 buffer 有没有 cell」缓存进 `vim.b.molten_has_cells`，`draw_current` 只读它；
  再加一层「范围没变就不重画」的短路。
- **没有 cell 的普通 `.py` 完全不受影响**（实测 `has_cells=false`、标记数 0）——
  否则整个文件会被当成一个 cell，每一行都挂上 sign。
- `line:match` 用的是 lua pattern（`%` 要写成 `%%`，所以是 `"^# %%%%"`），
  而 `vim.fn.search` 用的是 vim regex（`%` 不特殊，直接写 `"^# %%"`）。
  **两者不能混用**，写串了就是找不到 cell。

#### 前置依赖：两个系统包，不建 venv

```bash
sudo pacman -S --needed python-pynvim python-ipykernel   # 已在 packages.txt
```

`python-ipykernel` 连带拉进 `python-jupyter-client` 和 `ipython`，装完就有一个开箱可用的
`python3` kernel，`<leader>mi` 直接能起。

**为什么不像常见教程那样建 `~/.venvs/nvim` 装 pynvim**：那要在 `options.lua` 里写死一条
本机路径，正是 `sync.sh` 里 `#@nopull` 那段记录的、`qt6ct.conf` 踩过的坑。用系统包后
`vim.g.python3_host_prog = "/usr/bin/python3"`，任何 Arch 机器都成立，换机器零改动。

**项目自己的依赖（requests / curl_cffi / pandas…）不要往系统 python 装**（Arch 是
externally-managed，装不进去）。正确做法是项目 venv 注册成独立 kernel：

```bash
cd ~/myproject
python -m venv .venv && .venv/bin/pip install ipykernel requests curl_cffi
.venv/bin/python -m ipykernel install --user --name=myproject
# 然后在 nvim 里 <leader>mi 选 myproject
```

kernel 跑在项目 venv 里，nvim 的 host 环境保持干净，每个项目一个 kernel 互不干扰。

#### 五个坑（都是实测踩出来的）

1. **`~/.local/share/jupyter/runtime/` 不存在 → kernel 起不来。** 装完
   `python-ipykernel` 也不会预先建这个目录，jupyter_client 往里写 connection file 时
   直接 `Errno 2`，而 molten 只报一句「Could not initialize kernel named 'python3'」，
   完全看不出是目录问题，极易往 kernel spec / 权限方向乱查。
   `molten.lua` 的 `init` 里已经 `mkdir -p` 兜掉了（幂等），换机器不用记。

2. **`MoltenEvaluateRange` 是函数不是命令。** molten 40 多个接口里只有它（和几个内部
   回调）在 rplugin 清单里是 `'type': 'function'`，写成 `vim.cmd("MoltenEvaluateRange 2 4")`
   得到的是 `E492: Not an editor command`，必须 `vim.fn.MoltenEvaluateRange(s, e)`。
   自己验：`grep EvaluateRange ~/.local/share/nvim/rplugin.vim`。

3. **不能懒加载。** molten 是 remote plugin，`:UpdateRemotePlugins` 只扫描 runtimepath
   里的插件；挂 `ft` / `cmd` 触发器的话启动时它不在 rtp 上，扫不到就不生成 rplugin 清单，
   所有 `:Molten*` 报 E492。所以 spec 里是 `lazy = false`——代价几乎为零，python host
   进程要等第一次 `:MoltenInit` 才真正启动。

4. **`python3_host_prog` 必须显式钉死。** 不设的话 nvim 取 PATH 里的 `python3`，在
   activate 过 venv 的 shell 里启动 nvim 就会取到那个 venv，而它没有 pynvim，
   于是 molten 静默失效。同 `vim.opt.shell` 一样设在 `options.lua`。

5. **输出窗口里按 `q` 关不掉——本配置特有，而且有个二级坑。** molten 不给输出窗口设
   任何按键（它只在 `MoltenInfo` 窗口设了 `q`/`Esc`），官方退出方式是
   `:MoltenHideOutput`；而 `keymaps.lua` 又把 `q` 全局设成了 `<Nop>`（防手滑录宏），
   叠加结果是按 q 毫无反应。
   ⚠ 二级坑：光靠 `FileType molten_output` 的 autocmd **补不上**——molten 文档要求
   `MoltenEnterOutput` 带 `noautocmd`，而输出窗口正是在 enter 那一刻才创建的，
   `noautocmd` 把创建时的 `FileType` 事件一并抑制掉了，autocmd 永远不触发（实测）。
   所以 `molten.lua` 把 `<leader>mo` 包成了一个 lua 函数：先 `noautocmd` 进去，
   进去之后再手动补一次 buffer-local 映射，另外保留 autocmd 兜住非 noautocmd 的路径。

#### 两个调参经验

- **`molten_virt_text_max_lines = 12`**：长跑任务（翻页进度这类）是**真流式**的，
  kernel 每 print 一次就推一条 iopub 消息、虚拟文本实时增长，行数不封顶的话会把下面的
  代码顶得很远。超过 12 行就该 `<leader>mo` 进输出窗口看，那里能滚能搜。
- **`molten_image_provider = "image.nvim"`**（2026-09-12 起）：kernel 回传的图像
  （matplotlib 的 plot、`IPython.display.Image` 塞的 PNG 字节）直接画在 cell 下方的
  虚拟文本输出里。此前长期是 `"none"`，`plt.show()` 只能看到一行
  `<Figure size 640x480 with 1 Axes>`——卡住的原因和后来怎么绕开的，见下一节。
  ⚠ 配套必须 **`molten_auto_image_popup = false`**：molten 这项默认 `true`，每出一张图
  就调 python 的 `Image.show()` 用系统看图器外部弹一次窗，和内联渲染叠在一起很烦。

### image.nvim —— 打开图片、molten 出图，一套机制

2026-09-12 起图片渲染统一由 `image.nvim`（`plugins/image.lua`）承担两件事：
**用 nvim 打开一个图片文件**（mini.files 按 `l`、`:e x.png`、`gf`）就地渲染成图，以及
**给 molten 当图像 provider**，把 kernel 回传的 plot 画进 cell 输出。`snacks.image`
已关（`snacks.lua` 里 `image = { enabled = false }`）。

#### 来龙去脉：为什么先走 snacks，又为什么切回 image.nvim

最初的症状（2026-09-11）：在 mini.files 里按 `l` 打开一个 png，nvim 把二进制字节当文本
渲染，满屏乱码。根因是**整个 nvim 里没有任何东西能渲染图片**：没装 `image.nvim`，
而 `snacks.nvim` 自带的 image 模块处于关闭状态——它的 `defaults` 表里压根没有顶层
`enabled` 键（`snacks/image/init.lua:50`），取值为 `nil` 即假；LazyVim 默认也只开
indent / input / notifier / scope / scroll / words 六个模块，不含 image。

当时选 snacks.image 而不是 image.nvim，理由只有一条——**依赖形态**：

| | 要什么 | 本机状态 |
|---|---|---|
| `image.nvim`（默认 processor） | `magick` **luarock**（luarocks 装，可能要编译） | 没有 luarocks |
| `snacks.image` | ImageMagick 的**命令行程序** `/usr/bin/magick` | ✅ 已装（做 ASCII 壁纸用的） |

`molten.lua` 里那句「不接 image.nvim（需要 magick luarock）」记的就是这个坎。

但 snacks.image **顶不了 molten 的班**：molten 的 image provider 只认 `none` /
`image.nvim` / `wezterm` 三个值（`molten/images.py:265-274`），不认 snacks。两者是
彻底独立的机制——snacks.image 管「打开磁盘上的图片文件」，molten 管「把 kernel 通过
iopub 回传的图像字节画进输出」，后者根本不经过文件系统，`BufReadCmd` 无从拦截。
结果是 `plt.show()` 只剩一行 `<Figure size ...>`。

破局点是 **image.nvim 其实有两种 processor**：默认的 `"magick_rock"`（FFI 绑定，
要 luarock）之外还有 **`"magick_cli"`**——直接 shell out 到系统 ImageMagick 的
`magick` / `convert` / `identify`，零 luarock。这和 snacks.image 的依赖形态完全一样，
当初的顾虑就不存在了。既然 image.nvim 能同时干两件事，就没理由再养两套：**打开图片
文件也交给它，snacks.image 关掉。**

#### `image.lua` 里几处必须写对的地方

- **`build = false`**。lazy.nvim 看到 image.nvim 的 rockspec 会去跑 luarocks 装
  magick rock，本机没有 luarocks 那步必失败，插件直接装不上（image.nvim#91）。
  我们走 CLI 不需要它。
- **`processor = "magick_cli"`、`backend = "kitty"`**。两项其实都是默认值，显式写出
  是因为它们就是这套方案的要点。
- **`lazy = false`**。两个理由：molten 是 `lazy = false` 的 remote plugin，渲染图时要
  现成的 image.nvim API；「打开图片文件即渲染」靠它注册的 autocmd，启动即就位才拦得住
  第一次 `:e`。理论上可以挂事件懒加载，但 hijack 挂在 `BufWinEnter` 上，靠同一个事件
  触发加载会错过首次打开，不值得为省几毫秒引入这个坑。
- **snacks.image 必须关**，不是可选。两边都会拦图片文件，同时开谁后注册谁生效，
  行为不可预期。留一个即可。

#### 它做到了什么，没做到什么

**做到了：** 用 `hijack_file_patterns`（默认 png/jpg/jpeg/gif/webp/avif）在
**`BufWinEnter`** 上接管图片文件——注意是 `BufWinEnter` 不是 snacks 用的 `BufReadCmd`，
用 `nvim_get_autocmds` 查注册方时别查错事件（实测踩过）。markdown 里的图片内联渲染在
正文中（`integrations.markdown`）。molten 那边 `molten_image_location` 默认 `"both"`，
配合本配置的 `virt_text_output = true`，图就画在 cell 下方的内联输出里，不用另开窗。

**没做到：mini.files 的 preview 窗格仍然不显示图片。** 因为 mini.files 的预览不是
「打开文件」——它 `readfile` 出内容再 `nvim_buf_set_lines` 塞进一个 scratch buffer
（`mini/files.lua:2381`），没有任何 buffer 事件可拦。
⚠ 顺带纠正一个误判：preview 窗格**本来就不会**显示二进制乱码。mini.files 自己有
检测——读前 1024 字节找 `\0`，命中就显示 `-Non-text-file----`。而且本机 `mini.lua`
根本没开 preview（默认 `preview = false`）。所以当初看到的乱码一定来自「按 `l` 真的
打开了文件」，不是预览。这条路现在已经通了。真想要「光标移上去右边就出图」得用
`MiniFilesBufferUpdate` 事件拿路径自己往预览窗贴，属于几十行的定制，暂未做。

#### 前置条件：终端必须支持 kitty 图形协议

kitty / ghostty / wezterm 可以，**alacritty 不行**。本机两个终端都装了，日常用 kitty，
所以没问题——但如果哪天在 alacritty 里开 nvim，图片会静默地不显示，别以为是配置坏了。

真正把像素画到屏幕上的是 **kitty**，nvim / image.nvim / molten 都只是把图像字节按
kitty graphics protocol 的转义序列喂给终端的搬运工。所以 **`nvim --headless` 下
验证不了渲染**（没有终端可对话）；headless 里能验的只有「插件加载了、hijack 注册了、
snacks.image 关了」三件事，真出图要在 kitty 里 `:e x.png` 或跑一个 matplotlib cell。
（`pillow` 只有 `:MoltenImagePopup` 外部弹窗才用，内联渲染不需要，所以没进 packages.txt。）

### 其他小项

- **`q` 被禁用**（`keymaps.lua`）：手滑按 `q` 开始录制宏，然后所有按键被吞进寄存器
  是很烦的事。要录宏用 `@` 系列或临时 `:unmap q`。
- **tokyonight 透明**：`transparent = true` + sidebars/floats 也透明，配合 kitty 的
  `background_opacity 0.6` 才能真的透出壁纸。只改一边是没用的。
- **no-neck-pain**：`<leader>z` 居中 120 列阅读模式，scratchPad 存在 `~/doc/`。

---

## 语言工具链（Mason）

`lazyvim.json` 里开了 11 个语言 extras：

```
clangd  cmake  go  java  json  kotlin  markdown  php  python  sql  typescript
```

⚠️ **extras 只负责挂 LSP 配置，不负责装运行时。** Mason 装 `gopls` 需要 go、装
`typescript-language-server` 需要 node、装 `php-cs-fixer` 需要 php/composer。
运行时缺了 Mason 就会一片红叉——这不是配置错误。

两条路，选一条：

```bash
# A. 补齐运行时，然后进 nvim 用 :Mason 逐个装
sudo pacman -S nodejs npm go composer php jdk-openjdk tree-sitter-cli python-pip

# B. 不写那些语言 —— 直接删 lazyvim.json 里对应的 extras 条目，更省事
```

本机（快照时）缺的：`cmakelang` · `golangci-lint` · `ktlint` · `markdownlint-cli2`
· `markdown-toc` · `php-cs-fixer` · `phpcs` · `sqlfluff` · `tree-sitter-cli`。

---

## 已知历史问题（已处理，别改回去）

`lua/plugins/gp.lua` 曾经硬编码了 4 个 AI API 密钥，已整个删除，`lazy-lock.json` 里
的 `gp.nvim` 条目也一并删了（密钥已吊销）。
**想恢复 gp.nvim 的话，写成从环境变量读 key**，不要再硬编码。
