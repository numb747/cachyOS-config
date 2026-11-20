#!/usr/bin/env bash
# 安装 pacman 升级后的缺库检查：sudo ./setup.sh
# 卸载：sudo ./setup.sh --remove
# 说明见 docs/07-troubleshooting.md「升级后程序报 cannot open shared object」。
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=/usr/local/libexec/pacman-libcheck
HOOK=/etc/pacman.d/hooks/zz-pacman-libcheck.hook

[[ $EUID -eq 0 ]] || { echo "要 root：sudo $0 $*" >&2; exit 1; }

if [[ ${1:-} == --remove ]]; then
    rm -f "$HOOK" "$BIN"
    echo "已卸载：$HOOK、$BIN"
    exit 0
fi

install -Dm755 "$here/pacman-libcheck" "$BIN"
install -Dm644 "$here/zz-pacman-libcheck.hook" "$HOOK"
echo "已安装：$BIN"
echo "        $HOOK"
