# 12 · Waydroid：Android 容器

> Android 13（LineageOS VANILLA）跑在 LXC 容器里，AMD 核显硬件加速，
> 整屏界面独占 `name:android` 桌面，网络自动走 v2rayN 的 TUN，带 ARM 转译和 Rime 输入法。
> 2026-09-28 新增。
>
> ⚠ **这不是 `install.sh` 的模块。** 需要 root 的系统级步骤（装包、`/etc` 下的 drop-in、
> 第 8 节的清理服务、镜像初始化、往容器 overlay 里装 libndk）都不在本包管辖，换机器照第 2 节手动做。
> 包里只纳管了一处：`mykeys.lua` 第 19 节的窗口规则。

---

## 1. 可行性：本机条件一览

| 项 | 状态 | 依据 |
|---|---|---|
| binder | ✅ 零配置 | CachyOS 内核 `CONFIG_ANDROID_BINDER_IPC=y` + `BINDERFS=y` 编进内核，**不用 `binder_linux-dkms`** |
| ashmem | ✅ 不需要 | Android 11+ 走 memfd（`waydroid_base.prop` 里 `sys.use_memfd=true`） |
| 显卡 | ✅ 零配置 | Raphael 核显 / amdgpu / Mesa，init 自动识别为 `gralloc=gbm` `egl=mesa` `vulkan=radeon`，GLES 3.2 |
| 网络 | ⚠ 要一个 drop-in | 见第 3 节 —— 挡路的是 docker，不是 TUN |
| 宿主输入法 | ❌ 透传不了 | 见第 6 节，改在 Android 里装 |

---

## 2. 从零复现（换机器照做）

```bash
sudo pacman -S waydroid                      # extra 仓库；lxc 会取 cachyos-extra-znver4 的优化版
sudo waydroid init -s VANILLA                # ~2.4 GB（system 1.8 + vendor 0.56）。TUN 开着就自动走代理

# docker 的 FORWARD DROP 放行（第 3 节）—— 内容见下方
sudo install -Dm644 forward.conf /etc/systemd/system/waydroid-container.service.d/forward.conf
sudo systemctl daemon-reload && sudo systemctl start waydroid-container

# 清理卡死的 fork 子进程（第 8 节）—— 脚本与 unit 全文见第 8 节，先存成这两个文件
sudo install -Dm755 waydroid-fork-reaper /usr/local/bin/waydroid-fork-reaper
sudo install -Dm644 waydroid-fork-reaper.service /etc/systemd/system/waydroid-fork-reaper.service
sudo systemctl daemon-reload && sudo systemctl enable --now waydroid-fork-reaper.service

waydroid session start &                     # 等出现 "Android with user 0 is ready"

# 显示：让 Android 一开始就按整屏分辨率渲染（第 4 节）
waydroid prop set persist.waydroid.width  2560
waydroid prop set persist.waydroid.height 1440

# ARM 转译（第 5 节）。⚠ 必须带 -a 13
git clone --depth 1 https://github.com/casualsnek/waydroid_script ~/.local/share/waydroid_script
cd ~/.local/share/waydroid_script && python3 -m venv venv && venv/bin/pip install -r requirements.txt
waydroid session stop
sudo venv/bin/python main.py -a 13 install libndk

# 输入法（第 6 节）
waydroid session start &
waydroid app install org.fcitx.fcitx5.android-*-x86_64-release.apk
waydroid app install org.fcitx.fcitx5.android.plugin.rime-*-x86_64-release.apk
sudo waydroid shell -- sh -c 'id=$(ime list -a -s | grep fcitx); ime enable $id; ime set $id'
# 然后在 Android 里开 Fcitx5 → 输入法 → + Rime
# 打字时按 F4 → 选「朙月拼音·简化字」（默认方案出繁体，见第 6 节）
```

`/etc/systemd/system/waydroid-container.service.d/forward.conf`：

```ini
# docker 把 iptables FORWARD 策略设成了 DROP，Android 出网的转发流量会被丢掉。
# 只放行 waydroid0 的转发，跟容器服务同生命周期；不动 docker 的全局 DROP。
[Service]
ExecStartPre=/usr/bin/iptables -I FORWARD -i waydroid0 -j ACCEPT
ExecStartPre=/usr/bin/iptables -I FORWARD -o waydroid0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ExecStopPost=-/usr/bin/iptables -D FORWARD -i waydroid0 -j ACCEPT
ExecStopPost=-/usr/bin/iptables -D FORWARD -o waydroid0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

`waydroid-container` 实测是 **enabled** 的（软链接 2026-09-28 07:42 建立，waydroid 与
waydroid_script 的源码里都没有 enable 它的逻辑，来源没查清）。这无妨：它只是个 26 MB 的
守护进程，**Android 本身要等 `session start` 才开机**，开机自启并不会拉起 Android。
它还有 D-Bus 激活文件（`id.waydro.Container.service` → `SystemdService=waydroid-container.service`），
就算 disable 了，有人请求时也会被自动拉起，且走同一个 unit，drop-in 照样生效。

### 生命周期：三层，关窗 ≠ 关 Android

```
① 容器服务 waydroid-container   root 守护进程，只是管家                    26 MB
② 会话 session = Android 开机   show-full-ui 发现没会话会自己起一个      ~2.5 GB
③ 窗口 show-full-ui             只负责显示
```

Waydroid 不是虚拟机：LXC 容器，**和宿主共用内核**，内存不预留、用多少占多少。
②那 2.5 GB 实测拆开是 anon 898 MB（真占用）+ file 1400 MB（读 system.img 的页缓存，
内存紧时内核会回收）+ kernel 125 MB。

关窗后 Android 请求休眠，按 `waydroid.cfg` 的 `suspend_action` 处理：

- **`freeze`（默认，保留）** —— cgroup 冻结，CPU 归零，**内存原样留着**，下次打开瞬间恢复。
- `stop` —— 直接结束会话、内存全还。**2026-09-28 评估后不用**：每次打开都要把 LineageOS
  冷启动一遍，这比占着内存更碍事。

要手动把内存要回来：`waydroid session stop`（启动器里 Waydroid 条目的「Stop Waydroid」动作也是它）。

---

## 3. 网络

### 3.1 TUN 不用为 Waydroid 做任何事

v2rayN 的 sing-box TUN（`auto_route` + `strict_route`）下发的策略路由里有这么一条：

```
9003:  not from all iif lo lookup 2022      ← 表 2022 只有 default dev singbox_tun
```

「不是本机发出的流量」全部进 tun —— 从 `waydroid0` 网桥转发出来的 Android 流量正中这条。
回程包由 `9002: iif singbox_tun goto 9010` 交回 main 表，按 `192.168.240.0/24 dev waydroid0` 回去。
DNS 走 Android → dnsmasq(192.168.240.1) → resolved(127.0.0.53) → 被 sing-box 劫持。

所以 **Android 里不用设代理、`StrictRoute` 不用关**，不走系统代理的 app 和 UDP 也一并接管。
实测：Android 内 `www.baidu.com` / `www.google.com` 均 `HTTP/1.0 200 OK`，google 解析到真实地址。

⚠ `ip -6 rule` 里有 `9000: from all unreachable`（TUN 没开 IPv6 时 strict_route 的效果）。
Waydroid 默认只给网桥分 IPv4，所以无碍 —— **别去开 Waydroid 的 IPv6**。

### 3.2 挡路的是 docker 的 FORWARD DROP

docker 29 把 `ip filter` 的 FORWARD 策略设成 DROP。Waydroid 自己其实**会**放行转发，
但放错了地方：

- `waydroid-net.sh` 第 168 行：有 `nft` 且以 root 跑、`LXC_USE_NFT="true"`（默认）→ 走 **nft 分支**，
  建自己的 `table inet lxc`，在里面 `iifname waydroid0 accept`。
- nftables 里 **accept 只结束本张表**，包还要过同一 hook 上的其他表；**任何一张表 drop 就是终局**。
  于是 `inet lxc` 放行 → docker 的 `ip filter FORWARD` 策略 DROP 丢掉。
- 它的 iptables 分支（第 95–96 行）倒是直接往 FORWARD 插 ACCEPT，能和 docker 共存 —— 但走不到。

drop-in 做的就是把 iptables 分支那两条补进 docker 所在的那张表。

**实测对照**（2026-09-28，不装 drop-in 先跑一遍）：

| | 不装 drop-in | 装 drop-in |
|---|---|---|
| Android 拿 IP（DHCP） | ✅ 192.168.240.112 | ✅ |
| `ping 223.5.5.5` | ❌ 100% 丢包 | ✅ 0% |
| `FORWARD policy DROP` 计数 | 0 → **114** | 135 → **135**（不再增长） |

没用 docker 的 `"ip-forward-no-drop": true`：本机**没有主机防火墙**（见 3.3），
`ip_forward=1` 又开着，docker 这个 DROP 是唯一一道「别把本机当路由器」的闸，整体关掉放得太宽。

### 3.3 ⚠ 本机没有主机防火墙，别碰 `/etc/nftables.conf`

- `ufw.service` 是 active，但 `/etc/ufw/ufw.conf` 里 **`ENABLED=no`** —— 规则不生效。
  `user.rules` 里那些 allow（RustDesk、Vite、LocalSend）只是启用 ufw 时的预案。
- `nftables.service` 是 **disabled**，`/etc/nftables.conf` 是 Arch 自带的示例（input/forward 全 drop）。

2026-09-28 排查时把 `systemctl is-active firewalld ufw nftables` 的三行输出读错位，
以为 nftables 在跑，让人 `nft -f /etc/nftables.conf` —— **凭空加载了一张全 drop 的表**，
局域网服务和 docker 转发当场全挡，随后 `nft delete table inet filter` 撤回。
教训：**查服务状态一次查一个**；放行流量先看是不是 docker 的 FORWARD DROP。

### 3.4 测试时的两个假象

- **`inet lxc` 表和 `waydroid0` 网桥只在 `session start` 时才建**（`container_manager.py` 的
  `do_start` 里跑 `waydroid-net.sh start`）。容器服务刚起来时查不到它们是正常的。
- **Android 的 toybox `nc` 在 stdin EOF 后立刻退出**，`printf ... | nc host 80` 永远空输出。
  要写 `(printf "HEAD / HTTP/1.0\r\nHost: $h\r\n\r\n"; sleep 4) | nc $h 80`。
  `getprop net.dns1` 为空也是正常的（Android 10+ 不再写这个属性）。

---

## 4. 显示：整屏独占一个桌面

**Waydroid 的显示分辨率在窗口创建那一刻就定死**，之后窗口怎么缩放都不跟：
平铺状态下开出来是 1265×705，`wm size` 就一直是 1265x705。它和 Hyprland 的平铺天生不对付，
所以不追「自适应」，而是让窗口一出生就是整屏，两边对齐：

| 侧 | 设置 | 作用 |
|---|---|---|
| Android | `persist.waydroid.width/height = 2560/1440` | 存在 data 分区，重启不丢；改完要重启 session |
| Hyprland | `mykeys.lua` 第 19 节：`class ^(Waydroid)$` → `name:android` + `fullscreen = true` | 实测窗口 2560×1440 @ (0,0)，fullscreen 模式 2（盖住顶栏） |

`persist.waydroid.multi_windows` 保持默认（空 = 关）。多窗口模式下每个 app 的 class 是
`waydroid.<包名>`，第 19 节的规则不管它们。

### `name:android` 和导航键的关系

命名工作区的 id 固定为 **-1337**。2026-09-28 从每个桌面出发各按一次 `m-1` / `m+1` 实测：

```
ALT+[ ←                                    → ALT+]
   android(-1337) ⇄ 1 ⇄ 2 ⇄ 3 ⇄ （回绕到 android）
```

- **`ALT+[ ]` / `CTRL+2/3`**（`m±1`）：按 id 排序、到头回绕。android id 最小排最左，
  体感上夹在「最后一个」和「第一个」工作桌面之间，两头都一步够到。
- **`CTRL+1/4`、`ALT+T`**：只认 `w.id > 0`，看不见 android —— 工作桌面的头尾和新建编号不受干扰。
- **抽屉架**：android 不是 special，两个平面照旧互不相干。

注：`m±1` 本身就回绕 —— 没有 android 时实测 `3 → m+1` 到 1、`1 → m-1` 到 3。
`mykeys.lua` 第 4 节与 `docs/02` 里「工作桌面不回绕」的说法不准，但不影响使用，决定不改。

### DPI

默认 `wm density` 是 180（按 1265×705 时定的）。换成 2560×1440 后界面偏小，
**口味问题，尚未定**。临时试：`sudo waydroid shell -- wm density 240`，还原：`wm density reset`。

---

## 5. ARM 转译：libndk

国内很多 APK 只有 ARM 版，x86_64 镜像要装转译层。用 [waydroid_script](https://github.com/casualsnek/waydroid_script)，
装在 `~/.local/share/waydroid_script/`（独立 venv，不污染系统 Python）。

- **选 libndk 不选 libhoudini**：前者是 Google 的实现，AMD CPU 上的通行推荐；后者是 Intel 的。
- ⚠ **不带 `-a` 默认按 Android 11 装**，本机是 13，必须 `-a 13`。
- 下载源是 GitHub 上**钉死 commit** 的 zip，有 md5 校验；文件落在 `/var/lib/waydroid/overlay/system/`
  （overlayfs 覆盖层，共 44 MB），**不改 system.img**；10 条属性写进 `/var/lib/waydroid/waydroid.cfg` 的 `[properties]`。
- 卸载：`sudo venv/bin/python main.py -a 13 remove libndk`。
- 脚本会自己 stop 容器、跑 `waydroid upgrade -o`（离线，只重建配置不重下镜像）。
- Python 3.14 下会刷一串 `SyntaxWarning: invalid escape sequence`，是老式正则写法，无害。

验证（不用 root）：

```bash
waydroid prop get ro.product.cpu.abilist       # x86_64,x86,arm64-v8a,armeabi-v7a,armeabi
waydroid prop get ro.dalvik.vm.native.bridge   # libndk_translation.so
```

**实跑：企业微信**（2026-09-28）。官网 Android 直链只给 arm64 包，正好当纯 ARM 的验证样本：

```bash
curl -sSI 'https://work.weixin.qq.com/wework_admin/commdownload?platform=android' | grep -i location
# → https://dldir1.qq.com/wework/work_weixin/WeCom_android_5.0.11.81206_arm64_100038.apk（494 MB，只有 lib/arm64-v8a）
waydroid app install WeCom_android_*.apk      # 包名 com.tencent.wework，不需要 sudo
waydroid app launch com.tencent.wework
```

- 装完能启动、窗口持续存活（不是启动即崩），libndk 转译走通。登录与收发消息由用户自行验证。
- APK 留在 `~/Downloads/waydroid-apks/`，sha256 `e83ca845…6039f`。
- 2026-10-09 起这是本机**唯一**的企业微信，桌面 wine 版已卸载（`docs/09`）。

**实跑：微信**（2026-09-28）。官网 `weixin.qq.com` 页面里紧跟 iOS 链接的那个就是 Android 主包，同样只有 arm64：

```bash
curl -sS https://weixin.qq.com/ | grep -o -E 'https?://[^"]*\.apk' | sort -u   # 取版本号最大的 _arm64 那个
# 2026-09-28 为 weixin8078android3180_0x28004e32_arm64.apk（8.0.78，268 MB），dldir1v6 换成 dldir1 也能下
waydroid app install weixin_8.0.78_arm64.apk   # 包名 com.tencent.mm
```

- 启动后停在登录页，窗口持续存活。因为 `persist.waydroid.width/height` 是 2560x1440，
  **微信把自己当平板**，登录页出现「Log in on Tablet Only」—— 走平板登录可以和手机同时在线，不会挤掉手机。
- 升级：重复上面两步即可，`waydroid app install` 对已装的包是覆盖安装，数据保留。
- sha256 `41f7dc1f…c9c1ba`。

---

## 6. 中文输入法：fcitx5-android + Rime

**宿主机的 fcitx5 透传不进去。** Waydroid 没实现 Wayland 的 text-input 协议，
截至 2026-09 相关需求仍是开着的 issue（[#1255](https://github.com/waydroid/waydroid/issues/1255)、
[#792](https://github.com/waydroid/waydroid/issues/792)）。只能在 Android 里装输入法。

选 **[fcitx5-android](https://github.com/fcitx5-android/fcitx5-android) + Rime 插件**，理由：
和宿主机同一个引擎（fcitx5 + rime 朙月拼音），手感一致；对实体键盘支持好（悬浮候选条）；开源。

- 用 **x86_64** 版 APK（原生，不走 libndk）。2026-09-28 装的是 0.1.3，两个包的 sha256 与
  GitHub release 的 `digest` 字段逐一核对通过。APK 留在 `~/Downloads/waydroid-apks/`。
- `waydroid app list` 里**看不到 Rime 插件**是正常的 —— 它只列有桌面图标的 app，插件没有。
- **装完打出来一堆繁体字，不是缺字库**（2026-09-28）：Rime 开箱的方案是 `luna_pinyin`
  （朙月拼音），它**本来就默认出繁体**；宿主机用的是 `luna_pinyin_simp`（朙月拼音·简化字，
  `~/.local/share/fcitx5/rime/user.yaml` 的 `previously_selected_schema` 可查），两边词库是同一套。
  实体键盘按 **F4**（或 ``Ctrl+` ``）弹方案菜单 → 选「朙月拼音·简化字」，Rime 会记住，只需做一次。
  临时切简繁是 `Ctrl+Shift+4`。
- 宿主机的词频（`~/.local/share/fcitx5/rime/luna_pinyin.userdb`）**未同步**进 Android，待办。
- **虚拟键盘时弹时不弹、一按实体键又消失、那时退格失灵**（2026-09-30 修好）。
  两处都要改，缺一不可：
  1. Fcitx5 app → 候选窗口 → **显示候选窗口 = 系统默认**（出厂是「根据输入设备而定」）；
  2. Android 设置 → 系统 → 键盘 → 实体键盘 → **关掉「使用虚拟键盘」**
     （即 `settings put secure show_ime_with_hard_keyboard 0`，adb 直连就能改，不需 root）。

  根因在 fcitx5-android 0.1.3 的 `InputDeviceManager.kt`：「根据输入设备而定」模式下，
  点**尚未聚焦**的输入框沿用上次模式（上次用实体键盘就不弹），点**已聚焦**的输入框
  （`onViewClicked`）**无条件切成虚拟键盘**，再按实体字母键又切回悬浮候选条——所以「时弹时不弹」
  其实取决于点的时候光标在不在那个框里。企业微信的 `EmojiconEditText` 每次点击都调
  `showSoftInput`（logcat 可见），放大了这个问题。
  ⚠ 只关 Android 那个开关**没用**：fcitx5 重写了 `onEvaluateInputViewShown() = true`，
  只有「系统默认」模式才会去问系统设置。改完后有实体键盘时永远是悬浮候选条、虚拟键盘不再出现。
  退格为何只在虚拟键盘那个状态下失灵**没查实**（代码上两种状态走同一条转发路径），
  改完进不去那个状态，没再深究。

---

## 7. 待办 / 未验证

- DPI 未定（第 4 节）。
- 设完 `persist.waydroid.width/height` 后，Android 内的 `wm size` 还没复核到 2560x1440
  （Hyprland 侧窗口尺寸已实测对上）。
- ~~ARM 转译只验证到属性层~~ —— 2026-09-28 已用企业微信（纯 arm64）实跑，见第 5 节。
- Rime 词库同步。
- **偶发：开机后 Android 没网，重启会话即好**（2026-09-28 遇到一次）。症状是 Android 里连网关都
  `Network is unreachable`。宿主机侧全正常（FORWARD 放行规则在、DROP 计数 0、TUN 路由在），坏在 Android 内部：
  `dumpsys connectivity` 显示 Ethernet `CONNECTED` 且 LinkProperties 里有默认路由，
  但 netd 的 `eth0` 路由表是**空的**、`Active default network: none`。
  推测触发条件：会话启动时 eth0 抖了一下（那次 DHCP 做了两遍），内核删掉了该网卡的非内核路由，
  而 IP 没变，Android 认为配置没变，不会把路由加回去。**未复现，触发条件未确认。**
  修法：启动器里点 **「Waydroid 重启」**（`share/applications/waydroid-restart.desktop`，
  等同 `waydroid session stop` 后再打开，不需要 sudo），之后 `eth0` 表里就有
  `default via 192.168.240.1`、ping 和 DNS 都正常。
  做成图标是因为日常是从启动器开 Waydroid 的，不走命令行。官方 `Waydroid.desktop` 其实带了个
  「Stop Waydroid」desktop action，但 noctalia 启动器会不会显示它没确认，而且它只停不重开。
  ⚠ 这个图标会关掉 Android 里所有 app（登录态保留），和 `suspend_action = freeze` 的「关窗只冻结」是两回事。
  排查顺序：先 `sudo waydroid shell -- ip route show table eth0`，空的话直接重启会话，别去动防火墙。
- **摄像头不可用，决定不修**（2026-09-28）。设备已透传进容器并被识别（`external/100`，API1 可见），
  但所有相机 app 零帧，报 "Error while setting up the session"。logcat 关键行：
  ```
  GBM-MESA-WRAPPER: Failed to map the buffer at .../gbm_mesa_wrapper.cpp:228   ← 真正的第一个错
  ExtCamUtils@3.4: formatConvert: unsupported flexible yuv layout y 0x0 ...
  ```
  根因是 minigbm 对 YUV 的 1D fallback 缓冲 import 尺寸算错
  （[android_external_minigbm#3](https://github.com/waydroid/android_external_minigbm/issues/3)），
  与 GPU、摄像头型号无关。**无效的方向**：升级镜像（已是最新）、v4l2loopback（错在 Android 侧缓冲，不在摄像头格式）、
  改 gralloc（`gbm` 撞 #2339，`default` 丢 GPU 加速）。唯一修法是 NDK 独立编 `libgbm_mesa_wrapper.so`
  （32+64 位都要）放进 `overlay/vendor/lib{,64}/`，嫌麻烦没做。上游合并后 `waydroid upgrade` 再试。
  抓日志：`sudo waydroid shell -- logcat -d`（`waydroid logcat` 不认 `-d`）。
  ⚠ 原来视频通话靠宿主机 wine 版企业微信兜底，2026-10-09 wine 版已卸载（`docs/09`），
  现在**本机没有能视频通话的企业微信**。

---

## 8. 企业微信/微信用一阵就卡死，之后永远卡在启动页

**症状**（2026-09-29）：开机后企业微信正常，过一段时间（这次 18 分钟）界面无响应，
之后再点图标永远停在 WeCom 启动页，怎么点都进不去。微信的推送进程同病，只是没界面、不显眼
（开机 2 分钟就中招，表现是收不到消息）。

### 根因：fork 出来没 exec 的子进程，在 libndk 下挂死

```
app 里某个线程 popen / vfork（mars::4011、qm-thread-2、DefaultDispatch …）
  → 子进程在 libndk_translation 下还没 exec 就挂住，comm 保持发起线程的名字
  → 父线程 vfork 等待，D 态（ANR trace 里是 state=D + "Thread has not responded to signal"）
  → 主线程被拖住 → ANR → 点「关闭应用」，AMS 杀掉主进程
  → 但子进程继承了 /dev/binder 的 fd，binder 不释放，AMS 收不到死亡通知
  → 之后每次启动：「<pid> refused to die while trying to launch ... cancelling the process start」
```

真机上 AMS 用 `killProcessGroup` 连子进程一起杀，这里杀不到 —— **容器里 `/sys/fs/cgroup`
是只读的 cgroup2**，libprocessgroup 建不了 per-app 进程组（logcat：
`Failed to make and chown /sys/fs/cgroup/uid_10127: Read-only file system`），
所以 app fork 的东西 AMS 管不着。

**判据**（宿主机，不用 sudo）：
- `adb logcat -d | grep 'refused to die'`（adb 免 sudo：`adb connect <waydroid status 里的 IP>:5555`；`adb root` 不可用）
- 某个 app 进程的线程处在 D 态、且它有个子进程顶着那个线程的名字

2026-09-29 当场抓到的：企业微信 `mars::4011`（活了 3 小时，占 900 MB）、微信推送的 `mars::2548/2570`；
清掉后重开企业微信，一分钟内又冒出 `qm-thread-2`、`DefaultDispatch` 两个 —— 发起线程不固定，
**所以清理规则不按名字认**。01:09 那次企业微信 ANR 里也有 `mars::3691` 处在 D 态，是同一个病，不是偶发。

### 解法：宿主机常驻清理服务 `waydroid-fork-reaper`

每 15 秒扫一遍容器 cgroup，同时满足四条就 `SIGKILL`：

1. `/proc/<pid>/stat` 的 flags 带 **`PF_FORKNOEXEC`**（0x40）—— fork 后从没 exec 过。正常的 popen 子进程几毫秒内就 exec 成 `sh` 了。
2. 父进程**不是 zygote** —— 正常 app 进程全是 zygote 生的（它们也带 PF_FORKNOEXEC，靠这条排除）。
3. **comm ≠ cmdline 末 15 字符** —— 放过 system_server 崩溃重启后遗留的旧 app 进程
   （本机实测有 permissioncontroller、launcher3 两个，父进程也已是 init，但名字对得上）。
4. 活过 30 秒。会话被冻结（关窗 `freeze`）时整轮跳过，因为冻结期间存活时长照涨但并没卡。

在卡死阶段就杀掉子进程，父线程的 vfork 等待随即返回，**app 本身不用重启**，通常连 ANR 都走不到。
实测：装上后当场清掉 5 个，企业微信、微信推送随即恢复；微信推送重启后又连冒 3 轮，都被清掉后稳定。

做成常驻循环而不是 timer：timer 每 15 秒会往 journal 写一遍 Starting/Finished。
`PartOf` + `WantedBy=waydroid-container.service`，跟容器服务同起同停。
只要 `CAP_KILL`；读的 `/proc/<pid>/{stat,cmdline}` 都是全员可读，**不用 sudo 就能 dry-run**：

```bash
DRY_RUN=1 MIN_AGE=0 /usr/local/bin/waydroid-fork-reaper --once   # 看现在有哪些候选
journalctl -u waydroid-fork-reaper                                 # 看杀过谁
```

⚠ 别往「换 libhoudini 就好了」上赌：没有证据表明 houdini 的 vfork 更靠谱，没试过。
这个服务治的是后果（僵死子进程占 binder），不管转译层换成什么都兜得住。

`/usr/local/bin/waydroid-fork-reaper`：

```bash
#!/bin/bash
# 杀掉 Waydroid 里 fork 出来却卡死、没能 exec 的 app 子进程（企业微信/微信「卡在启动页再也进不去」）。
# app 线程 popen/vfork 出的子进程在 libndk 转译下没 exec 就挂住，父线程随之 D 态等它 → ANR；
# 父进程被杀后它又占着继承来的 binder fd，AMS 收不到死亡通知 →「refused to die」，app 再也起不来。
# 一开始只见到 mars:: 线程发起的，后来又见到 qm-thread-2、DefaultDispatch，所以不按名字认，按下面四条：
#   1. 内核标志 PF_FORKNOEXEC：fork 之后从没 exec 过
#   2. 父进程不是 zygote：正常的 app 进程都是 zygote 生的，这里只剩 app 自己 fork 的（或已成孤儿的）
#   3. comm 不等于 cmdline 的末 15 字符：它顶着发起线程的名字（mars::4011），不是 app 名 ——
#      这条放过 system_server 崩溃重启后留下的旧 app 进程（父进程也是 init，但名字对得上）
#   4. 活过 MIN_AGE 秒：正常 vfork 子进程几毫秒内就 exec 了
# 原理与排查过程见 ~/cachyOS-config/docs/12-waydroid.md 第 8 节。
set -u
cg=/sys/fs/cgroup/lxc.payload.waydroid
interval=${INTERVAL:-15}
min_age=${MIN_AGE:-30}
PF_FORKNOEXEC=0x40

reap() {
    [[ -d $cg ]] || return 0
    # 关窗后会话被冻结（suspend_action=freeze），存活时长照涨但并没卡，跳过
    grep -qx 'frozen 1' "$cg/cgroup.events" 2>/dev/null && return 0
    local clk now pid stat comm rest f ppid flags start age name name15 pname
    clk=$(getconf CLK_TCK)
    read -r now _ < /proc/uptime
    for pid in $(find "$cg" -name cgroup.procs -exec cat {} + 2>/dev/null); do
        stat=$(cat "/proc/$pid/stat" 2>/dev/null) || continue
        comm=${stat#*(}; comm=${comm%)*}
        rest=${stat##*) }
        read -r -a f <<< "$rest"                      # f[0]=state，即 stat 第 3 列
        ppid=${f[1]} flags=${f[6]} start=${f[19]}
        (( flags & PF_FORKNOEXEC )) || continue
        pname=$(tr '\0' ' ' < "/proc/$ppid/cmdline" 2>/dev/null)
        [[ $pname == *zygote* ]] && continue
        name=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -1)
        (( ${#name} > 15 )) && name15=${name: -15} || name15=$name   # 短于 15 时 ${name: -15} 是空串
        [[ -n $name && $comm != "$name15" ]] || continue
        age=$(( ${now%.*} - start / clk ))
        (( age >= min_age )) || continue
        if [[ ${DRY_RUN:-} ]]; then
            echo "would kill pid=$pid comm=$comm app=$name age=${age}s"
        elif kill -KILL "$pid" 2>/dev/null; then
            echo "killed pid=$pid comm=$comm app=$name age=${age}s"
        fi
    done
}

[[ ${1:-} == --once ]] && { reap; exit 0; }
while :; do reap; sleep "$interval"; done
```

`/etc/systemd/system/waydroid-fork-reaper.service`：

```ini
# 跟 waydroid-container 同生命周期：容器起它就起，容器停它就停。
# 做成常驻循环而不是 timer：timer 每 15 秒会往 journal 写一遍 Starting/Finished。
[Unit]
Description=Kill stuck never-exec forks of Waydroid apps (WeCom/WeChat hang)
Documentation=file:///home/david/cachyOS-config/docs/12-waydroid.md
After=waydroid-container.service
PartOf=waydroid-container.service

[Service]
ExecStart=/usr/local/bin/waydroid-fork-reaper
Restart=on-failure
CapabilityBoundingSet=CAP_KILL
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateNetwork=yes

[Install]
WantedBy=waydroid-container.service
```
