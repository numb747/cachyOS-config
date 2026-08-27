return {
  "nvim-mini/mini.files",
  keys = {
    {
      "<leader>fm",
      function()
        require("mini.files").open(vim.api.nvim_buf_get_name(0), true)
      end,
      desc = "Open mini.files (directory of current file)",
    },
    {
      "<leader>e",
      function()
        require("mini.files").open(vim.uv.cwd(), true)
      end,
      desc = "Open mini.files (cwd)",
    },
    {
      "<leader>E",
      function()
        require("mini.files").open(LazyVim.root(), true)
      end,
      desc = "Open mini.files (root)",
    },
  },
  opts = {
    mappings = {
      close = "q",
      go_in = "l",
      go_in_plus = "L",
      go_out = "h",
      go_out_plus = "H",
      reset = "<BS>",
      reveal_cwd = "@",
      show_help = "g?",
      synchronize = "=", -- 这是默认的保存键
      trim_left = "<",
      trim_right = ">",
    },
  },
  config = function(_, opts)
    -- 修复 LSP server 发送无效 glob 模式 (如 **/*.{}) 导致 vim.glob.to_lpeg 崩溃
    local orig_to_lpeg = vim.glob.to_lpeg
    vim.glob.to_lpeg = function(pattern)
      if pattern:find('%{%}') then
        pattern = pattern:gsub('%*%.%{%}', '*')
        pattern = pattern:gsub('%{%}', '*')
      end
      return orig_to_lpeg(pattern)
    end

    require("mini.files").setup(opts)

    -- 自定义键位映射
    local map_split = function(buf_id, lhs, direction)
      local rhs = function()
        local new_target_window
        vim.api.nvim_win_call(require("mini.files").get_target_window(), function()
          vim.cmd(direction .. " split")
          new_target_window = vim.api.nvim_get_current_win()
        end)
        require("mini.files").set_target_window(new_target_window)
        require("mini.files").go_in()
      end

      vim.keymap.set("n", lhs, rhs, { buffer = buf_id, desc = "Split " .. direction })
    end

    -- 添加 Ctrl+s 保存和 Esc 退出的映射
    vim.api.nvim_create_autocmd("User", {
      pattern = "MiniFilesBufferCreate",
      callback = function(args)
        local buf_id = args.data.buf_id

        -- Ctrl+s 保存修改（同步文件系统）
        vim.keymap.set("n", "<C-s>", function()
          require("mini.files").synchronize()
        end, { buffer = buf_id, desc = "Save changes (synchronize)" })

        -- Esc 退出 mini.files
        vim.keymap.set("n", "<Esc>", function()
          require("mini.files").close()
        end, { buffer = buf_id, desc = "Close mini.files" })

        -- 可选：添加分屏打开文件的快捷键
        map_split(buf_id, "gs", "belowright horizontal")
        map_split(buf_id, "gv", "belowright vertical")
      end,
    })
  end,
}
