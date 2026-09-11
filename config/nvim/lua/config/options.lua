-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
local opt = vim.opt
opt.fileencoding = "utf-8" -- 新文件的编码
opt.fileencodings = "utf-8,gbk,gb2312,gb18030" -- 打开文件时的编码检测顺序
opt.spelllang = { "en", "cjk" }
-- 设置文件编码
opt.encoding = "utf-8"
-- 禁用交换文件
opt.swapfile = false
-- ctrl+s 保存
vim.opt.spell = false
vim.opt.spelllang = ""
-- 默认启动自动换行
vim.opt.wrap = true
-- 默认禁用诊断
vim.diagnostic.enable(true)

-- 内置终端用 zsh，而不是 $SHELL（登录时的快照，可能是过期值）。
-- 必须设在这里：本文件在 lazy.nvim 启动前加载，而 toggleterm.lua 的
-- opts = { shell = vim.o.shell } 在 spec 构造那一刻就把值取走了。
-- 靠 kitty 的 -c 设置来不及——那要等 spec 构造之后才执行。
-- 一处设置，三处受益：:terminal、toggleterm(Ctrl+/)、:!cmd / vim.fn.system。
vim.opt.shell = vim.fn.executable("zsh") == 1 and vim.fn.exepath("zsh") or vim.o.shell

-- Python provider 钉死系统解释器（molten-nvim 这类 remote plugin 靠它跑）。
-- 不设的话 nvim 取 PATH 里的 python3——在 activate 过 venv 的 shell 里启动，
-- 取到的就是那个 venv，而它没装 pynvim，于是所有 :Molten* 命令静默失效。
-- 写绝对路径不算硬编码本机：Arch 上系统解释器恒在此，换机器不用改。
-- 依赖 python-pynvim + python-ipykernel（见 packages.txt），
-- 爬虫那些包不要往系统装，用项目 venv 注册成 kernel —— 见 docs/04-neovim.md。
vim.g.python3_host_prog = "/usr/bin/python3"
