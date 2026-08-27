-- ============================================================================
--  mykeys.lua —— 个人 Hyprland 配置（快捷键 + 鼠标行为）
-- ----------------------------------------------------------------------------
--  安装（真机装完 CachyOS 后，两步）：
--    1. 把本文件拷到  ~/.config/hypr/mykeys.lua
--    2. 在  ~/.config/hypr/hyprland.lua  末尾追加一行：
--           require("mykeys")
--    然后  hyprctl reload
--
--  官方的 config/*.lua 一行都不用动，pacman 升级 cachyos-hypr-noctalia 不冲突。
--
--  原理备忘：hl.bind 对同一键位是「叠加」不是「覆盖」，所以要替换官方键位
--  必须先 hl.unbind("键位字符串")。unbind 不存在的键位不会报错，幂等安全。
--  适用：Hyprland >= 0.56（Lua 配置）+ cachyos-hypr-noctalia
-- ============================================================================


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  开关                                                                     │
-- └──────────────────────────────────────────────────────────────────────────┘

--  全屏／最大化状态下按 CTRL+ALT+HJKL 切窗口时的行为：
--    true  → 切过去的新窗口继续保持同样的全屏级别（「轮播」感，推荐）
--    false → 退出全屏，回到平铺视图，焦点落在目标窗口上
local KEEP_FULLSCREEN_ON_FOCUS = true

--  ALT+SHIFT+S 把窗口丢进抽屉架时（见第 10 节）：
--    true  → 静默送走，窗口原地消失，抽屉架不弹出 —— 「藏起来」的语义
--    false → 送完把那一格拉出来显示，跟着窗口一起过去（本配置 2026-08 之前的旧行为）
--  实现上对应 window.move 的 follow 参数，注意不叫 silent —— 见第 10 节约束 3。
local STASH_SILENTLY = true


-- ────────────────────────────────────────────────────────────────────────────
--  1. 摘掉被替换的官方绑定
--     （不想丢弃 SUPER+方向键作为备用手感，把这四行注释掉即可）
-- ────────────────────────────────────────────────────────────────────────────
hl.unbind("SUPER + Left")
hl.unbind("SUPER + Right")
hl.unbind("SUPER + Up")
hl.unbind("SUPER + Down")

-- 抽屉（special workspace）改用 ALT，见第 10 节。
-- hl.bind 对同一键位是叠加不是覆盖，不 unbind 的话 SUPER + S 会同时留着。
hl.unbind("SUPER + S")
hl.unbind("SUPER + SHIFT + S")

-- 应用启动器改用 ALT + Space，见第 12 节。
-- 注意只摘 SUPER + Space，官方的 SUPER + ALT + Space（切浮动）是另一个键位，
-- 修饰键掩码不同，不受影响。
hl.unbind("SUPER + Space")


-- ────────────────────────────────────────────────────────────────────────────
--  1b. 双平面骨架 —— 让后面的导航键「知道自己在哪个平面」
--
--      本配置有两套平面：
--        ▸ 工作平面 —— 普通工作区（正数 id），正事在这儿
--        ▸ 抽屉架   —— 一组命名 special workspace（special:rack1/rack2/…），
--                      另一批程序住这儿，整体可以一键收起。详见第 10 节。
--
--      设计选择：不新增任何键位，而是把已有的导航键做成【模态】—— 同一个键
--      在两个平面里含义不同（ALT+] 在工作平面是切桌面，在抽屉架里是切抽屉格）。
--      这是本文件里唯一的模态，能接受是因为抽屉架浮出来是【满屏】的
--      （dwindle.special_scale_factor 默认 1.0），「我在哪个平面」一眼可见，
--      不存在传统 modal 那种「忘了自己在什么模式」的问题。
--
--      ⚠ 前向声明：抽屉架引擎（rack.*）在第 10 节才定义，但第 4/4c/7 节的绑定
--        需要引用它。Lua 闭包捕获的是【变量】不是【值】，rack 这张表的地址在
--        这里就定下来了，第 10 节往里填方法即可 —— 填的时机（配置加载时）
--        远早于任何一次按键，所以安全。反过来写成 local function 就不行了。
-- ────────────────────────────────────────────────────────────────────────────
local rack = {}

--  把「工作平面的行为」和「抽屉架里的行为」打包成一个键。
--    work    —— 工作平面的行为，可以是 dispatcher 对象也可以是函数
--                （实测预先构造的 dispatcher 可以延后 hl.dispatch，不必每次重建）
--    in_rack —— 抽屉架里的行为，收到当前格号
local function two_planes(work, in_rack)
    return function()
        local slot = rack.current_slot()
        if slot then return in_rack(slot) end
        if type(work) == "function" then work() else hl.dispatch(work) end
    end
end


-- ────────────────────────────────────────────────────────────────────────────
--  2. 窗口焦点切换：CTRL + ALT + H / J / K / L
--
--     普通平铺状态下就是朴素的方向切焦点。
--
--     全屏／最大化状态下，Hyprland 原生的 movefocus 方向感会失灵（整块屏幕
--     只有一个窗口，"左边"无从谈起）。这里先把全屏摘掉、让方向判断落在真实
--     的平铺布局上，切完再把同样的全屏级别还给新的活动窗口 —— 于是方向和
--     模式都保住了。
--
--     w.fullscreen 的取值：0 = 普通  1 = 最大化(SUPER+D)  2 = 真全屏(SUPER+F)
--     用 fullscreen_state{internal=,client=} 而不是 fullscreen{mode=}，因为
--     前者是幂等赋值、后者是 toggle（且两者编号不一致，toggle 容易写反）。
--
--     原生替代方案：hl.config({ binds = { movefocus_cycles_fullscreen = true } })
--     一行就能在全屏下切窗口，但它是「循环」不是「方向」——H 和 L 会变成
--     上一个/下一个，空间方向感丢失。所以这里没用它。
-- ────────────────────────────────────────────────────────────────────────────
local function focus_dir(dir)
    return function()
        local w  = hl.get_active_window()
        local fs = (w and w.fullscreen) or 0

        if fs == 0 then
            hl.dispatch(hl.dsp.focus({ direction = dir }))
            return
        end

        -- 摘掉全屏 → 在真实布局上按方向切 → 还原全屏级别
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0 }))
        hl.dispatch(hl.dsp.focus({ direction = dir }))

        if KEEP_FULLSCREEN_ON_FOCUS then
            hl.dispatch(hl.dsp.window.fullscreen_state({ internal = fs, client = fs }))
        end
    end
end

hl.bind("CONTROL + ALT + H", focus_dir("left"))
hl.bind("CONTROL + ALT + J", focus_dir("down"))
hl.bind("CONTROL + ALT + K", focus_dir("up"))
hl.bind("CONTROL + ALT + L", focus_dir("right"))

-- 配套：按住 SHIFT 把窗口本身挪过去（同一套手指记忆）
hl.bind("CONTROL + ALT + SHIFT + H", hl.dsp.window.move({ direction = "l" }))
hl.bind("CONTROL + ALT + SHIFT + J", hl.dsp.window.move({ direction = "d" }))
hl.bind("CONTROL + ALT + SHIFT + K", hl.dsp.window.move({ direction = "u" }))
hl.bind("CONTROL + ALT + SHIFT + L", hl.dsp.window.move({ direction = "r" }))


-- ────────────────────────────────────────────────────────────────────────────
--  3. 全屏：ALT + Enter
--     ALT+Enter       → 真全屏，盖住状态栏、无间距（＝官方 SUPER+F 的效果）
--     ALT+SHIFT+Enter → 最大化，保留 noctalia 状态栏（＝官方 SUPER+D 的效果）
--     官方的 SUPER+D / SUPER+F 保留不动，作为并存的第二套入口。
-- ────────────────────────────────────────────────────────────────────────────
hl.bind("ALT + Return",         hl.dsp.window.fullscreen())
hl.bind("ALT + SHIFT + Return", hl.dsp.window.fullscreen({ mode = 1 }))


-- ────────────────────────────────────────────────────────────────────────────
--  4. 工作区（桌面）左右切换：ALT + [ / ]
--     m-1 / m+1 是「本显示器内相对」，与 noctalia 官方风格一致。
--     注意 config/variables.lua 里 NUM_WPM = 3，默认只有三个工作区。
--
--     ★ 模态（见第 1b 节）：人在抽屉架里时这四个键切的是【抽屉格】，不是工作桌面。
--       抽屉格之间是【回绕】的（工作桌面不回绕）—— 因为抽屉架常态只有两格，
--       回绕让 ALT+] 直接变成两格来回切，比走到头就卡住好用。
-- ────────────────────────────────────────────────────────────────────────────
hl.bind("ALT + bracketleft",
        two_planes(hl.dsp.focus({ workspace = "m-1" }), function() rack.step(-1) end))
hl.bind("ALT + bracketright",
        two_planes(hl.dsp.focus({ workspace = "m+1" }), function() rack.step(1) end))

-- 配套：带着当前窗口一起跳过去
hl.bind("ALT + SHIFT + bracketleft",
        two_planes(hl.dsp.window.move({ workspace = "m-1" }), function() rack.carry(-1) end))
hl.bind("ALT + SHIFT + bracketright",
        two_planes(hl.dsp.window.move({ workspace = "m+1" }), function() rack.carry(1) end))


--  4b. 单手切屏：CTRL + 2 / 3 ＝ ALT + [ / ]
--
--      [ 和 ] 在右手区、CTRL 在左下角，切屏得两只手。CTRL + 2/3 全在左手：
--      小指压 CTRL，食指/中指够 2 和 3，右手可以一直放在鼠标上。
--      两套并存，不摘 ALT + [ / ]，看当时哪只手空着就用哪套。
--
--      为什么是 2 和 3 而不是 1 和 2：数字键相邻即可，选哪一对纯看手型；
--      2/3 让食指落在 home row 正上方，1 要伸小指。
--
--      ⚠ 和第 8 节 CTRL+W 是同一类代价：合成器的全局 bind 直接截获按键，
--        应用一点收不到。被占掉的两个用途：
--            浏览器（Chrome 系）→ 切到第 2 / 第 3 个标签页
--            VS Code / Zed      → 聚焦第 2 / 第 3 个编辑器分栏
--        kitty 的切标签是 CTRL+SHIFT+数字，不受影响。
--        官方 config/binds.lua 里没有裸 CTRL+数字（只有 SUPER+CTRL+数字 =
--        第 N 个存在的工作区），所以不必 unbind。
--
--      真被浏览器标签页咬到了，就把下面两行改成 CONTROL + ALT + 2/3 ——
--      多一个修饰键、零冲突，仍然是纯左手（小指 CTRL、拇指 ALT）。
-- 与 ALT + [ / ] 完全同义，包括第 4 节说的模态（抽屉架里切的是抽屉格）。
hl.bind("CONTROL + 2",
        two_planes(hl.dsp.focus({ workspace = "m-1" }), function() rack.step(-1) end))
hl.bind("CONTROL + 3",
        two_planes(hl.dsp.focus({ workspace = "m+1" }), function() rack.step(1) end))

-- 配套的「带窗口一起走」（CTRL+SHIFT+数字 在终端里会被解析成控制字符，
-- 且已被官方占作 SUPER+SHIFT+CTRL 的一部分手感，故默认不开）：
-- hl.bind("CONTROL + SHIFT + 2", hl.dsp.window.move({ workspace = "m-1" }))
-- hl.bind("CONTROL + SHIFT + 3", hl.dsp.window.move({ workspace = "m+1" }))


--  4c. 跳到头 / 跳到尾：CTRL + 1 / 4
--
--      和 4b 同一只左手：1 2 3 4 排成一行，两端是「直接到头/到尾」，
--      中间两个是「往左/往右挪一格」。四个键一组，语义连续。
--
--      ⚠ 不能写成绝对编号 1 和 4。本配置是纯动态工作区（见第 7 节）：
--        工作区随开随关，编号会留洞——剩 1、3、7 是常态。写死 4 会跳到一个
--        不存在的位置，凭空造出一个新工作区来。
--        所以这里实时扫一遍现存工作区取 min / max id。
--
--      为什么不用官方的 m~N token（＝本显示器上第 N 个已存在的工作区）：
--        m~1 确实等于「第一个」，但「最后一个」需要先知道总数，还是得扫一遍，
--        不如两边统一用 id，读起来对称。
--
--      过滤条件说明：
--        w.id > 0     —— hl.get_workspaces() 【会】返回 special 工作区，它们的 id
--                        是负数（-99 起）。不加这条的话 min 永远是抽屉格，CTRL+1
--                        会一头扎进抽屉架 —— 这条正是「两个平面互不干扰」的保证。
--                        （第 7 节只取 max，负数永远当不上 max，所以那里不需要。）
--        同显示器     —— 与 4b 的 m-1/m+1「本显示器内相对」保持一致语义。
--                        单屏时这条不起作用，接副屏才有区别。
--
--      占用代价同 4b：浏览器的「切到第 1 / 第 4 个标签页」会被合成器吃掉。
--      Chrome 系的 CTRL+1 尤其常用，介意的话改成 CONTROL + ALT + 1/4。
local function edge_ws(want_max)
    local mon  = hl.get_active_monitor()
    local best = nil
    for _, w in ipairs(hl.get_workspaces()) do
        local same_mon = (mon == nil) or (w.monitor == nil) or (w.monitor.name == mon.name)
        if w.id > 0 and not w.special and same_mon then
            if best == nil
                or (want_max and w.id > best)
                or (not want_max and w.id < best) then
                best = w.id
            end
        end
    end
    return tostring(best or 1)   -- best 为 nil 只可能发生在没有任何普通工作区时
end

-- 模态同第 4 节：抽屉架里跳的是第一格 / 最后一格。
hl.bind("CONTROL + 1", two_planes(
        function() hl.dispatch(hl.dsp.focus({ workspace = edge_ws(false) })) end,
        function() rack.edge(false) end))
hl.bind("CONTROL + 4", two_planes(
        function() hl.dispatch(hl.dsp.focus({ workspace = edge_ws(true) })) end,
        function() rack.edge(true) end))

-- 配套的「带着当前窗口跳到头/尾」，同 4b 的理由默认不开：
-- hl.bind("CONTROL + SHIFT + 1", function() hl.dispatch(hl.dsp.window.move({ workspace = edge_ws(false) })) end)
-- hl.bind("CONTROL + SHIFT + 4", function() hl.dispatch(hl.dsp.window.move({ workspace = edge_ws(true)  })) end)


-- ────────────────────────────────────────────────────────────────────────────
--  5. 分屏终端：ALT + \ 下方开一个 ／ CTRL + ALT + \ 右侧开一个
--
--     一个键直接在指定方向开出一个新终端 —— Windows Terminal 的 Alt+Shift+-
--     / tmux 的 split-window 那种手感。
--
--     原理两步：先用 dwindle 的 preselect 预选「下一个新窗口开在哪一边」，
--     紧接着把终端拉起来，于是它正好落进预选好的位置。preselect 是一次性的，
--     被这个新窗口消费掉后自动失效。
--
--     ⚠ 平铺布局没有「把当前窗口劈成两半」这个动作——窗口数量决定分几块，
--     所以「分屏」在这里只能表现为「往指定方向开一个新窗口」。
--
--     想要纯预选（预选完自己手动开任意程序，不限终端）：把函数里 exec_cmd
--     那一行删掉即可。
--     ALT+SHIFT+\ 是另一回事：把已经存在的两个窗口在上下／左右之间翻转。
-- ────────────────────────────────────────────────────────────────────────────
local launchPrefix = "uwsm app -- "   -- 与官方 binds.lua 保持一致；不用 UWSM 就改成 ""

local function split_term(dir)
    return function()
        hl.dispatch(hl.dsp.layout("preselect " .. dir))
        hl.dispatch(hl.dsp.exec_cmd(launchPrefix .. (TERMINAL or "kitty")))
    end
end

hl.bind("ALT + backslash",           split_term("d"))
hl.bind("CONTROL + ALT + backslash", split_term("r"))
hl.bind("ALT + SHIFT + backslash",   hl.dsp.layout("togglesplit"))


-- ────────────────────────────────────────────────────────────────────────────
--  6. 鼠标行为：打字时自动隐藏光标，一动鼠标就回来
--     （KDE「输入时隐藏光标」/ Windows「键入时隐藏指针」的等价物）
--
--     hide_on_key_press —— 按下任意键即隐藏光标，直到鼠标移动才重新出现。
--     Hyprland 原生支持，不需要 unclutter / xbanish 之类的外部守护进程。
--
--     官方 config/*.lua 没有配置任何 cursor 选项（binds.lua 里只用了
--     zoom_factor 做缩放），所以这里不会冲突。
-- ────────────────────────────────────────────────────────────────────────────
hl.config({
    cursor = {
        hide_on_key_press = true,

        -- 焦点切换时不要把鼠标指针瞬移(warp)到新窗口上。
        -- Hyprland 默认会 warp，而 hide_on_key_press 的「重新显形」条件正是
        -- 「指针发生移动」——于是每次切窗口光标都会闪一下再隐藏。
        -- 上面第 2 节的 focus_dir 每按一次连发三个 dispatch，闪烁被放大三倍。
        -- 关掉 warp 后指针原地不动，闪烁消失。
        no_warps = true,

        -- 可选：静止 N 秒后也自动隐藏（0 = 关闭）。想要「看视频时光标自己消失」
        -- 就把下面这行的注释去掉，数字按口味调。
        -- inactive_timeout = 3,

        -- 可选：触屏设备上碰屏幕后隐藏光标
        -- hide_on_touch = true,
    },
})


--  6b. 焦点跟随鼠标的程度
--      0 = 鼠标移动完全不改焦点
--      1 = 悬停即切键盘焦点（Hyprland 默认，官方配置未改）
--      2 = 悬停只切「光标焦点」（哪个窗口收鼠标事件），点击才切键盘焦点
--      3 = 光标焦点与键盘焦点彻底分离，点击也不切
--
--      配合 no_warps 使用：指针不再跟着焦点跑，若还停留在 follow_mouse=1
--      下，手碰一下鼠标就会把焦点抢回指针所在的那个窗口。改成 2 可避免。
hl.config({
    input = {
        follow_mouse = 2,

        -- 指针不动、但脚下的窗口因为切工作区/布局变化而换了一批时，
        -- 不要重新派发鼠标焦点。切桌面时光标闪一下正是这个引起的。
        mouse_refocus = false,
    },
})


-- ────────────────────────────────────────────────────────────────────────────
--  7. 新建桌面：ALT + T
--
--     Hyprland 的工作区是临时对象：非 persistent 的工作区在最后一个窗口关闭
--     后会自动消失，所以「新建」的语义就是【跳到一个空工作区】——不存在就
--     即时创建。（同理也没有「删除工作区」这回事，搬空它就等于删掉了。）
--
--     ★ 新桌面永远追加在【最右边】。
--
--     这里刻意不用官方的 emptym token。emptym = “本显示器上编号最小的空
--     工作区”，会往回找：你在 2 号按一下，它跳到空着的 1 号去——方向是反的。
--     改用 maxid + 1，语义变成“在末尾开一个新的”，跟直觉一致：
--     桌面永远从左往右长，ALT + ] 就能顺着走回来。
--
--     不用像第 4c 节那样过滤 special：hl.get_workspaces() 【确实会】返回抽屉架
--     那些 special 工作区，但它们的 id 是负数，永远当不上 max。取 min 的第 4c 节
--     就没这个便宜可占，必须显式写 w.id > 0。
--
--     编号会随着开关桌面出现空洞（比如剩 1、3 时新建的是 4 而不是 2），
--     这无所谓：本配置从不按绝对编号跳转，位置跳转用的是 m~N
--     （见 config/binds.lua，SUPER + CTRL + 数字 = 第 N 个存在的工作区）。
-- ────────────────────────────────────────────────────────────────────────────
local function next_ws()
    local maxid = 0
    for _, w in ipairs(hl.get_workspaces()) do
        if w.id > maxid then maxid = w.id end
    end
    return tostring(maxid + 1)
end

-- 模态同第 4 节：在抽屉架里按 ALT+T 是给抽屉架加一格，不是加工作桌面。
hl.bind("ALT + T", two_planes(
        function() hl.dispatch(hl.dsp.focus({ workspace = next_ws() })) end,
        function() rack.show(rack.new_slot()) end))
-- 配套：带着当前窗口去
hl.bind("ALT + SHIFT + T", two_planes(
        function() hl.dispatch(hl.dsp.window.move({ workspace = next_ws() })) end,
        function() rack.carry_to(rack.new_slot()) end))

--  —— 备选：复用编号最小的空桌面（官方行为，会向左跳）——
-- hl.bind("ALT + T",         hl.dsp.focus({ workspace = "emptym" }))
-- hl.bind("ALT + SHIFT + T", hl.dsp.window.move({ workspace = "emptym" }))


-- ────────────────────────────────────────────────────────────────────────────
--  8. 关闭窗口：ALT + W
--
--     ⚠ 不要用 CTRL+W。Wayland 下合成器的全局 bind 会直接截获按键，应用完全
--     收不到，而 CTRL+W 在三个高频场景里都有要紧的用途：
--         终端 readline/fish  → 删除前一个单词（unix-werase）
--         浏览器              → 关闭标签页
--         编辑器              → 关闭当前文件
--     占了它等于用「关窗口」换掉「终端里删单词」，得不偿失。
--
--     ALT+W 保留了同一个字母的肌肉记忆，只把小指从 Ctrl 挪到 Alt，且符合本
--     配置的分工：ALT = 动作（Enter/[/]/\/T/W），CTRL+ALT = 导航（HJKL）。
--     唯一代价：带菜单栏的应用里 Alt+W 原本是「Window」菜单助记键。
--
--     close() 是礼貌关闭，客户端仍可弹出「是否保存」。官方的 SUPER+Q 保留
--     不动，作为备用入口；真要强杀无响应窗口用官方的 SUPER+Escape。
-- ────────────────────────────────────────────────────────────────────────────
hl.bind("ALT + W", hl.dsp.window.close())

-- 想再加一个 Windows 经典手势（零冲突，但要抬手），取消注释：
-- hl.bind("ALT + F4", hl.dsp.window.close())


-- ────────────────────────────────────────────────────────────────────────────
--  9. 顶部栏显示/隐藏：ALT + 9
--
--     顶部栏归 noctalia 管（layer 名 noctalia-bar-default），不是 Hyprland 的
--     东西，所以走它的 IPC 而不是 hyprctl。
--
--     noctalia msg 的相关命令（noctalia msg --help 可看全集）：
--         bar-toggle          切换显示/隐藏  ← 这里用的
--         bar-hide / bar-show 单向隐藏／显示，并释放其占用的布局间距
--         bar-reserve-toggle  栏保留可见，但不再为它预留空间（窗口顶上去）
--         bar-auto-hide-set   自动隐藏模式，鼠标移到边缘才浮出
--
--     注意 noctalia msg 是发 IPC 消息，不是拉起应用，所以不加 uwsm 前缀
--     （与官方 binds.lua 里 noctCall 的用法一致）。
-- ────────────────────────────────────────────────────────────────────────────
local noctCall = "noctalia msg "

hl.bind("ALT + 9", hl.dsp.exec_cmd(noctCall .. "bar-toggle"))


-- ════════════════════════════════════════════════════════════════════════════
-- 10. 抽屉架（rack）—— 第二套工作平面
--     ALT + S 进出平面 ／ ALT + SHIFT + S 搬窗口进出
--
--     这一节是第 1b 节声明的 rack 引擎的实现体。
--
--     ▸ 它是什么
--       一组命名 special workspace：special:rack1 / special:rack2 / …
--       每一格都是一个满屏的桌面，用来放「不是正事」的那批程序（聊天、媒体、
--       下载器）。整个抽屉架可以一键收起，露出底下的工作桌面。
--
--       和「再开几个普通工作区当第二套环境」相比，special 的三个决定性优势：
--         · 收起来自动回原处。special 是【盖在】当前工作桌面上的，收起即复位，
--           不需要自己记「我进来之前在哪个桌面」。走普通工作区就得维护那个
--           变量，而本配置是纯动态工作区（config/workspaces.lua），工作区随时
--           会被销毁，那个变量必然失效 —— 是个 bug 温床。
--         · 隔离是免费的。第 4c 节 edge_ws() 的 w.id > 0 过滤已经把负数 id 的
--           special 挡在外面，CTRL+1/4 永远不会误入抽屉架。
--         · 视觉上无差别。dwindle.special_scale_factor 默认 1.0（实测未被官方
--           配置修改），浮出来就是整屏，不是缩小的浮动面板。
--
--       格数是【动态】的，和工作平面同哲学：ALT+T 加一格，搬空自动消失
--       （misc.close_special_on_empty 默认 true）。副作用：新开一格却没往里
--       放东西就离开，这一格会当场蒸发 —— 与「空工作区不赖着」是同一个规则。
--
--     ▸ 官方配置的残留
--       官方 config/binds.lua 第 160-161 行把 SUPER + S / SUPER + SHIFT + S 绑到
--       无名的 special:special，且【只绑了送进去，没有取出来的键】。第 1 节已经
--       hl.unbind 掉它们（hl.bind 是叠加不是覆盖，不摘会两套并存）。
--       本节完全不使用 special:special 这个名字。
--
--     ▸ 实测出来的 API 约束（stub 里 toggle_special 只写了 fun(...)，全靠试）
--       1) toggle_special 收【裸字符串】，且【不带 special: 前缀】：
--            toggle_special("rack2")                    ✅
--            toggle_special({ name = "rack2" })         ❌ 静默退回 special:special
--          {workspace=}/{special=} 同样静默失败 —— 不报错、不警告，最难查。
--       2) window.move 正相反：要 table，且 workspace 要【全名】：
--            window.move({ workspace = "special:rack2" })  ✅
--          同一节里两个 API 前缀要求相反，是最容易写错的地方。
--       3) window.move 送窗口进 special，默认会把那一格【拉出来显示】并把焦点
--          带过去。要「藏起来」得加 follow = false（见 STASH_SILENTLY）。
--          ⚠ 参数名不是 silent。实测 silent = true / silent = 1 / focus = false /
--            quiet = true 【全部静默失效】（照样弹出来），只有 follow = false 管用。
--            和约束 1 是同一类陷阱：不认识的键直接被忽略，不报错。
--            原生 dispatcher 叫 movetoworkspacesilent，名字对不上，别照着猜。
--       4) hl.get_workspaces() 【会】返回 special 工作区（见第 4c/7 节的注释），
--          所以枚举抽屉格直接遍历它就行，不用另找 API。
--       5) 从一格直接切到另一格是【一次】toggle_special 调用，不必先关再开。
--       6) 抽屉格的 id 不稳定：搬空后被销毁，再放东西进去是全新的 id
--          （实测 -99 → -98）。所以一切都认名字，绝不认 id。
--       7) 抽屉架收起时 monitor.active_special_workspace 是 nil，哪怕格里有窗口。
--          查内容要用 hl.get_workspace("special:rackN")，它不受开合影响。
--
--     ▸ monitor.active_workspace 始终是底下那个正常工作桌面，抽屉架浮出来也不变
--       —— 这正是「窗口取出来放哪儿」的答案，且与焦点在哪无关。
--
--     ▸ 调试提示：hyprctl dispatch 在这套 Lua 配置下会把参数当 Lua 代码解析
--       （"special:x,address:0x…" 报 ')' expected near 'special'），一律改用
--       hyprctl eval '...'。
-- ════════════════════════════════════════════════════════════════════════════
local RACK_PAT = "^special:rack(%d+)$"   -- 认名字不认 id，见约束 6

-- 上一次待过的格号。ALT+S 回来时优先落在这一格；也是 ALT+SHIFT+S 丢窗口的目的地。
local last_slot = 1

local function rack_ws(i) return "special:rack" .. i end   -- 全名，给 window.move（约束 2）
local function rack_bare(i) return "rack" .. i end         -- 裸名，给 toggle_special（约束 1）

-- 现存的抽屉格号，升序。空抽屉格会被系统销毁，所以这个列表随时在变（约束 4/6）。
function rack.slots()
    local out = {}
    for _, w in ipairs(hl.get_workspaces()) do
        local n = w.special and tostring(w.name):match(RACK_PAT)
        if n then out[#out + 1] = tonumber(n) end
    end
    table.sort(out)
    return out
end

-- 当前所在的格号；人不在抽屉架里就返回 nil。
-- ★ 这是【全部模态判断的唯一来源】—— 第 1b 节的 two_planes 只问这一个函数。
function rack.current_slot()
    local mon = hl.get_active_monitor()
    local sw  = mon and mon.active_special_workspace
    if not sw then return nil end                          -- 收起时为 nil（约束 7）
    return tonumber(tostring(sw.name):match(RACK_PAT))
end

-- 该落在哪一格：优先上次那格；它已经被搬空销毁了就退到现存的第一格；
-- 一格都不剩就用 1（rack.show 会把它当场建出来）。
function rack.target_slot()
    local slots = rack.slots()
    for _, i in ipairs(slots) do
        if i == last_slot then return i end
    end
    return slots[1] or 1
end

-- 切到第 i 格并记住它。
-- ⚠ toggle 语义：已经在第 i 格时这一下是【收起】。调用方负责避免误触发。
function rack.show(i)
    last_slot = i
    hl.dispatch(hl.dsp.workspace.toggle_special(rack_bare(i)))
end

-- ALT + S：切平面。在架里就收起（顺便把当前格记进 last_slot），不在就进去。
function rack.toggle_plane()
    local cur = rack.current_slot()
    if cur then rack.show(cur) else rack.show(rack.target_slot()) end
end

-- 架内左右挪一格，【回绕】。抽屉架常态只有两格，回绕让 ALT+] 变成来回切。
function rack.step(delta)
    local cur   = rack.current_slot()
    local slots = rack.slots()
    if not cur or #slots < 2 then return end
    for k, v in ipairs(slots) do
        if v == cur then
            local nxt = slots[((k - 1 + delta) % #slots) + 1]
            if nxt ~= cur then rack.show(nxt) end
            return
        end
    end
end

-- 架内跳到第一格 / 最后一格（CTRL + 1 / 4 的架内含义）
function rack.edge(want_max)
    local slots = rack.slots()
    local t = want_max and slots[#slots] or slots[1]
    if t and t ~= rack.current_slot() then rack.show(t) end
end

-- 下一个空闲格号（ALT + T 的架内含义）。追加在末尾，同第 7 节「桌面从左往右长」。
function rack.new_slot()
    local slots = rack.slots()
    return (slots[#slots] or 0) + 1
end

-- 带着当前窗口去第 i 格。这里【故意不 silent】—— 要的就是跟着窗口一起过去。
function rack.carry_to(i)
    local w = hl.get_active_window()
    if not w then return end
    hl.dispatch(hl.dsp.window.move({ workspace = rack_ws(i), window = w }))
    last_slot = i
end

-- 带着当前窗口左右挪一格（回绕，同 rack.step）
function rack.carry(delta)
    local cur   = rack.current_slot()
    local slots = rack.slots()
    if not cur or #slots < 2 then return end
    for k, v in ipairs(slots) do
        if v == cur then
            local nxt = slots[((k - 1 + delta) % #slots) + 1]
            if nxt ~= cur then rack.carry_to(nxt) end
            return
        end
    end
end

-- ALT + SHIFT + S：一个键管两个方向（跨平面搬窗口）
--   ① 焦点窗口在抽屉架里    → 捞回底下的工作桌面
--   ② 抽屉架浮着但焦点没进去 → 捞出当前格最后一个（兜底，见下方注释）
--   ③ 其余情况              → 把当前窗口丢进抽屉架的 target_slot 那一格
--
-- 关于 ②：老注释说「打开抽屉不会把键盘焦点送进去，必须兜底」。2026-08 在
-- Hyprland 0.56.2 上复验，焦点【是会】跟进去的（kitty@2 → v2rayN@special:…），
-- 所以 ① 通常就接住了。② 保留作为兜底：它只在焦点确实没进去时才有机会执行，
-- 留着零成本，删了则那种情况下这个键会变成「反而把窗口塞进去」。
function rack.move_window()
    local mon = hl.get_active_monitor()
    if not mon then return end

    local target = mon.active_workspace          -- 底下的工作桌面，抽屉浮出时也不变
    local w      = hl.get_active_window()

    -- ① 焦点已在抽屉架里
    if w and w.workspace and w.workspace.special then
        if target then
            hl.dispatch(hl.dsp.window.move({ workspace = target.id, window = w }))
        end
        return
    end

    -- ② 抽屉架浮着，捞当前格最后一个出来
    local slot = rack.current_slot()
    if slot and target then
        local ws   = hl.get_workspace(rack_ws(slot))
        local wins = ws and ws:get_windows() or {}
        if #wins > 0 then
            hl.dispatch(hl.dsp.window.move({ workspace = target.id, window = wins[#wins] }))
        end
        -- 这一格是空的就什么都不做：不要把当前窗口塞进去，那不是此刻的语义
        return
    end

    -- ③ 丢进抽屉架。follow = false 才是「不跟过去」，不是 silent（约束 3）
    if w then
        hl.dispatch(hl.dsp.window.move({
            workspace = rack_ws(rack.target_slot()),
            window    = w,
            follow    = not STASH_SILENTLY,
        }))
    end
end

hl.bind("ALT + S",         rack.toggle_plane)
hl.bind("ALT + SHIFT + S", rack.move_window)

-- 调试出口。hyprctl eval 是另一个 chunk，够不到本文件里的 local，验收/排查时
-- 没法直接调用上面这些函数（只能重敲键盘，或者照抄一遍逻辑 —— 那验的就不是
-- 真正跑着的这份代码了）。挂一个全局引用解决：
--     hyprctl eval 'RACK.toggle_plane()'
--     hyprctl eval 'local f=io.open("/tmp/r","w") f:write(table.concat(RACK.slots(),",")) f:close()'
-- 注意 hyprctl eval 拿不到返回值也没有 print，要看结果得自己写文件。
-- 代价只是一个全局名；Hyprland 的 Lua 环境是本配置独占的，不会撞到别人。
_G.RACK = rack


-- ────────────────────────────────────────────────────────────────────────────
-- 11. Caps Lock 当 Esc 用
--
--     走 XKB 的 kb_options，不是键位绑定 —— 它改的是键盘布局本身，所以
--     整个 Wayland 会话（含 XWayland 应用）全都生效，nvim 里也一样。
--     用 hl.bind 是做不到的：绑定只能触发 dispatcher，不能把键伪装成另一个键。
--
--     取值：
--         caps:escape      CapsLock → Esc，原来的 Esc 保持不变  ← 这里用的
--         caps:swapescape  两个键对调（Esc 变成 CapsLock）
--         caps:none        只是废掉 CapsLock，不映射成别的
--     完整列表：/usr/share/X11/xkb/rules/base.lst 里搜 caps:
--
--     官方 config/inputs.lua 只设了 accel_profile，没碰 kb_options，
--     不冲突。hl.config 是逐项合并，这里设 kb_options 不会把它的
--     accel_profile 冲掉（第 6b 节已经实测过这个合并行为）。
--
--     想要「轻按是 Esc、按住是 Ctrl」那种双功能，XKB 做不到，
--     需要 keyd 或 interception-tools 这类在 evdev 层做的工具。
-- ────────────────────────────────────────────────────────────────────────────
hl.config({
    input = {
        kb_options = "caps:escape",
    },
})


-- ────────────────────────────────────────────────────────────────────────────
-- 12. 应用启动器：ALT + Space
--
--     官方 config/binds.lua 第 80 行绑的是 SUPER + Space，走 noctalia 的
--     panel-toggle launcher。这里只换修饰键，命令原样不动。
--     unbind 在第 1 节。
--
--     ⚠️ ALT + Space 在 Windows / 传统 GTK 应用里是「窗口菜单」的助记键。
--     Wayland 下合成器的全局 bind 会直接截获，应用收不到 —— 和 ALT + W
--     一个性质。日常影响很小，但用 Wine 跑 Windows 程序时会感觉到。
-- ────────────────────────────────────────────────────────────────────────────
hl.bind("ALT + Space", hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher"))
