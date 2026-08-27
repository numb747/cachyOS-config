return {
  "nvim-lualine/lualine.nvim",
  opts = {
    options = {
      theme = "auto",  -- 直接使用 bubbles 主题
      component_separators = "",
      section_separators = { left = "", right = "" },
      globalstatus = true,  -- 可选：使用全局 statusline（Neovim 0.7+）
      disabled_filetypes = { statusline = { "dashboard", "alpha", "starter" } },
    },

    sections = {
      lualine_a = {
        { "mode", separator = { left = "" }, right_padding = 2 },
      },
      lualine_b = { "branch", "diff", "diagnostics" },
      lualine_c = { "filename" },
      lualine_x = { "encoding", "fileformat", "filetype" },
      lualine_y = { "progress" },
      lualine_x = {
        {
          require("noice").api.statusline.mode.get,
          cond = require("noice").api.statusline.mode.has,
          color = { fg = "#ff9e64" },
        },
      },
      lualine_z = {
        { "location", separator = { right = "" }, left_padding = 2 },
      },
    },

    inactive_sections = {
      lualine_a = { "filename" },
      lualine_b = {},
      lualine_c = {},
      lualine_x = {},
      lualine_y = {},
      lualine_z = { "location" },
    },
  },
}
