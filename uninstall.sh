#!/usr/bin/env bash
# ============================================================================
#  还原 install.sh 的改动
#
#  用法：
#      ./uninstall.sh              交互确认后还原全部
#      ./uninstall.sh --yes        不问直接还原
#      ./uninstall.sh --list-baks  只列出可用备份，不动任何文件
#
#  策略：优先「回滚到最近一次备份」，没有备份的（说明是本包新建的文件）才删掉。
#  官方 hypr config/*.lua 会尝试从 /etc/skel 还原成发行版原版。
# ============================================================================
set -uo pipefail

YES=0
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
inf()  { printf '  %s%s%s\n' "$DIM" "$*" "$RST"; }
warn() { printf '%s!%s %s\n' "$YEL" "$RST" "$*"; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP="$SRC/manifest.map"
[ -f "$MAP" ] || { printf '✗ 缺 %s\n' "$MAP" >&2; exit 1; }

# 目标列表从 manifest.map 读 —— 与 install.sh / sync.sh 共用同一份映射，
# 加文件只改那一处。两类条目排除在外：
#   config/nvim/*  走整目录还原，不逐个文件处理（见文件末尾）
#   wallpaper/*    ~/Pictures 下的脚本是【你自己的创作】，不是本包安装的东西。
#                  在原始机器上它们没有 .bak，删了就没了 —— 卸载不该造成数据丢失。
TARGETS=()
while read -r rel sys; do
    [ -z "${rel:-}" ] && continue
    case "$rel" in \#*|config/nvim/*|wallpaper/*) continue ;; esac
    sys="${sys/#\~/$HOME}"; sys="${sys//\$HOME/$HOME}"
    TARGETS+=("$sys")
done < "$MAP"

latest_bak() { ls -1d "$1".bak-* 2>/dev/null | sort | tail -1; }

if [ "${1:-}" = "--list-baks" ]; then
    for t in "${TARGETS[@]}" "$HOME/.config/nvim" "$HOME/.config/hypr/hyprland.lua"; do
        b="$(latest_bak "$t")"
        printf '%-52s %s\n' "${t/#$HOME/\~}" "${b:+→ $(basename "$b")}"
    done
    exit 0
fi
[ "${1:-}" = "--yes" ] && YES=1

if [ $YES -eq 0 ]; then
    warn "将把以下文件回滚到最近一次 .bak-*（没有备份的会被删除）："
    for t in "${TARGETS[@]}"; do inf "${t/#$HOME/\~}"; done
    inf "以及 ~/.config/nvim/ 整目录、hyprland.lua 里的 require(\"mykeys\") 行"
    read -rp "继续？[y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }
fi

for t in "${TARGETS[@]}"; do
    b="$(latest_bak "$t")"
    if [ -n "$b" ]; then
        mv -f "$b" "$t" && ok "还原 ${t/#$HOME/\~}  ($(basename "$b"))"
    elif [ -e "$t" ]; then
        case "$t" in
            */hypr/config/*.lua)
                s="/etc/skel/.config/hypr/config/$(basename "$t")"
                if [ -f "$s" ]; then cp -a "$s" "$t" && ok "从 /etc/skel 还原官方原版 $(basename "$t")"
                else warn "无备份且 /etc/skel 也没有：$t —— 保持原样"; fi ;;
            *)
                rm -f "$t" && ok "删除（本包新建，无备份）${t/#$HOME/\~}" ;;
        esac
    fi
done

# hyprland.lua：只摘挂载那一行，文件本身是官方的
H="$HOME/.config/hypr/hyprland.lua"
if [ -f "$H" ] && grep -q '^require("mykeys")$' "$H"; then
    cp -a "$H" "$H.bak-uninstall-$(date +%Y%m%d-%H%M%S)"
    sed -i '/^require("mykeys")$/d' "$H"
    sed -i -e :a -e '/^\n*$/{$d;N;};/\n$/ba' "$H"   # 清掉尾部空行
    ok 'hyprland.lua 已移除 require("mykeys")'
fi

# nvim：整目录
N="$HOME/.config/nvim"
NB="$(latest_bak "$N")"
if [ -n "$NB" ]; then
    rm -rf "$N" && mv "$NB" "$N" && ok "还原 ~/.config/nvim/  ($(basename "$NB"))"
elif [ -d "$N" ]; then
    warn "~/.config/nvim/ 无备份 —— 未删除，需要的话自己 rm -rf"
fi

echo
ok "完成。注销重进 Hyprland 生效。"
inf "本包新建的这些没有动，不影响任何东西，想清就手动删："
inf "  ~/.config/kitty/themes/  ~/.config/gtk-4.0/noctalia.css"
inf "  ~/.local/state/noctalia/community-palettes/  ~/Pictures/Wallpapers/"
if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null 2>&1 && ok "已重载 Hyprland（应回到官方 81 条绑定）"
fi
