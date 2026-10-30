return {
  "shortcuts/no-neck-pain.nvim",
  event = "VeryLazy",
  opts = {
    width = 120,
    autocmds = {
      enableOnVimEnter = false,
      enableOnTabEnter = false,
    },
    -- 两侧只当空白填充。2026-10-30 之前这里开着 scratchPad(侧边当 markdown 草稿本)，
    -- 插件升到 3.0 后实测草稿本模式下侧边窗口 number / relativenumber / cursorline 全是 true，
    -- 两侧第一行各显示一个行号、带光标行高亮。草稿本从没存上过盘(location 指的 ~/doc/ 不存在)，
    -- 关掉没有损失。
    buffers = {
      wo = {
        -- number / relativenumber / cursorline 插件默认已是 false；这两项是 LazyVim 全局设的
        statuscolumn = "",
        signcolumn = "no",
      },
    },
  },
  keys = {
    { "<leader>z", "<cmd>NoNeckPain<cr>", desc = "Toggle No Neck Pain (Zen-like)" },
  },
  -- 原先这里有一段 is_relative_window 运行时补丁(当前窗口是浮窗时关 NNP 会 quitall!)，
  -- 3.0 上游已按同样写法修好(util/api.lua)，补丁删了。
}
