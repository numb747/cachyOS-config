# ============================================================================
#  CachyOS 基线 + 旧机可移植部分
#
#  基线部分交给发行版维护，本文件只做叠加，pacman 升级 cachyos-zsh-config
#  不会冲突。提示符不在这里配 —— 见 ~/.p10k.zsh。
#
#  ⚠️ 不要在这里手动 source 任何主题（如 robbyrussell.zsh-theme）。
#     powerlevel10k 在 precmd 里重新赋值 PROMPT，静态赋值会被冲掉。
#     顺着 p10k 走：主题配置全部放 ~/.p10k.zsh。
# ============================================================================
source /usr/share/cachyos-zsh-config/cachyos-config.zsh
# 基线已提供 zsh-syntax-highlighting / zsh-autosuggestions /
# zsh-history-substring-search，无需再引入 oh-my-zsh 的等价插件。

# ─── PATH ───────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# nvim 的 mason 装的 LSP / formatter / DAP 二进制
[ -d "$HOME/.local/share/nvim/mason/bin" ] && \
    export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"

# ─── 编辑器 ─────────────────────────────────────────────────────────────────
export EDITOR=vim

# ─── Android SDK + 逆向工具 ─────────────────────────────────────────────────
# jadx / apktool / dex2jar / frida / objection / emulator / build-tools
# 全部定义在 env.sh，便于集中维护
[ -f "$HOME/mywork/tools/env.sh" ] && source "$HOME/mywork/tools/env.sh"

# ─── hacktools 工具链 ───────────────────────────────────────────────────────
# 原配置硬编码 /home/david/hacktools/，改成相对 $HOME，换用户名也不用回来改。
# 目录不存在时整段静默跳过，不会留下一堆指向空路径的别名。
: "${HACKTOOLS:=$HOME/hacktools}"
if [ -d "$HACKTOOLS" ]; then
    alias DatabaseTools="$HACKTOOLS/databaseTools/DatabaseTools_linux_amd64"
    alias fofax="$HACKTOOLS/fofax"
    alias jcode="$HACKTOOLS/jcode"
    alias vulnx="$HACKTOOLS/vulnx"
    command -v java >/dev/null 2>&1 && \
        alias vineflower="java -jar $HACKTOOLS/vineflower.jar"
fi

# ─── AI sandbox 容器 ────────────────────────────────────────────────────────
if command -v docker >/dev/null 2>&1; then
    alias sandbox='docker exec -it -w /workspace ai-sandbox bash'
    alias sandbox-up='cd ~/aiDocker && docker compose up -d --build && cd -'
    alias sandbox-down='cd ~/aiDocker && docker compose down && cd -'
fi

# ─── 可选工具链（未安装时完全静默，装上后自动生效）─────────────────────────
# RVM
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
[ -d "$HOME/.rvm/bin" ] && export PATH="$PATH:$HOME/.rvm/bin"

# zoxide（原配置是无条件 eval，未装时每开一个 shell 报一次错）
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# uv（原配置是无条件 source）
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Claude Code 多会话看板
alias ccw='~/.claude/cc-watch.py'          # 常驻看板
alias ccs='~/.claude/cc-watch.py --once'   # 打一次快照
alias ccp='~/.claude/cc-pet.py'            # 宠物版 TUI（可上下选择）
