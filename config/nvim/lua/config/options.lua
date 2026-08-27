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
