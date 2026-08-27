# 08 · Claude Code 本机工具

装在 `~/.claude/` 下的三件东西：**上下文占比状态栏**、**多会话看板**、**宠物版 TUI（能就地代答）**。
由 `install.sh cc` 安装，`manifest.map` 的 `#@module cc` 段是路径的单一事实来源。

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
