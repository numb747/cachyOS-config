#!/usr/bin/env bash
# Agent Teams 团队日志：谁给谁发了什么、谁停下了、任务建了/完成了。
#
# 两种用法：
#   team-log.sh --hook         钩子调用：stdin 的 JSON 追加一行到 ~/.claude/team-logs/<日期>.jsonl
#                              由 settings.json 的 PostToolUse(SendMessage) / TeammateIdle /
#                              TaskCreated / TaskCompleted 调用，见 docs/14-tmux.md 第 7 节
#   手动看（终端里直接跑）     team-log.sh          今天的日志，人读格式
#                              team-log.sh -f       跟随（开个 tmux 窗格当「团队频道」）
#                              team-log.sh -r       原始 JSON（字段名以这个为准）
#
# 为什么要它：队员之间直接发的消息【队长看不到】，窗格一关信箱文件也随会话删掉。
# 钩子收到的字段文档没写全，所以记录时把 stdin 原样存下，只加一个时间戳。
# 实测字段（2026-10-11，2.1.296）：队员的 SendMessage 带 agent_type（角色名）但没有队员名，
# 发送方要从 tool_response.routing.sender 取；队长发的没有 agent_type；
# TeammateIdle 带 teammate_name / team_name。

DIR="$HOME/.claude/team-logs"
LOG="$DIR/$(date +%F).jsonl"

pretty() {
    jq -r --unbuffered '
      def short: tostring | gsub("\n"; " ⏎ ") | if length > 400 then .[:400] + "…" else . end;
      (.ts | sub("^[0-9-]+T"; "") | sub("[+-][0-9:]+$"; "")) as $t
      | if .hook_event_name == "PostToolUse" then
          (.tool_response.routing.sender // .teammate_name // .agent_type // "team-lead") as $from
          | "\($t)  ✉ \($from) → \(.tool_input.to // .tool_input.recipient // "?")  \(.tool_input.message // .tool_input.content // .tool_input | short)"
        elif .hook_event_name == "TeammateIdle" then
          "\($t)  ⏸ \(.teammate_name // .agent_type // "?") 空闲"
        elif .hook_event_name == "TaskCreated" then
          "\($t)  ＋ 任务 \(.task_id // "") \(.task_subject // .task_description // "" | short)"
        elif .hook_event_name == "TaskCompleted" then
          "\($t)  ✔ 任务 \(.task_id // "") \(.task_subject // "" | short)  (\(.teammate_name // .agent_type // "?"))"
        else "\($t)  · \(.hook_event_name)" end'
}

# 用参数区分而不是 [ -t 0 ]：从脚本/管道里手动查看时 stdin 也不是终端，会被误当成钩子
if [ "${1:-}" = "--hook" ]; then
    mkdir -p "$DIR"
    jq -c --arg ts "$(date -Iseconds)" '{ts: $ts} + .' >> "$LOG" 2>/dev/null
    exit 0   # 日志失败也绝不能挡住队员（exit 2 会被当成「不许停 / 不许完成」）
fi

[ -f "$LOG" ] || { echo "今天还没有团队日志：$LOG"; exit 0; }
case "${1:-}" in
    -f) tail -n +1 -f "$LOG" | pretty ;;
    -r) cat "$LOG" ;;
    *)  pretty < "$LOG" ;;
esac
