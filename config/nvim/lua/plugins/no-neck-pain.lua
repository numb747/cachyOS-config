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

  -- ★ 上游 bug 补丁(截至 commit 0df6659,main 分支仍未修):
  --   util/api.lua 的 is_relative_window(win) 第一个判据写的是
  --   `nvim_win_get_config(0).relative ~= ""`,而 0 在 nvim API 里指"当前窗口",
  --   不是参数 win。于是只要当前窗口是浮窗,传任何 win 进去都返回 true。
  --
  --   触发路径:先 <leader>z 开 NNP,再 <leader>uz 开 snacks zen(浮窗),
  --   此时按 <leader>z 关 NNP → main.disable 里的
  --     wins = filter(w ~= left and w ~= right and not is_relative_window(w))
  --   把每一个窗口都误判成浮窗全部滤掉 → #wins == 0 → 走到 `vim.cmd("quitall!")`
  --   → nvim 强退、kitty 跟着关掉。带 ! 会丢弃未保存修改。
  --
  --   这里只把它改成"只看传入的 win"。三处无参调用(main.lua:234、
  --   event.lua:19/53)行为完全不变 —— 无参时 win 本就等于当前窗口,两个判据等价;
  --   五处带参调用(main.lua:266/449、state.lua:29/343/398)修复后才是其字面语义。
  --   运行时覆盖,不动插件文件,:Lazy update 不会冲掉。
  config = function(_, opts)
    local nnp_api = require("no-neck-pain.util.api")
    nnp_api.is_relative_window = function(win)
      win = win or vim.api.nvim_get_current_win()
      return vim.api.nvim_win_get_config(win).relative ~= ""
    end

    require("no-neck-pain").setup(opts)
  end,
}
