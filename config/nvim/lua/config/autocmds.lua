-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
-- 失去焦点时自动保存
vim.api.nvim_create_autocmd("FocusLost", {
  pattern = "*",
  command = "silent! wa",
})
-- 离开插入模式时自动保存
vim.api.nvim_create_autocmd("InsertLeave", {
  pattern = "*",
  command = "silent! write",
})
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    -- 双Esc退出terminal模式
    vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { buffer = true })
    -- 或者如果你更喜欢单Esc（可能会有输入延迟）
    -- vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { buffer = true })
  end,
})
