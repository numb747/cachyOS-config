-- Hyprland default apps

TERMINAL     = "kitty"
FILE_MANAGER = "dolphin"
BROWSER      = "firefox"
EDITOR       = "gnome-text-editor --new-window"
CALCULATOR   = "gnome-calculator"

-- Monitors
MONITOR1 = ""
MONITOR2 = ""
MONITOR3 = ""
PRIMARY_MONITOR = MONITOR1

-- Workspaces
-- ★ 本配置为纯动态工作区（config/workspaces.lua 不定义 persistent 规则），
--   所以这个值不再决定“有几个桌面”，只决定生成多少个【按位置跳转】的键位：
--     SUPER + CTRL  + 1..N        跳到本显示器第 N 个已存在的工作区
--     SUPER + SHIFT + CTRL + 1..N 把当前窗口丢到第 N 个
--   绑满 9 个没有代价：位置不存在时按下即空操作。
NUM_WPM = 9 -- Number of position-based workspace keybinds (Max 10)
