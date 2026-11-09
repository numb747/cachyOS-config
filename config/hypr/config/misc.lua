hl.config({
    dwindle = {
        preserve_split = true,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
    misc = {
        col = {
            splash = CACHYLGREEN,
        },
        -- noctalia 是在 layer-shell 的 background 层自己画壁纸，并不是"设置"壁纸，
        -- 底下压着的一直是 Hyprland 内置的 /usr/share/hypr/wall*.png。
        -- 合成器起来到 noctalia 铺好壁纸之间有 ~1.5s 空档，会闪一下那张内置图；
        -- noctalia 崩溃/重启时同样会露出来。这里把内置壁纸和 logo 都关掉，
        -- 空档改为纯色，取当前壁纸的主色 #1a1b26（magick 采样，占绝大多数像素）。
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        background_color = "rgb(1a1b26)",
        middle_click_paste = false,
        enable_swallow = true,
        swallow_regex = "(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)",
        vrr = 3,
    },
    render = {
        direct_scanout = 2,
        -- 默认 1：全屏窗口放 HDR 内容时自动把显示器切到 HDR，退出再切回。
        -- 每切一次都要 modeset（黑屏 + 输入卡 200ms+）；2026-11-03 Chrome 全屏放
        -- HDR 视频时 11 秒内来回切了 10 次。这台 HKC G27H4Max 的 HDR 也不值得用，关掉。
        cm_auto_hdr = 0,
    },
    xwayland = {
        force_zero_scaling = true
    },
})
