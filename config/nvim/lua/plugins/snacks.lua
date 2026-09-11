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

    -- 图片查看器。snacks 里 image 默认是关的（defaults 表里压根没有顶层
    -- enabled 键 → nil → 关），LazyVim 也不开它，所以 :e xxx.png 一直是二进制。
    --
    -- ★ 只依赖 ImageMagick 的 CLI（/usr/bin/magick），不需要 image.nvim 那个
    --   magick luarock —— 那正是 molten.lua 里当初放弃图片的原因。
    -- ★ 依赖终端的 kitty graphics protocol。kitty / ghostty / wezterm 可以，
    --   alacritty 不行（你两个都装了，别在 alacritty 里指望它）。
    -- ★ 它注册 BufReadCmd 拦截图片文件，所以 mini.files 里按 l/L 打开图片
    --   会直接渲染，而不是加载成二进制 buffer。
    image = {
      enabled = true,
      doc = {
        -- markdown 里的图片直接内联渲染在正文中
        inline = true,
        float = true,
        max_width = 60,
        max_height = 30,
      },
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
