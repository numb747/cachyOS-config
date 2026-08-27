# 04 · Neovim（LazyVim）

对应目录：`config/nvim/` → `~/.config/nvim/`
基座 LazyVim，锁 45 个插件（`lazy-lock.json`），实装 44 个。

---

## 首次启动

```bash
nvim        # 自动 clone lazy.nvim，然后按 lazy-lock.json 装 45 个插件
```

等 lazy 界面跑完再操作。**不要**把旧机的 `~/.local/share/nvim/lazy/` 拷过来——
版本由 `lazy-lock.json` 锁定，拷实体反而容易和 git 状态冲突。

> 44 装 / 45 锁不是 bug：`bufferline.nvim` 在锁文件里，但被
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
├── options.lua             编码、swapfile、内置终端 shell
├── keymaps.lua             只有一条：禁用 q 录制宏
└── autocmds.lua            自动保存、终端双 Esc
lua/plugins/
├── colorscheme.lua         tokyonight，透明
├── disabled.lua            关掉 bufferline
├── lualine.lua             状态栏
├── mini.lua                mini.files 文件管理器（替代 snacks explorer）
├── no-neck-pain.lua        居中阅读模式
├── snacks.lua              关掉与 mini.files 冲突的部分
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

#### mini.lua 里那段 `vim.glob.to_lpeg` 补丁

```lua
-- 修复 LSP server 发送无效 glob 模式 (如 **/*.{}) 导致 vim.glob.to_lpeg 崩溃
```

某些 LSP 会发出 `**/*.{}` 这种空花括号的 glob，Neovim 的 `vim.glob.to_lpeg` 解析
不了直接抛错，表现为打开某类文件时 nvim 弹一堆红色 stack trace。这段把空花括号
擦掉再交给原函数。属于上游 bug 的本地绕行——哪天 Neovim 修了可以删掉。

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
