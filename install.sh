#!/usr/bin/env bash
# ============================================================================
#  CachyOS + Hyprland 桌面配置安装器
#
#  用法：
#      ./install.sh                  装全部模块
#      ./install.sh hypr nvim        只装指定模块
#      ./install.sh --list           列出模块
#      ./install.sh --dry-run        只打印会做什么，不动任何文件
#
#  性质：
#      幂等      —— 重复执行结果一致，不会重复追加 require、不会叠加备份
#      先备份    —— 每个被覆盖的已有文件都存成 <名字>.bak-YYYYmmdd-HHMMSS
#      不碰系统  —— 只写 $HOME 下的文件，不需要 sudo
# ============================================================================
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=0
FAILED=0

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
inf()  { printf '  %s%s%s\n' "$DIM" "$*" "$RST"; }
warn() { printf '%s!%s %s\n' "$YEL" "$RST" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*" >&2; FAILED=1; }
head_() { printf '\n%s── %s %s\n' "$DIM" "$*" "$RST"; }

# ── 打包机 HOME 的改写 ──────────────────────────────────────────────────────
# 包里有几处**没法用 $HOME 表达**的绝对路径，因为它们所在的格式不做变量展开：
#   ~/.config/noctalia/config.toml      [storage] key_file
#   ~/.local/state/noctalia/settings.toml   [wallpaper.*] path
#   ~/.local/share/applications/wecom.desktop   Exec=
# 装到别的用户名下必须改写，否则**全是静默失效**，且症状都不指向路径：
#   密钥读不到 → 剪贴板历史又不持久化了（会以为是坑 12 没修好）
#   壁纸路径不存在 → 退回默认壁纸
#   Exec 找不到 → 启动器里点了没反应
# rewrite_home <目标绝对路径>
PKG_HOME="/home/david"
rewrite_home() {
    [ "$HOME" = "$PKG_HOME" ] && return 0
    if [ $DRY -eq 1 ]; then
        printf '  [dry] 改写 %s 里的 %s → %s\n' "$1" "$PKG_HOME" "$HOME"
        return 0
    fi
    [ -f "$1" ] || return 0
    grep -q "$PKG_HOME" "$1" 2>/dev/null || return 0
    sed -i "s#$PKG_HOME#$HOME#g" "$1" && inf "路径已改写到 \$HOME：$(basename "$1")"
}

# put <相对源路径> <目标绝对路径>
put() {
    local s="$SRC/$1" d="$2"
    [ -e "$s" ] || { err "包内缺文件：$1"; return 1; }
    if [ $DRY -eq 1 ]; then
        printf '  [dry] %s → %s%s\n' "$1" "$d" "$([ -e "$d" ] && echo '  (会先备份)')"
        return 0
    fi
    mkdir -p "$(dirname "$d")" || { err "建不了目录：$(dirname "$d")"; return 1; }
    if [ -e "$d" ]; then
        if cmp -s "$s" "$d"; then inf "$d 已是最新，跳过"; return 0; fi
        # 备份失败就别覆盖了 —— 覆盖掉又没备份是这里最坏的结果
        cp -a "$d" "$d.bak-$STAMP" || { err "备份失败，跳过不覆盖：$d"; return 1; }
        inf "备份 → $(basename "$d").bak-$STAMP"
    fi
    # ★ 2026-08-26：原来是 `cp -a … && ok`，cp 失败时既不报错也不设 FAILED，
    #   整轮 put 全挂了还照样打印「✓ 完成」并 exit 0（实测撞到过）。
    cp -a "$s" "$d" && ok "$d" || { err "写入失败：$d"; return 1; }
}

run() { if [ $DRY -eq 1 ]; then printf '  [dry] 执行: %s\n' "$*"; else "$@"; fi; }

# put_module <模块名> —— 按 manifest.map 里的 #@module 分组批量安装。
# 路径只写在 manifest.map 一处，三个脚本共用；新增文件不用改脚本。
put_module() {
    local want="$1" cur="" rel sys
    while read -r rel sys; do
        # 分组标记：read 把 "#@module hypr" 拆成 rel='#@module' sys='hypr'
        if [ "$rel" = "#@module" ]; then cur="$sys"; continue; fi
        case "$rel" in \#*|'') continue ;; esac
        [ "$cur" = "$want" ] || continue
        sys="${sys/#\~/$HOME}"; sys="${sys//\$HOME/$HOME}"
        put "$rel" "$sys"
    done < "$SRC/manifest.map"
}

# ─── 模块 ───────────────────────────────────────────────────────────────────

mod_hypr() {
    head_ "hypr —— Hyprland 键位与窗口行为"
    local D="$HOME/.config/hypr"
    if [ ! -f "$D/hyprland.lua" ]; then
        err "$D/hyprland.lua 不存在。要么没装 Hyprland，要么用的是传统 hyprland.conf" \
            && inf "本配置需要 Hyprland ≥ 0.56 的 Lua 配置（cachyos-hypr-noctalia）" && return 1
    fi

    if command -v luac >/dev/null 2>&1; then
        luac -p "$SRC/config/hypr/mykeys.lua" || { err "mykeys.lua 语法检查失败，中止"; return 1; }
        ok "mykeys.lua 语法检查通过"
    else
        inf "未装 lua，跳过语法预检（不影响安装）"
    fi

    put config/hypr/mykeys.lua "$D/mykeys.lua"

    # 挂载：官方 hyprland.lua 末尾追加一行，幂等
    if grep -q 'require("mykeys")' "$D/hyprland.lua" 2>/dev/null; then
        inf 'hyprland.lua 已有 require("mykeys")，跳过'
    elif [ $DRY -eq 1 ]; then
        printf '  [dry] 向 %s 追加 require("mykeys")\n' "$D/hyprland.lua"
    else
        cp -a "$D/hyprland.lua" "$D/hyprland.lua.bak-$STAMP"
        printf '\nrequire("mykeys")\n' >> "$D/hyprland.lua"
        ok 'hyprland.lua 末尾已追加 require("mykeys")'
    fi

    # 五个被改过的官方文件（纯动态工作区 + wine 幽灵窗规则 + 关内置壁纸）。见 docs/02、docs/10。
    warn "接下来覆盖 5 个 CachyOS 官方文件（binds/variables/workspaces/windowrules/misc）"
    inf  "它们属于 cachyos-hypr-noctalia 包，pacman 升级可能覆盖回去"
    inf  "届时用 config/hypr/patches/*.patch 重新打上即可"
    local f
    for f in binds variables workspaces windowrules misc; do
        put "config/hypr/config/$f.lua" "$D/config/$f.lua"
    done
    # ↑ 这三个单独列是因为要先打上面那两句 warn；其余模块统一走 put_module

    # 录屏脚本。binds.lua 的 Super+Shift/Alt/Ctrl+R 直接调它，少了它三个键位全哑。
    # ★ 因为 mod_hypr 不走 put_module，manifest.map 里那行不会被自动安装，必须显式列在这。
    put bin/hypr-screenrec "$HOME/.local/bin/hypr-screenrec"
    command -v wl-screenrec >/dev/null 2>&1 \
        || inf "未装 wl-screenrec（录屏键位依赖它）。装：yay -S wl-screenrec"

    if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        if [ $DRY -eq 1 ]; then
            printf '  [dry] 执行: hyprctl reload\n'
        else
            hyprctl reload >/dev/null && ok "已重载 Hyprland"
        fi
        if [ $DRY -eq 0 ] && command -v jq >/dev/null 2>&1; then
            inf "当前绑定总数：$(hyprctl binds -j | jq length)（预期 116；95 = mykeys 没挂上，差的 21 条就是它）"
        fi
    else
        inf "Hyprland 未在当前会话运行 —— 登录桌面后执行 hyprctl reload"
    fi
}

mod_term() {
    head_ "term —— kitty / alacritty / zsh / powerlevel10k"
    put_module term

    [ -f /usr/share/cachyos-zsh-config/cachyos-config.zsh ] \
        || warn "缺 cachyos-zsh-config —— .zshrc 第一行 source 会失败，装它：sudo pacman -S cachyos-zsh-config"

    # 比 basename，不比全路径 —— passwd 里可能是 /bin/zsh，command -v 给 /usr/bin/zsh，
    # 在 Arch 上这俩是同一个文件（/bin → usr/bin 软链），比字符串会误报。
    if [ "$(basename "$(getent passwd "$USER" | cut -d: -f7)")" != "zsh" ]; then
        warn "登录 shell 不是 zsh。改：chsh -s \$(command -v zsh) && 重新登录"
    else
        ok "登录 shell 已是 zsh"
    fi
}

mod_nvim() {
    head_ "nvim —— LazyVim 配置"
    local D="$HOME/.config/nvim"
    if [ -d "$D" ] && [ "$(ls -A "$D" 2>/dev/null)" ]; then
        if [ $DRY -eq 1 ]; then
            printf '  [dry] 整目录备份 %s → %s.bak-%s，然后替换\n' "$D" "$D" "$STAMP"
        else
            mv "$D" "$D.bak-$STAMP" && inf "旧配置整目录备份 → $(basename "$D").bak-$STAMP"
        fi
    fi
    if [ $DRY -eq 1 ]; then
        printf '  [dry] 复制 config/nvim/ → %s/\n' "$D"
    else
        mkdir -p "$D" && cp -a "$SRC/config/nvim/." "$D/" && ok "$D"
    fi
    inf "首次 nvim 启动会按 lazy-lock.json 自动装 45 个插件，等它跑完"
    inf "语言工具链（LSP/formatter）要在 :Mason 里装，前置运行时见 docs/04-neovim.md"
}

mod_ui() {
    head_ "ui —— noctalia 顶栏 / 主题 / 环境变量 / 输入法"
    put_module ui

    # ★ 主题真正生效的是 state/settings.toml，不是 config.toml。
    #   见 README「三件需要先知道的事」。下面两段是它专属的善后处理。
    local S="$HOME/.local/state/noctalia"
    rewrite_home "$S/settings.toml"
    # config.toml 的 [storage] key_file 同样写死了绝对路径（剪贴板持久化的
    # 主密钥位置）。2026-08-27 之前漏了这条，换用户名会静默退回仅本会话。
    rewrite_home "$HOME/.config/noctalia/config.toml"
    local p
    for p in "$SRC"/state/noctalia/community-palettes/*.json; do
        [ -e "$p" ] || continue
        put "state/noctalia/community-palettes/$(basename "$p")" "$S/community-palettes/$(basename "$p")"
    done
    if grep -q 'DP-1' "$SRC/state/noctalia/settings.toml" 2>/dev/null; then
        warn "settings.toml 里的显示器名写死为 DP-1"
        inf  "新机器输出名不同的话，壁纸不会自动上屏 —— 在 noctalia 设置里重选一次壁纸即可"
    fi

    if [ $DRY -eq 0 ] && [ -f "$HOME/.config/qt6ct/qt6ct.conf" ]; then
        # 官方 skel 里这行写的是字面量 $USER，qt6ct 不做展开，得替换成真路径
        sed -i "s#/home/\$USER/#$HOME/#" "$HOME/.config/qt6ct/qt6ct.conf"
    fi

    # ── 默认打开方式：图片 → imv，音视频 → mpv ──────────────────────────
    # 装完 imv-viewer.desktop 必须刷 desktop 数据库，否则它在 dolphin 的
    # 「打开方式」列表里查不到（mimeapps.list 已指向它，双击仍然能用，只是列表里看不见）。
    if [ $DRY -eq 1 ]; then
        printf '  [dry] 执行: update-desktop-database ~/.local/share/applications\n'
    elif command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null \
            && ok "desktop 数据库已刷新"
    fi
    command -v imv >/dev/null 2>&1 \
        || inf "未装 imv（图片默认打开方式）。装：sudo pacman -S imv；不装则双击图片无响应"
    command -v mpv >/dev/null 2>&1 \
        || inf "未装 mpv（音视频默认打开方式）。装：sudo pacman -S mpv；不装则双击视频无响应"

    [ -d /usr/share/icons/Bibata-Modern-Ice ] \
        || inf "未装 Bibata 光标（gtk/uwsm 配置引用了它）。要一致就 yay -S bibata-cursor-theme；不装则回退 Adwaita，无报错"

    # ── 字体：fonts.conf 改了字体优先级，缓存不刷新不生效 ────────────────
    if [ $DRY -eq 1 ]; then
        printf '  [dry] 执行: fc-cache -f\n'
    elif command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 && ok "fontconfig 缓存已刷新"
    fi

    # fonts.conf 首选更纱，缺了会静默落到 Noto 兜底 —— 能用，但等宽中文不对齐。
    # ★ 别写成 `fc-list | grep -q Sarasa`：grep -q 提前退出会让 fc-list 吃到 SIGPIPE，
    #   本脚本开了 set -o pipefail，管道整体返回 141，装了字体也会误报「未装」。
    #   命令替换只取输出、不看退出码，绕开这个坑。
    [ -n "$(fc-list 2>/dev/null | grep -m1 Sarasa)" ] \
        || inf "未装更纱黑体（fonts.conf 首选它）。装：sudo pacman -S ttf-sarasa-gothic；不装则回退 Noto CJK SC，无报错"

    # 验证汉字没落到韩文字形上 —— 这是本配置要解决的核心问题，见 docs/05
    if [ $DRY -eq 0 ] && command -v fc-match >/dev/null 2>&1; then
        local cjk
        cjk="$(fc-match -s "sans-serif:lang=zh-cn" 2>/dev/null | grep -iE 'CJK|Sarasa' | head -1)"
        case "$cjk" in
            *Sarasa*|*"CJK SC"*) ok "汉字字形 → ${cjk#*: }" ;;
            *CJK*) warn "汉字仍落到非简中字形：${cjk#*: }"
                   inf  "检查 ~/.config/fontconfig/fonts.conf 是否生效：fc-match -s 'sans-serif:lang=zh-cn'" ;;
        esac
    fi

    # ── 输入法主题：热重载，不用重启 fcitx5 ──────────────────────────────
    if [ $DRY -eq 1 ]; then
        printf '  [dry] 执行: 重载 fcitx5 classicui 配置\n'
    elif pgrep -x fcitx5 >/dev/null 2>&1 && command -v gdbus >/dev/null 2>&1; then
        gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
            --method org.fcitx.Fcitx.Controller1.ReloadAddonConfig "classicui" >/dev/null 2>&1 \
            && ok "fcitx5 输入法主题已重载" \
            || inf "fcitx5 重载失败（不影响，下次登录自动生效）"
    else
        inf "fcitx5 未运行 —— 登录桌面后自动生效"
    fi
}

mod_cc() {
    head_ "cc —— Claude Code 本机工具（看板 / 宠物 TUI / 状态栏）"
    put_module cc
    # manifest 里 cp -a 保原权限，但包里的权限万一被 tar 洗掉就跑不起来，兜一下
    [ $DRY -eq 0 ] && chmod +x "$HOME/.claude/cc-pet.py" "$HOME/.claude/cc-watch.py" \
                             "$HOME/.claude/statusline.sh" "$HOME/.claude/test-cc.py" 2>/dev/null

    command -v claude >/dev/null 2>&1 \
        || warn "没装 claude CLI —— 脚本装好了但没会话可看"
    python3 -c 'import curses' 2>/dev/null \
        || warn "python3 缺 curses 模块，ccp 起不来（ccw 不受影响）"

    # ── 激活状态栏 ──────────────────────────────────────────────────────────
    # settings.json 含明文 API token、永不入包（见 manifest.map 文末），所以这里
    # 不能整份铺开，只能把 statusLine 那一个键【合并】进本机已有的文件。
    # 只写不读 token；改前备份；jq 写临时文件再 mv，避免中途失败把配置写坏。
    local S="$HOME/.claude/settings.json"
    if ! command -v jq >/dev/null 2>&1; then
        warn "没有 jq，跳过状态栏激活。手动往 $S 加 statusLine 段（见 docs/08）"
        return 0
    fi
    if [ ! -f "$S" ]; then
        inf "settings.json 不存在 —— 只建一个带 statusLine 的最小文件，token 你自己填"
        if [ $DRY -eq 0 ]; then
            mkdir -p "$HOME/.claude"
            printf '%s\n' '{"statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":1}}' \
                | jq . > "$S" && ok "$S（已建）"
        else
            printf '  [dry] 新建 %s\n' "$S"
        fi
        return 0
    fi
    if [ "$(jq -r '.statusLine.command // ""' "$S" 2>/dev/null)" = "~/.claude/statusline.sh" ]; then
        inf "statusLine 已指向本包脚本，跳过"
        return 0
    fi
    if [ $DRY -eq 1 ]; then
        printf '  [dry] 合并 statusLine 段进 %s\n' "$S"
        return 0
    fi
    cp -a "$S" "$S.bak-$STAMP" && inf "备份 → settings.json.bak-$STAMP"
    if jq '.statusLine = {type:"command", command:"~/.claude/statusline.sh", padding:1}' \
            "$S" > "$S.tmp-$$" && [ -s "$S.tmp-$$" ]; then
        mv "$S.tmp-$$" "$S" && ok "statusLine 已合并进 settings.json"
    else
        rm -f "$S.tmp-$$"
        err "jq 合并失败，settings.json 原样未动（备份仍在）"
    fi
}

mod_wall() {
    head_ "wall —— 壁纸"
    local W="$HOME/Pictures/Wallpapers/tokyonight"
    put wallpaper/11-w55gjr.png "$W/A-最搭/11-w55gjr.png"
    # D-ASCII 款多数是本包 _ascii.py 自己的产出，但重生成依赖 wallhaven 上的源图还在
    # ——那个不可控，所以直接带成品兜底。其中 a1 是 settings.toml 默认指向的那张，
    # 少了它装完就是纯色背景（且 misc.lua 的 background_color 正是按 a1 采样的）。
    # ★ 别把通配符写死成 *.png：c2-网点少女是 .jpg，只匹配 png 会静默漏掉它。
    # glob 走 $SRC 绝对路径：脚本可能从任意 cwd 调用，相对 glob 展不开就会
    # 退化成字面量，put 只会报「包内缺文件」，看不出是 cwd 的问题。
    local a
    for a in "$SRC"/wallpaper/ascii/*; do
        [ -f "$a" ] || continue
        put "wallpaper/ascii/$(basename "$a")" "$W/D-ASCII/$(basename "$a")"
    done
    put_module wall
    inf "带了 1 张参考图 + $(ls -1 "$SRC"/wallpaper/ascii/ 2>/dev/null | wc -l) 张 D-ASCII 成品。整库（77 张 / 167 MB）用 python _fetch.py 重新拉，见 docs/05"

    # settings.toml 里记的是【当时正在用的】那张，未必是包里带的这张 ——
    # 壁纸换得比配置勤，包不可能每次都跟着塞图。缺了就明确告诉用户去哪补。
    if [ $DRY -eq 0 ]; then
        local want
        want="$(sed -n 's/^path = "\(.*\)"$/\1/p' "$HOME/.local/state/noctalia/settings.toml" 2>/dev/null | head -1)"
        if [ -n "$want" ] && [ ! -f "$want" ]; then
            warn "noctalia 记录的壁纸不在磁盘上：${want/#$HOME/\~}"
            inf  "桌面会显示纯色背景。补救二选一："
            inf  "  · 在 noctalia 里重选一张（$W/ 下有本包带的 11-w55gjr.png）"
            inf  "  · 或 cd $W && python _fetch.py 把整库拉回来"
        fi
    fi
}

# ─── 参数解析 ───────────────────────────────────────────────────────────────

mod_wine() {
    head_ "wine —— winapp 工具链与企业微信"
    put_module wine
    [ $DRY -eq 0 ] && chmod +x "$HOME/.local/bin/winapp" 2>/dev/null
    # .desktop 的 Exec= 用绝对路径（桌面环境的 PATH 不保证含 ~/.local/bin），
    # 所以换用户名必须改写，否则启动器里点了完全没反应。
    rewrite_home "$HOME/.local/share/applications/wecom.desktop"

    command -v wine >/dev/null 2>&1 \
        || inf "未装 wine：sudo pacman -S wine-staging wine-mono wine-gecko winetricks"
    command -v bwrap >/dev/null 2>&1 \
        || inf "未装 bubblewrap（沙箱依赖）：sudo pacman -S bubblewrap"

    # prefix 有 2GB+，含聊天记录与登录态，不入包 —— 新机器要重装一遍。
    # 企业微信【公有云版没有 Linux 客户端】：官网 platform=linux 返回的就是
    # Windows exe，/server 页那个 Linux 包是私有部署版，公有云账号登不上。
    if [ ! -d "$HOME/.local/share/wineprefixes/wecom" ]; then
        inf "企业微信尚未安装（prefix 不入包）。两步，下载链接见 docs/09-wine-apps.md："
        inf "  winapp create wecom"
        inf "  winapp install wecom <下载的 WeCom_x.x.x.exe>"
    fi

    if [ $DRY -eq 0 ]; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null
    fi
    return 0
}

mod_ocr() {
    head_ "ocr —— 屏幕取字（RapidOCR 常驻服务）"
    put_module ocr
    if [ $DRY -eq 0 ]; then
        chmod +x "$HOME/.local/bin/ocr-server" "$HOME/.local/bin/ocr-grab" 2>/dev/null
    fi

    # ★ 本仓库唯一需要「激活」而不只是「拷文件」的模块。put 把 .socket/.service 放到
    #   ~/.config/systemd/user/ 就完事了，不 daemon-reload systemd 根本不知道它们存在，
    #   不 enable 则按键时没人在 8265 端口上接。装完却没反应，十有八九是漏了这两步。
    #   都是 --user 级别，写的仍然只有 $HOME，不需要 sudo（符合本脚本的「不碰系统」）。
    run systemctl --user daemon-reload
    run systemctl --user enable --now ocrd.socket

    # 运行时依赖。python-rapidocr 在 AUR，且**不能直接 yay 装**：它的 PKGBUILD 写了
    # makedepends python-installer>=1.0.1，而 Arch 全仓库最新只有 1.0.0，yay 会报
    # 「could not find all required packages」。要本地放宽这个约束再 makepkg，
    # 完整步骤（含装完后锁 IgnorePkg、以及怎么复核这个 AUR 包没被投毒）见 docs/10-ocr.md。
    if ! python3 -c "import rapidocr" 2>/dev/null; then
        warn "未装 python-rapidocr —— 按键会报「识别服务连不上」"
        inf "  它不能直接 yay 装（上游 PKGBUILD 的版本约束有 bug），照 docs/10-ocr.md 走"
    fi
    python3 -c "import onnxruntime" 2>/dev/null \
        || inf "未装推理运行时：sudo pacman -S python-onnxruntime-cpu"

    for c in grim slurp wl-copy jq; do
        command -v "$c" >/dev/null 2>&1 || inf "缺 $c（截图/剪贴板链路要用）"
    done
    return 0
}

ALL=(hypr term nvim ui cc wall wine ocr)
declare -A DESC=(
    [hypr]="Hyprland 键位、鼠标行为、动态工作区"
    [term]="kitty / alacritty / zsh / powerlevel10k"
    [nvim]="LazyVim 全套配置"
    [ui]="noctalia 顶栏、GTK/Qt/btop 主题、环境变量、输入法"
    [cc]="Claude Code 会话看板 / 宠物 TUI / 上下文状态栏"
    [wall]="壁纸与壁纸库脚本"
    [wine]="winapp（wine 应用沙箱工具链）与企业微信"
    [ocr]="屏幕取字（RapidOCR 常驻服务，Super+Shift/Alt+O）"
)

SELECTED=()
for a in "$@"; do
    case "$a" in
        --list)
            echo "可用模块："
            for m in "${ALL[@]}"; do printf '  %-6s %s\n' "$m" "${DESC[$m]}"; done
            exit 0 ;;
        --dry-run|-n) DRY=1 ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) err "未知参数：$a"; exit 2 ;;
        *)
            [[ " ${ALL[*]} " == *" $a "* ]] || { err "未知模块：$a（--list 看全部）"; exit 2; }
            SELECTED+=("$a") ;;
    esac
done
[ ${#SELECTED[@]} -eq 0 ] && SELECTED=("${ALL[@]}")

[ $DRY -eq 1 ] && warn "DRY RUN —— 不会修改任何文件"
inf "备份后缀：.bak-$STAMP"

for m in "${SELECTED[@]}"; do "mod_$m"; done

echo
if [ $FAILED -eq 0 ]; then
    ok "完成（模块：${SELECTED[*]}）"
else
    warn "完成，但有步骤失败 —— 往上翻红色的 ✗"
fi
cat <<'EOF'

下一步：
  1. 注销并重新登录 Hyprland（uwsm/env 和登录 shell 只在登录时读一次）
  2. 打开终端 → 应直接进 nvim；:q 退出后是 zsh + p10k 提示符
  3. 逐项验收清单见 INSTALL.md
  4. 键位速查见 docs/06-keymap-cheatsheet.md
EOF
exit $FAILED
