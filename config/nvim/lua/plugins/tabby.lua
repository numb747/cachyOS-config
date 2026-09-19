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

    -- ★ term_cmd / term_prog / term_label 已搬到 lua/util/term.lua，这里改成 require。
    --   搬家理由正是本插件当初踩过的那条：「名字和图标走同一个 term_label()。最早是
    --   两条独立代码路径，出现过『魔杖图标 + zsh 名字』这种同一个 tab 两个信息源打架
    --   的情况」。现在 <leader>fb 的终端条目也要显示同一个值，再抄一份 /proc 解析
    --   就是把那个教训在更大范围里重演一次 —— 所以收敛成一份，两边都 require 它。
    --   /proc 读取、1 秒缓存、BufWipeout 清理全在那边，逻辑逐字保留。
    local term_label = function(buf)
      return require("util.term").term_label(buf)
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
