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
#      ./sync.sh --docs      只核对文档数字是否过期（不写任何东西，check.sh 调它）
#      ./sync.sh --manifest  只重新生成 MANIFEST（不读系统文件，笔记本上也能跑）
#
#  单一事实来源：文件映射表 manifest.map（包内路径 ⇄ 系统路径）。
#  install.sh / uninstall.sh / 本脚本都读它，加一个文件只需改那一处。
# ============================================================================
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP="$SRC/manifest.map"
MODE=check
FAILED=0

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
inf()  { printf '  %s%s%s\n' "$DIM" "$*" "$RST"; }
warn() { printf '%s!%s %s\n' "$YEL" "$RST" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*" >&2; FAILED=1; }

for a in "$@"; do
    case "$a" in
        --check) MODE=check ;;
        --diff)  MODE=diff ;;
        --pull)  MODE=pull ;;
        --pack)  MODE=pack ;;
        --docs)  MODE=docs ;;
        --manifest) MODE=manifest ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf '%s✗%s 未知参数：%s\n' "$RED" "$RST" "$a" >&2; exit 2 ;;
    esac
done

[ -f "$MAP" ] || { printf '%s✗%s 缺 %s\n' "$RED" "$RST" "$MAP" >&2; exit 1; }

# ── 文档里「能算出来的数字」统一对账 ──────────────────────────────────────
# ★ 2026-09-12 加。这类数字没有任何机制提醒它陈旧，只能靠人记得改，而人不会记得。
#   一次对账查出 5 处过期：键位 118→124、ASCII 成品 4→8、壁纸库 167→348 MB、
#   claude/ 9→10 个文件、docs 230→203 KB。加上此前 MANIFEST 跟着裸 find 走、
#   hypr patch 文档只记 3 个实际 5 个，同类问题已是第七次 —— 形状完全一样：
#   某个数字由人维护，却没有任何东西会在它过期时报警。能算出来的就别让人记。
#   ⚠ 新增一条只要在 docnums 里加一行 docnum，别再写独立的 sed 分支。
# ★ 2026-10-10 抽成函数，两种模式共用这一张表（--pull 改写；--docs 只比对，check.sh 调它）。
#   不另抄一份表给检查用：检查表自己也会过期，那就又是同一个 bug。
DOCS_STALE=0
docnum() {   # docnum <包内文件> <ERE 正则> <替换式>
    # 用 # 作 sed 分隔符（文档里有 / 但没有 #），正则里因此不能带 #
    local f="$SRC/$1"
    [ -f "$f" ] || { warn "docnum：$1 不存在"; DOCS_STALE=1; return 0; }
    # ★ 2026-10-10：一处都匹配不到时以前是静默 no-op —— 有人改了文档措辞，
    #   这个数字就从此再也不会被对账，而且没有任何提示。现在报出来。
    if ! grep -qE "$2" "$f"; then
        warn "docnum 没匹配到（文档措辞改了？这个数字从此不会再对账）：$1 ⇐ /$2/"
        DOCS_STALE=1; return 0
    fi
    if [ "$MODE" = docs ]; then
        local old new
        old="$(grep -oE "$2" "$f" | sort -u | paste -sd '|')"
        new="$(grep -oE "$2" "$f" | sed -E "s#$2#$3#" | sort -u | paste -sd '|')"
        [ "$old" = "$new" ] || { warn "$1 数字过期：「$old」→ 应为「$new」"; DOCS_STALE=1; }
    else
        sed -i -E "s#$2#$3#g" "$f"
    fi
}

docnums() {
    # 自定义键位数只认**行首**的 hl.bind( —— mykeys.lua 里 49 处含 hl.bind 的行有
    # 11 处在注释里（文件开头那段原理备忘），裸 grep -c 会数成 49 而不是 38。
    # ⚠ grep -c 零匹配时会输出 0 **并且**返回 1，再 `|| echo 0` 就成了两行 "0\n0"
    local MINE TOTAL="" ASCII_N CLAUDE_N DOCS_KB DOCS_N WALL_MB=""
    MINE=$(grep -cE '^[[:space:]]*hl\.bind\(' "$SRC/config/hypr/mykeys.lua" 2>/dev/null)
    MINE=${MINE:-0}
    # 键位总数和壁纸库体积取决于【本机状态】（活的 Hyprland、~/Pictures），
    # 只读核对时跳过 —— 笔记本的壁纸库只拉了一部分，拿它去比只会误报。
    if [ "$MODE" != docs ]; then
        command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
            && TOTAL=$(hyprctl binds -j 2>/dev/null | jq length 2>/dev/null || echo "")
        WALL_MB=$(du -sm "$HOME/Pictures/Wallpapers" 2>/dev/null | cut -f1)
    fi
    # ★ 2026-10-10：文件数改跟 git 索引走（同 MANIFEST）。裸 ls 会把 __pycache__ 和
    #   还没 git add 的文件也数进去。上面那句「claude/ 9→10」其实就是这么来的：
    #   写下 10 的那个提交（376d442）里 git 只有 9 个文件，是 ls 多数了一个，
    #   对账把对的数字「修」成了错的。非 git 环境退回 ls 并排掉 __pycache__。
    if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
        ASCII_N=$(git -C "$SRC" ls-files -- wallpaper/ascii | wc -l)
        CLAUDE_N=$(git -C "$SRC" ls-files -- claude | wc -l)
    else
        ASCII_N=$(ls "$SRC/wallpaper/ascii" 2>/dev/null | wc -l)
        CLAUDE_N=$(ls "$SRC/claude" 2>/dev/null | grep -vc __pycache__)
    fi
    DOCS_KB=$(cat "$SRC"/docs/*.md 2>/dev/null | wc -c | awk '{printf "%.0f", $1/1024}')
    DOCS_N=$(ls "$SRC"/docs/*.md 2>/dev/null | wc -l)

    if [ -n "$TOTAL" ] && [ "$TOTAL" -gt 0 ] 2>/dev/null; then
        docnum README.md       "[0-9]+ custom binds → [0-9]+ total" "$MINE custom binds → $TOTAL total"
        docnum README.zh-CN.md "[0-9]+ 条自定义绑定 → 共 [0-9]+ 条" "$MINE 条自定义绑定 → 共 $TOTAL 条"
        # ★ 2026-09-23 加。CLAUDE.md「现状」段也记着这两个数，却一直不在对账表里，
        #   于是第 18 节把自定义数加到 38 之后它还写着 37（总数 124 没变 —— SUPER+V 是
        #   unbind + bind，净增 0，正好让「总数对得上」掩护了自定义数的过期）。
        docnum CLAUDE.md "Hyprland 绑定 \*\*[0-9]+\*\* 条（自定义 [0-9]+ 条）" \
                         "Hyprland 绑定 **$TOTAL** 条（自定义 $MINE 条）"
    else
        # 总数取不到时，自定义数照样能核：只替换自定义那一半，总数原样保留
        docnum README.md       "([0-9]+) custom binds → ([0-9]+) total" "$MINE custom binds → \\2 total"
        docnum README.zh-CN.md "([0-9]+) 条自定义绑定 → 共 ([0-9]+) 条" "$MINE 条自定义绑定 → 共 \\2 条"
        docnum CLAUDE.md "Hyprland 绑定 \*\*([0-9]+)\*\* 条（自定义 ([0-9]+) 条）" \
                         "Hyprland 绑定 **\\1** 条（自定义 $MINE 条）"
        [ "$MODE" = docs ] || warn "hyprctl binds 读不到，键位总数这次没同步（不在 Hyprland 会话里？）"
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
    # ★ 2026-09-28 加。docs/ 篇数写在四处，加 docs/12-waydroid.md 时发现不在对账表里。
    if [ "$DOCS_N" -gt 0 ] 2>/dev/null; then
        docnum README.md       "The [0-9]+ documents under"   "The $DOCS_N documents under"
        docnum README.md       "[0-9]+ documents, see the"    "$DOCS_N documents, see the"
        docnum README.zh-CN.md "[0-9]+ 篇说明，见上表"        "$DOCS_N 篇说明，见上表"
        docnum CLAUDE.md       "[0-9]+ 篇，见下表"            "$DOCS_N 篇，见下表"
    fi
    # ★ 2026-10-10 加。nvim 插件数原来注明「不在对账表里，要手改」，结果没人改：
    #   CLAUDE.md 写 47/48、docs/04 写 46/47，lazy-lock.json 里实际是 55 个。
    #   锁的数 = lockfile 条目数；装的数 = 锁 − disabled.lua 里 enabled = false 的条数
    #   （差额就是那里主动关掉的插件，见 docs/04 开头）。
    local LOCK_N OFF_N
    LOCK_N=$(grep -c '": {' "$SRC/config/nvim/lazy-lock.json" 2>/dev/null)
    OFF_N=$(grep -c 'enabled = false' "$SRC/config/nvim/lua/plugins/disabled.lua" 2>/dev/null)
    if [ "${LOCK_N:-0}" -gt 0 ] 2>/dev/null; then
        local INST_N=$((LOCK_N - ${OFF_N:-0}))
        docnum CLAUDE.md          "nvim \*\*[0-9]+ 装 / [0-9]+ 锁\*\*" "nvim **$INST_N 装 / $LOCK_N 锁**"
        docnum docs/04-neovim.md  "[0-9]+ 装 / [0-9]+ 锁不是 bug"      "$INST_N 装 / $LOCK_N 锁不是 bug"
    fi
    # 壁纸全库在包外、随机器而异；取不到就跳过，不写入错数
    if [ -n "$WALL_MB" ]; then
        docnum README.md       "library \([0-9]+ MB\)" "library ($WALL_MB MB)"
        docnum README.zh-CN.md "全库（[0-9]+ MB）"      "全库（$WALL_MB MB）"
        docnum INSTALL.md      "[0-9]+ MB。本包"        "$WALL_MB MB。本包"
    fi
    if [ "$MODE" = docs ]; then
        [ $DOCS_STALE -eq 0 ] && ok "文档数字全部是最新的（键位总数、壁纸库体积取决于本机，未核）"
    else
        ok "文档数字已对账（键位 $MINE/$TOTAL · ASCII $ASCII_N · claude/ $CLAUDE_N · docs ${DOCS_N} 篇 ${DOCS_KB}KB · 壁纸库 ${WALL_MB:-?}MB）"
    fi
}

# ── MANIFEST：最后一步，--pull / --pack / --manifest 共用 ─────────────────
gen_manifest() {
    cd "$SRC" || return 1
    # ★ 2026-10-10：MANIFEST 和 --pack 都只认 git 索引，没 git add 的文件两边都【看不见，且不报错】
    #   （2026-09-18 加 tabby.lua 时踩过：MANIFEST 142 条里没有它，sha256sum -c 照样全过）。
    #   上面「包里不存在（新文件）」那条分支拉进来的文件正好全是未跟踪的，在这里拦一下。
    if git rev-parse --git-dir >/dev/null 2>&1; then
        UNTRACKED="$(git ls-files --others --exclude-standard)"
        if [ -n "$UNTRACKED" ]; then
            warn "这些文件还没 git add —— MANIFEST 和 tar.gz 都不会包含它们："
            printf '%s\n' "$UNTRACKED" | while read -r u; do inf "$u"; done
            inf "确认要入库就 git add 之后再跑一次本脚本；不要的话删掉或加进 .gitignore"
        fi
    fi

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
               -type f ! -name MANIFEST.txt ! -name '*.key' -printf '%P\0' \
               | LC_ALL=C sort -z | xargs -0 sha256sum
      fi
    } > MANIFEST.txt
    N_MAN=$(grep -c '^[0-9a-f]' MANIFEST.txt)
    ok "MANIFEST.txt 已重新生成（$N_MAN 个文件）"
    # 索引里有、磁盘上已删的文件，sha256sum 只往 stderr 报一句就跳过，条数会悄悄变少
    if git rev-parse --git-dir >/dev/null 2>&1; then
        N_GIT=$(git ls-files -- ':!MANIFEST.txt' | wc -l)
        [ "$N_MAN" -eq "$N_GIT" ] \
            || err "MANIFEST 只有 $N_MAN 条，git 索引有 $N_GIT 个文件 —— 有文件删了没 git rm？（git status 看）"
    fi
}

if [ "$MODE" = docs ]; then
    docnums
    exit $DOCS_STALE
fi
# ★ 2026-10-10 加。只重算 MANIFEST，不碰系统文件、不重生成 patch、不改文档。
#   给不能跑 --pull 的笔记本用（docs/11）：以前那边改了包内文件，MANIFEST 就只能一直过期着。
if [ "$MODE" = manifest ]; then
    gen_manifest
    exit $FAILED
fi

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
        if [ "$MODE" = pull ] || [ "$MODE" = pack ]; then
            mkdir -p "$(dirname "$pkg")" && cp -a "$sys" "$pkg" && ok "已拉入 $rel" || err "拉入失败：$rel"
        fi
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
                # ★ 2026-10-10：原来是 `cp …; ok`，cp 失败照样打 ✓ —— install.sh 的 put
                #   在 2026-08-26 修过一模一样的 bug，这边一直漏着
                cp -a "$sys" "$pkg" && ok "已更新 $rel" || err "更新失败：$rel"
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
# hypr 的五个官方文件改了的话，patch 也要跟着重生成
# （windowrules 是 2026-08-27 为企业微信幽灵窗加的；2026-10-09 wine 卸载后规则已删，文件仍有零星改动）
if [ -d /etc/skel/.config/hypr/config ]; then
    for f in binds variables workspaces windowrules misc; do
        s="/etc/skel/.config/hypr/config/$f.lua"
        [ -f "$s" ] && [ -f "$SRC/config/hypr/config/$f.lua" ] || continue
        diff -u "$s" "$SRC/config/hypr/config/$f.lua" > "$SRC/config/hypr/patches/$f.lua.patch"
    done
    ok "config/hypr/patches/*.patch 已按当前 /etc/skel 重生成"
fi
docnums

gen_manifest

if [ "$MODE" = pack ]; then
    # ★ 仓库根就是包本身（没有中间层目录），所以不能像以前那样
    #   「tar 上一级目录里的那个包目录」——那会把整个 $HOME 的同级内容、
    #   以及 .git（历史越长越大）一起打进去，还把产物丢在 $HOME 下。
    #   产物统一落在 .snapshots/。
    # ★ 2026-10-10：文件清单改跟 git 索引走（同 MANIFEST）。原来是 tar 整个目录、只排
    #   .git 和 .snapshots，于是 .gitignore 挡掉的东西全进了包：aur/ 下 makepkg 的源码树、
    #   .onnx 模型、成品包（笔记本上实测未压缩 159 MB，正常应是几 MB），以及 *.key ——
    #   源机器仓库里有 secret-age.key（2026-09-11 那次 MANIFEST 修复里列出过）。
    #   和 2026-09-11 修掉的 MANIFEST 裸 find 是同一个 bug，当时只修了一半。
    NAME="cachyos-desktop-config"
    mkdir -p "$SRC/.snapshots"
    OUT="$SRC/.snapshots/$NAME-$(date +%Y%m%d).tar.gz"
    # --transform 让解包后仍是 <NAME>/ 开头的目录，保持和旧快照一致的解压体验
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git ls-files -z | tar -czf "$OUT" -C "$SRC" --null -T - --transform "s#^#$NAME/#"
    else
        find . \( -path ./.git -o -path ./.snapshots -o -name __pycache__ \) -prune -o \
             -type f ! -name '*.key' -printf '%P\0' \
             | tar -czf "$OUT" -C "$SRC" --null -T - --transform "s#^#$NAME/#"
    fi || { err "打包失败：$OUT"; rm -f "$OUT"; exit 1; }
    ok "已打包 $OUT （$(du -h "$OUT" | cut -f1)）"
fi

echo
inf "别忘了：改动的「为什么」写进 docs/，不然下次就想不起来了"
exit $FAILED
