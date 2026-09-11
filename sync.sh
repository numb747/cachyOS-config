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

# ── pull / pack：重新生成 MANIFEST ──────────────────────────────────────────
cd "$SRC"
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
