#!/usr/bin/env bash
# Claude Code 状态栏：模型 | 目录 | git 分支 | 上下文占比进度条 | 花费
# 输入：Claude Code 从 stdin 喂进来的会话 JSON

input=$(cat)

# 用 tab 分隔：模型名和目录路径都可能含空格，按空格切会整行错位
IFS=$'\t' read -r MODEL DIR PCT USED SIZE COST EFFORT < <(
  printf '%s' "$input" | jq -r '
    [ .model.display_name // "?"
    , .workspace.current_dir // .cwd // "?"
    , ((.context_window.used_percentage // 0) | floor)
    , ((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0))
    , (.context_window.context_window_size // 200000)
    , ((.cost.total_cost_usd // 0) * 100 | round / 100)
    , (.effort.level // "-")
    ] | @tsv'
)

# git 分支（不在仓库里就留空）
BRANCH=$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$BRANCH" ]; then
  # 有未提交改动加个 *
  git -C "$DIR" diff --quiet --ignore-submodules HEAD 2>/dev/null || BRANCH="${BRANCH}*"
  GIT=" \033[35m⎇ ${BRANCH}\033[0m"
else
  GIT=""
fi

# 进度条：10 格，按占比上色（绿 <50，黄 <75，红 >=75）
WIDTH=10
FILLED=$(( PCT * WIDTH / 100 ))
[ "$FILLED" -gt "$WIDTH" ] && FILLED=$WIDTH
[ "$FILLED" -lt 0 ] && FILLED=0
EMPTY=$(( WIDTH - FILLED ))

if   [ "$PCT" -lt 50 ]; then COLOR="\033[32m"
elif [ "$PCT" -lt 75 ]; then COLOR="\033[33m"
else                         COLOR="\033[31m"
fi

BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf '█%.0s' $(seq 1 $FILLED))
[ "$EMPTY"  -gt 0 ] && BAR="${BAR}$(printf '░%.0s' $(seq 1 $EMPTY))"

# token 数缩写成 k
fmt_k() { awk -v n="$1" 'BEGIN{ if (n>=1000) printf "%.0fk", n/1000; else printf "%d", n }'; }
USED_K=$(fmt_k "$USED")
SIZE_K=$(fmt_k "$SIZE")

printf "\033[2m[%s·%s]\033[0m \033[36m%s\033[0m%b │ %b%s %s%%\033[0m \033[2m%s/%s\033[0m \033[2m\$%s\033[0m\n" \
  "$MODEL" "$EFFORT" "${DIR##*/}" "$GIT" "$COLOR" "$BAR" "$PCT" "$USED_K" "$SIZE_K" "$COST"
