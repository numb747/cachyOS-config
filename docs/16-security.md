# 16 · 每周安全体检

> 每周日晚由系统级 timer 自动跑一次 `sec-audit`，**和上次人工确认过的基线比**，只报变化；
> 桌面弹通知，你花 15 分钟复核，确认无误后 `sudo sec-audit --accept "备注"` 更新基线。
> 代码在 `security/`，装到 `/usr/local` 和 `/etc`（**不走 manifest.map**，理由见第 5 节）。

```
每周日 20:17（关机错过 → 开机补跑）
  └─ sec-audit（root，Nice 19 / IO idle，约 5–10 分钟）
       ├─ 报告 /var/log/sec-audit/<日期>.md   ← sec-audit --show
       └─ latest.json 变了 → 用户级 path 单元 → 桌面通知「🔴 n 🟡 n」，点开用 kitty 看
  └─ 你：复核 → sudo sec-audit --accept "本周装了 xx、改了 zshrc"
            或 → 第 7 节应急
```

---

## 1. 安装

```bash
cd ~/cachyOS-config/security
sudo ./setup.sh audit      # 装 lynis rkhunter arch-audit clamav + 检查器 + timer + auditd 规则，建初始基线
sudo ./setup.sh firewall   # 开 ufw，默认拒入，只对局域网网段放行在用的服务（第 4 节）
./setup.sh status          # 只读：装上去的和仓库里是否一致、timer 下次何时跑
```

| 装到哪 | 是什么 |
|---|---|
| `/usr/local/sbin/sec-audit` | 检查器本体（root:root 755） |
| `/usr/local/bin/sec-audit-notify` | 通知脚本，用户级单元调它 |
| `/etc/systemd/system/sec-audit.{service,timer}` | 每周日 20:17，`Persistent=true` |
| `/etc/systemd/user/sec-audit-notify.{path,service}` | `--global enable`，盯 `latest.json` + 登录时补报 |
| `/etc/audit/rules.d/50-sec-audit.rules` | auditd 规则，**按本机已存在的路径生成** |
| `/var/lib/sec-audit/` (700) | `base/` 基线、`cur/` 最近一次采集 |
| `/var/log/sec-audit/` (750 root:wheel) | 报告、`accept.log`（每次接受的时间与备注） |

改了 `security/` 里的东西要**重跑 `sudo ./setup.sh audit`**（幂等，不会重建基线）。
`./setup.sh status` 报「不一致」而你又没改过仓库 —— 那就是检查器本身被动过，按 🔴 处理。

## 2. 每周复核（15 分钟）

1. 点通知或 `sec-audit --show`，先看 🔴：**每一条都要有结论**（是我干的 / 是升级带来的 / 查不清 → 第 7 节）。
2. 🟡 逐条对照本周自己做过的事：装了包？改了 zshrc？插了新键盘？对得上就过。
3. `sudo sec-audit --accept "本周做了什么"` —— 备注写进 `accept.log`，日后回查「这条是哪天、为什么被接受的」。
4. arch-audit 报了 🔴 高危漏洞，当场 `sudo pacman -Syu`。

**不 accept 会怎样**：下周继续和旧基线比，本周的变化会再报一遍（不会丢，只是更长）。
所以没空复核就别 accept，**绝不要为了让报告变短而 accept**。

## 3. 查什么

| 分类 | 内容 | 怎么查 | 采集文件（`/var/lib/sec-audit/cur/`） |
|---|---|---|---|
| 系统文件 | 不归任何包管的 `/etc` `/usr` `/opt` 变动 | 每次建 snapper 快照，`snapper status 基线..现在`，再滤掉 `pacman -Ql` 里有的 | `snapper.num` |
| | 包里的文件被改（sha256 / 权限 / 属主） | `paccheck --sha256sum --file-properties` | `paccheck` |
| | `/boot`（vfat，不在快照里） | 指纹 | `boot` |
| 持久化 | systemd 单元、autostart、shell rc、`ld.so.preload`、pam、sudoers、polkit、pacman hooks、udev、cron、ssh、`/usr/local`、`~/.local/bin`、Hyprland 配置… | 路径 → sha256 清单 | `persist-sys` `persist-<用户>` |
| | **Claude Code 的 hooks / MCP / 插件 / env 键名** | jq 抽 `settings.json` `.claude.json` `plugins/*.json` | `claude-<用户>` |
| | 谁改的 | auditd 按 key `sec-*` 查本周写入 | — |
| 账户权限 | passwd / group / 密码状态（不抄哈希）、UID 0、空密码 | | `accounts` |
| | 新增 SUID/SGID（不归包管 → 🔴）、file capabilities | `find -perm` · `getcap` | `suid` `caps` |
| 网络 | 对外监听端口（非回环，高位端口归并为「高位随机」） | `ss -tulpn` | `listen` |
| | 防火墙状态与规则、NM 连接（新 VPN/Wi-Fi） | | `ufw` `nm` |
| 内核进程 | 启动参数 / taint / lockdown、新加载的模块 | | `kernel` `kmod` |
| | 从 `/tmp` `/dev/shm` 跑的、memfd 无文件落地的、exe 已删且不归包管的进程 | `/proc/*/exe` | — |
| 一周事件 | sudo 失败与常用命令、**sudo 跑了普通用户可改的程序**、锁屏/登录/su 失败、sshd 活动（本机没开 → 🔴）、polkit、陌生用户会话、新 USB 设备、coredump、OOM、失败的单元、**RustDesk 被连入的来源 IP**（按归属地分级，见下） | journalctl / RustDesk 日志 | `sudo-uw` `usb` |
| 浏览器 | Chrome 系与 Firefox 的已装扩展（只记 id + 名字，不记版本，否则自动更新每周都报）；`/etc/opt/chrome` 等策略目录（强装扩展用的）在持久化那项里 | `manifest.json` / `_locales` · `extensions.json` | `browser-<用户>` |
| 软件 | AUR 包增减、本周 `pacman -U`、新装/删除、多久没 `-Syu`、有修复版的 CVE、npm/pip/uv/cargo 全局包 | `pacman.log` · arch-audit | `aur` `userpkg-<用户>` |
| 扫描器 | rkhunter 警告、lynis 加固评分与警告、clamav 扫本周新下载的文件 | | `rkhunter` `lynis` |

**RustDesk 来源分级**：用户 2026-10-28 说「石家庄或美国的 IP 一般都是自己」。离线归属地库对国内移动网络
只准到省（同一部手机会被标成石家庄或承德），所以规则写的是 `RUSTDESK_HOME='^(LAN|CN-Hebei|US)'`：
河北、美国、局域网 → 🟢 只列出；其他地区 → 🟡「是你吗」。归属地库是
[DB-IP](https://db-ip.com) 每月免费发布的城市库（CC BY 4.0，报告里按授权要求署名），
`mmdblookup` 本地查询，**不把 IP 发给任何人**；存在 `/var/lib/sec-audit/`，超过 35 天自动重拉（约 60 MB 下载）。

## 4. 防火墙（`setup.sh firewall`）

此前**本机没有主机防火墙**（ufw `ENABLED=no`，见 `docs/12` 3.3），而 rustdesk、kdeconnect、
pear-desktop、ccmon、feedback 都监听在所有网卡上 —— 连咖啡馆 Wi-Fi 时同网段的人都能碰到。

规则：默认拒入、放行出站；只对**装的那一刻所在的私有网段**（如 `192.168.1.0/24`）放行
KDE Connect `1714-1764`、RustDesk `21118/tcp` `21119/udp`、feedback/ccmon `18765,18767`、mDNS `5353/udp`；
Waydroid 的 `waydroid0` 进出与转发全放（容器要从宿主拿 DHCP/DNS）；
**v2rayN 的 `singbox_tun` 入站全放** —— sing-box TUN（system 栈）把代理连接的回程注入回本机，
ufw 看来是从 TUN 进来的新连接。2026-10-27 刚开墙时没放它，一晚上 3000+ 条 `UFW BLOCK` 几乎全是这张网卡，
来源里有 RustDesk 中继 `8.140.18.211`。只有 sing-box 能往这张网卡送包，放行安全；v2rayN 里改了网卡名要跟着改。
查「墙挡了什么」：`journalctl _TRANSPORT=kernel -g 'UFW BLOCK' --since today`。
pear-desktop 的 `26538` `9863` 没放行（它的遥控 API，用到再加）；systemd-resolved 的 LLMNR `5355` 也被挡掉了，正好。

⚠ 换了家里的网段（换路由器）要重跑 `sudo ./setup.sh firewall`。
⚠ RustDesk 经中继/打洞的远程连接是本机**主动外连**，不受入站规则影响。
⚠ docker 自己写 iptables，**发布到宿主的容器端口绕过 ufw**，这是 docker 的老问题，不是规则漏了。

## 5. 设计取舍

- **只报变化，不报现状。** 第一次跑会把现有的一切（paccheck 的已知不一致、rkhunter 的 Arch 误报……）
  记进基线，之后每周只看新增。报告看不完 = 没查。
- **检查器 root 所有、系统级 timer 跑。** 放 `~/.local/bin`、用户级 timer 的话，以你身份运行的恶意程序
  改一行就能让它对自己视而不见。所以 `security/` 不进 `manifest.map`（那套只管 `$HOME`），
  也因此改了仓库要重跑 `setup.sh`。
- **基线只能人 accept。** 自动滚动基线 = 入侵者只要撑过一周就成了「正常」。
- **snapper 代替 AIDE。** 根分区本来就是 btrfs + snapper，每周建一个不带 cleanup 算法的快照
  （snap-pac 的 number 清理不会动它），和基线快照比，零额外数据库。旧快照由 sec-audit 自己删，
  任何时候只留「基线」和「最近一次」两个。⚠ limine-snapper-sync 会把它们也列进启动菜单，无害，
  但它每周都改 `/boot/limine.conf`，所以 `/boot` 指纹里跳过了它和 `limine_history/`
  （改启动参数仍会在重启后被 `/proc/cmdline` 那项抓到）。
- **归包管的文件交给 paccheck，不归包管的交给快照。** 两者互补：升级会改一大堆包文件，
  paccheck 拿包数据库的 sha256 验它们；快照对比只报包数据库不认识的文件。
- **rkhunter 关掉 `properties` 测试。** 它不认 pacman，每次升级都会把改过的二进制全报红，
  唯一的办法是升级后自动 `--propupd` —— 那就等于把篡改也一并吸收了。这件事 paccheck 做得更好，
  rkhunter 只留 rootkit 特征、隐藏文件、可疑端口这些。
- **内核日志用 `_TRANSPORT=kernel`，不用 `journalctl -k`。** `-k` 隐含 `-b`，只看本次开机，
  一周里重启过就漏。
- **USB 只按 `vid:pid` 比。** 根集线器的名字里带内核版本，按名字比每次升级内核都报「新设备」。
- **「sudo 跑了普通用户可改的程序」** 是首次体检时实测出来才加的：v2rayN 每次开 TUN 都
  `sudo ~/.local/share/v2rayN/...`，能改那个文件的任何东西下次都能借 sudo 拿 root。
  记成只增集合，同一个程序只在第一次出现时报。

## 6. 每月 / 每季度（人工，timer 不做）

**每月第一周**（复核完周报之后顺手）：
- `sudo lynis audit system` 全量，挑一条建议修掉，`sudo lynis show details <ID>` 看说明
- `sudo sec-audit --scan ~`：clamav 整个家目录扫一遍
- AUR 包升级时看 PKGBUILD diff（yay 会给，别一路回车）
- 浏览器扩展：每周只报新增，每月把整个列表过一遍，用不上的删掉（扩展越少越安全）
- 轮换明文 token：`~/.claude/settings.json` 里的 `ANTHROPIC_AUTH_TOKEN`、discord-sync 的 `.env`

**每季度**：演练一次 snapper 回滚（知道怎么回比回不回更重要）；复审防火墙放行清单和第 3 节的检查范围。

## 7. 出 🔴 了怎么办

1. **先断网，别关机**：`nmcli networking off`。内存里的进程、网络连接是证据，关机就没了。
2. **留证据**到 U 盘：报告、`journalctl --since -7d > j.txt`、`ps auxf`、`ss -tupan`、可疑文件的 `sha256sum`。
   查 VirusTotal **只查哈希，不上传文件**。
3. **判断层级**：只动了你家目录（用户级）还是动了 `/etc` `/usr`（root 级）。⚠ 你在 docker 组，
   用户级也可能已经借 docker 提权，看到 `/var/lib/docker` 附近的异常要按 root 级算。
4. 用户级：清掉报告里列出的持久化点 → **用另一台设备**改密码、轮换 token / ssh key / age key。
   root 级：**从可信介质重装**是唯一可靠的办法；snapper 回滚只适合确认「不是入侵、是误改」。

## 8. 已知并接受的风险 / 不覆盖的

- **docker 组 = root**：`docker run -v /:/host` 就能改任何东西，包括本检查器。要堵就退组改用
  `sudo docker` 或 rootless docker；目前选择接受，报告末尾每周提醒一次。
- **v2rayN 以 root 跑家目录里的程序**（`sudo ~/.local/share/v2rayN/bin/sing_box/sing-box` 和
  `binConfigs/kill_as_sudo.sh`，开 TUN 用）：用户确认**就是要这样**（2026-10-27），不改。
  代价是能改这两个文件的东西都能借它拿 root；它们在 `sudo-uw` 基线里，换了别的用户可写程序才会再报。
- **防不住已经拿到 root 的入侵者**（能改检查器、能改日志、能删快照）。本套针对的是用户级恶意程序、
  供应链投毒和事后发现。
- **不覆盖**：项目目录里的 `.claude/settings.json` 与 `.mcp.json`、flatpak、Waydroid 里的 Android 应用、
  外连（恶意程序回连 C2 —— 入站防火墙看不到，要 OpenSnitch 这类逐程序外连防火墙，太吵，暂不装）。
- ⚠ **最大的缺口是恢复不是检测：`/home` 没有任何备份**（snapper 只配了 root，且快照和原数据在同一块盘上，
  勒索软件 / root 入侵 / 坏盘会一起带走）。体检只管「发现」。待办：restic 或 borg 备份到另一块盘或网盘。
- `/etc/pacman.d/gnupg/` 不在快照对比里（每次 keyring 更新都会变，噪音太大）。

## 9. 调噪音

报告里某类东西每周都报、又确实无害：改 `security/sec-audit` 顶部的清单 ——
`SNAP_SKIP`（快照对比里滤掉的生成文件）、`PERSIST_SKIP`（持久化里跳过的路径）、`SYS_PERSIST` / `user_persist`（检查范围），
然后 `sudo ./setup.sh audit` 重装。**加 SKIP 之前想清楚：攻击者也会往「不看的地方」放东西。**
