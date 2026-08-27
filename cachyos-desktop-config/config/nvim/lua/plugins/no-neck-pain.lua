return {
  "shortcuts/no-neck-pain.nvim",
  event = "VeryLazy",
  opts = {
    width = 120,
    autocmds = {
      enableOnVimEnter = false,
      enableOnTabEnter = false,
    },
    buffers = {
      scratchPad = {
        enabled = true,
        -- 保存目录，末尾带斜杠
        location = "~/doc/",
      },
      bo = {
        filetype = "markdown", -- 正确的 filetype 值
      },
    },
  },
  keys = {
    { "<leader>z", "<cmd>NoNeckPain<cr>", desc = "Toggle No Neck Pain (Zen-like)" },
  },
}
