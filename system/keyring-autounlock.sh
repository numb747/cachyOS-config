#!/usr/bin/env bash
# 让 gnome-keyring 在 greetd 登录时自动解锁，消掉「开机后第一次开 Chrome 要输 Default keyring 密码」。
# 原理和取舍见 docs/05-theme-ui.md「钥匙环开机自动解锁」。可重复跑，每一步都先检查再动手。
#
#   1. /etc/pam.d/greetd 补 pam_gnome_keyring（auth 截住登录密码，session 拿它去解锁）
#   2. 把 Default_Keyring 改名成 login —— pam_gnome_keyring 只认名叫 login 的那个环
#   3. 密钥环密码和登录密码不同时，弹 gcr 对话框改成一致（密码只进对话框，不经过终端）
set -euo pipefail

KR="$HOME/.local/share/keyrings"
PAM=/etc/pam.d/greetd
ts=$(date +%Y%m%d-%H%M%S)

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "别用 sudo 跑，脚本在改 PAM 那一步会自己要 sudo"
[[ -n ${XDG_RUNTIME_DIR:-} ]] || die "要在图形会话的终端里跑（第 3 步要弹对话框）"

# ---- 1. PAM -----------------------------------------------------------------
say "1/3 PAM：$PAM"
if grep -q pam_gnome_keyring "$PAM"; then
    echo "已有 pam_gnome_keyring，跳过"
else
    sudo cp -a "$PAM" "$PAM.bak.keyring.$ts"
    # 追加在末尾：session 那行必须排在 pam_systemd 之后（要用它建好的 XDG_RUNTIME_DIR）
    printf '%s\n' \
        'auth       optional     pam_gnome_keyring.so' \
        'session    optional     pam_gnome_keyring.so auto_start' \
        | sudo tee -a "$PAM" >/dev/null
    echo "已追加（备份：$PAM.bak.keyring.$ts）"
fi

# ---- 2. Default_Keyring → login ---------------------------------------------
say "2/3 密钥环改名为 login"
if [[ -f $KR/login.keyring ]]; then
    echo "login.keyring 已存在，跳过"
elif [[ ! -f $KR/Default_Keyring.keyring ]]; then
    die "$KR 里既没有 login.keyring 也没有 Default_Keyring.keyring，情况和预期不符，停下"
else
    # 守护进程开着时改文件，它内存里那份可能回写覆盖，所以先全停。
    # 同时有两个：socket 拉起的那个 + D-Bus 激活的那个（登录时序竞争的产物）。
    systemctl --user stop gnome-keyring-daemon.socket gnome-keyring-daemon.service
    pkill -x -u "$USER" gnome-keyring-d || true   # comm 名被截成 15 字符
    for _ in {1..20}; do pgrep -x -u "$USER" gnome-keyring-d >/dev/null || break; sleep 0.2; done
    pgrep -x -u "$USER" gnome-keyring-d >/dev/null && die "gnome-keyring-daemon 停不掉，没动任何文件"

    cp -a "$KR" "$KR.bak-$ts"
    mv "$KR/Default_Keyring.keyring" "$KR/login.keyring"
    printf 'login' > "$KR/default"
    echo "已改名（备份：$KR.bak-$ts）"

    systemctl --user start gnome-keyring-daemon.socket
fi

# ---- 3. 密钥环密码 = 登录密码 -----------------------------------------------
say "3/3 密钥环密码"
echo "pam 只能用「登录密码」去解锁，两者必须一致。"
read -rp "当初设的密钥环密码和开机登录密码一样吗？[y=一样 / n=不一样 / 回车=不确定] " same
if [[ $same == [yY]* ]]; then
    echo "跳过改密码"
else
    echo "马上弹对话框：先输【旧的密钥环密码】，新密码填【开机登录密码】。"
    # 放进 if：set -e 下裸跑，对话框被取消时脚本会直接退出、看不到下面的提示
    if python3 - <<'EOF'
import sys
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
call = lambda path, iface, method, args, ret: bus.call_sync(
    "org.freedesktop.secrets", path, iface, method, args,
    GLib.VariantType(ret) if ret else None, Gio.DBusCallFlags.NONE, -1, None)

(prompt,) = call("/org/freedesktop/secrets",
                 "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
                 "ChangeWithPrompt",
                 GLib.Variant("(o)", ("/org/freedesktop/secrets/collection/login",)),
                 "(o)").unpack()

loop, result = GLib.MainLoop(), {}
def done(_c, _s, _p, _i, _sig, params):
    result["dismissed"] = params.unpack()[0]
    loop.quit()
# 必须等 Completed：本进程一退出，gnome-keyring 会把它发起的 prompt 一并撤掉
bus.signal_subscribe("org.freedesktop.secrets", "org.freedesktop.Secret.Prompt",
                     "Completed", prompt, None, Gio.DBusSignalFlags.NONE, done)
call(prompt, "org.freedesktop.Secret.Prompt", "Prompt", GLib.Variant("(s)", ("",)), None)
loop.run()
sys.exit(1 if result["dismissed"] else 0)
EOF
    then echo "密码已改"
    else die "对话框被取消，密码没改；重跑本脚本即可（前两步会自动跳过）"
    fi
fi

say "完成。注销再登录（或重启）后打开 Chrome，应当不再弹窗。"
echo "本次会话里，已开着的程序可能还会再要一次密码（守护进程刚重启，环是锁的），属正常。"
echo "另外：下次周日安全体检会把 /etc/pam.d/greetd 的改动报出来，复核后 sudo sec-audit --accept \"钥匙环 PAM 自动解锁\"。"
