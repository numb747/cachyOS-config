# 08 · Claude Code 本机工具

装在 `~/.claude/` 下的三件东西：**上下文占比状态栏**、**多会话看板**、**宠物版 TUI（能就地代答）**。
由 `install.sh cc` 安装，`manifest.map` 的 `#@module cc` 段是路径的单一事实来源。

Agent Teams（一个队长 claude 指挥几个队员、tmux 分屏、团队日志）也在 cc 模块里，但写在
[14-tmux.md](14-tmux.md) 第 7 节 —— 它和 tmux 绑得更紧。

`arch-map` skill（给 git 项目画架构地图）也归 cc 模块，见第 8 节。

用手机 Discord 远程驱动本机 Claude Code（claude-discord-sync）**不在 cc 模块里**，只是记在这，见第 9 节。

提示缓存用 1h 还是 5m 见第 10 节；在这个设置下什么时候 `/compact`、离开前和 `/resume` 回来怎么做最省，见第 11 节。

全部实测于 **Claude Code 2.1.246**。凡是写「实测」的结论，都跟直觉相反过，改之前先看第 4 节。

---

## 1 · 三个入口

| 命令 | 是什么 |
|---|---|
| `ccw` | 常驻看板，纯文本，2 秒刷新。有会话新进入等待状态会响一声铃 |
| `ccs` | 打一次快照就退出。适合塞进别的状态栏 |
| `ccp` | 宠物版 curses TUI。能上下选、**能就地把别的终端里那道选择题答掉** |
| —— | 状态栏没有命令，装完自动出现在 Claude Code 底部 |

alias 定义在 `home/.zshrc`（**term 模块**）。所以只装 `term` 不装 `cc`，会得到三个指向不存在文件的 alias。

```
[Opus 5·high] web-admin │ ███░░░░░░░ 33% 338k/1000k $0.47
```

```
   /\_/\      Claude 会话看板
  ( O_O ) !   3 个会话 · 1 个等你处理

 ▸ ▲ web-admin-2c   ~/Projects/web-admin   等你回答     1m37s
   ● web-admin-cb   ~/Projects/web-admin   忙碌        10m48s
   ○ david-08       ~                      空闲        36m58s

   ↑↓/jk 选择   Enter 代答   r 刷新   q 退出
```

猫有五种心情，取**最需要注意的那一档**而不是多数决：一个会话在等你，哪怕另外五个都在跑，它也是警觉脸。

---

## 2 · 数据从哪来

Claude Code 自己维护着每个会话的实时状态，**不需要 hook**：

| 来源 | 内容 | 成本 |
|---|---|---|
| `claude agents --json` | 权威列表。**唯一提供 `waitingFor`**（区分"等授权"/"等回答"） | 0.2s / 次 |
| `~/.claude/sessions/<pid>.json` | 含 `statusUpdatedAt`，用来算"这状态持续多久" | 0.5ms / 次 |
| `~/.claude/projects/*/<sid>.jsonl` | transcript，用来读"它到底在问什么" | 读文件 |

⚠ **TUI 版 `claude agents` 只显示后台会话**，交互式终端不 `/bg` 就不出现；但 `--json` 会列出交互式会话。
两者口径不同 —— 这是整个看板能成立的全部前提。

`ccp` 三个时钟各走各的：动画 100ms、状态 400ms（读文件）、`claude agents --json` 1.5s 扔后台线程。
不这么拆的话，10fps 去调那个 0.2s 的命令等于把一个核吃满。

---

## 3 · 状态栏为什么要 install.sh 特殊处理

`statusline.sh` 要靠 `~/.claude/settings.json` 里的 `statusLine` 段才生效，而**那个文件含明文
API token、永不入包**（见 `manifest.map` 文末排除段、`README.md` 的密钥清单）。

所以 `mod_cc` 用 `jq` 把那一个键**合并**进本机已有的 settings.json：只写不读 token，改前备份，
写临时文件再 `mv`。三条分支都实测过：

| 情况 | 行为 |
|---|---|
| 已指向本包脚本 | 跳过，不重复备份 |
| 有 settings.json 但没 statusLine | 合并。token / base_url / theme / 插件全部原样保留 |
| 没有 settings.json | 只建一个带 statusLine 的最小文件，token 你自己填 |
| 没装 jq | 只 warn，**绝不碰已有文件** |

手动加的话就是这一段：

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh",
  "padding": 1
}
```

---

## 4 · 就地代答：实测出来的按键序列

`ccp` 选中一个"等你回答"的会话按 Enter，会读出它在问什么并列出选项，再按 Enter 就替你选了。
底层是 **nvim RPC `chansend`** 把按键送进那个 terminal buffer 里跑着的 claude。

> **为什么要绕这一圈**：Claude Code 对交互式会话只给只读 —— `claude logs/attach/stop` 全都报
> `No job matching`，它们只认后台会话。但终端栈自己有通道。

### 心智模型

顶部是一排标签 `← [第1题] [第2题] … [✔ Submit] →`，光标在**当前标签**的选项列表里。

| 在哪 | 怎么操作 |
|---|---|
| 单选题标签 | `↓` 移动，**`Enter` = 选中并切到下一个标签** |
| 多选题标签 | `空格` 勾选当前项，`↓` 移动，**`→` = 切到下一个标签** |
| Submit 标签 | `Enter` 提交（光标停在 `Submit answers`） |

⚠ **唯一的例外：单个单选题没有 Submit 标签**，那个 `Enter` 当场就提交完了。
其余情况（多个问题、或单个多选题）最后都要**再多按一次 Enter**。多按或少按都是错的：
少按停在 review 页不提交，多按会打进输入框。

### 四条反直觉的结论

**① 数字键在 AskUserQuestion 选择器里无效。**
实测发 `2`，光标纹丝不动；再按 Enter 仍然选中第 1 项。底栏原话只有
`Enter to select · ↑/↓ to navigate · Esc to cancel`。
⚠ 「是否信任此文件夹」那个框**认数字键而且按下即提交**，那是另一个界面，别混。

**② 单选题的 `Enter` 是「选中 + 前进」两件事。**
多问题时答完第 1 题会**自动跳到第 2 题**，不需要自己按 `→`。
而且新题的**光标复位到第 1 项** —— 下标是每题独立的，不累加。

**③ 多问题答完最后一题会落在 review 页**，长这样：

```
←  ☒ 颜色  ☒ 水果  ✔ Submit  →
Review your answers
 ● 你喜欢什么颜色？  → AAA
 ● 你喜欢什么水果？  → DDD
Ready to submit your answers?
❯ 1. Submit answers
  2. Cancel
```

**④ 必须逐键发、间隔 ~0.2s。**
一次性把 5 个键灌进去，首个空格和末尾回车会在 TUI 重绘的间隙里被丢掉 ——
review 页只勾上了一项，而且停在没提交的状态。

### 按键序列速查

| 情况 | 序列 |
|---|---|
| 1 题单选，选第 3 项 | `↓ ↓ Enter` |
| 1 题多选，选第 1+3 项 | `空格 ↓ ↓ 空格 → Enter` |
| 2 题单选，选第 3 项 + 第 1 项 | `↓ ↓ Enter` `Enter` `Enter` |
| 3 题单选，各选第 2 项 | `↓ Enter` `↓ Enter` `↓ Enter` `Enter` |
| 混合：第 1 题单选第 2 项 + 第 2 题多选第 1+3 项 | `↓ Enter` `空格 ↓ ↓ 空格 →` `Enter` |

`cc_common.py` 的 `build_keys(questions, picks)` 就是这张表，`test-cc.py` 里每行都有对应断言。

### 三个只在真跑时才暴露的静默陷阱

**① `nvim --remote-expr` 的 stdin 必须 `DEVNULL`。**
调用方是 curses 应用时，子进程继承 raw 模式的 tty，`--remote-expr` 会**返回空串而且退出码是 0**。
同一时刻、同一 socket，普通进程算得出结果，curses 里是空 —— 靠这个对照才定位到。

**② halfdelay 下 ncurses 会把箭头键拆成 ESC、`[`、`B` 三次 getch 返回。**
上下键整个失灵且不报错。第一次端到端就是这么选错的：面板里按 ↓ 光标没动，结果选了第 1 项。
`cc-pet.py` 的 `read_key()` 自己把拆开的序列拼回去。

**③ 匹配 terminal buffer 必须用整条祖先链。**
不能只比 claude 的直接父进程 —— `:terminal` 跑复合命令会留一层 `sh -c` 不 exec 掉，层数不定。

### 怎么定位到某个会话在哪个 nvim 里

读 `/proc/<pid>/environ` 里的 **`NVIM`** 变量。nvim 会把自己的 socket 路径注入到 `:terminal`
起的所有子进程环境里。这比"往上走找第一个 nvim 再拼 `/run/user/UID/nvim.<pid>.0`"可靠得多：
任意 `--listen` 路径都认，也不依赖"取第一个还是最后一个 nvim"那个容易搞反的启发式。

⚠ 顺带：进程链里**可能有两个 nvim**（内层带 socket、外层不带）。靠猜路径的写法必须取第一个。

### 多问题的界面

面板把**所有问题一起列出来**，光标走的是摊平后的行（跨题连续），空格选中：

```
代答 · web-admin-2c   共 2 题
────────────────────────────────
1. 你喜欢哪个颜色？
   单选
   ○ 红色
   ○ 蓝色
 ▸ ◉ 绿色
2. 你喜欢哪个水果？
   单选 · 未选
   ○ 苹果
   ○ 香蕉
   ○ 橙子

↑↓/jk 移动   空格 选中   q 取消   还差第 2 题没选
```

**每题都选了才让按 Enter** —— 底栏会明确告诉你还差第几题。单选题的空格是单选钮语义
（顶掉原来那个），多选题是切换。

### 刻意不做的

- **权限提示框** —— 另一套 UI。非 AskUserQuestion 的等待一律只显示、不代答。
- **打字输入** —— 只选预设项。选项列表末尾那个 `Type something` 不在代答范围内。
- **没有预设选项的问题** —— 面板拒绝并说明是第几题。

### 注入前的复核闸

按下 Enter 后、真正注入前，会重新确认那个会话还在 `waiting`、待答题还是同一道 id。
**如果这中间你已经在终端里自己答了**，选择器早就没了，这时候再灌箭头键会打进输入框 ——
所以状态对不上必须中止。

---

## 5 · 会漂的一环

判定"有没有待答问题"靠解析 transcript 的 JSONL：**有 `tool_use` 但没有对应 `tool_result`**
就是在等。这个判据本身不依赖任何字段的业务含义，比按时间取最后一条稳。

但**官方明说 transcript 是内部格式、版本间会变**（见 `docs/en/sessions` 的
"Where transcripts are stored"），而这台机器 `autoUpdatesChannel: latest` 是自动更新的。

所以：哪天 Claude Code 更新之后 `ccp` 的代答面板打不开、或者报「问题结构读不出来」，
就是这里漂了。按键序列同理 —— 全部实测于 2.1.246，写在 `cc_common.py` 的注释里。

`ccw` / `ccs` / 状态栏不依赖 transcript，不受影响。

---

## 6 · 文件与测试

| 文件 | 行数 | 干什么 |
|---|---:|---|
| `cc_common.py` | 544 | 判据 + 数据采集 + 路由解析 + 按键/注入。两个前端共用 |
| `cc-pet.py` | 497 | 宠物版 curses TUI |
| `cc-watch.py` | 128 | 纯文本看板（只剩渲染，判据全在 common） |
| `statusline.sh` | 52 | 状态栏 |
| `test-cc.py` | 203 | 86 条单元测试，纯函数、零成本。数以实跑为准：`test-cc.py \| grep -c '^  [✓✗]'` |
| `e2e_answer.py` | 170 | 数据层端到端（`multi` 参数切多选） |
| `e2e_ui.py` | 180 | 界面级端到端，pty 驱动 `ccp` 真答一道题（`multiq` 参数切两问题） |
| `pty_drive.py` | 84 | TUI 冒烟 |
| `probe_multiq.py` | 96 | 探针：多问题选择器长什么样、按键怎么走。**格式漂了就先跑它重新摸一遍** |

```bash
python3 ~/.claude/test-cc.py                      # 日常改动跑这个就够，秒回
python3 ~/.claude/test-cc.py /tmp/mutant.py       # 传路径测变异体，验测试本身有效
python3 ~/.claude/e2e_ui.py                       # ⚠ 起真 claude 会话，烧 API 额度，约 3 分钟
python3 ~/.claude/e2e_ui.py multiq                # 同上，测两个问题的那条路径
python3 ~/.claude/e2e_answer.py multi             # 数据层，多选题
```

⚠ **三个 e2e 脚本会起真 claude 子会话。测试用的子会话必须 `env -u CLAUDE_CODE_CHILD_SESSION`**，
否则不写 transcript，整套检测无从谈起（脚本里已经处理了，改的时候别删）。

---

## 7 · 排错

**`ccp` 起不来** —— `python3 -c 'import curses'` 试一下。Arch 的 python 自带，别的发行版可能要单装。

**看板空的** —— `claude agents --json` 自己跑一下。空数组说明真没有会话在跑。

**状态栏不显示** —— `jq '.statusLine' ~/.claude/settings.json` 看有没有那一段（见第 3 节）。
另外新会话在第一条消息之前百分比恒为 0，那是正常的：数据取自最近一次 API 响应。

**代答面板打不开** —— 面板会直接告诉你原因，常见三种：
「在等的不是选择题（Bash）」= 它在跑工具不是在问你；
「它不在带 socket 的 nvim 里」= 那个 claude 不是从 nvim 的 `:terminal` 里起的，送不进按键；
「问题结构读不出来」= 第 5 节说的格式漂移。

**代答选错了项** —— 停用 `ccp` 的代答（照样能当看板用），去 `cc_common.py` 重新核对第 4 节那几条
按键序列。多半是 Claude Code 改了选择器的交互。

---

## 8 · arch-map：给项目画「架构地图」（2026-10-13）

用途：项目迭代太快、自己把握不住全貌时，让 Claude 读代码，在 `<git 根>/docs/arch/` 下生成一套分层的
手绘风 Mermaid 图：`00` 总览 → `10` 模块 → `2N` 关键流程 → `3N` 模块细节，外加 `CHANGES.md`。
看图用 ui 模块的 `mmd-view`（见 [05](05-theme-ui.md)「手绘风 Mermaid 出图」）。

**两个入口**：

- 在项目里的 claude 会话中说「画架构图」或敲 `/arch-map`；
- Dolphin 里右键项目文件夹 →「生成 / 更新架构地图」（`share/kio/servicemenus/arch-map.desktop`），
  会开一个 kitty 跑 `claude /arch-map`。新文件夹会先弹 Claude 的「信任这个文件夹吗」，默认选项是 No，要手动选 Yes。

同一个入口既能首次生成，也能增量更新：`00-overview.mmd` 末尾的 `%% @commit <hash>` 记着上次画到哪个提交，
更新时只看那之后的改动，变化的节点画成黄色虚线框（`:::changed`），删掉的写进 `CHANGES.md`。

文件：`claude/skills/arch-map/SKILL.md`（流程和写法规则）+ `scripts/check.py`（校验）。
check.py 是每次生成的硬性完成标准：要能渲染、节点不超上限（总览 10、其余 15）、`@src` 文件存在且锚点唯一、
`@link` 目标存在、每张图都能从总览沿 `@link` 走到、`@commit` 是有效提交。没标 `@src` 的节点会列出来，逐个确认是外部系统或存储。

**几条从实测里来的规则**（2026-10-13，两轮无上下文子代理在 ccmon 上实跑：一轮首次生成，一轮造了一次结构改动再增量更新）：

- **`@src` 用锚点不用行号**。更新那轮，代码顶部加了一行 import，所有行号全部错位，
  而且大多落在非空行上，旧版 check.py 只抓到碰巧落在空行上的那部分。现在写成 `@src <id> <路径> <定义行里的一段文字>`，
  打开时现场找行号；锚点必须在文件里唯一。
- **「脏」要排除 `docs/arch/` 自己**。首次生成后 `docs/arch/` 是未跟踪文件，不排除的话工作区永远是脏的，
  「地图已是最新」的判断永远不会成立。命令是 `git status --porcelain -- . ':(exclude)docs/arch'`。
- **更新时对比到工作区**（`git diff <旧>`，不带 `..HEAD`），这样未提交的改动也算进去。
- **只有流程图能交互**：高亮上下游、跳源码、手绘线条都只对 `flowchart` 生效，时序图只在交互顺序本身是重点时用。
- 校验脚本取节点 id 时要读**渲染后 SVG** 里的 `-flowchart-<id>-<n>`，不能对源码做全文正则。
  后者会被标签文字骗过：`@src poll` 指向一个不存在的 id，只因为别的节点标签里有 poll 这个词，就通过了。

**两个 skill，一套格式**：格式（结构、写法、`@src` 锚点、`@note`、`changed` / `planned` 标记）只写在
`arch-map/FORMAT.md` 一处，两个 skill 都引用它：

| skill | 方向 | 产物 |
|---|---|---|
| `arch-map` | 代码 → 图 | 首次生成 / 增量更新 / 只补或只改一张图（「加一张退款流程图」） |
| `arch-design` | 讨论 → 图 → 代码 | 节点是 `:::planned`（紫色虚线框），`docs/arch/DESIGN.md` 记决策和实现顺序；照顺序一步步写代码，写一步转正一批节点 |

设计阶段的循环是：画草图 → 用户在 mmd-view 里按 `n` 写备注 → arch-design 读备注改图、记决策 → 直到定稿。
全新项目还没有提交时，`@commit` 写 `none`。

**省 token**（用户要求，arch-map 里是硬规则）：已有的地图就是项目的索引。更新时只看 `git diff --stat`，
能一眼判定的非结构改动不读；其余先看 diff 的改动块，看不出结构影响才读整个文件。只要一张图时只勘察那张图涉及的代码。
汇报也只讲变化，不重讲整个项目。arch-design 的 `DESIGN.md` 让新会话直接接着做，不用重新讨论。
参考量（ccmon，23 个跟踪文件）：首次生成约 11.5 万 token，增量更新约 6.9 万。后者是在这些规则之前测的，那次还顺带把所有行号改成了锚点。

skill 写法遵循本机 `~/.claude/skills/writing-great-skills`：每步一个可检查的完成标准；**地图**、**证据**、**锚点**是贯穿全文的关键词。


## 9 · Discord 远程驱动：claude-discord-sync（2026-10-14）

用途：人不在电脑前时，用手机 Discord 接着驱动本机 tmux 里**一直开着**的 Claude Code：
看输出、发消息、批准权限、答选择题、审计划、开新会话或恢复旧会话。
每个会话对应服务器里的一个频道，另有一个「控制台」频道显示所有会话的状态。

**不是 install.sh 模块**。本包只记了 `packages.txt` 里的 `bun`，其余三样都不入包：

| 东西 | 在哪 | 为什么不入包 |
|---|---|---|
| 代码 | `~/src/claude-discord-sync`（fork：`github.com/numb747/claude-discord-sync`，`origin` 是 fork，`upstream` 是原作者 Cnyn0403） | 自己有 git 仓库，守护进程直接跑检出的源码 |
| 配置和 bot token | `~/.claude/channels/discord-sync/`：`config.json` + `.env`（权限 600） | `.env` 是凭据；`config.json` 里的服务器 ID 换台机器就不同（一台机器一个服务器） |
| systemd 单元 | `~/.config/systemd/user/claude-discord-sync.service` | 由向导生成，里面写死了当时的 `PATH`，换机器重跑向导即可 |

`~/.local/bin/ccd` 是向导建的符号链接，指向检出里的 `bin/ccd`。
⚠ 检出**不一定**在 `~/src/claude-discord-sync`：笔记本上是 `~/claude-discord-sync`（2026-10-14）。
要改哪份源码，以 systemd 单元为准：`grep ExecStart ~/.config/systemd/user/claude-discord-sync.service`。

### 新机器上装

```bash
sudo pacman -S --needed bun tmux git
git clone https://github.com/numb747/claude-discord-sync.git ~/src/claude-discord-sync
cd ~/src/claude-discord-sync
git remote add upstream https://github.com/Cnyn0403/claude-discord-sync.git
bun install --frozen-lockfile   # 别 bun update，见下面「坑」
bun src/cli.ts setup            # 语言选 3（简体中文）；bot 要新建一个，或者重置原来那个的 token
```

向导跑完后，往 `config.json` 里补上本机用的两项：`"language": "zh-CN"`（向导选过就有）和
`"deleteEndedAfterDays": 7`（已结束的会话频道 7 天后删掉，不然频道越堆越多）。改完重启服务。
完整用法（命令、按钮、每种卡片）看 fork 里的 `docs/guide.zh-CN.md`。

### 为什么用 fork、为什么不走 channels

原项目靠 Claude Code 的 **channels**（`--dangerously-load-development-channels`）把消息送进会话。
**本机用不了**：本机走第三方中转（`settings.json` 的 `ANTHROPIC_BASE_URL`），没有 claude.ai 登录，
channels 的服务端开关拿不到，启动时提示 `Channels are not currently available`。官方的 Remote Control
也是同样原因用不了。**别去绕这个开关。**

fork 改成默认 `"channels": false`，换两条路：

- **Discord 发的消息**：用 tmux 的 bracketed paste 粘进会话输入行再回车。终端正开着对话框、
  或者输入行里有没发出去的草稿时，拒绝发送，不会把字打进错的地方。
- **权限 / 选择题 / 计划**：`ccd` 启动时用 `--settings` 挂一个 `PermissionRequest` hook，
  把对话框转成 Discord 上带按钮的卡片。终端里同时显示同一个对话框，哪边先答以哪边为准。
  这个 hook **不写进 `~/.claude/settings.json`**，所以只有用 `ccd` 启动的会话才有卡片；
  直接用 `claude` 启动的会话，对话框超过几秒没人答，会发终端截图过去，选项变成按钮。

所以日常在 tmux 里用 **`ccd` 代替 `claude`**，参数原样透传（`ccd --resume`、`ccd --model opus`）。

### 默认 bypass 模式（2026-10-14，fork 提交 968c81c）

fork 的 `bin/ccd` 启动 `claude` 时带上了 `--dangerously-skip-permissions`，所以 Discord 的
`/new`、`/resume` 和终端里的 `ccd` 开的会话，**一启动就是 bypass permissions**，底栏显示
`bypass permissions on`。

为什么要改代码，而不是用 `/mode` 切过去：

- **bypass 只能在启动时打开**。启动时没带 `--dangerously-skip-permissions` 或
  `--allow-dangerously-skip-permissions`，Shift+Tab 的切换列表里就没有它。Discord 的 `/mode` 其实就是
  一直按 Shift+Tab，所以切一圈也找不到（bot 会回「所有模式都切了一轮，还是没有 bypass permissions」）。
- **Discord 上没有地方传启动参数**。`/new <目录> [提示词]` 只传提示词，`/resume` 只传
  `--resume <id>`，`config.json` 也没有「额外 claude 参数」这种选项。所以只能写进 `bin/ccd`。

改了之后：

- **Discord 上基本不再有权限卡片**，命令直接执行。选择题和计划审批照常走卡片。
  ⚠ **例外：bypass 也跳不过的安全检查**（2026-10-16 查明，CC 2.1.273）。命令里有 `rm`、同时结构复杂到
  CC 分析不出会删什么（实测是 `rm -f dir/*` 和 `$(for …; do … "$(basename …)"; done)` 写在同一条里），
  CC 的「灾难性删除」检查会强制人工确认，二进制里的提示是「too many to analyze for catastrophic removals.
  This requires explicit approval」，同类规则注明「不能被权限规则自动放行」。权限卡片照样会出现在 Discord 上。
  当时翻遍所有 bypass 会话，一百多条含 `rm` 的命令里只有这 2 条被拦。
  **没让 `ccd` 的钩子自动放行它**（那等于拆掉 CC 特意留的最后一道防线），改在全局 `CLAUDE.md`
  （`claude/global-CLAUDE.md`）里约束写法：`rm` 单独一条调用、参数串用数组不用嵌套 `$(for …)`。
- `bin/ccd` 每次开会话时才执行，**改它不用重启服务**；在这之前就开着的会话不受影响，要退出再 `/resume`。
- 同一个提交还在 `src/daemon.ts` 的 `STARTUP_PROMPTS` 里加了 bypass 警告框（自动选「Yes, I accept」）。
  **新机器才用得上**：这个警告默认选「No, exit」，没接受过的机器上 `/new` 会卡在这里，直到 45 秒超时。
  笔记本以前接受过，实测不弹。警告的匹配文字没实测过，到时候真卡住了，看一眼屏幕再改正则。
- 想换回「默认普通模式、需要时再切 bypass」：把 `bin/ccd` 里那个参数换成
  `--allow-dangerously-skip-permissions`，之后在会话频道里发 `/mode bypassPermissions`。

### 坑

- **改了 fork 的源码要重启服务**：`systemctl --user restart claude-discord-sync`，
  日志 `journalctl --user -u claude-discord-sync -f`。
- **别 `bun update`**：锁定的 MCP SDK 1.32.1 协商的协议版本和当前 Claude Code 对得上，升级可能对不上。
- **连 Discord 靠 sing-box 的 TUN**：代码里没有代理设置，`HTTPS_PROXY` 对 discord.js 无效。TUN 一关就断。
- **测试会话里别用 `/model`**：它会把模型写进 `~/.claude/settings.json` 变成全局默认。要换模型用 `ccd --model …`。
- **计划只能在终端批准**：hook 对 ExitPlanMode 返回「允许」不生效（实测，Claude Code 2.1.273），
  Discord 上的「批准」按钮其实是往终端按数字键；「打回修改」走 hook，正常。
- **Discord 的限额**：频道话题 10 分钟只能改 2 次（连续重启几次服务，频道名和话题会晚一会儿才更新）；
  每个分类最多 50 个频道，整个服务器最多 500 个，剩 10 个时会先删最早结束的。
- **想从头来过**：停服务 → 删掉两个 Claude 分类下的所有频道 → `state.json` 写成 `{}` → 启动。
  正在运行的会话会重建频道，带最近 15 条记录。2026-10-14 做过一次。


## 10 · 1 小时提示缓存（2026-10-21）

`~/.claude/settings.json` 里加了一行 `"promptCacheTtl": "1h"`（CC 2.1.242 起支持）。这个文件含 token、不入包，
换机器要手动加。

**为什么要手动设**：不设时，用 Claude 订阅登录的主对话默认是 1 小时；本机走中转、用 API token，默认只有 **5 分钟**。
停下来超过 5 分钟再接着聊（比如人在 Discord 上回消息），整段上下文要按写入价重算一遍。

**实测过中转支持**（4router，Haiku，`claude -p` 加 `--output-format json` 看 `usage`）：
两组各自先写一次缓存，7 分钟后再调用一次：

| | 7 分钟后命中 | 7 分钟后写入 |
|---|---|---|
| 5m | 0 | 重写 32786 |
| 1h | 27629 | 只重写每次都会变的约 5000 |

当时那一次调用，CC 本地算的费用是 5m $0.041 对 1h $0.014。中转后台实际怎么扣费没核对。

**代价**：1 小时缓存的写入价约是普通输入的 2 倍（5 分钟是 1.25 倍），读的价格一样。连续一问一答时反而略贵。

**默认用 1h 还是 5m（2026-10-21 拿 30 天会话记录模拟过）**：234 个主会话，同一份调用记录分别按两套规则算钱。
全用 5m ¥2181，全用 1h ¥1888（省 13%）。如果事先就猜对每个会话该用哪个，也只能再省 ¥65；
按「短于 30 分钟的会话用 5m」来切，只省 ¥18。每周单独看都是 1h 更省。
1h 更贵的那些会话都是短会话（时长中位 19 分钟），单个只多花约 ¥0.25；1h 更省的那些单个能省约 ¥0.92。
**结论：默认 1h，不必按项目切换**。只有脚本里一次性的 `claude -p` 才值得用 5m，因为写进去的缓存不会再被读。
本机只留 30 天的会话记录（`cleanupPeriodDays` 默认 30），想拿更长的数据得先调大这个值。考虑过调成 90，用户决定保持默认。

**临时用 5m：`claude5m`**（`.zshrc` 里的 alias，term 模块），等于 `CLAUDE_CODE_PROMPT_CACHE_TTL=5m claude`，
参数原样透传，比如 `claude5m --dangerously-skip-permissions`。环境变量比 settings 里的 `promptCacheTtl` 优先，
实测写入的确实是 `ephemeral_5m_input_tokens`。⚠ 测试时别把命令名放进变量（`$c …`），zsh 不会展开 alias。

**子代理没开**：`subagentPromptCacheTtl` 显式写成 `"5m"`（等于默认值，2026-10-22 补上，免得以为漏设），
子代理、Workflow、后台请求一般跑得短，用 1h 不划算。换机器时和 `promptCacheTtl` 一起手动加。

几个相关开关（名字在 CC 二进制里核对过）：

- `CLAUDE_CODE_PROMPT_CACHE_TTL` / `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`：环境变量版，比 settings 优先
- `ENABLE_PROMPT_CACHING_1H=1`：主对话和子代理一起 1h
- `FORCE_PROMPT_CACHING_5M=1`：强制 5m，优先级最高。想临时退回就用它

**验证生效**：新会话里跑 `claude -p hi --output-format json </dev/null | jq .usage.cache_creation`，
看 `ephemeral_1h_input_tokens` 不为 0。⚠ 测试时三个坑：不加 `</dev/null` 会往 stdout 混进一行 stdin 警告，jq 解析失败；
工具定义那段约 2.7 万 token 的前缀在所有调用之间共享，换目录也隔离不开；
「立刻重跑」只能证明能命中，要隔 5 分钟以上才能看出 TTL 有没有生效。


## 11 · 上下文与缓存的使用技巧（2026-10-21）

第 10 节定的是 TTL。这一节是在 1h 缓存下，日常怎么用最省、上下文也最干净。
数字来自笔记本 25 天的会话记录（144 个主会话、8082 次请求，94% 是 Opus 5.5），
按官方价格模拟（输入 $4 / 输出 $20 每百万 token；1h 写入 2 倍、读取 0.05 倍），不是账单。
模拟脚本在笔记本本地 `~/Documents/cache-ttl-analysis/`，没入库。

**为什么上下文越大越贵**：每次请求都要把整段上下文按读取价读一遍。按 1h 缓存算，
上下文 100–200k 时单次请求平均 $0.05，200–400k 时 $0.08，400–600k 时 $0.11。
200k 以上的请求占了缓存总费用的 48%。看当前上下文多大，就看状态栏的 `338k/1000k` 那一段。

### 什么时候 `/compact`：250–300k，且刚做完一个阶段

模拟「上下文一到阈值就压缩」，和实际花费比（实际 17 次压缩**全是手动的**，压缩时从 65k 到 650k 都有）。
最大的未知数是压缩后要重读多少文件，所以分三档算：

| 阈值 | 压缩后不重读 | 重读 30k | 重读 60k |
|---|---|---|---|
| 100k | −34% | +27% | **+1768%** |
| 150k | −31% | −13% | +20% |
| 200k | −26% | −16% | −1% |
| **250k** | −22% | **−15%** | −7% |
| **300k** | −18% | −13% | −7% |
| 400k | −9% | −7% | −5% |

⚠ **别压得太早。** 压缩后剩下的是固定前缀（约 31k，见下）+ 摘要 + 重读的文件，
阈值定在 150k 以下，没几轮又涨回阈值，反复压缩，成本成倍上涨。250–300k 在三种假设下都稳定省 7%–22%。
只算了钱：压缩会丢细节，每次还要等 1–6 分钟（那 17 次平均约 2 分钟）。所以不必卡死在这条线上，
到了这个区间、正好做完一个阶段时再压。要保留的东西直接写在命令后面：`/compact 保留 XX 的报错和改过的文件路径`。

### 要离开超过 1 小时：先压缩再走

1h 缓存过期后，回来的第一次请求要按 2 倍写入价把整段上下文重写一遍。
25 天里有 45 次停顿超过 1 小时，重写一共约 $63，其中 14 次发生在上下文 200k 以上，占 $37。

以 300k 为例：回来直接继续，重写约 **$2.4**；走之前先 `/compact`（缓存还热，读取便宜，加摘要输出约 $0.3），
回来只重写约 73k（约 $0.6），合计约 **$0.9**。

| 离开多久 | 做法 |
|---|---|
| 1 小时以内 | 什么都不用做，缓存还在 |
| 超过 1 小时，还要接着做 | **先 `/compact` 再走** |
| 任务已经做完 | `/clear` 或直接关掉 |

### `/resume` 回来时：看还要做多少

⚠ 缓存过期以后，**回来先压缩并不能省掉第一步的大账**：不管第一步是提问还是 `/compact`，
整段上下文都要完整处理一遍。先压缩只是让之后每一轮读的上下文变小
（300k 时每次请求约 $0.06，压缩后约 $0.015）。压缩请求读那一遍时会不会同时写进缓存没核实，
所以第一步的成本是 $2.0–3.2，直接提问是 $2.4，两者差不多。

| 情况 | 做法 |
|---|---|
| 1 小时内回来 | 直接问 |
| 超过 1 小时，只问一两句、收个尾 | 直接问，为两句话压缩不值得 |
| 超过 1 小时，上下文 250k 以上，还要做很久 | 先 `/compact` 再继续 |
| 要问的事依赖旧上下文里的细节 | 先问，或压缩时写明要保留什么 |

另一条路：在旧会话里让它写一份简短的交接说明，再开新会话把说明交给它。通常更省，上下文也更干净。

### 其他习惯

- **一个会话只做一件事。** 话题换了就 `/clear` 或开新会话。之后每次请求都要把前面无关的上下文再读一遍。
- **大段阅读交给子代理。** 翻日志、扫代码、查文档这类只要结论的活让子代理去读，只把结论带回来，主对话涨得慢。
  子代理是 5m 缓存、跑完就结束，比较便宜。
- **会话中途别换模型、别增减 MCP 工具。** 缓存按模型分开；工具定义在缓存前缀的最前面，改了整段都要重写。
- **一次性脚本用 `claude5m -p ...`**（第 10 节）。
- **固定前缀约 31k，不用砍。** 2026-10-21 用 `/context` 查过：系统提示 2.5k + 内置工具定义 29.7k +
  记忆/agents/skills 约 3k；MCP 工具（IDA、mitmweb）和不常用的内置工具都是按需加载（deferred），平时只占名字。
  大头是内置工具定义，是 Claude Code 自带的，在缓存里每次请求只按 0.05 倍读（约 $0.006）。
  ⚠ 最初从会话记录估出来的「61k」是错的：用的是每个会话第一次请求的前缀，`/resume` 的会话把旧历史也算了进去；
  10-20 之后新开会话的第一次请求都是 30–31k。

速记：

```
新话题 → /clear          到 250–300k 并做完一阶段 → /compact
离开 >1h → 先压缩再走     大段阅读 → 交给子代理
脚本 → claude5m -p        中途 → 不换模型、不动 MCP
```

---

## 12 · AI Chrome：给 Claude Code 一个能操作的浏览器（2026-10-30）

让 Claude Code 自己开网页、读内容、点按钮、填表，用的是 Google 官方的
[chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp)。
浏览器是一个**独立配置**的 Chrome，和日常浏览分开：

| | 配置目录 | 打开方式 |
|---|---|---|
| 日常浏览 | Firefox（系统默认浏览器） | `Super+W` |
| 日常 Chrome | `~/.config/google-chrome` | 启动器 |
| **AI Chrome** | **`~/.config/chrome-ai`** | `Super+Ctrl+W`、启动器搜「AI Chrome」，或者 MCP 自动拉起 |

窗口 class 是 `chrome-ai`（`--class` 在 Wayland 下就是 app_id），Hyprland 规则和任务栏都能把它和日常 Chrome 分开。

### 怎么接上的

```
Claude Code ──stdio──> bin/chrome-ai-mcp ──npx──> chrome-devtools-mcp@1.12.0
                              │                         │ --browser-url
                              │ 没开就先拉起              ▼
                              └──────────────> bin/chrome-ai（127.0.0.1:9222）
```

- **为什么连已有实例，而不让 MCP 自己起 Chrome**：MCP 自己起的是另一个 profile
  （默认 `~/.cache/chrome-devtools-mcp/chrome-profile`），你手动开的窗口和 AI 操作的不是同一个，
  登录状态不通。现在两边是**同一个实例**：你在 AI Chrome 里登录过的网站，AI 直接能用，AI 在干什么你也看得见。
- **独立 profile 是硬性要求**：Chrome 136 起不许在默认 profile 上开 `--remote-debugging-port`。
- **`--password-store=basic`：不碰系统钥匙环**（2026-10-30 加）。默认 Chrome 把加密密钥存进
  gnome-keyring / freedesktop Secret portal，于是全新 profile 首次启动（或钥匙环还没解锁时）会弹
  「解锁登录钥匙环」密码框。AI Chrome 按设计不登敏感账号（见下方坑 1），所以直接 `basic`——
  加密密钥落在 profile 目录里，**任何机器、任何时候都不再弹密码框**，也绕开 Chrome 156 那个
  `prev_init_success:false`、时好时坏的 Secret portal 后端。代价是 profile 里存的密码等于明文，
  但这个 profile 本就不该存密码。切到 basic 前若已用钥匙环起过一次，旧密钥不通，清掉
  `~/.config/chrome-ai` 重新起最干净（里面没有值得留的数据）。
- **注册在 `~/.claude.json`（user 作用域），不入包**。新机器装完要手动执行一次：
  `claude mcp add --scope user chrome-devtools -- ~/.local/bin/chrome-ai-mcp`。
  在**新开的** Claude Code 会话里才能用（第 11 节：会话中途别动 MCP）。
- **版本钉在 1.12.0**：用 `@latest` 的话，每次启动都要去 npm 查新版，既慢，也等于自动更新一段能操控浏览器的代码。
  升级就改 `chrome-ai-mcp` 里的 `VERSION`。另外关掉了使用统计（`--no-usage-statistics`）和 CrUX 上报。

### 坑

**1. 调试端口谁都能连。** 9222 只监听 127.0.0.1，但本机任何进程都能连上来控制这个浏览器、读它的 cookie。
所以 **AI Chrome 里别登录银行、主力邮箱这类账号**，只登 AI 需要用的网站。网页里藏的提示词注入
（让 AI 去执行网页里写的指令）也是同一个道理：这个 profile 能碰到的东西越少越好。

**2. MCP 的 stdout 是通信通道。** `chrome-ai-mcp` 里拉起 Chrome 那一步的输出必须全部扔掉，
漏出一行字，Claude Code 那边就会解析失败、连接断开。

**3. 1.12.0 默认按页面路由（page id routing）。** `take_snapshot` 等页面级工具必须带 `pageId`，
不带就报 `Invalid arguments ... pageId`。Claude Code 会先调 `list_pages` 拿到 id，自己处理好；
只有手写 JSON-RPC 测试时才会碰到。

**4. 每周安全体检会报它。** `sec-audit` 监控 Claude 的 MCP 配置（`docs/16`），
新增这个 MCP 后下一次体检会报变化，属于预期，复核后 `--accept`。

验收（2026-10-30）：先关掉 AI Chrome，用 MCP 握手，1.4 秒内拉起 Chrome，32 个工具可用，
`new_page` 打开 example.com 后，`take_snapshot` 能读出正文。

## 13 · MCP 按需加载：ccx 套餐（2026-10-31）

**问题**：MCP 不像 skill。skill 是懒加载——平时只有一行简介在系统提示里，调用那一刻才读正文，装再多都几乎零开销。
MCP 不是：只要配在**全局**（`~/.claude.json` 的 `mcpServers`）或由**插件**启用，每个会话一开就把进程拉起来、
把全套工具定义常驻进上下文。平时用不到的 `mitmweb`（抓包）、`chrome-devtools`（AI 浏览器）、`ida`（逆向）、`burp`
就这么白占着 token 和内存。

**改法**：全局 `mcpServers` 清空、停用 `ida-mcp` 插件，把每个 MCP 拆成 `~/.claude/mcp/<名字>.json` 一个片段，
启动时用 `bin/ccx` 按名字叠 `--mcp-config` 带上。平时干净，用到才起。

```
ccx            # 干净，只有 matrix-sync（手机同步）
ccx web        # + chrome-devtools
ccx cap web    # + mitmweb + chrome
ccx rev        # + ida 逆向
ccx -l         # 列出可用套餐
ccx web -- "帮我看下这个页面"   # -- 之后原样透传给 claude
```

套餐名 → MCP：`web`=chrome-devtools、`cap`=mitmweb、`rev`=ida、`burp`=burp。加新套餐直接往 `~/.claude/mcp/`
丢一个 `{"mcpServers":{...}}` 文件，`ccx` 自动认。

### 为什么经 ccm、而不是直接 claude

`ccx` 最后 `exec ccm`（见 `docs/14`、`claude-discord-sync`），这样 **Matrix 手机同步照常保留**。
`ccm` 用 `exec … "$@"` 透传参数，而 Claude Code 的 `--mcp-config` **可以重复出现、全部合并**，所以叠套餐就是
多拼几个 `--mcp-config`。Matrix daemon 平时起的是裸 `ccm`（无套餐）→ 现在是干净的；要给手机同步的会话带 MCP，
得自己在 tmux pane 里跑 `ccx <套餐>`。

### 密钥怎么不泄露

`cap.json` 要 mitmweb 的 token。入库版写成占位符 `"MITMWEB_TOKEN": "${MITMWEB_TOKEN}"`
（Claude Code 支持在 `command`/`args`/`env`/`url`/`headers` 里展开 `${VAR}` 和 `${VAR:-default}`），
真值放 `~/.claude/mcp/secrets.env`（`export MITMWEB_TOKEN=…`）。该文件 **gitignore、不入包**（见 CLAUDE.md「边界」），
`ccx` 启动时 `source` 它，变量进子进程环境，claude 再展开回真值。新机器要手动建 `secrets.env`。

### 坑

**1. `--mcp-config` 是可变参数，会吞后面的裸 token。** `claude --mcp-config a.json mcp list` 会把 `mcp`、`list`
也当成配置路径。`ccx` 在套餐后补一个布尔 flag `--dangerously-skip-permissions` 当终止符，透传的 prompt 才不被吞。

**2. ida 片段的路径锁了插件版本号**（`…/ida-mcp/20261008.0.1`）。插件已停用不会自更新；将来若报路径不存在，
去 `~/.claude/plugins/cache/HexRaysSA/ida-mcp/` 看新版本号改 `rev.json`。片段里 MCP 名是 `ida`
（原插件是 `plugin:ida-mcp:ida`），工具名相应变 `mcp__ida__*`。

**3. 改动只对新会话生效。** 当前已加载的 MCP 不变，下次启动才干净。

**4. settings.json 的插件停用不入包。** `~/.claude/settings.json` 含明文 token、本就不入包，所以
「停用 ida-mcp 插件」这个开关只在本机生效，新机器装 cc 模块不会带过去（新机器可能根本没装那插件，无所谓）。

验收（2026-10-31）：`ccx -l` 列出 4 个套餐；`ccx cap` 启动的会话里 `${MITMWEB_TOKEN}` 展开为真值、
mitmweb 连得上；裸 `ccm`（含手机发起的会话）只有 matrix-sync；`./check.sh` 凭据扫描无命中。
