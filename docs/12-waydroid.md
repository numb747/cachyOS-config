# 12 · Waydroid（已移除）

> **2026-11-17 起本机不再用 Waydroid。** 当初（2026-09-28）装它只为跑安卓版企业微信 / 微信；
> 本机企业微信已整套不用（wine 版 2026-10-09 先卸，见 `docs/09`），Waydroid 跟着卸掉。
> 原文（Android 13 容器、网络、显示覆盖层、libndk 转译、Rime 输入法、fork 子进程清理服务等 8 节）在 git 历史里：
>
> ```bash
> git show f23564b:docs/12-waydroid.md
> ```

## 1 · 拆掉了什么

| 位置 | 内容 |
|---|---|
| 系统 | `waydroid` 包、镜像与数据、`waydroid-fork-reaper` 清理服务、`waydroid-container.service.d/forward.conf`（docker 转发补丁） |
| 包内 | `share/applications/waydroid-restart.desktop`；`security/setup.sh` 不再给 `waydroid0` 放行 ufw |
| 留着没动 | `mykeys.lua` 第 19 节的窗口规则（没装 Waydroid 时无副作用） |

## 2 · 还通用的经验

- **docker 的 FORWARD DROP 会挡掉别的网桥的转发。** docker 把 `ip filter` 的 FORWARD 策略设成 DROP；
  nftables 里 accept 只结束本张表、任何一张表 drop 就是终局，所以别的程序在自己表里放行（Waydroid 的 `inet lxc`）没用。
  要在 docker 那张表里按网桥插 ACCEPT（`iptables -I FORWARD -i <网桥> -j ACCEPT` + 回程 `RELATED,ESTABLISHED`），
  别整体开 docker 的 `ip-forward-no-drop`。放行流量不通时先看这条。
- **fork 后没 exec 的子进程在 libndk（ARM 转译）下会挂死**：父线程 vfork 等它进 D 态 → ANR；
  子进程还占着继承来的 binder fd，app 被杀后再也起不来（logcat `refused to die`）。
  容器里 cgroup 只读，AMS 连进程组一起杀不到。当时靠宿主机按 `PF_FORKNOEXEC` 等条件定期清理，脚本在原文第 8 节。
- **`/etc/nftables.conf` 是 Arch 自带的全 drop 示例，别加载它**（`nftables.service` 是 disabled）。
  2026-09-28 把几个服务的状态输出读错位、误加载过一次，局域网服务和 docker 转发当场全挡。
  查服务状态一次查一个；本机防火墙现在是 ufw（见 `docs/16`）。
