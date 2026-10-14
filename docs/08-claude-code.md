# 08 · Claude Code 本机工具

装在 `~/.claude/` 下的三件东西：**上下文占比状态栏**、**多会话看板**、**宠物版 TUI（能就地代答）**。
由 `install.sh cc` 安装，`manifest.map` 的 `#@module cc` 段是路径的单一事实来源。

Agent Teams（一个队长 claude 指挥几个队员、tmux 分屏、团队日志）也在 cc 模块里，但写在
[14-tmux.md](14-tmux.md) 第 7 节 —— 它和 tmux 绑得更紧。

`arch-map` skill（给 git 项目画架构地图）也归 cc 模块，见第 8 节。

用手机 Discord 远程驱动本机 Claude Code（claude-discord-sync）**不在 cc 模块里**，只是记在这，见第 9 节。

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
