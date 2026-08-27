return {
  "akinsho/toggleterm.nvim",
  version = "*",
  event = "VeryLazy",
  opts = {
    size = function(term)
      if term.direction == "horizontal" then
        return 15
      elseif term.direction == "vertical" then
        return vim.o.columns * 0.4
      end
    end,
    open_mapping = [[<c-/>]],
    hide_numbers = true,
    shade_terminals = true,
    shading_factor = 2,
    start_in_insert = true,
    insert_mappings = true,
    terminal_mappings = true,
    persist_size = true,
    direction = "float",
    close_on_exit = true,
    shell = vim.o.shell,
    float_opts = {
      border = "curved",
      winblend = 0,
      highlights = {
        border = "Normal",
        background = "Normal",
      },
      -- 居中竖长条：宽度锁在 80~110 列的阅读舒适区，高度尽量拉满
      -- 不指定 row/col 时 toggleterm 会按 width/height 自动居中
      width = function()
        local cols = vim.o.columns
        -- 宽屏取半屏并封顶 110 列；窄屏时退让到 90% 避免溢出
        return math.min(math.max(80, math.min(110, math.floor(cols * 0.5))), math.floor(cols * 0.9))
      end,
      height = function()
        return math.floor(vim.o.lines * 0.9)
      end,
    },
  },
  keys = {
    { "<c-/>", "<cmd>ToggleTerm<cr>", desc = "切换终端", mode = { "n", "t" } },
    { "<leader>th", "<cmd>ToggleTerm direction=horizontal<cr>", desc = "水平终端" },
    { "<leader>tv", "<cmd>ToggleTerm direction=vertical<cr>", desc = "垂直终端" },
  },
  config = function(_, opts)
    require("toggleterm").setup(opts)
    -- 快速生成4个终端的函数
    local function create_four_terminals()
      local Terminal = require("toggleterm.terminal").Terminal

      -- 生成4个随机ID的终端
      for i = 1, 4 do
        local random_id = math.random(1000, 9999)
        local term = Terminal:new({
          id = random_id,
          direction = "float",
          -- display_name = "终端 #" .. i,
          display_name = "",
        })
        term:open()
        -- 添加延迟，避免终端重叠
        vim.defer_fn(function() end, 50 * i)
      end

      vim.notify("已创建4个终端", vim.log.levels.INFO)
    end
    -- 命名终端函数
    local function name_terminal()
      local terms = require("toggleterm.terminal").get_all()
      if #terms == 0 then
        vim.notify("没有打开的终端", vim.log.levels.WARN)
        return
      end

      -- 查找当前缓冲区对应的终端
      local current_term = nil
      local current_buf = vim.api.nvim_get_current_buf()
      for _, term in ipairs(terms) do
        if term.bufnr == current_buf then
          current_term = term
          break
        end
      end

      -- 如果当前不在终端缓冲区，使用最后一个终端
      if not current_term then
        current_term = terms[#terms]
      end

      vim.ui.input({
        prompt = "终端名称: ",
        default = current_term.display_name or "",
      }, function(name)
        if name and name ~= "" then
          current_term.display_name = name
          vim.notify("终端已重命名为: " .. name, vim.log.levels.INFO)
        end
      end)
    end

    -- 列出并切换终端函数
    local function list_terminals()
      local terms = require("toggleterm.terminal").get_all()
      if #terms == 0 then
        vim.notify("没有打开的终端", vim.log.levels.WARN)
        return
      end

      local items = {}
      for _, term in ipairs(terms) do
        local name = term.display_name or ("终端 #" .. term.id)
        table.insert(items, {
          id = term.id,
          name = name,
          display = string.format("[%d] %s", term.id, name),
        })
      end

      vim.ui.select(items, {
        prompt = "选择终端:",
        format_item = function(item)
          return item.display
        end,
      }, function(choice)
        if choice then
          local term = require("toggleterm.terminal").get(choice.id)
          if term then
            term:toggle()
          end
        end
      end)
    end

    -- Normal 模式快捷键
    vim.keymap.set("n", "<leader>tn", name_terminal, { desc = "命名终端" })
    vim.keymap.set("n", "<leader>tl", list_terminals, { desc = "列出终端" })
    vim.keymap.set("n", "<leader>tt", create_four_terminals, { desc = "创建4个终端" })
    -- 设置快捷键
    local function set_terminal_keymaps()
      local opts = { buffer = 0, silent = true }
      -- 双击 Esc 退出终端模式
      vim.keymap.set("t", "<esc><esc>", [[<C-\><C-n>]], opts)
      -- Ctrl+r 命名终端
      vim.keymap.set({ "t", "n" }, "<C-r>", function()
        vim.cmd("stopinsert")
        vim.schedule(name_terminal)
      end, opts)
      -- Ctrl+f 列出终端
      vim.keymap.set({ "t", "n" }, "<C-f>", function()
        vim.cmd("stopinsert")
        vim.schedule(list_terminals)
      end, opts)
    end

    -- 使用 autocmd 自动设置终端快捷键
    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "term://*toggleterm#*",
      callback = set_terminal_keymaps,
      desc = "设置 ToggleTerm 快捷键",
    })
  end,
}
