#!/usr/bin/env bash
# ============================================================================
#  setup.sh —— 把每周安全体检装进系统。设计、流程、坑都在 docs/16-security.md
#
#      sudo ./setup.sh audit      装工具 + 检查器 + timer + auditd 规则，建初始基线
#      sudo ./setup.sh firewall   开 ufw：默认拒绝入站，只对局域网放行本机在用的服务
#      ./setup.sh status          只读：装上去的和仓库里的是否一致、timer 何时跑
#
#  和 install.sh 的分工：install.sh 只碰 $HOME、不要 sudo；这里装的全是系统文件
#  （/usr/local、/etc、/var），检查器必须 root 所有，否则用户级恶意程序能改掉它。
#  所以这些文件不进 manifest.map，改了仓库里的版本要重跑 `sudo ./setup.sh audit`。
#  幂等：重跑只会覆盖文件、补规则，不会动已有的基线（基线只有 --init / --accept 会改）。
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USR=${SUDO_USER:-$(id -un)}
UHOME=$(getent passwd "$USR" | cut -d: -f6)

# 装上去的位置 ⇄ 仓库里的文件
FILES=(
    "sec-audit                          /usr/local/sbin/sec-audit                       755"
    "sec-audit-notify                   /usr/local/bin/sec-audit-notify                 755"
    "systemd/sec-audit.service          /etc/systemd/system/sec-audit.service           644"
    "systemd/sec-audit.timer            /etc/systemd/system/sec-audit.timer             644"
    "systemd/sec-audit-notify.path      /etc/systemd/user/sec-audit-notify.path         644"
    "systemd/sec-audit-notify.service   /etc/systemd/user/sec-audit-notify.service      644"
)
AUDIT_RULES=/etc/audit/rules.d/50-sec-audit.rules

need_root() { [ "$(id -u)" -eq 0 ] || { echo "要 root：sudo $0 $*" >&2; exit 1; }; }
step() { printf '\n\033[1m── %s\033[0m\n' "$*"; }

# auditd 规则：盯持久化位置的写入，体检报告里会列出「哪个进程改的」。
# 只为已存在的路径生成 —— auditctl 遇到父目录不存在的 -w 会整条规则加载失败。
gen_audit_rules() {
    local p
    echo "# 由 ~/cachyOS-config/security/setup.sh 生成，别手改；key 都以 sec- 开头，sec-audit 按 key 查"
    # 先清空再加载：augenrules 会把 -D 挪到合并结果的第一行。没有它，重复加载会报 Rule exists，
    # audit-rules.service 直接失败（2026-10-27 首次安装时实测踩到）
    echo "-D"
    for p in /etc/passwd /etc/shadow /etc/group /etc/gshadow; do echo "-w $p -p wa -k sec-acct"; done
    for p in /etc/sudoers /etc/sudoers.d /etc/pam.d /etc/polkit-1/rules.d /etc/doas.conf; do
        [ -e "$p" ] && echo "-w $p -p wa -k sec-priv"
    done
    for p in /etc/ld.so.preload /etc/ld.so.conf.d /etc/systemd/system /etc/systemd/user /etc/xdg/autostart \
             /etc/profile.d /etc/environment /etc/pacman.d/hooks /etc/udev/rules.d /etc/modules-load.d \
             /etc/cron.d /var/spool/cron /etc/ssh/sshd_config /root/.ssh /usr/local/bin /usr/local/sbin \
             "$UHOME/.ssh" "$UHOME/.config/systemd/user" "$UHOME/.config/autostart" "$UHOME/.config/environment.d" \
             "$UHOME/.zshrc" "$UHOME/.zprofile" "$UHOME/.zshenv" "$UHOME/.profile" "$UHOME/.bashrc" \
             "$UHOME/.local/bin" "$UHOME/.claude/settings.json" "$UHOME/.gitconfig"; do
        # /etc/ld.so.preload 平时不存在、出现本身就是信号，盯它的父目录不现实，这里也允许不存在（父目录 /etc 一定在）
        [ -e "$p" ] || [ "$p" = /etc/ld.so.preload ] && echo "-w $p -p wa -k sec-persist"
    done
    echo "-a always,exit -F arch=b64 -S init_module,finit_module -F key=sec-kmod"
}

do_audit() {
    need_root audit

    step "装工具：lynis rkhunter arch-audit clamav mmdblookup"
    pacman -S --needed --noconfirm lynis rkhunter arch-audit clamav mmdblookup

    step "装检查器与 systemd 单元"
    local line src dst mode
    for line in "${FILES[@]}"; do
        read -r src dst mode <<< "$line"
        install -D -o root -g root -m "$mode" "$HERE/$src" "$dst"
        echo "  $dst"
    done
    install -d -o root -g root -m 700 /var/lib/sec-audit
    install -d -o root -g wheel -m 750 /var/log/sec-audit

    step "auditd 规则 → $AUDIT_RULES"
    gen_audit_rules > "$AUDIT_RULES"
    chmod 640 "$AUDIT_RULES"
    # 别自己再跑 augenrules --load：enable auditd 会顺带拉起 audit-rules.service，两边并发加载会撞车
    systemctl enable --now auditd
    systemctl restart audit-rules.service
    echo "  已加载 $(auditctl -l | grep -c 'sec-') 条"

    step "clamav 病毒库（第一次要下 ~300 MB，失败了不影响别的，体检时会再试）"
    timeout 900 freshclam || echo "  ! freshclam 失败，网络问题的话见 docs/16"

    step "启用 timer 与通知"
    systemctl daemon-reload
    systemctl enable --now sec-audit.timer
    systemctl --global enable sec-audit-notify.path sec-audit-notify.service
    systemctl --user -M "$USR@" daemon-reload 2>/dev/null &&
        systemctl --user -M "$USR@" start sec-audit-notify.path ||
        echo "  ! 没能替 $USR 启动通知单元，重新登录一次就会生效"

    if [ -d /var/lib/sec-audit/base ]; then
        step "已有基线，不重建（要重建：sudo sec-audit --init）"
    else
        step "第一次采集并建基线（几分钟）"
        /usr/local/sbin/sec-audit --init
        echo "  报告：sec-audit --show"
    fi
}

do_firewall() {
    need_root firewall
    local lan
    # 本机所在的私有网段，如 192.168.1.0/24。规则只对这个网段放行 —— 换到别的网络（咖啡馆 Wi-Fi）就全挡
    # 只认物理网卡（/sys/class/net/<dev>/device 存在）：本机还有 docker0、singbox_tun、vmnet*、waydroid0
    # 一堆虚拟网卡，按网段猜会挑中 sing-box TUN 的 172.18.0.0/30
    local net dev
    while read -r net _ dev _; do
        [ -e "/sys/class/net/$dev/device" ] && [[ $net =~ ^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]] &&
            { lan=$net; break; }
    done < <(ip -4 route show scope link proto kernel)
    [ -n "$lan" ] || { echo "没找到局域网网段（没连网？）" >&2; exit 1; }

    step "ufw：默认拒绝入站，放行 $lan 的这些"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow from "$lan" to any port 1714:1764 proto tcp comment 'KDE Connect'
    ufw allow from "$lan" to any port 1714:1764 proto udp comment 'KDE Connect'
    ufw allow from "$lan" to any port 21118 proto tcp comment 'RustDesk 局域网直连'
    ufw allow from "$lan" to any port 21119 proto udp comment 'RustDesk 局域网发现'
    ufw allow from "$lan" to any port 18765,18767 proto tcp comment 'feedback / ccmon'
    ufw allow from "$lan" to any port 5353 proto udp comment 'mDNS（adb-wifi 发现手机）'
    # Waydroid：容器要从宿主拿 DHCP/DNS，流量还要经宿主转发出去（docs/12 第 3 节）
    ufw allow in on waydroid0 comment 'Waydroid'
    ufw route allow in on waydroid0 comment 'Waydroid'
    ufw route allow out on waydroid0 comment 'Waydroid'
    # v2rayN 的 sing-box TUN（system 栈）把代理连接的回程「注入」回本机，在 ufw 看来是从 TUN 进来的新连接，
    # 不放行就挡掉了走 TUN 的代理流量和 RustDesk 中继（2026-10-27 开墙后日志里 3000+ 条 UFW BLOCK 几乎全是它）。
    # 只有 sing-box 能往这张网卡里送包，放行是安全的。v2rayN 里改了 TUN 网卡名要跟着改
    ufw allow in on singbox_tun comment 'sing-box TUN（v2rayN）'
    ufw --force enable
    systemctl enable ufw
    ufw status verbose
    echo
    echo "验一下：KDE Connect 能发文件、Waydroid 能上网、RustDesk 局域网能连、p2p 直传能收"
}

do_status() {
    local line src dst mode
    step "装上去的 vs 仓库里的"
    for line in "${FILES[@]}"; do
        read -r src dst mode <<< "$line"
        if [ ! -e "$dst" ]; then printf '  ✗ 没装       %s\n' "$dst"
        elif cmp -s "$HERE/$src" "$dst"; then printf '  ✓ 一致       %s\n' "$dst"
        else printf '  ! 不一致     %s（改了仓库就重跑 sudo ./setup.sh audit；没改过仓库就要警惕了）\n' "$dst"; fi
    done
    step "timer"
    systemctl list-timers sec-audit.timer --no-pager | head -2
    step "最近一次报告"
    ls -l /var/log/sec-audit/latest.md 2>/dev/null || echo "  还没有"
    cat /var/log/sec-audit/latest.json 2>/dev/null || true
}

case "${1:-}" in
    audit)    do_audit ;;
    firewall) do_firewall ;;
    status)   do_status ;;
    *) sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
