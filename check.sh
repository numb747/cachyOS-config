#!/usr/bin/env bash
# ============================================================================
#  check.sh —— 只读体检：把 CLAUDE.md 里「静默失败」那类坑变成机器检查
#
#  用法：
#      ./check.sh            全部检查，有 ✗ 就返回 1
#      ./check.sh -q         只打印有问题的项
#
#  为什么有它：这个仓库踩过的坑几乎全是同一个形状 —— 不报错、不警告，事后才发现
#  （MANIFEST 漏文件、文档数字过期、hl.dsp 参数名写错被静默忽略、mod_hypr 漏装文件……）。
#  以前的对策是把坑写进 CLAUDE.md 让下一个会话记住；能机器判定的就别靠记。
#
#  性质：不写任何文件、不读 $HOME 下的配置，只看仓库本身 —— 源机器和笔记本上都能跑，
#  结果也应该一样。（sync.sh 的默认模式查的是「系统 vs 包」，和这个是两回事。）
#
#  ✗ = 一定是错的，要修；! = 可疑或可选工具缺失，看一眼。
#  新增一条检查：照下面的样子写一个 chk_* 函数，加进末尾的列表。
# ============================================================================
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SRC" || exit 2
QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
ERRS=0 WARNS=0
ok()   { [ $QUIET -eq 1 ] || printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
inf()  { printf '  %s%s%s\n' "$DIM" "$*" "$RST"; }
warn() { printf '%s!%s %s\n' "$YEL" "$RST" "$*"; WARNS=$((WARNS+1)); }
bad()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*"; ERRS=$((ERRS+1)); }
head_() { [ $QUIET -eq 1 ] || printf '\n%s── %s%s\n' "$DIM" "$*" "$RST"; }

git rev-parse --git-dir >/dev/null 2>&1 || { bad "不在 git 仓库里 —— 本脚本的检查都以 git 索引为准"; exit 1; }

# 入库文件清单（-z：wallpaper/ascii/ 下有中文文件名，不带 -z 会被转义成 \347...）
mapfile -d '' TRACKED < <(git ls-files -z)
is_tracked() { git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }

# ── 1. 语法 ────────────────────────────────────────────────────────────────
chk_syntax() {
    head_ "语法（bash -n · luac -p · python ast）"
    local f first n=0 fail=0
    for f in "${TRACKED[@]}"; do
        [ -f "$f" ] || continue
        case "$f" in
            *.lua)
                command -v luac >/dev/null 2>&1 || continue
                n=$((n+1)); luac -p "$f" 2>/dev/null || { bad "Lua 语法错误：$f"; luac -p "$f" 2>&1 | sed 's/^/    /'; fail=1; } ;;
            *.py)
                n=$((n+1)); python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1],"rb").read())' "$f" 2>/dev/null \
                    || { bad "Python 语法错误：$f"; fail=1; } ;;
            *)
                IFS= read -r first < "$f" 2>/dev/null || continue
                case "$first" in
                    '#!'*bash*|'#!'*/sh) n=$((n+1)); bash -n "$f" 2>/dev/null || { bad "shell 语法错误：$f"; bash -n "$f" 2>&1 | sed 's/^/    /'; fail=1; } ;;
                    '#!'*python*)        n=$((n+1)); python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1],"rb").read())' "$f" 2>/dev/null \
                                             || { bad "Python 语法错误：$f"; fail=1; } ;;
                esac ;;
        esac
    done
    command -v luac >/dev/null 2>&1 || warn "没有 luac，跳过 Lua 语法（pacman -S lua）"
    [ $fail -eq 0 ] && ok "$n 个脚本/配置语法通过"
}

# ── 2. MANIFEST ⇄ git 索引 ─────────────────────────────────────────────────
# 坑：没 git add 的文件 MANIFEST 看不见且不报错（2026-09-18 tabby.lua）；
#     MANIFEST 生成完被别的步骤改了文件，哈希当场过期（2026-09-12 调序）。
chk_manifest() {
    head_ "MANIFEST.txt ⇄ git 索引"
    [ -f MANIFEST.txt ] || { bad "缺 MANIFEST.txt"; return; }
    local missing extra failed
    # core.quotePath=false：否则中文文件名输出成 "\347..." 带引号的转义，和 MANIFEST 对不上；
    # comm 也要 LC_ALL=C，排序规则必须和 sort 一致，不然它报 not in sorted order 然后乱比
    local in_git in_man
    in_git="$(git -c core.quotePath=false ls-files -- ':!MANIFEST.txt' | LC_ALL=C sort)"
    in_man="$(grep -v '^#' MANIFEST.txt | grep . | sed 's/^[0-9a-f]\{64\}  //' | LC_ALL=C sort)"
    missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$in_git") <(printf '%s\n' "$in_man"))"
    extra="$(LC_ALL=C comm -13 <(printf '%s\n' "$in_git") <(printf '%s\n' "$in_man"))"
    failed="$(grep -v '^#' MANIFEST.txt | grep . | sha256sum -c --quiet 2>/dev/null | sed 's/: FAILED.*//')"
    [ -n "$missing" ] && { bad "入库了但 MANIFEST 里没有："; printf '%s\n' "$missing" | sed 's/^/    /'; }
    [ -n "$extra" ]   && { bad "MANIFEST 里有但已不在 git 索引："; printf '%s\n' "$extra" | sed 's/^/    /'; }
    [ -n "$failed" ]  && { bad "哈希对不上（改了文件没重新生成 MANIFEST）："; printf '%s\n' "$failed" | sed 's/^/    /'; }
    if [ -z "$missing$extra$failed" ]; then
        ok "MANIFEST 与 git 索引一致（$(git ls-files | grep -vcx MANIFEST.txt) 个文件，哈希全对）"
    else
        inf "重新生成：源机器 ./sync.sh --pull；笔记本 ./sync.sh --manifest"
    fi
    local u
    u="$(git -c core.quotePath=false ls-files --others --exclude-standard)"
    if [ -n "$u" ]; then
        warn "未跟踪、也没被 .gitignore 挡掉的文件（MANIFEST 和 --pack 都看不见它们）："
        printf '%s\n' "$u" | sed 's/^/    /'
    fi
}

# ── 3. manifest.map ⇄ 仓库 ⇄ install.sh ────────────────────────────────────
# 坑：模块在 manifest.map 里有、install.sh 里没人 put_module 它 —— sync.sh 收得进来，
#     install.sh 永远装不出去（mod_hypr 硬编码 put 时连着漏过三次）。
chk_map() {
    head_ "manifest.map ⇄ 仓库 ⇄ install.sh"
    local rel sys cur="" fail=0 m
    declare -A seen_sys=() mods=() entries=()
    local nopulls=()
    while read -r rel sys; do
        case "$rel" in
            '#@module') cur="$sys"; mods[$cur]=1; continue ;;
            '#@nopull') nopulls+=("$sys"); continue ;;
            \#*|'') continue ;;
        esac
        entries[$rel]=1
        # nvim 模块是 mod_nvim 整目录 cp config/nvim/，不走 put_module —— 所以这一段
        # 只能放 config/nvim/ 下的文件，放别处的东西会被 sync.sh 收、却没人装
        if [ "$cur" = nvim ] && [ "${rel#config/nvim/}" = "$rel" ]; then
            bad "manifest.map：$rel 在 nvim 段，但 mod_nvim 只整目录复制 config/nvim/，它装不出去"; fail=1
        fi
        [ -n "$cur" ] || { bad "manifest.map：$rel 在第一个 #@module 之前，install.sh 永远不会装它"; fail=1; }
        if [ ! -e "$rel" ]; then bad "manifest.map 引用的包内文件不存在：$rel"; fail=1
        elif ! is_tracked "$rel"; then bad "manifest.map 引用的文件没入库（git add）：$rel"; fail=1
        fi
        if [ -n "${seen_sys[$sys]:-}" ]; then bad "两条映射装到同一个目标：$sys（$rel 和 ${seen_sys[$sys]}）"; fail=1; fi
        seen_sys[$sys]="$rel"
    done < manifest.map
    for rel in "${nopulls[@]}"; do
        [ -n "${entries[$rel]:-}" ] || { bad "#@nopull $rel 不对应任何映射条目（写错了路径？）"; fail=1; }
    done
    local all
    all="$(sed -n 's/^ALL=(\(.*\))$/\1/p' install.sh)"
    for m in "${!mods[@]}"; do
        case " $all " in *" $m "*) ;; *) bad "#@module $m 不在 install.sh 的 ALL=(…) 里，这个模块装不出去"; fail=1 ;; esac
        [ "$m" = nvim ] && continue   # 见上：整目录复制
        grep -qE "^[[:space:]]*put_module $m([[:space:]]|$)" install.sh \
            || { bad "install.sh 里没有 put_module $m —— manifest.map 的 $m 段不会被安装"; fail=1; }
    done
    [ $fail -eq 0 ] && ok "${#entries[@]} 条映射、${#mods[@]} 个模块：文件都在且已入库，每个模块都有 put_module"
}

# ── 4. hl.dsp 参数名白名单 ─────────────────────────────────────────────────
# 坑 8：hl.dsp.* 对不认识的参数键【静默忽略】，stub 里全是 fun(...) 查不到类型。
#   函数名：从 Hyprland 自带的 stub 自动取（升级后自动跟上）。
#   参数名：stub 里没有，只能用「本仓库实测生效过的」做白名单。新参数先实测确认生效，
#           再加进下面的 ALLOWED；不在表里的一律报出来 —— 宁可多问一句，不要静默失效。
chk_hl_dsp() {
    local stub=/usr/share/hypr/stubs/hl.meta.lua
    local files=()
    local f
    for f in "${TRACKED[@]}"; do case "$f" in config/hypr/*.lua) files+=("$f") ;; esac; done
    python3 -I - "$stub" "${files[@]}" <<'PY'
import os, re, sys

# 实测生效的参数名（出处：mykeys.lua 各节注释 / CLAUDE.md 坑 8）。新增前先实测。
ALLOWED = {
    "focus":                   {"workspace", "direction", "monitor", "window"},
    "window.move":             {"workspace", "direction", "monitor", "window", "follow"},
    "window.fullscreen":       {"mode"},
    "window.fullscreen_state": {"internal", "client"},
    "window.float":            {"action"},
}
# 已知写错的名字 → 正确写法（都是实测踩过的）
KNOWN_WRONG = {
    "silent": "不叫 silent，「不跟过去」是 follow = false（mykeys.lua 第 10 节约束 3）",
    "quiet":  "无效，「不跟过去」是 follow = false",
}

stub, files = sys.argv[1], sys.argv[2:]
funcs = None
if os.path.exists(stub):
    funcs, cls = set(), None
    for line in open(stub, encoding="utf-8"):
        m = re.match(r"---@class HL\.Dsp(\w*)Namespace", line)
        if m:
            cls = m.group(1).lower(); continue
        if line.startswith("---@class"):
            cls = None; continue
        m = re.match(r"---@field (\w+) fun\(", line)
        if m and cls is not None:
            funcs.add(f"{cls}.{m.group(1)}" if cls else m.group(1))

def strip_comments(src):
    """把 Lua 注释换成空格（保留换行，行号不变）；字符串原样保留。"""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = src.find("\n", i); end = n if end < 0 else end
            out.append(re.sub(r"[^\n]", " ", src[i:end])); i = end; continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            end = src.find("]" + m.group(1) + "]", i)
            end = n if end < 0 else end + len(m.group(1)) + 2
            out.append(src[i:end]); i = end; continue
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j+1]); i = j + 1; continue
        out.append(c); i += 1
    return "".join(out)

def balanced(code, i, open_, close):
    """code[i] == open_，返回匹配的 close 的下标（跳过字符串）。"""
    depth, n = 0, len(code)
    while i < n:
        c = code[i]
        if c in "\"'":
            j = i + 1
            while j < n and code[j] != c:
                j += 2 if code[j] == "\\" else 1
            i = j + 1; continue
        if c == open_: depth += 1
        elif c == close:
            depth -= 1
            if depth == 0: return i
        i += 1
    return -1

def top_keys(tbl):
    """{ a = 1, b = { c = 2 } } 的顶层键 → ['a', 'b']"""
    keys, depth, i, n = [], 0, 1, len(tbl) - 1
    while i < n:
        c = tbl[i]
        if c in "\"'":
            j = i + 1
            while j < n and tbl[j] != c:
                j += 2 if tbl[j] == "\\" else 1
            i = j + 1; continue
        if c in "{([": depth += 1
        elif c in "})]": depth -= 1
        elif depth == 0:
            m = re.match(r"([A-Za-z_]\w*)\s*=(?!=)", tbl[i:])
            if m and (i == 1 or not (tbl[i-1].isalnum() or tbl[i-1] == "_")):
                keys.append(m.group(1)); i += m.end(); continue
        i += 1
    return keys

errs = calls = 0
for path in files:
    code = strip_comments(open(path, encoding="utf-8").read())
    for m in re.finditer(r"hl\.dsp\.([A-Za-z_][\w.]*)\s*\(", code):
        name, line = m.group(1), code.count("\n", 0, m.start()) + 1
        where = f"{path}:{line}"
        calls += 1
        if funcs is not None and name not in funcs:
            print(f"✗ {where}  hl.dsp.{name} 不在 Hyprland stub 里（拼错了？）"); errs += 1
        close = balanced(code, m.end() - 1, "(", ")")
        arg = code[m.end():close].strip() if close > 0 else ""
        if name == "workspace.toggle_special":
            if arg.startswith("{"):
                print(f"✗ {where}  toggle_special 收裸字符串，传 table 会静默退回默认工作区"); errs += 1
            if re.match(r"""["']special:""", arg):
                print(f"✗ {where}  toggle_special 的参数不带 special: 前缀（mykeys.lua 约束 1）"); errs += 1
        if not arg.startswith("{"):
            continue
        tbl_end = balanced(arg, 0, "{", "}")
        for k in top_keys(arg[:tbl_end + 1]):
            if k in ALLOWED.get(name, set()):
                continue
            hint = KNOWN_WRONG.get(k) or (
                f"不在 hl.dsp.{name} 的已验证参数里（{', '.join(sorted(ALLOWED[name]))}）"
                if name in ALLOWED else f"hl.dsp.{name} 还没有任何已验证的参数")
            print(f"✗ {where}  hl.dsp.{name} 的参数 `{k}`：{hint}"); errs += 1
if funcs is None:
    print(f"! 没有 {stub}，函数名没核（只核了参数名）")
print(f"__SUMMARY__ {calls} {errs}")
sys.exit(1 if errs else 0)
PY
    local rc=$?
    return $rc
}
run_hl_dsp() {
    head_ "hl.dsp 调用（函数名对 stub、参数名对白名单）"
    local out line calls errs
    out="$(chk_hl_dsp)"
    while IFS= read -r line; do
        case "$line" in
            __SUMMARY__*) read -r _ calls errs <<<"$line" ;;
            '✗ '*) bad "${line#✗ }" ;;
            '! '*) warn "${line#! }" ;;
            *) [ -n "$line" ] && printf '%s\n' "$line" ;;
        esac
    done <<<"$out"
    if [ "${errs:-1}" -eq 0 ]; then
        ok "${calls:-0} 处 hl.dsp 调用，函数名和参数名都在已知范围内"
    else
        inf "参数名确认实测生效后，加进 check.sh 的 ALLOWED 表"
    fi
}

# ── 5. 文档数字 ────────────────────────────────────────────────────────────
# 表只有一份，在 sync.sh 的 docnums 里；这里调它的只读模式，不另抄一份（抄的那份也会过期）
chk_docs() {
    head_ "文档里能算出来的数字"
    local out rc line
    out="$("$SRC/sync.sh" --docs 2>&1)"; rc=$?
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')"
        case "$line" in
            '✓ '*) ok "${line#✓ }" ;;
            '! '*) bad "${line#! }" ;;
            *) [ -n "$line" ] && printf '%s\n' "$line" ;;
        esac
    done <<<"$out"
    [ $rc -eq 0 ] || inf "源机器 ./sync.sh --pull 会自动改写；只由仓库决定的数字（文件数、插件数）手改也行"
}

# ── 6. 凭据 ────────────────────────────────────────────────────────────────
# CLAUDE.md「边界」那条 grep 的入库文件版。正则比那条严：要求后面真跟着一段密钥字符，
# 否则会命中 CLAUDE.md 里那条 grep 命令本身、INSTALL.md 里的 jq 示例。
chk_secrets() {
    head_ "凭据扫描（入库文件）"
    local hits
    hits="$(git grep -nIE 'sk-[A-Za-z0-9_-]{20,}|AIzaSy[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[Aa][Uu][Tt][Hh]_?[Tt][Oo][Kk][Ee][Nn]["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9._-]{16,}' -- ':!MANIFEST.txt' 2>/dev/null)"
    if [ -n "$hits" ]; then
        bad "疑似凭据进了 git："; printf '%s\n' "$hits" | cut -c1-160 | sed 's/^/    /'
    else
        ok "没有疑似凭据"
    fi
}

# ── 7. 可选 lint（只报真 bug，不管风格）────────────────────────────────────
# shellcheck 只看 error 级；ruff 只开 F（pyflakes：未定义名、未用的 import/变量）。
# 风格类（一行多语句、行太长）这个仓库是有意为之，不报。这一节只给 !，不给 ✗。
chk_lint() {
    head_ "可选 lint（shellcheck -S error · ruff F）"
    local sh=() py=() f first
    for f in "${TRACKED[@]}"; do
        [ -f "$f" ] || continue
        case "$f" in *.py) py+=("$f"); continue ;; *.*) case "$f" in *.sh) ;; *) continue ;; esac ;; esac
        IFS= read -r first < "$f" 2>/dev/null || continue
        case "$first" in '#!'*bash*|'#!'*/sh) sh+=("$f") ;; '#!'*python*) py+=("$f") ;; esac
    done
    if command -v shellcheck >/dev/null 2>&1; then
        local out; out="$(shellcheck -S error "${sh[@]}" 2>&1)"
        [ -z "$out" ] && ok "shellcheck：${#sh[@]} 个脚本无 error" \
                      || { warn "shellcheck 报 error："; printf '%s\n' "$out" | sed 's/^/    /'; }
    else
        inf "没有 shellcheck，跳过（pacman -S shellcheck）"
    fi
    local ruff; ruff="$(command -v ruff || ls "$HOME"/.local/share/nvim/mason/bin/ruff 2>/dev/null)"
    if [ -n "$ruff" ]; then
        local out; out="$("$ruff" check --no-cache --quiet --select F --output-format concise "${py[@]}" 2>&1)"
        [ -z "$out" ] && ok "ruff F：${#py[@]} 个 Python 文件干净" \
                      || { warn "ruff（pyflakes）："; printf '%s\n' "$out" | sed 's/^/    /'; }
    else
        inf "没有 ruff，跳过"
    fi
}

chk_syntax
chk_manifest
chk_map
run_hl_dsp
chk_docs
chk_secrets
chk_lint

echo
if [ $ERRS -eq 0 ]; then
    printf '%s✓%s 体检通过（%d 条提示）\n' "$GRN" "$RST" "$WARNS"
else
    printf '%s✗%s %d 处问题、%d 条提示 —— 往上翻红色的 ✗\n' "$RED" "$RST" "$ERRS" "$WARNS"
fi
exit $(( ERRS > 0 ))
