-- Window rules wiki https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- Generic floating position
hl.window_rule({ match = { float = true }, center = true, persistent_size = true })

-- Picture-in-Picture
hl.window_rule({
    match             = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" },
    float             = true,
    keep_aspect_ratio = true,
    size              = { "max(monitor_w, monitor_h)*0.25", "min(monitor_w, monitor_h)*0.25" },
    pin               = true,
})

-- Gaming
local gamingApps = "^(steam_app.*|gamescope)$"
local gamingWorkspace = "name:gaming"

hl.window_rule({ match = { content = "game" }, workspace = gamingWorkspace })
hl.window_rule({ match = { xdg_tag = "^(.*game.*)$" }, workspace = gamingWorkspace, fullscreen_state = 2, content = "game", sync_fullscreen = true })
hl.window_rule({ match = { class = gamingApps }, workspace = gamingWorkspace })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Friends List)$" }, float = true })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Launching\\.{3})$" }, float = true, center = true, workspace = gamingWorkspace })
hl.window_rule({
    match = {
        class         = gamingApps,
        title         = "^(.+)$",
        initial_title = "negative:^(.*\\\\home\\\\.*)$",
    },
    content          = "game",
    decorate         = false,
    fullscreen_state = 2,
    size             = { "monitor_w", "monitor_h" },
    sync_fullscreen  = true,
})
hl.window_rule({
    match = {
        class         = "^(steam_app.*)$",
        initial_title = "^$",
    },
    center           = true,
    float            = true,
    fullscreen       = false,
    fullscreen_state = 0,
    workspace        = gamingWorkspace,
})

-- Apps
hl.window_rule({ match = { class = "^(.*\\.exe)$", float = true }, monitor = PRIMARY_MONITOR, center = true, fullscreen_state = 0 })
hl.window_rule({ match = { class = "^(.*[Ll]auncher.*)$" }, float = true, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(vesktop|discord)$" }, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(.*[Cc]alc.*)$" }, float = true, size = { "max(monitor_w, monitor_h)*0.17", "min(monitor_w, monitor_h)*0.43" } })
hl.window_rule({ match = { class = "^(org\\.kde\\.keditfiletype)$" }, float = true })
hl.window_rule({ match = { class = "^(org\\.kde\\.ark)$" }, size = { "max(monitor_w, monitor_h)*0.40", "min(monitor_w, monitor_h)*0.40" } })
hl.window_rule({ match = { class = "^(.*satty.*)$", title = "^(Satty)$" }, min_size = { "max(monitor_w, monitor_h)*0.35", "min(monitor_w, monitor_h)*0.35" }, float = true })
hl.window_rule({ match = { class = "^(dev\\.)?(noctalia\\.Noctalia(\\.Settings)?)$" }, float = true, size = { "monitor_w*0.70", "monitor_h*0.70" } })
hl.window_rule({
    match = {
        class = "^(org\\.kde\\.dolphin)$",
        title = "negative:^(Moving.*|Create New.*|Extract.*|Compress.*|Copying.*|Progress.*|Configure.*|Properties.*|Choose\\sApplication.*)$",
    },
    float = true,
    size = { "max(monitor_w, monitor_h)*0.50", "min(monitor_w, monitor_h)*0.55" },
    move = {
        "max(20, min(cursor_x - (window_w*0.50), monitor_w - window_w + 20))", -- X axis clamping
        "max(20, min(cursor_y - 50, monitor_h - window_h + 20))" -- Y axis clamping
    },
})

-- Opacity Overrides
local terminals = "^(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)$"

hl.window_rule({ match = { class = "^(firefox|zen)$" }, opacity = "1.0 override" })
hl.window_rule({ match = { class = terminals }, opacity = "1.0 override" }) -- Override opacity in favor of terminal settings for opacity. If your terminal doesn't support transparency, you can remove this rule.
hl.window_rule({ match = { class = "^(mpv|org.kde.haruna|.*plex.*|org\\.kde\\.gwenview|.*vlc.*)$" }, opacity = "1.0 override" })

-- Float Utility Windows
local floatApps = {
    { class = "^(kvantummanager|qt[56]ct|nwg-look)$" },
    { class = "^(org.pulseaudio.pavucontrol|blueman-manager|nm-applet|nm-connection-editor)$" },
    { title = "^(Winetricks.*|Protontricks.*)$" },
}
for _, m in ipairs(floatApps) do hl.window_rule({ match = m, float = true }) end

-- Float Common Modals
local modalMatches = {
    { title = "^(Open|Authentication Required|Add Folder to Workspace|Choose Files|Save As|Confirm to replace files|File Operation Progress)$" },
    { initial_title = "^(Open File)$" },
    { class = "^([Xx]dg-desktop-portal-gtk)$" },
    { title = "^(File Upload|Choose wallpaper|Library)(.*)$" },
    { class = "^(.*dialog.*)$" },
    { title = "^(.*dialog.*)$" },
    { class = "^(hyprland-share-picker)$"},
}
for _, m in ipairs(modalMatches) do hl.window_rule({ match = m, float = true }) end

-- Ignore maximize requests from all apps. You'll probably like this.
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- Noctalia layer rule
hl.layer_rule({
  name = "noctalia",
  match = {
    namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
  },
  no_anim = true,
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})

-- 企业微信的幽灵窗
--
-- wxwork.exe 启动时除主窗口外还会创建几个空白窗口：一个约 986x28 的细长条、
-- 一个和主窗口差不多大的纯白窗口、以及两个 0x0 的隐藏窗口。它们都是浮动的，
-- 而 Hyprland 里浮动窗恒在平铺窗之上，于是那个白窗正好把主界面整个罩住。
--
-- ★ 判据用 initial_title 而不是 title。
--   title 会随窗口生命周期变化——窗口刚创建时【所有】窗口的 title 都是空的，
--   用 title = "^$" 匹配会把主窗口一起误伤（曾经因此让整个窗口 no_focus、
--   鼠标点击全部落空，排查了很久）。initial_title 记录的是创建那一刻的标题，
--   主窗口从一开始就是"企业微信"，幽灵窗从一开始就是空——这才是稳定判据。
--
-- 注：GPU 报错（vulkan/egl 初始化失败）与这些窗口无关，实测强制软件渲染
--     并不能消除它们，别再往那个方向查。
hl.window_rule({
    name  = "wecom-ghost-windows",
    -- 不加 float = true：那个 986x28 的细条在【创建瞬间】还不是浮动的，
    -- 加上这个条件它就漏网了。initial_title 本身已经足够精确。
    match = {
        class         = "^(wxwork\\.exe)$",
        initial_title = "^$",
        xwayland      = true,
    },
    workspace = "special:wine_ghosts silent",
})

-- 上面那条 workspace 规则对其中一个约 986x28 的细条不起作用（它贴在主窗口正上方
-- 同一坐标，看起来就是「一个顶栏高度的白色细框」）。原因是这类浮层窗口 Hyprland
-- 不接管其工作区归属，workspace 规则落不到它身上。
--
-- 光加 opacity 不够：opacity 只作用于窗口【内容】，Hyprland 给它画的【边框】
-- 照样可见 —— 那圈边框正是肉眼看到的"白框"。所以三样一起上：
--   decorate = false  去掉边框/阴影，消灭白框本体
--   move              挪到屏幕外，眼不见为净
--   opacity           内容也一并透明，作为兜底
hl.window_rule({
    name  = "wecom-ghost-overlay-hide",
    match = {
        class         = "^(wxwork\\.exe)$",
        initial_title = "^$",
        xwayland      = true,
    },
    decorate = false,
    move     = { "-9999", "-9999" },
    opacity  = "0.0 override",
})
