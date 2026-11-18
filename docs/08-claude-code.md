# 08 · Claude Code 本机工具

cc 模块装在 `~/.claude/` 下，由 `install.sh cc` 安装，`manifest.map` 的 `#@module cc` 段是路径的单一事实来源。现在包括：

- **上下文占比状态栏**（第 3 节）；
- **Agent Teams**（队长指挥几个队员、tmux 分屏、团队日志），写在 [14-tmux.md](14-tmux.md) 第 7 节——它和 tmux 绑得更紧；
- **`arch-map` / `arch-design` skill**（给 git 项目画架构地图），第 8 节；
- **ccx 套餐**（MCP 按需加载，含 Grok 的 `ggx`、GLM 的 `ccglm`），第 13 节。

其余各节：提示缓存 1h 还是 5m（第 10 节）；1h 缓存下什么时候 `/compact`、离开前和 `/resume` 回来怎么最省（第 11 节）；
AI Chrome（第 12 节）；花费统计 `cc-cost`（第 14 节）；几个会话、子代理都跑完就自动关机 `cc-shutdown`（第 15 节）；
版本钉死与安全升级、贴图片 / 对话里看图（第 16 节）。

手机远程驱动本机 Claude Code 走自建 Matrix（`ccm` 启动，代码与部署说明在 `~/src/matrix-migration`，见其 `docs/DEPLOY.md`），**不在 cc 模块里**。
多会话总览用 tmux 的 `Alt+a`（`bin/tmux-panes`，见 [14](14-tmux.md) 第 9 节）或网页监控站 `~/ccmon`。

现用 **Claude Code 2.1.326**（第 16 节）。

---

## 1 · 三个入口（已移除）

多会话看板 `ccw` / `ccs`、宠物版 TUI `ccp`（能就地代答别的终端里的选择题）已于 2026-11-18 删除，
网页监控站 `~/ccmon` 取代了它们。原文见 `git show f23564b:docs/08-claude-code.md`。

---

## 2 · 数据从哪来（已移除）

看板的数据层随 `ccw` / `ccp` 删除。仍有用的两条：

- Claude Code 自己在 `~/.claude/sessions/<pid>.json` 里维护每个会话的实时状态（含 `status`、`statusUpdatedAt`），**不需要 hook**；
  `tmux-panes`、`cc-shutdown` 读的就是它。
- ⚠ TUI 版 `claude agents` 只显示后台会话（交互式终端不 `/bg` 就不出现），`claude agents --json` 却会列出交互式会话，
  而且只有它提供 `waitingFor`（区分「等授权」/「等回答」）。`claude logs/attach/stop` 对交互式会话都报 `No job matching`。

---

## 3 · 状态栏为什么要 install.sh 特殊处理

```
[Opus 5·high] web-admin │ ███░░░░░░░ 33% 338k/1000k $0.47
```

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

**状态栏不显示** —— `jq '.statusLine' ~/.claude/settings.json` 看有没有那一段。
新会话在第一条消息之前百分比恒为 0，那是正常的：数据取自最近一次 API 响应。

---

## 4 · AskUserQuestion 选择器的按键序列（`ccp` 代答已移除，结论仍有效）

`ccp` 当初经 nvim RPC 把按键送进别的终端代答，已删除。实测出来的按键规律仍然适用于任何往 Claude Code 送键的场景
（tmux `send-keys`，见 [14](14-tmux.md) 第 5 节）。实测于 2.1.246，升级后可能漂。

顶部是一排标签 `← [第1题] [第2题] … [✔ Submit] →`，光标在**当前标签**的选项列表里。

| 在哪 | 怎么操作 |
|---|---|
| 单选题标签 | `↓` 移动，**`Enter` = 选中并切到下一个标签**（新题光标复位到第 1 项） |
| 多选题标签 | `空格` 勾选当前项，`↓` 移动，**`→` = 切到下一个标签** |
| Submit 标签 | `Enter` 提交（光标停在 `Submit answers`） |

⚠ **单个单选题没有 Submit 标签**，那个 `Enter` 当场就提交完了。其余情况（多个问题、或单个多选题）
最后都要**再多按一次 Enter**：少按停在 review 页不提交，多按会打进输入框。

- **数字键在 AskUserQuestion 选择器里无效**（光标不动）。⚠ 「是否信任此文件夹」那个框**认数字键而且按下即提交**，别混。
- **必须逐键发、间隔 ~0.2s**。一次灌进去，首尾的键会在 TUI 重绘间隙里被丢掉。
- 送键前要复核它还在等同一道题：如果已经在终端里答了，选择器早没了，再灌箭头键会打进输入框。

| 情况 | 序列 |
|---|---|
| 1 题单选，选第 3 项 | `↓ ↓ Enter` |
| 1 题多选，选第 1+3 项 | `空格 ↓ ↓ 空格 → Enter` |
| 2 题单选，选第 3 项 + 第 1 项 | `↓ ↓ Enter` `Enter` `Enter` |
| 3 题单选，各选第 2 项 | `↓ Enter` `↓ Enter` `↓ Enter` `Enter` |
| 混合：第 1 题单选第 2 项 + 第 2 题多选第 1+3 项 | `↓ Enter` `空格 ↓ ↓ 空格 →` `Enter` |

另一条顺带的：`:terminal` 里跑的进程，`/proc/<pid>/environ` 的 **`NVIM`** 变量就是所在 nvim 的 socket 路径。

---

## 5 · 会漂的一环（已移除）

讲的是 `ccp` 靠解析 transcript 判定待答问题。仍有效的一条：**官方明说 transcript 是内部格式、版本间会变**
（`docs/en/sessions` 的 "Where transcripts are stored"），依赖它的工具升级前按第 16 节先隔离测。

---

## 6 · 文件与测试（已移除）

看板 / 宠物 TUI 的脚本和测试（`cc_common.py`、`cc-pet.py`、`cc-watch.py`、`test-cc.py`、`e2e_*.py`、`pty_drive.py`、`probe_multiq.py`）已删除。
仍有效的一条：⚠ **脚本里起的 claude 子会话要 `env -u CLAUDE_CODE_CHILD_SESSION`**，否则不写 transcript。

---

## 7 · 排错（已移除）

看板和代答的排错随之删除；状态栏的排错并入第 3 节末。

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


## 9 · Discord 远程驱动：claude-discord-sync（已移除）

早已移除（`~/.claude/channels/discord-sync` 不复存在），手机远程改走自建 Matrix：`ccm` 启动，
代码在 `~/src/matrix-migration`，部署说明见该仓库 `docs/DEPLOY.md`。原文见 `git show f23564b:docs/08-claude-code.md`。
当时查明、至今仍有效的几条：

- 本机走第三方中转、没有 claude.ai 登录，Claude Code 的 **channels 和官方 Remote Control 都用不了**（`Channels are not currently available`），别去绕。
- **bypass 只能在启动时打开**：没带 `--dangerously-skip-permissions` / `--allow-dangerously-skip-permissions` 启动，Shift+Tab 的切换列表里就没有它。
- ⚠ **bypass 也跳不过「灾难性删除」检查**（2.1.273 查明）：命令里有 `rm`、同时结构复杂到分析不出会删什么
  （如 `rm` 和 `$(for …; do … "$(…)"; done)` 写在同一条），会强制人工确认，权限规则也放行不了。
  所以全局 `CLAUDE.md`（`claude/global-CLAUDE.md`）约束写法：`rm` 单独一条调用、参数串用数组。
- **会话里别用 `/model`**：它会把模型写进 `~/.claude/settings.json` 变成全局默认。临时换模型用启动参数 `--model …`。
- **hook 对 ExitPlanMode 返回「允许」不生效**（2.1.273 实测），计划只能在终端批准；「打回修改」走 hook 正常。


## 10 · 1 小时提示缓存（2026-10-21）

`~/.claude/settings.json` 里加了一行 `"promptCacheTtl": "1h"`（CC 2.1.242 起支持）。这个文件含 token、不入包，
换机器要手动加。

**为什么要手动设**：不设时，用 Claude 订阅登录的主对话默认是 1 小时；本机走中转、用 API token，默认只有 **5 分钟**。
停下来超过 5 分钟再接着聊（比如人在手机上回消息），整段上下文要按写入价重算一遍。

**实测过中转支持**（Haiku，`claude -p` 加 `--output-format json` 看 `usage`）：
两组各自先写一次缓存，7 分钟后再调用一次：

| | 7 分钟后命中 | 7 分钟后写入 |
|---|---|---|
| 5m | 0 | 重写 32786 |
| 1h | 27629 | 只重写每次都会变的约 5000 |

当时那一次调用，CC 本地算的费用是 5m $0.041 对 1h $0.014。中转后台实际怎么扣费没核对。

**代价**：1 小时缓存的写入价约是普通输入的 2 倍（5 分钟是 1.25 倍），读的价格一样。连续一问一答时反而略贵。

**结论：默认 1h，不必按项目切换。** 理由（2026-10-21 拿 30 天、234 个主会话的调用记录按两套规则模拟）：
全 5m ¥2181、全 1h ¥1888（省 13%），每周单独看都是 1h 更省；就算事先猜对每个会话该用哪个，也只能再省 ¥65。
只有脚本里一次性的 `claude -p` 才值得用 5m，因为写进去的缓存不会再被读。
本机只留 30 天的会话记录（`cleanupPeriodDays` 默认 30，用户决定保持默认），想拿更长的数据得先调大这个值。

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

### 不带 web 套餐时：`cdp-fetch`（2026-11-16）

chrome-devtools MCP 是按需加载的（第 13 节），没用 `ccx web` 开的会话里没有这组工具。
只是要**读**网页的话不用重开会话：`bin/cdp-fetch` 直接连 9222 走 CDP，
在 AI Chrome 里新开标签页、等渲染、取 `innerText`、关掉标签页。

```bash
cdp-fetch URL [等待秒数=10] [最多字符=15000]   # 新开标签页读，读完关掉
cdp-fetch current [关键字]                      # 读已打开的标签页，不跳转、不关
```

- **`current` 是给「人点开、AI 读」用的**：Cloudflare 人机验证、要登录、要点选的页面（WebFetch 和新开标签页都会被拦），
  用户在 AI Chrome 里点到那一页，Claude 再用 `current <URL 或标题里的词>` 读。
- **比 WebFetch 强的地方**：执行 JS，WHMCS 商品页的库存数、Cloudflare 后面的页面都能拿到。
- 依赖 `python-websockets`（pacman）。AI Chrome 必须已经开着（`chrome-ai` 或 `Super+Ctrl+W`），
  它不会自己拉起。
- ⚠ **等待时间不够会抓到空壳，而且不报错**（实测某商品页等 12 秒只抓到标题，curl 原始 HTML 里却有商品列表）。
  结果反常时先加长等待或用 curl 对照，再下结论。
- 只读不点：要点按钮、填表还是用 MCP。安全边界和上面坑 1 一样，读的是同一个 profile。

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
ccx web cap    # 叠多个 = 自动组合：浏览器自动走抓包代理 + 自动生成「怎么串起来用」的说明
ccx rev        # + ida 逆向
ccx hunt       # 别名，= web cap（re = rev cap）；别名和套餐可以混着叠
ccx -s 名字 套餐…  # 增改别名
ccx -l         # 列出套餐和别名
ccx web -- "帮我看下这个页面"   # -- 之后原样透传给 claude
```

套餐名 → MCP：`web`=chrome-devtools、`cap`=mitmweb、`rev`=ida、`burp`=burp。加新套餐直接往 `~/.claude/mcp/`
丢一个 `{"mcpServers":{...}}` 文件，`ccx` 自动认。

### 自动组合（2026-11-14）

只拼几个 `--mcp-config` 的话，几个 MCP 之间**不会接线**（浏览器和抓包同在，浏览器却不走代理），
模型也**不知道怎么串着用**。做法是**知识按套餐写，组合现算**（不按组合手写说明：组合数随套餐数爆炸）。每个套餐 json 在 `mcpServers` 之外多一个 `"ccx"` 块
（Claude Code 会忽略未知顶层键，实测过）：

| 键 | 作用 |
|---|---|
| `role` | 一行：这个 MCP 干什么、产出什么 |
| `needs` | 依赖服务，对应 `claude/mcp/services.sh` 里的 `ensure_<名字>`（启动前拉起/检查，可 export 变量） |
| `with` | `{"<另一个套餐>": {"env": {...}, "hint": "..."}}`：两者**同时加载时**才生效的接线 |

带 ≥2 个套餐时，`ccx` 把各自 `role` + 命中的 `hint` 拼成一段说明，经 `--append-system-prompt` 追加。
工作量 = N 条 role + 少数几条真实接线，加一个新 MCP 只写它自己的 json。眼下的接线只有两条：

- **web × cap**：`web.json` 的 `with.cap.env` 设 `CHROME_AI_MODE=mitm`，`bin/chrome-ai-mcp` 见到就不连 9222 那个
  日常登录的 AI Chrome，改由 chrome-devtools-mcp 另起一个 `--proxyServer=127.0.0.1:8080`、profile 在
  `~/.cache/chrome-ai-mitm` 的 Chrome。**故意不用日常 profile**：登录态不该流经抓包。mitmproxy 的 CA 已在
  用户级 NSS 库，不用 `--acceptInsecureCerts`。Chrome 默认不代理 localhost，本机目标抓不到。
- **rev × cap**：只有说明（流量里的常量去 IDA 搜、IDA 推出的算法用 replay_flow 验证）。

依赖服务：`ensure_mitmweb` 在 8081 没人听时**后台起一个不带 Chrome 的 mitmweb**（参数、env 文件、日志都和
`mitm-start` 对齐，停用照旧 `mitm-stop`；代理只听 127.0.0.1，要抓手机请手动 `mitm-start`）。不调 `mitm-start`
是因为它会顺带开自己的 Chrome，web 同在时由 AI 浏览器顶替、rev 同在时根本用不着。`ensure_burp` 只检查 9876，
Burp 没开就拦下。`ensure_ida` 自动取插件缓存里最新版本目录 export 成 `IDA_MCP_DIR`（见坑 2）。

### 工具延迟加载（2026-11-14）

**走中转时 Claude Code 默认不开 MCP 工具搜索**，所有工具定义每轮整套带上；`ENABLE_TOOL_SEARCH=true` 强制开启后
中转照样能用（只放工具名，用到时 ToolSearch 取）。实测 `web + cap` 每轮前缀 **46k → 21k token**。
`ccx` 带了套餐就默认开，代价是每个工具第一次用多一轮；不要就 `ENABLE_TOOL_SEARCH=false ccx web`。

验收（2026-11-14）：`ccx hunt` 实跑，chrome-devtools 打开 example.com 后 mitmweb 的 `list_flows` 抓到请求
（证明自动接线生效）、模型先 ToolSearch 再调工具；`ccx burp` 在 Burp 未开时退出码 1 并提示。

> 顺带：shell 历史里常见 `ccx web --dangerously-skip-permissions`，那个 flag 多余，ccx 和 ccm 都已自带。

### 为什么经 ccm、而不是直接 claude

`ccx` 最后 `exec ccm`（Matrix 同步，代码在 `~/src/matrix-migration`），这样 **Matrix 手机同步照常保留**。
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

**2. ida 片段原先锁了插件版本号**（`…/ida-mcp/20261008.0.1`）。2026-11-14 起 `rev.json` 写 `${IDA_MCP_DIR}`，
由 `services.sh` 的 `ensure_ida` 取 `~/.claude/plugins/cache/HexRaysSA/ida-mcp/` 下版本号最大的目录，
并检查 `~/.idapro/ida-config.json` 里的 IDA 安装目录还在；不用再手改。片段里 MCP 名是 `ida`
（原插件是 `plugin:ida-mcp:ida`），工具名相应变 `mcp__ida__*`。

**3. 改动只对新会话生效。** 当前已加载的 MCP 不变，下次启动才干净。

**4. settings.json 的插件停用不入包。** `~/.claude/settings.json` 含明文 token、本就不入包，所以
「停用 ida-mcp 插件」这个开关只在本机生效，新机器装 cc 模块不会带过去（新机器可能根本没装那插件，无所谓）。

验收（2026-10-31）：`ccx -l` 列出 4 个套餐；`ccx cap` 启动的会话里 `${MITMWEB_TOKEN}` 展开为真值、
mitmweb 连得上；裸 `ccm`（含手机发起的会话）只有 matrix-sync；`./check.sh` 凭据扫描无命中。

### Grok 的同一套：ggx（2026-11-16）

Grok 把 `~/.grok/config.toml` 里 `enabled = true` 的 MCP 每个新会话都拉起来。它没有 Claude 的
`--mcp-config`。`grok mcp enable` / `disable` 和 TUI 里 `/mcps` 的空格都会写进那份配置，下次照样开。
`GROK_CONFIG_PATH` 的白名单不含 `mcp_servers`，塞了会被丢掉。家目录不是 git 仓库时，Grok 还把
`~/.grok/config.toml` 当成项目配置读，换 `GROK_HOME` 也盖不住。

`bin/ggx` 和 `ccx` 共用 `~/.claude/mcp/` 的套餐、别名和 `services.sh`：

```
ggx            # 干净，不挂任何 MCP（用户配置里的也这次关掉）
ggx web        # 只要 chrome-devtools
ggx web cap    # 叠多个，接线和说明跟 ccx 一样，说明经 grok 的 --rules 追加
ggx -l         # 列出套餐；别名仍用 ccx -s 增改
ggx -h         # 用法（也认 --help、help）
ggx web -- -p "帮我看下这个页面"
```

做法：真实配置在 `~/.grok/config.d/base.toml`，`config.toml` 是指向它的符号链接。`ggx` 写一份会话副本
（去掉用户配置里的 MCP，再补上点名的套餐），整个会话期间把链接指过去，退出再指回来。中途不能指回去，
Grok 会热重载，几秒内把这次的 MCP 卸掉。同时只开一个 `ggx`，两个会抢同一条链接。
直接跑 `grok` 不走 `ggx`，仍按 `base.toml` 来（眼下 `chrome-devtools` 是开着的）。

验收（2026-11-16）：`ggx -- inspect` 的 MCP 列表是空的；`ggx web` 期间 `grok inspect` 只有
`chrome-devtools`，退出后链接指回 `base.toml`，里面的 `enabled = true` 没被改掉。裸 `grok inspect` 仍有
`chrome-devtools`。

### GLM 也用同一套：ccglm（2026-11-16）

`bin/ccglm` 是跑在 GLM 上的 Claude Code，用来评测 GLM，**不替换**日常的 `claude`。两条隔离：

- **配置目录独立**：`CLAUDE_CONFIG_DIR=~/.claude-glm`，设置、记忆、会话都在那，`~/.claude` 不读不写。
  不能只在终端里临时设 `ANTHROPIC_BASE_URL`：`~/.claude/settings.json` 的 `env` 优先级更高，会盖回日常那套。
  所以全局 CLAUDE.md、自动记忆、skill 都不带过去，这是有意的。cc-cost、`Alt+a`、ccmon 只读 `~/.claude`，看不到 GLM 会话。
- **不进 Matrix**：带套餐时交给 ccx，但用 `CCX_LAUNCHER` 把最后 exec 的 `ccm` 换成裸 `claude`。

```
ccglm              # 干净启动，用法同 claude
ccglm web          # 套餐、别名、接线、组合说明全由 ccx 处理
ccglm -l           # 等于 ccx -l
```

第一个参数是套餐名、别名或 `-l` 才走 ccx，其余（prompt、claude 的参数）直接给 claude。

⚠ **在家目录启动会用错 key**（2026-11-16 踩到）：报 `503 分组 <日常 key 的分组> 下模型 glm-… 无可用渠道`。
cwd 是 `~` 时，`~/.claude/settings.json` 同时也是「项目设置」，优先级高于 `~/.claude-glm` 的用户设置，
于是 key 和地址换成了日常那套、模型名却还是 GLM 的。所以 ccglm 在家目录时加 `--setting-sources user`。
带套餐时这个 flag 不能排在套餐名前面（ccx 遇到 `-` 开头就停止解析套餐），所以 ccx 的 `CCX_LAUNCHER`
指回 ccglm 自己（带 `CCGLM_DIRECT=1`），由它在末尾补上。其他项目目录的 `.claude/settings*.json`
当时扫过，没有设 key 或地址的。
`~/.claude-glm/settings.json`（中转地址、模型映射）和 `relay.key`（600）**不入包**，新机器要手建。

验收（2026-11-16）：`ccglm web -- -p …` 的 init 里 MCP 只有 `chrome-devtools`，没有 matrix-sync；
工具延迟加载在 GLM 上能用（先 ToolSearch 再调 `list_pages`）；会话文件落在 `~/.claude-glm/projects/`。

## 14 · 花费统计：cc-cost（2026-11-13）

Windows 上的 ccswitch 自带用量统计，本机没有，就写了这个终端命令。输出分类表（输入 / 缓存写 5m / 缓存写 1h /
缓存读 / 输出各多少 token、多少钱）、按项目、最贵的 8 个会话（带单次最大上下文）；一天以内附「按小时」，跨天附「按天」。

```
cc-cost                            # 今天
cc-cost 昨天    cc-cost 11-12      # 某一天（也认 2026-11-12、前天）
cc-cost 7d      cc-cost 本月       # 最近 N 天含今天 / 本月 / 上月
cc-cost 11-01 11-13                # 一段日期，两头都算
cc-cost 09:00   cc-cost 09:00 11:30            # 今天某钟点起到现在 / 到某钟点
cc-cost "11-12 20:00" "11-13 02:00"            # 精确到分钟
cc-cost -h                         # 忘了怎么用就看这个（也认 help、帮助）
```

只做终端命令：启动器弹通知的版本用户不要，已撤。

⚠ **Claude Code 默认删掉 30 天没动过的会话记录**（`settings.json` 的 `cleanupPeriodDays`，本机没设 = 30），
更早的花费查不到；查的时间段早于最旧那份记录时，输出会提示「数字偏少」。

**数据**：`~/.claude/projects/**/*.jsonl`（含 `subagents/` 下的子代理记录），每条 assistant 消息带 API 返回的 `usage`，
是真实计数不是估算。项目按会话**启动**目录归，不按逐条 `cwd`（会话里 `cd` 一下就被拆成一堆子目录）。

**金额只是官方标价折算**。本机走中转，实付看中转后台。价格表手抄在脚本顶部，出新模型要补；
没补的模型**不计入金额**，输出里会列出来提醒（2026-11-12 就有一批 `claude-opus-4-8` 当时没收录）。

**人民币用实时汇率**（写死的汇率会让人民币一栏偏差几个百分点）：从
`open.er-api.com`（免 key、每天更新）取美元兑人民币，缓存 12 小时在 `~/.cache/cc-cost/usdcny.json`；
联网失败用旧缓存，连缓存都没有才退回脚本里的 `CNY = 7.1`。合计行括号里会写汇率和来源日期，
看到「旧缓存」「固定值」就说明这次没取到。没用 frankfurter（欧央行数据）：它只在工作日更新，
而且域名 2026 年改到了 `api.frankfurter.dev`，旧地址返回 301。

### 坑

**1. 必须去重。** 流式输出时同一次请求会在记录里出现好几行，usage 一模一样。按 `message.id + requestId` 去重，
不去重会多算一倍多。

**2. 缓存写要拆 5m / 1h。** 两档单价差 1.6 倍（Opus 5.5 是 $5 / $8），`usage.cache_creation` 里有
`ephemeral_1h_input_tokens`，剩下的才是 5m。主会话走 1h（第 10 节），子代理是 5m。

**3. Opus / Sonnet 5.5 的缓存读是输入价的 0.05x**（$0.20），不是以前的 0.1x，抄价格别照旧倍率推。

### 看出来的钱都花在哪（2026-11-13 上午，供以后对照）

约 4.7 亿 token、$208：缓存读 44%、缓存写 50%、输出 6%，不走缓存的输入几乎为 0。
token 数里 96% 是缓存读，看着吓人，但单价便宜；真正贵的是**上下文长度 × 请求次数**。
那天 82% 的钱花在同一个会话派出的 8 个「经典研读」子代理上，其中一个跑了 317 次请求、上下文涨到 99.6 万。
缓存写里有 74% 来自 39 次一次性 5 万 token 以上的整段重建（缓存过期、压缩、新开子代理）。
省钱方向：子代理拆小、做完就结束，别让一个子代理滚到 100 万；输出只占 6%，不用管。

## 15 · 做完关机：cc-shutdown（2026-11-14）

晚上挂着好几个 Claude 会话、子代理在跑，人要走：启动器点 **「Claude 做完关机」**，全停下就关机；
反悔点 **「取消 Claude 做完关机」**。两个都会弹通知说结果。终端里同样能用：

```
cc-shutdown              # 挂上
cc-shutdown --cancel     # 取消
cc-shutdown --status     # 挂没挂、现在还有谁在干活（逐条列出）
journalctl --user -u cc-shutdown-watch    # 盯的过程日志
```

也可以直接跟任何一个 Claude 会话说「做完关机」，让它跑 `cc-shutdown`。
后台是 `systemd-run --user` 起的临时单元 `cc-shutdown-watch`，关掉终端 / 那个 Claude 会话都不影响。

**用户定的规则：停在「等你授权 / 等你回答」也算做完，照样关机。** 也就是说只看「还有没有在跑」，
不管有没有活等你拍板 —— 挂上之前心里要有数，第二天回来接着点就是。

### 怎么判断「还在干活」（任一条成立就不关）

| 对象 | 看什么 |
|---|---|
| 会话 | `~/.claude/sessions/<pid>.json` 的 `status == busy`（`idle`、`waiting` 都算停了），进程不在的残留文件跳过 |
| 子代理 | `~/.claude/projects/*/<会话>/subagents/**/*.jsonl` 最后一条 assistant/user 记录不是 `end_turn`，且 20 分钟内动过 |
| Agent Teams 队员 | tmux 里进程名是版本号的窗格，屏幕上有转圈行（同 `tmux-panes`，见 14-tmux 第 9 节） |
| 命令 | claude 进程底下 cmdline 带 `shell-snapshots` 的 shell（Bash 工具起的，含后台命令），跑超 1 小时的不算 |

全停之后还要**连续保持 3 分钟**，再弹「60 秒后关机」的通知倒数；倒数中又有活就作废、接着等。
关机用 `systemctl poweroff --check-inhibitors=no`，不让 Chrome、QQ 之类的抑制锁拦（它们本来也只是 delay 型）。

### 为什么这么判

**1. 子代理不能只看会话状态。** 主会话把子代理派到后台后自己就收工了，`status` 落回 `idle`，
可子代理还在跑。所以单独看子代理的记录文件：跑完的子代理最后一条一定是 assistant 的 `end_turn`
（2026-11-14 抽查 150 个已结束的：143 个 `end_turn`，`stop_sequence` / `refusal` 各 1，
剩下 4 个是被打断的，停在 tool_result 上）。

**2. 被打断 / 被杀的子代理长得跟「正在跑工具」一样**，所以加了「20 分钟没动静就当死了」。
代价：遇到这种残骸最多晚关 20 分钟；一个子代理单条命令跑超过 20 分钟没写记录，会被误判成做完（Bash 工具默认最长 10 分钟，实际很少见）。

**3. 要等 3 分钟稳定。** 子代理交差后会把主会话重新叫醒，中间有几秒空档全是 `idle`，不等就会在空档里关掉。

**4. 后台命令跑超 1 小时不算。** Claude 常起 `npm run dev` 之类的常驻服务挂在后台，不排除就永远关不了；
代价是真有超过 1 小时的后台构建会被当成常驻服务。

**5. `--status` 从 Claude 的 Bash 工具里跑时会排除自己那条 shell**，不然永远看到「还有一条命令在跑」。
后台单元不是谁的子进程，看得到所有会话的命令，包括正在调它的那个会话。

### 没管的

- 会话卡在 `busy` 不动（比如 API 一直重试）就一直不关。没加「最多等多久」，需要再加。
- 只看本机，局域网 MacBook 上的 Claude 不算。
- 测试时可以用环境变量 `CC_SHUTDOWN_POLL` / `CC_SHUTDOWN_STABLE` / `CC_SHUTDOWN_GRACE` 缩短时间，加 `--dry-run` 只通知不关机。

验收（2026-11-14）：用假状态序列跑 `--watch --dry-run`，「全停→倒数→本该关机」和「倒数中又有活→作废→再倒数」两条路都走通；
启动器两个条目 `gtk-launch` 挂上 / 取消正常，重复挂上会提示已挂着；`--status` 正确列出 3 个 busy 会话和 2 个在跑的子代理。

---

## 16 · 版本钉死、手动升级；贴图片与对话里看图（2026-11-17）

### 版本：关自动更新，升级前先隔离测

现用 **2.1.326**（2026-11-17 从 2.1.273 升上来）。自动更新两处都关了：

| 位置 | 设置 |
|---|---|
| `~/.claude.json` | `"autoUpdates": false`（之前就关着） |
| `~/.claude/settings.json` 的 `env` | `"DISABLE_AUTOUPDATER": "1"`（这次加的；这个文件含 token、不入包，新机器手动加） |

**为什么关：** 手机远程靠 Matrix 同步（`~/src/matrix-migration`，`ccm` 启动），它读 `~/.claude/sessions/*.json`、
transcript、状态栏，还用 tmux `capture-pane` 读屏、`send-keys` 送字；本机的 `tmux-panes`、`cc-shutdown`
也靠读屏正则。哪个都可能被一次静默升级弄坏。

**升级步骤**（2026-11-17 这次就是这么做的）：

1. 下载到别处，不碰 `~/.local/bin/claude`：
   ```bash
   B=https://downloads.claude.ai/claude-code-releases
   V=$(curl -fsS $B/latest)
   curl -fsS $B/$V/manifest.json | jq -r '.platforms["linux-x64"].checksum'   # 记下校验和
   curl -fsS -o ~/.cache/claude-test/claude-$V $B/$V/linux-x64/claude && sha256sum ~/.cache/claude-test/claude-$V
   ```
2. **不带 hooks 的隔离配置**试新功能：`CLAUDE_CONFIG_DIR` 指向一个只放 `env` 的 settings.json 的目录，
   不然 PermissionRequest 之类的钩子会把测试会话转发到手机。在**家目录以外**启动（家目录下 `~/.claude/settings.json`
   同时算项目设置，见第 13 节末 ccglm 的坑）。
3. **Matrix 端到端**：先备份 `~/.claude.json` 和 settings.json（新版会读写真实 `~/.claude`），然后
   `PATH=<放了指向新版的 claude 软链接的目录>:$PATH ccm` 起一个会话。要验的项：建房间、本地输入镜像、回复镜像、
   AskUserQuestion 变投票并能从手机答、手机发消息能送进去、完成通知。手机方向要人在手机上点。
4. 读屏正则：在 tmux 里让它前台干几秒活，看 `tmux-panes` 的 `SPIN_LINE` 还能不能命中转圈行。
5. 都过了再切：拷进 `~/.local/share/claude/versions/<版本>`、`ln -sfn` 改 `~/.local/bin/claude`。
   旧版本文件留着，回退只要改回软链接。已开着的会话重启后才换新版。

2.1.326 实测：上面 3、4 全过（转圈行现在长这样 `· Crafting… (5s · thinking)`，旧正则照样命中）。
没测到的是权限卡片（ccm 默认 bypass，不弹），它和投票走同一个 PermissionRequest 钩子。

### 升级后的新弹框：`--add-dir` 的目录每次都问信任（2026-11-18）

2.1.326 起，用 `--add-dir` 加进会话的目录如果**没被信任过**，每开一个会话都弹
「This session hasn't worked here before. Is this a directory you created or one you trust?」。
框里选信任**只管这一个会话**，所以下次开还会问。`ccm`（还有经它启动的 `ccx`）带了
`--add-dir ~/.claude/channels/matrix-sync/inbox`（手机发来的文件放这里），于是每次都弹。

永久信任要写进 `~/.claude.json`：`.projects["<绝对路径>"].hasTrustDialogAccepted = true`
（和"在那个目录里启动 Claude Code 并点信任"效果一样）。inbox 这条本机已写，具体命令和
为什么信任它没风险见 matrix-migration 仓库的 `docs/DEPLOY.md`（`bin/ccm` 那段）。
**以后给 ccm/ccd/ccx 再加 `--add-dir` 目录，也要同样补一条信任**，换机器时一并重做。

### 贴图片：Dolphin 的 Ctrl+C 贴不进来

Claude Code 在 Linux 上按 **Ctrl+V** 时只认剪贴板里的 `image/*`（实际跑的是
`wl-paste -l | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"`）。Dolphin 复制文件**只放文件引用**：

```
text/uri-list                  file:///home/david/xxx.png
application/x-kde4-urilist
application/vnd.portal.filetransfer
application/x-kde-source-id
```

没有图片数据，也没有 `text/plain`，所以 Ctrl+V 和 kitty 的 Ctrl+Shift+V 都贴出空的。复制的是 png 也一样。

| 想给 Claude 的东西 | 怎么做 |
|---|---|
| 截图、浏览器「复制图片」 | 直接 **Ctrl+V**（不是 Ctrl+Shift+V），出现 `[Image #1]` |
| Dolphin 里的文件（任何类型） | 选中按 **Ctrl+Alt+C**（复制位置 = 路径文字），Claude 里 **Ctrl+V** 或 Ctrl+Shift+V 都行。图片路径自动变成 `[Image #1]`，PDF 等其他文件贴的是路径，发出去 Claude 用 Read 去读（2.1.326 实测：Ctrl+V 找不到图片时会退回贴文字，2.1.273 不会） |

### 对话里看图：inline-images 插件

2.1.294 起 Claude Code 有了插件扩展接口（mods）和 kitty 图形协议的图片组件，但**自己不画图**，
粘贴的图片在记录里只是一行 `⎿ [Image #1]`。画图靠第三方插件
[alexjsp/claude-inline-images](https://github.com/alexjsp/claude-inline-images)：粘贴的图、Read 读到的图、
MCP 返回的截图、回复里 `![](/绝对路径.png)` 都画在对话里，标题 `▾` 点一下折叠，`↗ open` 用默认程序打开。

- 代码钉在 `~/src/claude-inline-images`（cb86e9e，2026-11-17 审过：不联网，只调 `ps`/`perl` 量格子、`magick` 转格式、
  `xdg-open` 打开，缓存在 `$TMPDIR/claude-inline-images-<uid>`，0700）。从本地目录装的，不会自己跟 GitHub 更新：
  ```bash
  claude plugin marketplace add ~/src/claude-inline-images
  claude plugin install inline-images@inline-images
  ```
  要更新先 `git pull` 再审 diff。
- 作者只在 macOS 上测过，本机 Linux 实测可用（依赖 `magick`、`perl` 都在）。

**只有 kitty 直连 tmux 才看得到图。** 本机平时的链路是 kitty → nvim `:terminal` → tmux → claude，
nvim 的终端不转发 kitty 图形协议，图片会变成一块空白（实测）。所以两处配置这样分工：

| 文件 | 设置 | 为什么 |
|---|---|---|
| `~/.tmux.conf` | `set -g allow-passthrough on` | 让图片数据穿过 tmux 到外层 kitty |
| `~/.zshrc`（tmux 窗格状态那段里） | 客户端是 `xterm-kitty` 时才 `export CLAUDE_CODE_FORCE_TERMINAL_IMAGES=1` | 隔着 tmux Claude 认不出 kitty，要强制开图；但经过 nvim 时强制开只会留下一大块空白（每张图最高 30 行），不如不开时显示一行 `[image 宽×高]` |

判断的是**开这个窗格时**连着的客户端：kitty 直连是 `xterm-kitty`，经 nvim 是 `xterm-256color`。
从 Matrix `!new` 开的会话没有客户端，不会强制开。之后换个客户端去看同一个窗格，不会跟着变。

**踩过的坑（2026-11-18）：原生 kitty 连着 tmux 也只显示 `[image 宽×高]`。** 那个窗格是早先经 nvim 开的，
zsh 当时没设变量；后来改从原生 kitty attach，窗格里的 zsh 和在它里面（重新）起的 claude 继承的还是旧环境。
自查：`tr '\0' '\n' < /proc/<claude 的 pid>/environ | grep -E 'FORCE_TERMINAL|NVIM'`——有 `NVIM=`、
没 `FORCE_TERMINAL_IMAGES` 就是这个。修法：在原生 kitty 连着时**新开窗格**（prefix + c）再起 claude，
要接着原对话用 `claude --resume`。实测新窗格里 Read 图片正常显示。

**为什么 nvim 里不行、image.nvim 却行：** image.nvim 是 nvim 进程自己往外层 kitty 写图形协议
（nvim 是 kitty 的直接程序，知道图该放哪个窗口哪一格）。而 `:terminal` 里跑的程序，输出先经 nvim 内置的
终端模拟器（libvterm），它不认 kitty 图形协议、收到就丢，也没有 tmux `allow-passthrough` 那样原样转发的开关。
「绕开 nvim 直接写 kitty 的 tty」理论上可行，但要自己算 claude 区域在屏幕上的位置、跟着 nvim 分屏和滚动走，不划算，没做。

⚠ 截屏卡片（Matrix 那边用 `capture-pane` 截屏）赶上屏幕上有图时，卡片里会混进一串占位字符，不影响功能。
