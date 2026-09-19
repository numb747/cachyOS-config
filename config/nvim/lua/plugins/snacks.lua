return {
  "folke/snacks.nvim",
  opts = {
    explorer = { enabled = false },

    -- ★ zen 的 `enabled = false` 是无效的:LazyVim 在 config/keymaps.lua 里直接
    --   `Snacks.toggle.zen():map("<leader>uz")` 手动调用,`enabled` 只拦得住
    --   自启动 setup 的模块(indent/scroll/notifier),拦不住按需调用。
    -- ★ 真正要关的是 toggles.dim:snacks.zen 默认 dim = true,进 zen 会顺手打开
    --   Snacks.dim —— 用 treesitter 算光标所在 scope,把 scope 外的所有行变暗,
    --   跟着光标实时重算。效果就是"只有光标附近是实的,其他代码全是虚的"。
    zen = {
      toggles = { dim = false },
    },
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

    -- 终端条目只显示名字。snacks 默认的 buffer 格式化器(picker/format.lua 的 M.buffer)
    -- 会把 bufnr、flags、完整路径、[terminal] 全拼上，终端那行长成
    --   %a  term:/…/usr/bin/zsh [zsh:monkey#5]:1  [terminal]
    -- 没法扫读。终端条目改走 util/term.lua 自己渲染，非终端原样交回默认实现。
    picker = {
      sources = {
        buffers = {
          format = function(item, picker)
            return require("util.term").format_buffer(item, picker)
          end,
        },
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
