-- 标题渲染恢复为 render-markdown 官方默认(LazyVim extra 把 icons/sign 关掉了)
return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    heading = {
      sign = true,
      icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
    },
  },
}
