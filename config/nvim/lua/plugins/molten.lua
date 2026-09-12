-- molten-nvim —— 在普通 .py 文件里跑 Jupyter kernel，输出内联显示
--
-- 为什么不是 iron.nvim / vim-slime 那种 REPL：那类插件把代码喂进伪终端再读回字符，
-- 执行是同步的、输出是一条流水账、分不清哪段输出属于哪段代码。molten 走的是
-- Jupyter 的 ZeroMQ 协议（shell + iopub 双通道），于是拿到三件 tty REPL 给不了的东西：
--   1. 提交即返回，跑几分钟的 cell 不阻塞编辑，期间可以切窗口甚至排队执行别的 cell
--   2. 每条输出带 msg_id，精确绑定到发起它的那段代码，重跑就地覆盖
--   3. 中断走独立信道（:MoltenInterrupt），打断卡住的请求而不丢失命名空间
--
-- 为什么坚持用 .py + `# %%` 而不是 .ipynb：buffer 就是一个普通 Python 文件，
-- basedpyright 看到的是完整上下文，补全/跳转/重命名全部原生满血。走 .ipynb 得靠
-- otter.nvim 把 cell 抠出来喂影子 buffer，是打补丁，跨 cell 引用经常失效。
-- 附带好处：文件能直接 `python x.py` 跑，git diff 是纯代码而不是一坨 JSON。
--
-- 见 docs/04-neovim.md「molten —— Python 的 Jupyter 式内联执行」
return {
  "benlubas/molten-nvim",
  version = "^1.0.0",
  build = ":UpdateRemotePlugins",
  -- ★ 不能懒加载。molten 是 remote plugin，:UpdateRemotePlugins 只扫描
  --   runtimepath 里的插件；挂 ft/cmd 触发器的话插件目录启动时不在 rtp 上，
  --   扫不到就不会生成 rplugin 清单，所有 :Molten* 命令报 E492。
  --   代价几乎为零：python host 进程要等第一次 :MoltenInit 才真正启动。
  lazy = false,

  init = function()
    -- ★ jupyter 的 runtime 目录不存在的话，kernel 起不来 —— jupyter_client 往里写
    --   connection file 时直接 Errno 2，molten 只报一句「Could not initialize kernel」，
    --   看不出是目录问题。系统装完 python-ipykernel 也不会预先建它（实测 2026-09-11）。
    --   幂等，放这里让配置自包含，换机器不用记得手动 mkdir。
    vim.fn.mkdir(((vim.env.XDG_DATA_HOME or vim.env.HOME .. "/.local/share") .. "/jupyter/runtime"), "p")

    -- 输出以虚拟文本内联显示在 cell 下方，不开第二个窗口
    vim.g.molten_virt_text_output = true
    vim.g.molten_auto_open_output = false
    vim.g.molten_virt_lines_off_by_1 = true
    vim.g.molten_wrap_output = true
    vim.g.molten_output_show_exec_time = true

    -- 内联只留 12 行。长跑任务（翻页进度这类）的流式输出会不断长出虚拟行、
    -- 把下面的代码顶走，超了就该 <leader>mo 进输出窗口看，那里能滚能搜。
    vim.g.molten_virt_text_max_lines = 12
    vim.g.molten_output_win_max_height = 30

    -- ★ 一次按键就进输出窗口。默认 "open_then_enter" 是「第一次开窗、第二次才进去」，
    --   而虚拟文本是画上去的、选不中也复制不了，想 yank 输出就必须进那个真 buffer，
    --   让它按两次很别扭。改成 open_and_enter：<leader>mo 直达，能 v/y 正常复制，
    --   q 或 Esc 退出（退出键是下面 FileType autocmd 补的）。
    vim.g.molten_enter_output_behavior = "open_and_enter"

    -- 图像 provider 走 image.nvim(见 plugins/image.lua)。molten 只认
    --   none / image.nvim / wezterm 三个值,不认 snacks —— 要 molten 内联出图,
    --   就必须挂 image.nvim。当初躲它是因为它默认要 magick luarock;现在用它的
    --   processor = "magick_cli" 走系统 ImageMagick,零 luarock,顾虑没了。
    -- 效果:kernel 回传的 matplotlib / PNG 直接画在 cell 下方的虚拟文本输出里
    --   (molten_image_location 默认 "both",virt_text_output=true 时就显示在内联输出中,
    --   不用另开输出窗口)。
    vim.g.molten_image_provider = "image.nvim"

    -- ★ 关掉"自动用系统看图器弹窗"(molten 默认 true)。否则每产生一张图,molten
    --   就调 python 的 Image.show() 用系统默认看图器外部弹一次 —— 我们要的是
    --   image.nvim 在 nvim 里内联渲染,不是外部 viewer 满屏乱弹。
    vim.g.molten_auto_image_popup = false
  end,

  config = function()
    local map = vim.keymap.set

    -- 运行「当前 cell」：上溯最近的 `# %%`，下探下一个，把中间交给 kernel。
    -- molten 本身没有 cell 概念（只有 line / visual / operator），cell 是这里补的。
    -- ★ MoltenEvaluateRange 在 rplugin 清单里是 'type': 'function' 而不是 'command'
    --   （`grep EvaluateRange ~/.local/share/nvim/rplugin.vim` 可验），
    --   写成 vim.cmd("MoltenEvaluateRange 2 4") 会得到 E492，必须用 vim.fn 调。
    --   molten 全部命令里只有它和几个内部回调是这样，其余都是正经 command。
    local function run_cell()
      local s = vim.fn.search("^# %%", "bcnW")
      s = (s == 0) and 1 or s + 1
      local e = vim.fn.search("^# %%", "nW")
      e = (e == 0) and vim.fn.line("$") or e - 1
      if s > e then
        return
      end
      vim.fn.MoltenEvaluateRange(s, e)
    end

    -- Jupyter 的 Shift+Enter：执行并跳到下一个 cell
    local function run_and_next()
      run_cell()
      vim.fn.search("^# %%", "W")
    end

    -- 输出窗口里的退出键。★ molten 自己不给输出窗口设任何按键（只给 MoltenInfo
    --   窗口设了 q/Esc），官方退出方式是 :MoltenHideOutput；而本配置在 keymaps.lua
    --   里把 q 全局设成了 <Nop>（防手滑录宏）。两边叠加 = 按 q 毫无反应。
    --   buffer-local 优先于全局映射，只在 molten_output 里生效。
    local function set_output_keys(buf)
      if vim.bo[buf].filetype ~= "molten_output" then
        return
      end
      vim.keymap.set("n", "q", "<cmd>MoltenHideOutput<cr>", { buffer = buf, desc = "关闭输出窗口" })
      vim.keymap.set("n", "<esc>", "<cmd>MoltenHideOutput<cr>", { buffer = buf, desc = "关闭输出窗口" })
    end

    -- ★★ 自己坑自己的地方：molten 文档要求 MoltenEnterOutput 带 noautocmd，
    --    而输出窗口是在 enter 那一刻才创建的 —— noautocmd 把创建时的 FileType
    --    事件一并抑制掉，于是下面那条 autocmd 永远不触发、q 绑不上（实测）。
    --    所以进去之后必须再手动补一次（重复 set 无害）。
    local function enter_output()
      vim.cmd("noautocmd MoltenEnterOutput")
      set_output_keys(vim.api.nvim_get_current_buf())
    end

    -- <leader>m 是干净的前缀：LazyVim 默认没占，本目录里 <leader>t 归 toggleterm、
    -- <leader>e/E 归 mini.files、<leader>z 归 no-neck-pain、<leader>l 是 :Lazy、
    -- <leader>x 是 Trouble 组 —— 都不能碰。
    map("n", "<leader>mi", "<cmd>MoltenInit<cr>", { desc = "Molten: 启动 kernel" })
    map("n", "<leader>mm", run_and_next, { desc = "Molten: 运行 cell 并下移" })
    map("n", "<leader>me", run_cell, { desc = "Molten: 运行当前 cell" })
    map("n", "<leader>ml", "<cmd>MoltenEvaluateLine<cr>", { desc = "Molten: 运行当前行" })
    map("v", "<leader>me", ":<C-u>MoltenEvaluateVisual<cr>gv", { desc = "Molten: 运行选区" })
    map("n", "<leader>mr", "<cmd>MoltenReevaluateCell<cr>", { desc = "Molten: 重跑该 cell" })
    -- 虚拟文本是画上去的、选不中，要复制输出就得进这个真 buffer（v/y 正常用）
    map("n", "<leader>mo", enter_output, { desc = "Molten: 进入输出窗口（可复制）" })
    map("n", "<leader>mh", "<cmd>MoltenHideOutput<cr>", { desc = "Molten: 隐藏输出" })
    map("n", "<leader>mc", "<cmd>MoltenInterrupt<cr>", { desc = "Molten: 中断执行（保留变量）" })
    map("n", "<leader>mR", "<cmd>MoltenRestart!<cr>", { desc = "Molten: 重启 kernel（清空变量）" })
    map("n", "<leader>md", "<cmd>MoltenDelete<cr>", { desc = "Molten: 删除该输出" })
    map("n", "<leader>ms", "<cmd>MoltenInfo<cr>", { desc = "Molten: kernel 状态" })

    -- cell 间跳转。LazyVim 的 ]/[ 系列没用 x。
    map("n", "]x", function()
      vim.fn.search("^# %%", "W")
    end, { desc = "下一个 cell" })
    map("n", "[x", function()
      vim.fn.search("^# %%", "bW")
    end, { desc = "上一个 cell" })

    -- Shift+Enter 走 kitty keyboard protocol（nvim 0.12 自动协商），
    -- 换个不支持的终端就只剩 <leader>mm，功能不丢。
    map("n", "<S-CR>", run_and_next, { desc = "Molten: 运行 cell 并下移" })

    -- 非 noautocmd 路径（比如 MoltenShowOutput 开的窗）走这条兜底
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "molten_output",
      callback = function(ev)
        set_output_keys(ev.buf)
      end,
    })

    -- ── cell 的视觉分隔 ────────────────────────────────────────────────────
    -- cell 不是语言特性，`# %%` 在 Python 眼里就是条普通注释 —— 是上面 run_cell 的
    -- search("^# %%") 赋予它意义的。默认它灰扑扑地混在代码里，看不出边界，所以这里
    -- 自己画两层：
    --   1) 标记行拉一条横线到行尾（`# %% 抓列表页` 就变成带标题的分隔线）
    --   2) 光标所在的那个 cell 在 signcolumn 用竖线标出来，相当于 Jupyter 的选中态
    -- 用 extmark 而不是 matchadd：extmark 挂在 buffer 上，换窗口/分屏都不用重设。
    local ns_mark = vim.api.nvim_create_namespace("molten_cell_marks")
    local ns_cur = vim.api.nvim_create_namespace("molten_cell_current")
    -- default = true：链接到主题已有的组，换 colorscheme 自动跟着走，也允许用户覆盖
    vim.api.nvim_set_hl(0, "MoltenCellBorder", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "MoltenCellCurrent", { link = "Function", default = true })

    -- lua pattern 里 % 是转义符，要匹配字面的 `# %%` 得写四个 %
    local CELL = "^# %%%%"

    local function draw_marks(buf)
      if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "python" then
        return
      end
      vim.api.nvim_buf_clear_namespace(buf, ns_mark, 0, -1)
      local width = vim.api.nvim_win_get_width(0)
      local found = false
      for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:match(CELL) then
          found = true
          -- 留 12 列余量给 number/sign/fold 列，算宽了也只是横线短一截，不会折行
          local pad = math.max(width - vim.fn.strdisplaywidth(line) - 12, 3)
          vim.api.nvim_buf_set_extmark(buf, ns_mark, i - 1, 0, {
            virt_text = { { " " .. string.rep("─", pad), "MoltenCellBorder" } },
            virt_text_pos = "eol",
            priority = 10,
          })
        end
      end
      -- 缓存给 draw_current 用：CursorMoved 是高频事件，不能每次都扫全文件
      vim.b[buf].molten_has_cells = found
    end

    local last = {}
    local function draw_current(buf)
      if not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].molten_has_cells then
        return
      end
      -- ★ 注意这里是 vim regex（search 用），不是上面那个 lua pattern：
      --   vim regex 里 % 不是特殊字符，写字面的 `^# %%` 就行，别套 CELL 常量
      local s = vim.fn.search("^# %%", "bcnW")
      s = (s == 0) and 1 or s
      local e = vim.fn.search("^# %%", "nW")
      e = (e == 0) and vim.fn.line("$") or e - 1
      -- 范围没变就别重画，否则每次光标移动都要清 + 设几十个 extmark
      if last.buf == buf and last.s == s and last.e == e then
        return
      end
      last = { buf = buf, s = s, e = e }
      vim.api.nvim_buf_clear_namespace(buf, ns_cur, 0, -1)
      for l = s, math.min(e, vim.api.nvim_buf_line_count(buf)) do
        vim.api.nvim_buf_set_extmark(buf, ns_cur, l - 1, 0, {
          sign_text = "▎",
          sign_hl_group = "MoltenCellCurrent",
          priority = 5, -- 低于 gitsigns，改动行让位给 git 标记
        })
      end
    end

    vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave", "WinResized" }, {
      pattern = "*.py",
      callback = function(ev)
        draw_marks(ev.buf)
        draw_current(ev.buf)
      end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      pattern = "*.py",
      callback = function(ev)
        draw_current(ev.buf)
      end,
    })
  end,
}
