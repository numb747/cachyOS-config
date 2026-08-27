return {
  "folke/snacks.nvim",
  opts = {
    explorer = { enabled = false },
    zen = { enabled = false },
    terminal = {
      enabled = false,
      -- win = {
      --   position = "float",
      --   border = "rounded",
      -- },
    },
  },
  keys = {
    -- 帮助禁用snacks内置的相关文件浏览器插件,从而使用mini-files
    { "<leader>fe", false },
    { "<leader>fE", false },
    { "<leader>E", false },
    { "<leader>e", false },
    { "<c-/>", false },
  },
}
