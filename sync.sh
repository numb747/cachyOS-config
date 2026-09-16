#!/usr/bin/env bash
# ============================================================================
#  sync.sh —— 把「线上配置」和「包里的快照」对齐
#
#  install.sh 是 包 → 系统；本脚本是反方向 系统 → 包。
#  改完配置跑一下，包就跟上了，不用手动记得拷哪些文件。
#
#  用法：
#      ./sync.sh --check     只看哪些文件不一致（默认，不写任何东西）
#      ./sync.sh --diff      逐个打印差异内容
#      ./sync.sh --pull      把线上配置拉进包里，并重新生成 MANIFEST
#      ./sync.sh --pack      --pull 之后再打 tar.gz
#
#  单一事实来源：文件映射表 manifest.map（包内路径 ⇄ 系统路径）。
#  install.sh / uninstall.sh / 本脚本都读它，加一个文件只需改那一处。
# ============================================================================
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP="$SRC/manifest.map"
MODE=check

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
inf()  { printf '  %s%s%s\n' "$DIM" "$*" "$RST"; }
warn() { printf '%s!%s %s\n' "$YEL" "$RST" "$*"; }

for a in "$@"; do
    case "$a" in
        --check) MODE=check ;;
        --diff)  MODE=diff ;;
        --pull)  MODE=pull ;;
        --pack)  MODE=pack ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf '%s✗%s 未知参数：%s\n' "$RED" "$RST" "$a" >&2; exit 2 ;;
    esac
done

[ -f "$MAP" ] || { printf '%s✗%s 缺 %s\n' "$RED" "$RST" "$MAP" >&2; exit 1; }

DIFFER=0 MISSING=0 SAME=0

# ── #@nopull：这些文件【永远不从系统拉回包里】 ──────────────────────────────
# 包里存的是**模板**（含 /home/$USER 这类占位符），install.sh 安装时才改写成真路径。
# 拉回来就等于把本机路径写死进包，换机器直接废 —— 这个坑真发生过一次
# （qt6ct.conf 一度被写死成 /home/david，导致 install.sh 的 sed 匹配不到）。
# check/diff 里它们仍会显示为不一致，那是**预期状态**，不是待办事项。
NOPULL=""
while read -r tag val; do
    [ "$tag" = "#@nopull" ] && NOPULL="$NOPULL $val"
done < "$MAP"
is_nopull() { case " $NOPULL " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# manifest.map 每行：<包内相对路径>  <系统路径，可含 ~ 和 $HOME>
while read -r rel sys; do
    [ -z "${rel:-}" ] && continue
    case "$rel" in \#*) continue ;; esac
    sys="${sys/#\~/$HOME}"; sys="${sys//\$HOME/$HOME}"
    pkg="$SRC/$rel"

    if [ ! -e "$sys" ]; then
        warn "系统上不存在：${sys/#$HOME/\~}"; MISSING=$((MISSING+1)); continue
    fi
    if [ ! -e "$pkg" ]; then
        warn "包里不存在（新文件）：$rel"; DIFFER=$((DIFFER+1))
        [ "$MODE" = pull ] || [ "$MODE" = pack ] && { mkdir -p "$(dirname "$pkg")"; cp -a "$sys" "$pkg"; ok "已拉入 $rel"; }
        continue
    fi
    if cmp -s "$pkg" "$sys"; then SAME=$((SAME+1)); continue; fi

    DIFFER=$((DIFFER+1))
    NOTE=""; is_nopull "$rel" && NOTE="  ${DIM}[nopull · 预期不一致]${RST}"
    case "$MODE" in
        check) printf '%s≠%s %-46s %s%s\n' "$YEL" "$RST" "$rel" "${sys/#$HOME/\~}" "$NOTE" ;;
        diff)  printf '\n%s─── %s ───%s%s\n' "$YEL" "$rel" "$RST" "$NOTE"
               diff -u "$pkg" "$sys" | head -60 ;;
        pull|pack)
            if is_nopull "$rel"; then
                warn "跳过 $rel —— 标了 #@nopull，包里是模板，拉回来会写死本机路径"
            else
                cp -a "$sys" "$pkg"; ok "已更新 $rel"
            fi ;;
    esac
done < "$MAP"

echo
inf "一致 $SAME · 不一致 $DIFFER · 系统上缺失 $MISSING"

if [ "$MODE" = check ] || [ "$MODE" = diff ]; then
    [ $DIFFER -gt 0 ] && inf "把线上改动收进包里： ./sync.sh --pull"
    exit 0
fi

# ── pull / pack：hypr patch → 文档数字 → 最后才生成 MANIFEST ─────────────
# ★ 2026-09-12 调序：MANIFEST 必须是最后一步。原来它排在 patch 重生成和
#   文档数字对账之前，于是 --pull 跑完那一刻，被改写的 4 份文档在 MANIFEST
#   里已是陈旧哈希，`sha256sum -c` 当场就会失败 —— 和 2026-09-11 修掉的
#   「裸 find 导致 MANIFEST 生成完立刻过期」是同一个形状的 bug。
cd "$SRC"
# hypr 的四个官方文件改了的话，patch 也要跟着重生成
# （windowrules 是 2026-08-27 加的，为了企业微信的幽灵窗规则，见 docs/09）
if [ -d /etc/skel/.config/hypr/config ]; then
    for f in binds variables workspaces windowrules misc; do
        s="/etc/skel/.config/hypr/config/$f.lua"
        [ -f "$s" ] && [ -f "$SRC/config/hypr/config/$f.lua" ] || continue
        diff -u "$s" "$SRC/config/hypr/config/$f.lua" > "$SRC/config/hypr/patches/$f.lua.patch"
    done
    ok "config/hypr/patches/*.patch 已按当前 /etc/skel 重生成"
fi
# ── 文档里「能算出来的数字」统一对账重写 ──────────────────────────────────
# ★ 2026-09-12 加。这类数字没有任何机制提醒它陈旧，只能靠人记得改，而人不会记得。
#   一次对账查出 5 处过期：键位 118→124、ASCII 成品 4→8、壁纸库 167→348 MB、
#   claude/ 9→10 个文件、docs 230→203 KB。加上此前 MANIFEST 跟着裸 find 走、
#   hypr patch 文档只记 3 个实际 5 个，同类问题已是第七次 —— 形状完全一样：
#   某个数字由人维护，却没有任何东西会在它过期时报警。能算出来的就别让人记。
#   ⚠ 新增一条只要加一行 docnum，别再写独立的 sed 分支。
docnum() {   # docnum <包内文件> <ERE 正则> <替换式>
    # 用 # 作 sed 分隔符（文档里有 / 但没有 #），正则里因此不能带 #
    [ -f "$SRC/$1" ] && sed -i -E "s#$2#$3#g" "$SRC/$1"
}

# 自定义键位数只认**行首**的 hl.bind( —— mykeys.lua 里 48 处含 hl.bind 的行有
# 11 处在注释里（文件开头那段原理备忘），裸 grep -c 会数成 48 而不是 37。
MINE=$(grep -cE '^[[:space:]]*hl\.bind\(' "$SRC/config/hypr/mykeys.lua" 2>/dev/null || echo 0)
TOTAL=""
command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
    && TOTAL=$(hyprctl binds -j 2>/dev/null | jq length 2>/dev/null || echo "")
ASCII_N=$(ls "$SRC/wallpaper/ascii" 2>/dev/null | wc -l)
CLAUDE_N=$(ls "$SRC/claude" 2>/dev/null | wc -l)
DOCS_KB=$(cat "$SRC"/docs/*.md 2>/dev/null | wc -c | awk '{printf "%.0f", $1/1024}')
WALL_MB=$(du -sm "$HOME/Pictures/Wallpapers" 2>/dev/null | cut -f1)

if [ -n "$TOTAL" ] && [ "$TOTAL" -gt 0 ] 2>/dev/null; then
    docnum README.md       "[0-9]+ custom binds → [0-9]+ total" "$MINE custom binds → $TOTAL total"
    docnum README.zh-CN.md "[0-9]+ 条自定义绑定 → 共 [0-9]+ 条" "$MINE 条自定义绑定 → 共 $TOTAL 条"
else
    warn "hyprctl binds 读不到，键位数这次没同步（不在 Hyprland 会话里？）"
    TOTAL="skip"
fi
if [ "$ASCII_N" -gt 0 ] 2>/dev/null; then
    docnum README.md       "[0-9]+ rendered ASCII pieces" "$ASCII_N rendered ASCII pieces"
    docnum README.zh-CN.md "[0-9]+ 张 ASCII 成品"         "$ASCII_N 张 ASCII 成品"
    docnum INSTALL.md      "[0-9]+ 张 ASCII 成品"         "$ASCII_N 张 ASCII 成品"
fi
[ "$CLAUDE_N" -gt 0 ] 2>/dev/null && \
    docnum CLAUDE.md "[0-9]+ 个文件在 \`claude/\`" "$CLAUDE_N 个文件在 \`claude/\`"
[ -n "$DOCS_KB" ] && \
    docnum README.md "roughly [0-9]+ KB explaining" "roughly $DOCS_KB KB explaining"
# 壁纸全库在包外、随机器而异；取不到就跳过，不写入错数
if [ -n "$WALL_MB" ]; then
    docnum README.md       "library \([0-9]+ MB\)" "library ($WALL_MB MB)"
    docnum README.zh-CN.md "全库（[0-9]+ MB）"      "全库（$WALL_MB MB）"
    docnum INSTALL.md      "[0-9]+ MB。本包"        "$WALL_MB MB。本包"
fi
ok "文档数字已对账（键位 $MINE/$TOTAL · ASCII $ASCII_N · claude/ $CLAUDE_N · docs ${DOCS_KB}KB · 壁纸库 ${WALL_MB:-?}MB）"



{
  echo "# 文件清单与校验和（sha256）"
  echo "# 由 sync.sh 生成。核对包完整性："
  echo "#   grep -v '^#' MANIFEST.txt | sha256sum -c -"
  echo "#"
  echo "# 只覆盖【入库的文件】。.git/ 自身、.snapshots/ 快照、__pycache__、*.key 不计。"
  echo
  # ★ 2026-09-11：原来是裸 `find . -type f ! -name MANIFEST.txt`，把 .gitignore
  #   挡掉的东西全收了进来 —— 305 条里 163 条是 .git/ 内部对象，还有 secret-age.key、
  #   __pycache__、两个 2.7 MB 的 .snapshots/*.tar.gz。三重后果：
  #     ① 每次 commit 都改写 .git/，MANIFEST 生成完立刻过期；
  #     ② git 对象在别的机器上必然不同，`sha256sum -c` 在新机器上一定失败，
  #        正好废掉这个文件「核对包完整性」的唯一用途；
  #     ③ 上次提交时 docs/05-theme-ui.md 的哈希就已经是陈旧的，没人发现。
  #   改成跟着 git 索引走，.gitignore 以后新增条目也自动跟上，不用维护排除清单。
  #   -z 不可省：不带它 git 会把中文文件名输出成 "\347\264\253..." 转义形式，
  #   sha256sum 按那个名字找不到文件（wallpaper/ascii/ 下有 8 个中文名壁纸）。
  if git rev-parse --git-dir >/dev/null 2>&1; then
      git ls-files -z -- ':!MANIFEST.txt' | xargs -0 sha256sum
  else
      # 解压出来的 tar.gz 里没有 .git，退回 find 并手动排掉同样这些东西
      find . \( -path ./.git -o -path ./.snapshots -o -name __pycache__ \) -prune -o \
           -type f ! -name MANIFEST.txt ! -name '*.key' -printf '%P\n' \
           | LC_ALL=C sort | xargs sha256sum
  fi
} > MANIFEST.txt
ok "MANIFEST.txt 已重新生成（$(grep -c '^[0-9a-f]' MANIFEST.txt) 个文件）"

if [ "$MODE" = pack ]; then
    # ★ 仓库根就是包本身（没有中间层目录），所以不能像以前那样
    #   「tar 上一级目录里的那个包目录」——那会把整个 $HOME 的同级内容、
    #   以及 .git（历史越长越大）一起打进去，还把产物丢在 $HOME 下。
    #   改成：产物统一落在 .snapshots/，打包时显式排除 .git 与 .snapshots 自身。
    NAME="cachyos-desktop-config"
    mkdir -p "$SRC/.snapshots"
    OUT="$SRC/.snapshots/$NAME-$(date +%Y%m%d).tar.gz"
    # --transform 让解包后仍是 <NAME>/ 开头的目录，保持和旧快照一致的解压体验
    tar -czf "$OUT" -C "$SRC" \
        --exclude='./.git' --exclude='./.snapshots' \
        --transform "s#^\.#$NAME#" . 2>/dev/null
    ok "已打包 $OUT （$(du -h "$OUT" | cut -f1)）"
fi

echo
inf "别忘了：改动的「为什么」写进 docs/，不然下次就想不起来了"
