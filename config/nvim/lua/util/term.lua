-- 终端体验补丁。四块互相独立，哪块出问题都可以单独摘掉：
--   0. 认出终端里【真正在跑】的程序（与 plugins/tabby.lua 共用同一份实现）
--   1. 终端手动命名 —— <leader>fb 里一排 term://...:/usr/bin/zsh 只有 pid 不同
--   2. picker 选中的文件不落在当前终端窗口，跑去别的窗口打乱布局
--   3. 终端窗口被文件顶掉后 toggleterm 仍记着旧窗口，下次召回会把那个文件挤走
local M = {}

--------------------------------------------------------------------------------
-- 0. 终端里在跑什么
--------------------------------------------------------------------------------

-- ★ 这一段原本是 plugins/tabby.lua 里的局部函数，搬到这里做成单一来源。
--   搬的理由就写在 tabby 那次提交的说明里：「名字和图标走同一个 term_label()。
--   最早是两条独立代码路径，出现过『魔杖图标 + zsh 名字』这种同一个 tab 两个
--   信息源打架的情况」。顶栏和 buffer 列表要是各读各的 /proc，迟早重演同一个
--   形状的 bug —— 所以宁可让 tabby 反过来 require 这里。

-- 终端 buffer 名形如 term://{cwd}//{pid}:{cmd}，把 cmd 抠出来
---@param buf integer
---@return string|nil
function M.term_cmd(buf)
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
--     一开始对话就变成会话话题，拿它匹配 claude 三中一。
--   所以只能问内核：shell 进程的子进程是谁。这个与对话状态无关，稳定。
--
-- 顺带把 lazygit/btop 这类也认出来了，不再一律显示 zsh。
local prog_cache = {}

---@param buf integer
---@return string|nil
function M.term_prog(buf)
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

---终端的显示名：正在跑的程序 > 启动命令 > 兜底
---@param buf integer
---@return string
function M.term_label(buf)
  return M.term_prog(buf) or M.term_cmd(buf) or "term"
end

--------------------------------------------------------------------------------
-- 1. 手动命名
--------------------------------------------------------------------------------

-- ★ 这里【���有自动命名】，是砍掉的，不是漏了。
--   原先在 TermOpen 时生成 "zsh:目录#序号" 烤进 buffer 名，两个问题：
--   ① 那一刻 shell 刚起来、还没有子进程，term_prog() 只能得到 "zsh" ——
--      正是 tabby 那次提交认定「没有信息量」的名字，烤死了就永远是它；
--   ② 每次改名 nvim_buf_set_name 都会留下一个孤儿 buffer，开机就白改一次。
--   现在没起名的终端在 picker 里直接走 term_label() 动态算，跑 claude 就显示
--   claude，跟顶栏同步变化。只有你【主动起名】时才真的改 buffer 名。

-- toggleterm 靠 buffer 名字末尾的数字认终端（toggleterm/terminal.lua 的 identify()）：
--   term://~/proj//12345:/usr/bin/zsh;#toggleterm#7   ->   7
-- 实现是 vim.split(name, sep) 之后对最后一段 tonumber()，所以标签只能插在
-- ";#toggleterm#N" 之前。追加到末尾会让 tonumber("7 [编译]") 得到 nil，
-- 之后 :ToggleTerm 7、toggle、关闭全部失效 —— 这个坑实测过。
local SUFFIX_PATTERNS = {
  "^(.-)(;?#toggleterm#%d+)$",
  "^(.-)(::toggleterm::%d+)$",
}

---把终端 buffer 名拆成「可改写的前缀」和「不能碰的 toggleterm 后缀」
---@param name string
---@return string base, string suffix
function M.split_name(name)
  for _, pat in ipairs(SUFFIX_PATTERNS) do
    local base, suffix = name:match(pat)
    if base then
      return base, suffix
    end
  end
  return name, "" -- 原生 :terminal 没有后缀，整段都可以改
end

-- 首次改名前把原始名字存进 buffer 变量，之后每次都从它重建。
-- 否则改名两次会套娃成 "... [a] [b]"。
local function pristine(buf)
  local saved = vim.b[buf].term_ux_base
  if saved then
    return saved, vim.b[buf].term_ux_suffix or ""
  end
  local base, suffix = M.split_name(vim.api.nvim_buf_get_name(buf))
  vim.b[buf].term_ux_base = base
  vim.b[buf].term_ux_suffix = suffix
  return base, suffix
end

---某个标签是否已被别的终端占用
---@param label string
---@param except_buf integer
---@return boolean
local function label_taken(label, except_buf)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= except_buf and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "terminal" then
      if vim.b[b].term_ux_label == label then
        return true
      end
    end
  end
  return false
end

---找出某个 buffer 对应的 toggleterm 终端实例（不是 toggleterm 开的就返回 nil）
---@param buf integer
---@return table|nil
function M.find_term(buf)
  local ok, terms = pcall(require, "toggleterm.terminal")
  if not ok then
    return nil
  end
  for _, term in pairs(terms.get_all(true)) do
    if term.bufnr == buf then
      return term
    end
  end
  return nil
end

---给终端 buffer 打标签（label 为空则还原成原始名字，回到动态显示）
---@param buf integer
---@param label string
---@return boolean ok
function M.set_label(buf, label)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then
    return false
  end
  local base, suffix = pristine(buf)

  -- 重名消歧必须盯着「标签」，不能靠 nvim_buf_set_name 报 E95 来兜：buffer 名里
  -- 带 pid（term:///tmp//4276:/usr/bin/zsh），两个终端的全名永远撞不上，靠 E95
  -- 的写法是死代码。真正会撞的是标签本身，而 format_buffer 只显示标签 ——
  -- 撞了就是 picker 里两行一模一样，还没有 bufnr 可区分。
  if label ~= "" then
    local wanted = label
    for n = 2, 99 do
      if not label_taken(label, buf) then
        break
      end
      label = wanted .. "(" .. n .. ")"
    end
  end

  local old_name = vim.api.nvim_buf_get_name(buf)
  local new_name = label ~= "" and (base .. " [" .. label .. "]" .. suffix) or (base .. suffix)
  if not pcall(vim.api.nvim_buf_set_name, buf, new_name) then
    return false
  end

  -- nvim_buf_set_name 内部走 rename_buffer，会把旧名字留成一个未列出的空 buffer。
  -- 每改一次名泄漏一个。它们是 unlisted 所以现在看不见，但一旦把 buffers picker
  -- 的 hidden 打开就全冒出来了。顺手清掉。
  if old_name ~= "" and old_name ~= new_name then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= buf and vim.api.nvim_buf_get_name(b) == old_name and not vim.api.nvim_buf_is_loaded(b) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
  end

  vim.b[buf].term_ux_label = label ~= "" and label or nil
  -- toggleterm 的浮窗标题和 <leader>tl 读的是 display_name，一并同步，别让两处名字打架
  local term = M.find_term(buf)
  if term then
    term.display_name = label ~= "" and label or nil
    -- 标题是 nvim_open_win 那一刻烤进 win config 的，改 display_name 不会自动生效。
    -- 浮窗正开着时要显式刷一次，否则边框标题一直停在旧名字上。
    if
      term.window
      and vim.api.nvim_win_is_valid(term.window)
      and vim.api.nvim_win_get_config(term.window).relative ~= ""
    then
      pcall(function()
        require("toggleterm.ui").update_float(term)
      end)
    end
  end
  return true
end

---交互式重命名当前终端
function M.rename()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then
    vim.notify("当前 buffer 不是终端", vim.log.levels.WARN)
    return
  end
  -- 只预填你自己起过的名字（方便小改）。没起过就是空的，直接打字 ——
  -- 动态名是算出来的、不是占位符，没有「先删掉再输入」这一步。
  local default = vim.b[buf].term_ux_label or ""
  vim.ui.input({ prompt = "终端名称: ", default = default }, function(name)
    if name == nil then
      return -- 用户取消
    end
    if M.set_label(buf, name) then
      vim.notify(
        name ~= "" and ("终端已重命名为: " .. name) or ("已清除自定义名，恢复动态显示: " .. M.term_label(buf)),
        vim.log.levels.INFO
      )
    else
      vim.notify("重命名失败", vim.log.levels.ERROR)
    end
  end)
end

--------------------------------------------------------------------------------
-- 2. picker 里终端只显示名字
--------------------------------------------------------------------------------

-- snacks 默认的 buffer 格式化器（snacks/picker/format.lua 的 M.buffer）会拼出
--   %a   term:/…/usr/bin/zsh [编译]:1  [terminal]
-- bufnr、flags、完整路径、[terminal] 全在里面。终端的路径没有信息量，
-- 我们只想看名字。非终端条目原样交回默认实现，不动文件的显示。
---@param item table
---@param picker table
---@return table
function M.format_buffer(item, picker)
  if item.buftype ~= "terminal" then
    return Snacks.picker.format.buffer(item, picker)
  end
  local buf = item.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return { { " ", "Special", virtual = true }, { "term", "SnacksPickerFile" } }
  end
  -- 自定义名优先；没起过名就动态算，和顶栏显示同一个值
  local label = vim.b[buf].term_ux_label
  if not label or label == "" then
    label = M.term_label(buf)
  end
  return {
    { " ", "Special", virtual = true },
    { label, "SnacksPickerFile" },
  }
end

--------------------------------------------------------------------------------
-- 3. 让 picker 认得终端窗口
--------------------------------------------------------------------------------

-- snacks picker 的 main window 解析（snacks/picker/core/main.lua 的 find()）默认
-- 带 file=true，会把所有 buftype ~= "" 的窗口排除掉，终端窗口永远选不上，
-- 于是文件被扔进别的窗口、布局被打乱。
--
-- 不用全局 main={file=false}：那是把 buftype 过滤整个摘掉，quickfix / help /
-- trouble 也会一起变成候选，副作用太大。改用窗口局部变量 snacks_main —— 它在
-- 过滤器里提前 return true，只对打了标的窗口生效。
--
-- 浮动终端排除掉，但**不是**因为 bufhidden=wipe —— 那是我一开始的误判。
-- toggleterm/ui.lua 的 open_float 走 nvim_create_buf(false, false)，从不设 bufhidden；
-- 那句 bufhidden="wipe" 在 open_tab 里，管的是 `tabedit new` 造出的空临时 buffer。
-- 实测浮动终端被文件覆盖后 buffer 和 shell 进程都活着。
-- 真正的理由是：toggleterm 在 WinLeave 上自动关浮窗，它根本不是你布局的一部分，
-- 把文件 edit 进一个随时会消失的覆盖层没有意义。
function M.refresh_main_marks()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
      local want = vim.bo[buf].buftype == "terminal" and not is_float
      if want then
        vim.w[win].snacks_main = true
        vim.w[win].term_ux_marked = true
      elseif vim.w[win].term_ux_marked then
        -- 只清自己打的标，别动别人设的 snacks_main
        pcall(function()
          vim.w[win].snacks_main = nil
          vim.w[win].term_ux_marked = nil
        end)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- 4. 清掉 toggleterm 的陈旧窗口引用
--------------------------------------------------------------------------------

-- toggleterm 把 self.window 记在终端实例里。窗口被别的 buffer 占走之后这个引用
-- 不会更新，下次 toggle 召回时它既抢回旧窗口、又新开一个 —— 终端同时占两个窗口，
-- 而你刚打开的文件被挤没了。实测过，正是第 3 条想保住的布局又被打乱。
---@param buf integer 终端 buffer
---@param wins integer[] 它离开前所在的那些窗口
function M.clear_stale_window(buf, wins)
  local term = M.find_term(buf)
  if not term then
    return
  end
  for _, win in ipairs(wins) do
    -- 窗口整个关掉了(invalid)就不管：那是正常的 toggle close，交给 toggleterm 自己处理。
    -- 只在窗口还在、但已经换了别的 buffer 时才算「被顶掉」。
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) ~= buf and term.window == win then
      term.window = nil
    end
  end
end

--------------------------------------------------------------------------------

function M.setup()
  local group = vim.api.nvim_create_augroup("term_ux", { clear = true })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    desc = "终端重命名快捷键",
    callback = function(args)
      -- <C-r> 重命名。绑在这里(pattern="*")而不是 toggleterm 的 config 里，
      -- 后者 pattern 是 term://*toggleterm#* ，原生 :terminal 匹配不到。
      -- 代价是终端模式下 zsh 的反向历史搜索(Ctrl+R)会被 nvim 截走 —— 用户确认不用。
      -- 想要回来：把下面 mode 里的 "t" 去掉，<leader>tn 仍可用。
      vim.keymap.set({ "t", "n" }, "<C-r>", function()
        vim.cmd("stopinsert")
        vim.schedule(M.rename)
      end, { buffer = args.buf, silent = true, desc = "命名终端" })

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          M.refresh_main_marks()
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "WinClosed", "TermClose" }, {
    group = group,
    desc = "标记终端窗口供 picker 使用",
    callback = function()
      vim.schedule(M.refresh_main_marks)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    desc = "终端被顶出窗口时清掉 toggleterm 的陈旧引用",
    callback = function(args)
      if vim.bo[args.buf].buftype ~= "terminal" then
        return
      end
      -- 不能用 nvim_get_current_win()：BufWinLeave 说的是「buffer 要离开某个窗口」，
      -- 那个窗口未必是当前窗口 —— 别的插件用 nvim_win_set_buf(其它窗口, buf) 顶掉
      -- 终端时根本不切焦点，取到的就是错的句柄，该清的陈旧引用反而漏了。
      -- 取此刻所有显示该 buffer 的窗口，稍后再看谁真的换了内容。
      local wins = vim.fn.win_findbuf(args.buf)
      vim.schedule(function()
        M.clear_stale_window(args.buf, wins)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    desc = "清理 term_prog 缓存",
    callback = function(a)
      prog_cache[a.buf] = nil
    end,
  })
end

return M
