# 00 · 装系统之前：发行版、启动盘、镜像、动态壁纸

本篇是**装 CachyOS 本身**的决策与操作，发生在 [INSTALL.md](../INSTALL.md) 之前。
系统装好之后就不用再看这篇了。

> 整理于 2026-08-25。命令与包名基于当时的 Arch / CachyOS 状态，执行前建议对照上游文档确认。
>
> ⚠️ **本篇第 6、7 节的组件选型不是本配置在用的东西**，见那两节开头的说明。

---

## 1. 发行版选择

按「Arch 系 + Hyprland + 轻量」排序。注意正确拼写是 **Hyprland**，不是 Hyperland——
搜资料时很关键。

| 发行版 | 特点 | 适合 |
|---|---|---|
| **CachyOS**（本配置用的） | Arch 内核 + 性能优化，安装器可直接选 Hyprland 桌面，开箱已配好 | 想少折腾又要性能 |
| 原版 Arch | 最轻最可控，零预装冗余，需手动装 Hyprland | 愿意花两三小时配置，上限最高 |
| Omarchy | Arch + Hyprland 固执己见发行版，装完即用，审美统一 | 接受别人的配置口味 |
| Archcraft | 极简取向，多 WM 可选含 Hyprland，非常轻 | 社区较小，能自己解决问题 |
| EndeavourOS | 接近原版 Arch 体验 + 友好安装器 | 要官方仓库纯净度 |

**不建议**：Manjaro（仓库延迟发布会与 AUR 打架，装 `-git` 类包容易踩编译问题）；
Garuda Hyprland 版（能用但预装太多，与轻量目标冲突）。

**折中方案**：想要 CachyOS 的内核收益但不想引入第三方仓库依赖——装原版 Arch 或
EndeavourOS，然后单独装 `linux-cachyos` 内核。内核那部分是主要收益，指令集重编译的
几个百分点性价比一般。这样核心包全是 Arch 官方的，出问题排查路径干净。

---

## 2. CachyOS 优化了什么，代价是什么

**编译层面**：维护了 x86-64-v3 / v4 以及 Zen4 专门优化重编译的仓库，配合 `-O3`、LTO、
部分包 PGO。安装时自动检测 CPU 选对应仓库。实测收益通常个位数百分比，编译/压缩/转码
明显一点，日常点开应用感知不到。

> 老 CPU 不用担心：Intel 4 代以前没有 AVX2，安装器检测到会自动落回通用仓库。

**内核（真正的大头）**：`linux-cachyos` 系列，可选多种调度器——

- **BORE**（默认）：偏向交互响应，桌面手感比上游 EEVDF 更跟手
- **sched-ext / scx 系列**（`scx_lavd`、`scx_bpfland`、`scx_rusty`）：BPF 实现的可热插拔
  调度器，游戏与低延迟场景有优势
- 其他：1000Hz tick、preempt full、THP 默认开、BBRv3 拥塞控制、LRU 优化

**系统默认值调优**：btrfs + zstd + 自动快照 · zram 默认开 · `ananicy-cpp` 自动分配进程
优先级 · 按设备类型分 I/O 调度器（NVMe `none`、HDD `bfq`）· 关闭 split lock mitigation ·
游戏向的 proton-cachyos / gamemode。

### 代价与权衡

**主要风险是多了一个第三方仓库依赖。** CachyOS 仓库优先级高于 Arch 官方，且重新打包了
一部分核心包（glibc、gcc、mesa、systemd）。打包质量一直不错，但系统从此依赖一个小团队的
维护节奏。同步通常滞后几小时到一天，偶尔出现版本与官方错位导致的依赖冲突，需手动处理。
**这是「是否接受」的问题，不是「会不会坏」的问题。**

- `-O3`/LTO：极少数情况会把软件自身的未定义行为暴露成诡异 bug，历史上有个别案例
- scx 调度器：较新，偶发卡顿可直接停服务回退到 BORE，代价很低
- 内核更新频繁：DKMS 模块（NVIDIA、VirtualBox）要跟着重编。CachyOS 提供预编译 nvidia 包
- 关闭 split lock mitigation：理论上有本地 DoS 面，桌面场景无实质影响
- **求助渠道变窄**：Arch 官方论坛/Wiki 对修改过的发行版态度是「不支持」，得去 CachyOS
  自己的 Discord/论坛，活跃但规模小

基础没变：仍同步上游 Arch 仓库，AUR 完整可用，pacman 就是 pacman。

---

## 3. 用 Ventoy 制作启动盘

### 写入 Ventoy 到 U 盘

- **用较新版本**：1.1.05 之后对新 archiso/dracut 引导兼容修得较全。老版本（1.0.7x 及更早）
  遇到新 ISO 偶尔卡在 initramfs 找不到镜像
- 分区方案选 **GPT + UEFI**
- 文件系统用 **exFAT，别选 FAT32**。CachyOS ISO 约 2.5–3 GB 虽未超 4 GB 限制，但 exFAT
  省心，以后放大镜像不用重做
- **USB 3.0 口 + 3.0 盘**：squashfs 不小，2.0 口上启动能慢到让人以为卡死

### 拷入 ISO：先校验 sha256，别跳过

Ventoy 引导失败最常见的原因就是下载不完整，而**报错信息完全不会提示你这一点**。

```powershell
# Windows PowerShell
Get-FileHash .\cachyos-desktop-linux-*.iso -Algorithm SHA256
```
```bash
# Linux
sha256sum cachyos-desktop-linux-*.iso
```

文件名保持原样，放根目录或英文目录下——路径含中文或特殊符号时 Ventoy 偶发解析问题。

### BIOS/UEFI

- **关掉 Secure Boot。** Ventoy 自带签名 shim 理论上能在 Secure Boot 下启动，但它加载 ISO
  时会绕过后续验证，行为不完全可预期；且 CachyOS 的 ISO 内核不是微软签名的，多半直接被拒。
  装完系统后如需开启，可用 `sbctl` 自签名，那是另一件事。
- **关掉 Fast Boot**（UEFI 里跳过设备枚举的选项），否则可能识别不到 U 盘
- 双系统额外两件：Windows 里关掉 **Fast Startup**（休眠式关机会让 NTFS 处于脏状态）；
  BitLocker 先暂停或记好恢复密钥

### 进菜单后

- 选中 ISO，按 Enter 用默认 **Normal 模式**先试
- 卡在「找不到根设备」之类的错误 → 按 **F6 切 GRUB2 Mode** 再试。这是 Ventoy 应对
  Arch 系 ISO 的标准降级路径
- NVIDIA 黑屏/花屏 → 引导菜单有对应选项；实在不行加 `nomodeset` 先把安装器跑起来

> **判断标准很简单**：两种模式都进不去就别耗着，直接用 `dd`（Windows 下 Rufus 的 DD 模式）
> 把 ISO 原生写盘——这是 CachyOS 官方推荐方式，兼容性最好，代价只是这块 U 盘暂时只能放
> 一个镜像。**Ventoy 是为了方便，不是必须品，卡住超过十分钟就换。**

---

## 4. 安装过程要点

> 🔴 **选目标磁盘时格外看清楚，别把 Ventoy U 盘选进去。**
> 它在 Calamares 里会显示成一个正常磁盘（一个大 exFAT 分区 + 一个 32 MB EFI 分区），
> 跟内置盘混在同一列表。**按容量和型号确认，别只看 `/dev/sdX` 编号**——编号顺序不固定。
> 手动分区模式下尤其小心，这一步弄错不可逆。

- **装 Hyprland 需要联网**：安装器选桌面环境时是从网络拉包的。先连好 Wi-Fi 或插网线
- **先改镜像再点安装**：安装器通常能进 TTY（`Ctrl+Alt+F2`），把 mirrorlist 改成国内源
  再回去装，能省不少时间。见下一节
- 装完**拔掉 U 盘**再重启，别让 UEFI 又从 Ventoy 起来
- 双系统确认引导项能看到 Windows；看不到则进系统后跑一次 `os-prober` 相关配置

装完系统后，接着走 [INSTALL.md](../INSTALL.md) 装本配置。

---

## 5. 软件包从哪里下载：镜像与 AUR

Hyprland 从**镜像**下载，与 hyprland.org 无关——官网只是项目主页和文档，不是软件源。

**官方仓库的包**：Hyprland 现已进入 Arch 官方 `extra` 仓库（早年在 AUR，后来提升），
`pacman -S hyprland` 走的是 `/etc/pacman.d/mirrorlist`。

CachyOS 上**多一层**：若它针对你的 CPU 重编译了某个包，会优先从自己的仓库
（`cachyos-v3`/`v4`）取，那份列表在 `/etc/pacman.d/cachyos-mirrorlist`，与 Arch 官方列表
并行存在。**所以要关心两份 mirrorlist。**

### AUR 的行为不一样

AUR 只存 PKGBUILD 脚本，不存编译好的包，也不存源码：

| 环节 | 来源 | 速度 |
|---|---|---|
| PKGBUILD | `aur.archlinux.org` | 无官方国内镜像渠道 |
| **源码** | 直接 `git clone` GitHub | **真正会卡的地方** |
| 依赖的官方包 | 走 pacman 镜像 | 快 |

> **关键区别**：官方仓库的包换镜像就够快；**AUR 包的慢是慢在 GitHub 上，换 pacman
> 镜像对它没有任何帮助**。这条得靠代理或 GitHub 镜像解决。

### 换镜像

```bash
# Arch 官方那份：编辑 /etc/pacman.d/mirrorlist，国内源放最前
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch

# 或按测速自动排序
sudo reflector --country China --protocol https --latest 20 --sort rate \
  --save /etc/pacman.d/mirrorlist

# CachyOS 那份用自带工具，不要手写（会同时给两个仓库测速排序）
sudo cachyos-rate-mirrors
```

---

## 6. ⚠️ Wayland 组件生态（**本配置不用这一套**）

> **本配置用的是 CachyOS 自带的 `cachyos-hypr-noctalia`**：noctalia 一个包同时提供
> 顶栏、启动器、通知、锁屏、主题引擎；终端是 kitty。**不是**下面这套 waybar + fuzzel +
> mako + foot 的组合。
>
> 这一节保留是因为它讲清了 Hyprland 下各类组件的分工——**换机器时不需要执行它**，
> 只在你想脱离 noctalia 自己拼一套时才有用。装本配置请看 [INSTALL.md](../INSTALL.md)。

```bash
# 核心
sudo pacman -S hyprland xdg-desktop-portal-hyprland
# 会话 / 锁屏 / 待机
sudo pacman -S greetd greetd-tuigreet hyprlock hypridle
# 状态栏 / 通知 / 启动器
sudo pacman -S waybar mako fuzzel
# 终端 / 文件管理
sudo pacman -S foot yazi thunar
# 音频 / 剪贴板 / 截图
sudo pacman -S pipewire pipewire-pulse wireplumber wl-clipboard grim slurp
# 壁纸：静态 + 动态
sudo pacman -S hyprpaper swww mpvpaper
```

**启动器选型**（同样不适用于本配置，noctalia 自带启动器）：

| 启动器 | 轻重 | 说明 |
|---|---|---|
| fuzzel | 极轻 | 原生 Wayland，启动几乎无延迟 |
| tofi | 最轻 | 比 fuzzel 更极端，追求毫秒级 |
| wofi | 轻 | 老牌，CSS 可定制 |
| rofi-wayland | 稍重 | 功能最全：dmenu、剪贴板、窗口切换、电源菜单 |
| walker / anyrun | 最重 | 插件化，计算器、翻译、文件搜索扩展强 |

**现成 dotfiles**（想省事又不用本配置时）：HyDE（完整度高，结构清晰）·
JaKooLit/Hyprland-Dots（安装脚本齐全）· end-4/dots-hyprland（偏华丽，稍重）。

---

## 7. Wallpaper Engine 在 Wayland 下的方案

**能用，但不是 Steam 上那个官方 Wallpaper Engine。** 三条路：

### 方案一：Steam 官方版 —— 基本不可行

至今没有原生 Linux 版。用 Proton 能把程序跑起来，但**只能显示在普通窗口里，无法真正
接管桌面背景层**。X11 时代有人用 `xwinwrap` 硬塞，Wayland 下连这个 hack 都没有。放弃。

### 方案二：linux-wallpaperengine —— 实际可行

社区开源重实现（`Almamu/linux-wallpaperengine`），直接读取 Steam 创意工坊**已下载的**
壁纸资源来渲染。已支持 `wlr-layer-shell`，能在 Hyprland 上正常作为背景层使用。

```bash
paru -S linux-wallpaperengine-git

# Wayland 下 --screen-root 填 hyprctl monitors 里的输出名
linux-wallpaperengine --screen-root DP-1 --bg 1234567890 \
  --assets-dir ~/.steam/steam/steamapps/common/wallpaper_engine/assets \
  --scaling fill --fps 30 --silent
```

前提是本地要有创意工坊内容，路径通常是
`steamapps/workshop/content/431960/<壁纸ID>/`。获取方式：在 Linux Steam 里用 Proton 装
一次 Wallpaper Engine 订阅壁纸，或直接从 Windows 分区把 workshop 目录拷过来。

| 壁纸类型 | 支持程度 | 备注 |
|---|---|---|
| 视频类 | 基本没问题 | 最稳，首选这类 |
| Scene 场景类 | 大部分能跑 | 粒子 / 音频反应 / 鼠标交互属半支持 |
| **Web（HTML5）类** | **最差** | 依赖 CEF，经常直接不行 |
| 多屏 | 支持 | 每个 `--screen-root` 单独指定 |

### 方案三：只要动态效果，不要 WE 生态

很多 WE 壁纸本质就是个 mp4。用 RePKG 把 `.pkg` 解出来拿到视频文件，交给 `mpvpaper`：

```bash
mpvpaper -o "no-audio loop hwdec=auto" DP-1 ~/Videos/wallpaper.mp4
```

最轻、最稳、最省心，缺点是失去 WE 的交互和参数调节。

> 如果 Wallpaper Engine 的完整体验是第一优先级，KDE Plasma 6 +
> `wallpaper-engine-kde-plugin` 的支持度明显好于 Hyprland。但那就不是轻量 Hyprland 了。

---

## 8. 动态壁纸的功耗控制

动态壁纸持续占 GPU，这是实际代价。两个手段：

1. **限帧**：`--fps 30` 能省不少电，视觉损失很小
2. **全屏时暂停**：监听 Hyprland IPC socket，检测到全屏窗口就暂停进程

```bash
#!/usr/bin/env bash
# ~/.config/hypr/we-autopause.sh   需要 socat
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - UNIX-CONNECT:"$SOCK" | while read -r line; do
  case "$line" in
    fullscreen\>\>1) pkill -STOP -x linux-wallpaperengine ;;
    fullscreen\>\>0) pkill -CONT -x linux-wallpaperengine ;;
  esac
done
```

> ⚠️ **未在真机验证。** socket2 的事件名在版本间偶有调整。不生效就先跑
> `socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`
> 观察实际输出，再对着调整匹配串。
>
> 另外本配置的自启动写在 `~/.config/hypr/config/autostart.lua`（Lua 的
> `hl.exec_cmd(...)`），不是 `exec-once =`。

`hypridle` 里也可以顺手接上「关屏前先暂停壁纸」：

```ini
listener {
    timeout = 300
    on-timeout = pkill -STOP -x linux-wallpaperengine; hyprctl dispatch dpms off
    on-resume  = hyprctl dispatch dpms on; pkill -CONT -x linux-wallpaperengine
}
```

---

## 9. 装机阶段故障排查

| 现象 | 先查什么 |
|---|---|
| Ventoy 引导卡在 initramfs | 校验 ISO sha256；Ventoy 升到 1.1.05+；按 F6 试 GRUB2 Mode |
| 识别不到 U 盘 | UEFI 里关 Fast Boot 和 Secure Boot；换 USB 3.0 口 |
| 安装器里分不清哪个盘 | 按容量和型号认，**不看 `/dev/sdX` 编号** |
| 安装 Hyprland 桌面时极慢 | 进 TTY 先改**两份** mirrorlist（Arch + CachyOS） |
| AUR 包卡在 clone | 那是 GitHub 网络，换 pacman 镜像无效，需代理 |
| Hyprland 启动黑屏（NVIDIA） | 装 `nvidia-dkms`；检查环境变量；临时用 `nomodeset` |
| 动态壁纸不显示 | `hyprctl monitors` 确认输出名；确认 `--assets-dir` 与 workshop 路径存在 |
| Web 类壁纸完全无效 | 已知限制，改用视频类或走 RePKG + mpvpaper |
| GPU 占用持续偏高 | 加 `--fps 30`；接上全屏暂停脚本 |
| 更新后依赖冲突 | CachyOS 与 Arch 版本错位，等几小时或手动指定版本 |

系统装好之后的问题看 [07-troubleshooting.md](07-troubleshooting.md)。

---

## 已删除的一节

原文档第 10 节是一份完整的**传统 `hyprland.conf`**（`bind = SUPER, F, fullscreen, 0`
那种写法）+ waybar/hyprlock 配置。已删除，原因有二：

1. **范式不对。** 本机用的是 Hyprland 0.56+ 的 **Lua 配置**（`hl.bind` / `hl.dsp.*`），
   与 `.conf` 写法不通用。真实配置见 [02-hyprland.md](02-hyprland.md)。
2. 原文自己标注了「未在真机验证」。

需要传统 conf 写法的话，Hyprland wiki 是更可靠的来源。
