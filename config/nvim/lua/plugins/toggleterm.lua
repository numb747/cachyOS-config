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
    local term_ux = require("util.term")

    -- 快速生成4个终端的函数
    local function create_four_terminals()
      local Terminal = require("toggleterm.terminal").Terminal

      -- 生成4个随机ID的终端
      for i = 1, 4 do
        local random_id = math.random(1000, 9999)
        local term = Terminal:new({
          id = random_id,
          direction = "float",
          -- 不设 display_name：留空让 util.term 自动命名。
          -- 原先设成 ""，而 toggleterm 的 _display_name() 是 `self.display_name or ...`，
          -- 空串在 Lua 里是真值 —— 于是浮窗标题恒为空，也盖掉了自动名。
        })
        term:open()
        -- 添加延迟，避免终端重叠
        vim.defer_fn(function() end, 50 * i)
      end

      vim.notify("已创建4个终端", vim.log.levels.INFO)
    end

    -- 列出并切换终端函数
    local function list_terminals()
      local terms = require("toggleterm.terminal").get_all(true)
      if #terms == 0 then
        vim.notify("没有打开的终端", vim.log.levels.WARN)
        return
      end

      local items = {}
      for _, term in ipairs(terms) do
        -- 和 <leader>fb、顶栏显示同一个值：自定义名优先，没起过名就动态算
        -- （util.term.term_label 读 /proc 拿正在跑的程序，跑 claude 就显示 claude）
        local name
        if term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
          local label = vim.b[term.bufnr].term_ux_label
          name = (label and label ~= "") and label or term_ux.term_label(term.bufnr)
        else
          name = term.display_name or ("终端 #" .. term.id)
        end
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
          -- get() 的签名是 get(id, include_hidden)，不传第二个参数时 hidden 的终端
          -- 一律返回 nil。上面用 get_all(true) 把 hidden 的也列出来了，这里不传就会
          -- 选中后毫无反应还不报错 —— 两边必须一致。
          local term = require("toggleterm.terminal").get(choice.id, true)
          if term then
            term:toggle()
          end
        end
      end)
    end

    -- Normal 模式快捷键
    vim.keymap.set("n", "<leader>tn", term_ux.rename, { desc = "命名终端" })
    vim.keymap.set("n", "<leader>tl", list_terminals, { desc = "列出终端" })
    vim.keymap.set("n", "<leader>tt", create_four_terminals, { desc = "创建4个终端" })
    -- 设置快捷键
    local function set_terminal_keymaps()
      local opts = { buffer = 0, silent = true }
      -- 双击 Esc 退出终端模式
      vim.keymap.set("t", "<esc><esc>", [[<C-\><C-n>]], opts)
      -- Ctrl+f 列出终端（只列 toggleterm 的终端，所以留在这里）
      -- ⚠ 终端模式下会盖掉 shell 的 Ctrl+F。想要回来就把 mode 里的 "t" 去掉。
      vim.keymap.set({ "t", "n" }, "<C-f>", function()
        vim.cmd("stopinsert")
        vim.schedule(list_terminals)
      end, opts)
      -- Ctrl+r 重命名不在这里绑：它对原生 :terminal 也要生效，
      -- 已统一挪到 util/term.lua 的 TermOpen(pattern="*") 里。
    end

    -- 使用 autocmd 自动设置终端快捷键
    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "term://*toggleterm#*",
      callback = set_terminal_keymaps,
      desc = "设置 ToggleTerm 快捷键",
    })
  end,
}
