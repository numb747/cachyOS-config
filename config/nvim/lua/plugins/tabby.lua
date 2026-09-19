-- tabby：给 tab 起名字 + 重画顶栏。
--
-- 为什么要这个：三个 tab 里有两个是终端（Claude Code / 常驻 shell），
-- 原生 tabline 会把它们都显示成 term://~/xxx//12345:zsh，肉眼分不出谁是谁。
--
-- 风格对齐：分隔符用圆头 \u{e0b6}/\u{e0b4}，和 lualine.lua 的 bubbles 保持一致；
-- 配色全部走高亮组名（不写死颜色），所以 tokyonight 的 transparent
-- 和以后换 flavour 都会自动跟上。
--
-- ★ 图标一律写成 \u{xxxx} 转义，不写字面字符 —— 字面 Nerd Font 字形
--   在编辑/传输环节会被静默吃掉（本文件第一版就是这么变成空格的，
--   现象是顶栏只剩文字、当前 tab 是直角方块，看着像缺字体其实不是）。
--   改图标前先确认码位在 kitty 的 symbol_map 范围内（~/.config/kitty/kitty.conf
--   第 17 行），否则会落到没有该字形的 fallback 字体上，那才是真的方块。
-- Claude Code 的图标。换之前先确认候选在 kitty symbol_map 范围内（见文件末注释），
-- 这几个都验过可用：
--   \u{f0ae2} md-star_four_points（四角星，最接近 Claude logo）
--   \u{f0674} md-creation（三点星芒）      \u{f06a9} md-robot（实心机器人）
--   \u{f167a} md-robot_outline（线框机器人）\u{f09d1} md-brain（大脑）
--   \u{f085f} md-comment_multiple（对话气泡）
local ICON_CLAUDE = "\u{f1844}" -- md-magic_staff：魔杖
local ICON_TERM = "\u{f489}" -- 终端
local ICON_FILE = "\u{f15b}" -- 通用文件（mini.icons 认不出时兜底）
local SEP_L = "\u{e0b6}" -- 圆头左
local SEP_R = "\u{e0b4}" -- 圆头右
local GAP = "  " -- tab 之间的留白，嫌挤/嫌散改这一个值

return {
  "nanozuki/tabby.nvim",
  event = "VeryLazy",
  keys = {
    -- 不带 <cr>，停在命令行等你输入名字
    { "<leader><tab>r", ":Tabby rename_tab ", desc = "Rename Tab" },
  },
  config = function()
    local theme = {
      -- transparent = true 时 TabLineFill 的 bg 是 none，顶栏透出壁纸
      fill = "TabLineFill",
      -- fg=black bg=blue，没被 transparent 影响，圆头是实心的
      current = "TabLineSel",
      -- 注意：不能用 TabLine，它的 fg 是 fg_gutter，在透明背景上几乎看不见
      inactive = "Comment",
    }

    -- 取某个 tab 当前窗口的 buffer
    local function tab_buf(tabid)
      local ok, win = pcall(vim.api.nvim_tabpage_get_win, tabid)
      if not ok then
        return nil
      end
      local ok2, buf = pcall(vim.api.nvim_win_get_buf, win)
      return ok2 and buf or nil
    end

    -- 终端 buffer 名形如 term://{cwd}//{pid}:{cmd}，把 cmd 抠出来
    local function term_cmd(buf)
      local cmd = vim.api.nvim_buf_get_name(buf):match("term://.-//%d+:(.*)$")
      if not cmd then
        return nil
      end
      return vim.fn.fnamemodify(cmd:match("^(%S+)") or cmd, ":t")
    end

    -- 终端里【真正在跑】的程序名。
    --
    -- ★ 为什么不用别的两个更省事的信号：
    --   · buffer 名 —— 记的是启动命令。先开 shell 再敲 claude 时永远是 /usr/bin/zsh。
    --   · b:term_title —— Claude Code 只在【新会话】时是「✳ Claude Code」，
    --     一开始对话就变成会话话题（实测三个实例分别是「✳ Claude Code」
    --     「✳ 院感模块的…」「◑ LazyVim 中 tab 重命名」），拿它匹配 claude 三中一。
    --   所以只能问内核：shell 进程的子进程是谁。这个与对话状态无关，稳定。
    --
    -- 顺带把 lazygit/btop 这类也认出来了，不再一律显示 zsh。
    local prog_cache = {}
    local function term_prog(buf)
      local pid = vim.b[buf].terminal_job_pid
      if not pid then
        return nil
      end
      -- tabline 重绘很频繁（终端有输出就重绘），缓存 1 秒，别每次都读 /proc
      local now = vim.uv.now()
      local c = prog_cache[buf]
      if c and now - c.t < 1000 then
        return c.prog
      end
      local function comm_of(p)
        local cf = io.open(("/proc/%s/comm"):format(p), "r")
        if not cf then
          return nil
        end
        local s = (cf:read("*l") or ""):gsub("%s+$", "")
        cf:close()
        return s ~= "" and s or nil
      end

      local prog = nil
      -- 先看子进程：交互 shell 里敲 claude 属于这种（最常见）
      local f = io.open(("/proc/%d/task/%d/children"):format(pid, pid), "r")
      if f then
        local line = f:read("*l") or ""
        f:close()
        for cpid in line:gmatch("%d+") do
          prog = comm_of(cpid)
          if prog then
            break
          end
        end
      end
      -- 没有子进程就看 job 进程自己：终端直接以某程序启动（不经过 shell）属于这种，
      -- 此时那个程序【就是】job 进程。闲着的交互 shell 也走这条，得到 "zsh"，正确。
      prog = prog or comm_of(pid)
      prog_cache[buf] = { t = now, prog = prog }
      return prog
    end
    vim.api.nvim_create_autocmd("BufWipeout", {
      callback = function(a)
        prog_cache[a.buf] = nil
      end,
    })

    -- 终端 tab 显示什么名字：正在跑的程序 > 启动命令 > 兜底
    local function term_label(buf)
      return term_prog(buf) or term_cmd(buf) or "term"
    end

    local function tab_icon(tabid)
      local buf = tab_buf(tabid)
      if not buf then
        return ICON_FILE
      end
      if vim.bo[buf].buftype == "terminal" then
        -- 和名字走同一个函数，两者不会打架
        return term_label(buf):find("claude") and ICON_CLAUDE or ICON_TERM
      end
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        local ok, icons = pcall(require, "mini.icons")
        if ok then
          local icon = icons.get("file", vim.fn.fnamemodify(name, ":t"))
          if icon and icon ~= "" then
            return icon
          end
        end
      end
      return ICON_FILE
    end

    require("tabby").setup({
      line = function(line)
        return {
          -- 两端各一个 spacer = tab 居中。想左对齐就删掉下面这行
          line.spacer(),
          line.tabs().foreach(function(tab)
            -- ★ 图标和名字必须拼成【一个】节点。tabby 的 margin 是插在子节点
            --   【之间】的，不是给整组加外边距：写成多个节点会被 margin 撑开
            --   （图标和文字隔老远），而组与组之间反倒没有间隔（相邻 tab 贴住）。
            --   所以这里不用 margin，间距全部自己写。
            local label = tab_icon(tab.id) .. " " .. tab.name()
            if tab.is_current() then
              return {
                { GAP, hl = theme.fill }, -- 药丸外侧留白，要用 fill 才透明
                line.sep(SEP_L, theme.current, theme.fill),
                { " " .. label .. " ", hl = theme.current }, -- 药丸内侧留白
                line.sep(SEP_R, theme.current, theme.fill),
                { GAP, hl = theme.fill },
              }
            end
            -- 非当前 tab 不给背景块，顶栏才留得住空。
            -- 多一个空格是为了补上当前 tab 那两个圆头占的宽度，让间距看着齐。
            return { GAP .. " " .. label .. " " .. GAP, hl = theme.inactive }
          end),
          line.spacer(),
          hl = theme.fill,
        }
      end,
      option = {
        tab_name = {
          -- 没 rename 过的 tab 显示什么：终端显示【正在跑的程序】，其余显示文件名。
          -- 用的是和图标同一个 term_label()，所以跑 claude 时名字和图标一起变。
          name_fallback = function(tabid)
            local buf = tab_buf(tabid)
            if not buf then
              return "[tab]"
            end
            if vim.bo[buf].buftype == "terminal" then
              return term_label(buf)
            end
            local name = vim.api.nvim_buf_get_name(buf)
            return name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":t")
          end,
        },
      },
    })

    -- 只有一个 tab 时自动隐藏顶栏
    vim.o.showtabline = 1
  end,
}
