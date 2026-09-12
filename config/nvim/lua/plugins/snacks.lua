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

    -- 图片渲染已统一交给 image.nvim(见 plugins/image.lua):打开图片文件、
    -- markdown 内联、molten 预览图,三件事走同一套 provider,只维护一处。
    --
    -- ★ snacks.image 必须关:它和 image.nvim 都注册 BufReadCmd 抢图片文件,
    --   两个同时开会打架(谁后注册谁生效,行为不可预期)。留一个即可。
    -- ★ 之所以从 snacks 切走:molten 的图像 provider 只认 none/image.nvim/wezterm,
    --   不认 snacks —— 要 molten 内联出图就必须上 image.nvim,索性打开图片也统一用它。
    image = { enabled = false },
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
