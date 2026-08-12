<h1 align="center">🥊 Sparring</h1>

<p align="center">
  <strong>AI 写代码，另一个 AI 找茬。<br>
  像拳击陪练一样，互相推动变强——直到代码值得上线。</strong>
</p>

<p align="center">
  <a href="#-快速开始"><img src="https://img.shields.io/badge/Quick_Start-2_min-blue?style=for-the-badge" alt="Quick Start"></a>
  <a href="#-核心特性"><img src="https://img.shields.io/badge/Features-4_pillars-purple?style=for-the-badge" alt="Features"></a>
  <a href="#-审查后端"><img src="https://img.shields.io/badge/Backends-Claude_%7C_opencode-green?style=for-the-badge" alt="Backends"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/plugin-Claude_Code-E9DBFC?logo=anthropic&logoColor=black" alt="Claude Code">
  <img src="https://img.shields.io/badge/version-3.0.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/primary_%2B_fallback-auto--degrade-orange" alt="Fallback">
  <img src="https://img.shields.io/badge/config-JSON_%2B_env-lightgrey" alt="Config">
</p>

**一句话：** 你描述任务，Claude 写方案+代码，另一个 AI 自己进仓库找茬，人类只在关键节点拍板。

Sparring 是 Claude Code 的插件。它给 Claude 配一个"对手"——专门挑毛病的第二个 AI，以"假设有 bug，找到它"的心态审查方案和代码。最多 5 轮，直到双方一致。

reviewer 不是只收一段 diff 文本的模型调用，它是个 agent：给它一段 git range，它自己跑 `git diff`、读文件、grep 调用方，看懂上下文再下结论。

[English](README.en.md)

---

## 📰 What's New

- **2026-08** · 🥊 **3.0（破坏性）**：reviewer 从"收一段 diff 文本"变成**自己进仓库查的 agent**——`sparring review --range origin/main...HEAD` 建只读快照，reviewer 在里面自己跑 `git diff`、读文件、追调用方。随之：后端收敛到 `claude` + `opencode`（`cursor` / `codex` / `glm` 三个后端**已删除**），diff 管道输入直接报错，diff 体量门禁和分片建议一并移除
- **2026-07** · 📓 `sparring review` 执行日志：每次调用落一行 JSONL，事后能查是哪个后端审的、有没有降级、耗时多久
- **2026-06** · 🧠 新增 **`claude` 后端**：用 Claude Code CLI（`claude -p`）跑 review
- **2026-05** · 🔥 新增 JSON 配置系统（`~/.config/sparring/config.json` + `.sparring/config.json`），支持团队共享；主/备降级机制；仓库正式更名为 `sparring`（旧 `workflow` 命令保留为软链兼容）
- **2026-04** · 🎯 新增后台 review job（长耗时 review 可异步跑）
- **2026-03** · 首发：Claude + Cursor 双 AI 协作 + 最多 5 轮 review 机制；GitHub Issue 驱动工作流（从 Project 看板接任务，讨论自动同步到 Issue 评论）

---

## 🌟 核心特性

<table>
<tr>
<td width="50%">

### 🥊 双 AI 对抗式审查
一个 AI 写，另一个 AI 找茬。不是互相夸奖，是像拳击陪练那样互相逼出更好的输出。reviewer 自己进仓库看上下文，不靠你贴的那段 diff 猜。**最多 5 轮**，直到双方一致才放行。

</td>
<td width="50%">

### 🎛️ 双后端 + 主备降级
`claude`（Claude Code CLI）/ `opencode`（plan agent）任选，还能配主+备。主 backend CLI 调用失败时（超时 / 网络错 / 进程异常退出）自动切备，工作流不阻塞。两个后端都用各自 CLI 已登录的账号，sparring 不存任何 API key。

</td>
</tr>
<tr>
<td width="50%">

### ⚙️ 四层配置系统
**内置默认 → 全局 config → 项目 config → 环境变量**。用哪个后端、哪个模型放全局（各开发者自己）；项目 config 只放团队需统一的非主观项（超时/重试），不约束用谁审查；临时覆盖走 env。一键 `sparring config init` 初始化。

</td>
<td width="50%">

### 📋 GitHub Issue 驱动
从 Project 看板认领 Issue，AI 讨论自动同步到 Issue 评论，完成后开 PR。全程带身份标记（🧠 Claude Code / 🛠 opencode），协作过程可追溯。

</td>
</tr>
</table>

---

## 🤔 为什么需要

AI 写代码快，但会犯错——幻觉 API、漏掉边界、引入回归。让人逐行 review？不现实。

|  | 没有 Sparring | 有 Sparring |
|---|---|---|
| AI 的每个结论 | 直接告诉你 | 先过另一个 AI 审一遍 |
| 漏掉边界情况 | 🤷 发 PR 才发现 | 🛡️ reviewer 在 review 环节抓住 |
| 看起来对但有隐患 | 😬 上线后出事 | 🎯 "假设有 bug 找它" 的视角挑出来 |
| reviewer 缺上下文 | 🙈 只能盯着 diff 猜 | 🔍 reviewer 自己读文件、grep 调用方 |
| 主 reviewer 后端挂了 | ❌ 工作流卡住 | 🔄 自动降级到备用 backend |
| 两个 AI 视角不一致 | — | ✅ 必然至少两种意见，降低盲区 |

**效果**：AI 产出更可靠，人工 review 更少，心智负担更低。

---

## 🚀 快速开始

### 1. 安装插件

```bash
# 在 Claude Code 里
/plugin marketplace add krislavten/sparring
/plugin install sparring@sparring
```

### 2. 初始化（自动装依赖 + 选 reviewer 后端）

```bash
# 退出 Claude Code 后重新打开
/sparring:setup
```

### 3. 开干

```bash
/sparring:workflow 给登录接口加 rate limiting
```

就这样。Claude 写方案 → reviewer 找茬 → 你确认 → Claude 实现 → reviewer 再找茬 → 你合并。

---

## 🎮 三种模式

| 模式 | 命令 | 适用场景 |
|------|------|---------|
| 💬 **普通** | `/sparring:workflow <任务>` | 你参与方案讨论，AI 双方自动完成审查，你最后拍板 |
| 🚀 **YOLO** | `/sparring:yolo <任务>` | AI 全自动，你只确认最终提交。小改动 / 明确任务 |
| 🎫 **Issue** | `/sparring:issue <看板URL> [编号]` | 从 GitHub Issue 接任务，讨论同步到 Issue 评论 |

---

## 🔁 工作流程

```
   你描述任务
       ↓
  ┌─────────────────┐
  │  Claude 写方案   │
  └────────┬────────┘
           ↓
  ┌─────────────────┐    CONCERNS
  │ Reviewer 挑战方案 │─────────┐
  └────────┬────────┘         ↓
           ↓ APPROVE      Claude 修改
           ↓             (最多 5 轮)
       你确认
           ↓
  ┌─────────────────┐
  │  Claude 写代码   │
  └────────┬────────┘
           ↓
  ┌─────────────────┐    CONCERNS
  │ Reviewer 挑战代码 │─────────┐
  └────────┬────────┘         ↓
           ↓ APPROVE      Claude 修复
           ↓             (最多 5 轮)
     你确认并提交
```

**交叉审查原则**：Claude 给你**任何建议或结论**之前，都会先让 reviewer 审一遍。"建议用 Redis 做缓存" → 先让 reviewer 质疑 → 确认或调整 → 再告诉你。

---

## ⚡ 快速审查：`sparring review`

不建 task、不进工作流，直接让 reviewer 审一次。两种输入形态：

### 形态一：审一段仓库改动（推荐）

```bash
sparring review --range origin/main...HEAD --title "登录限流"
sparring review --range HEAD~3..HEAD
```

`--range` 会用 `git worktree add --detach` 给这段改动建一个**只读快照**（临时目录），reviewer 的工作目录就是快照——它自己跑 `git diff <range>`、按需读文件、grep 调用方，审完自动删快照（正常结束、失败、被 Ctrl-C / kill 都清）。

因为 diff 不进 prompt，**没有体量上限，也不需要按文件分片**。

### 形态二：审一段结论或方案

```bash
echo "建议用 Redis 做缓存，理由是……" | sparring review --title "缓存选型"
```

纯文本审查不建快照，reviewer 跑在一个临时空目录里，就事论事裁决。

### 契约

- 输出首列就是裁决词：`APPROVE` 或 `CONCERNS`
- 退出码：`0` = APPROVE，`2` = CONCERNS，`1` = 调用错误。**解析不出裁决按错误处理，绝不默认放行**
- 每次调用追加一行 JSONL 到 `~/.local/state/sparring/review-YYYYMMDD.jsonl`（字段 `ts` / `title` / `mode` / `range` / `input_lines` / `backend` / `via` / `duration_s` / `exit_code` / `verdict`），默认保留 7 天（`review.log_retention_days`，`0` = 禁用），用来事后查"哪次超时了、有没有降级"

> ⚠️ **不再接收 diff 文本**。`git diff ... | sparring review` 会直接报错并提示改用 `--range`，不做静默兼容（判定：stdin 里有 `diff --git ` 或 `--- a/` 打头的行）。`--range` 模式**不读 stdin**——非交互环境里 stdin 常是个不会关闭的管道，读它会永久卡死；`--range` 和文本内容同时给也会报错。

> 🔒 **快照的"只读"是什么意思**：reviewer 手里有 Bash（不然它跑不了 `git diff`），工具层面挡不住它写文件。这里的只读靠的是 detached（不动任何分支）+ 审完即删，不是文件系统权限；快照与主仓库共用 `.git` 对象库。别把它当沙箱用。

---

## 🎛️ 审查后端

两个 backend，可自由组合主备。两者都用各自 CLI **已登录的账号**，sparring 不存任何 API key：

| Backend | 怎么跑 | 工具权限 |
|---------|--------|---------|
| 🧠 `claude` | Claude Code CLI（`claude -p` 非交互模式），**默认主后端** | 放行 `Bash` + `Read` / `Grep` / `Glob`；禁 `Edit` / `Write` / `NotebookEdit` / `Task` / `WebFetch` / `WebSearch` |
| 🛠 `opencode` | `opencode run --agent plan`，**默认备后端** | plan agent 本身就不带编辑能力 |

> 写类和联网工具被禁掉了，但 Bash 没有——reviewer 需要它跑 `git diff` / `grep`。所以"reviewer 不会改东西"靠的是审完删快照，不是工具权限，见上面那条。

### 主 + 备降级

主 backend 调用失败（超时 / 网络错 / CLI 异常）时**自动切到备**，工作流不阻塞：

```
⚠ 主 backend Claude Code 调用失败，降级到 opencode (plan)...
```

**典型组合**（写进你**全局**配置 `~/.config/sparring/config.json`，按个人偏好；项目级不要设 backend）：

```jsonc
// A) 默认：Claude Code 主 + opencode 备
{ "review": { "backend": "claude", "fallback": "opencode" } }

// B) 反过来：opencode 主，Claude Code 兜底
{ "review": { "backend": "opencode", "fallback": "claude" } }

// C) 只用一个后端，关掉降级
{ "review": { "backend": "claude", "fallback": null } }
```

> ⚠️ **`cursor` / `codex` / `glm` 三个后端在 3.0 已删除。** 配置里还写着这些值的会**直接报错退出**（不静默降级）——改成 `claude` 或 `opencode`，或者重跑 `sparring config init --force`。

---

## ⚙️ 配置系统

四层优先级（低→高）：**内置默认 → 全局 → 项目 → 环境变量**。

```bash
sparring config init                # 生成 ~/.config/sparring/config.json（chmod 600）
sparring config init project        # 生成 .sparring/config.json（团队共享非主观项，不放 backend/模型）
sparring config show                # 看合并后的配置
sparring config get review.backend  # 取单值
```

**全局配置** `~/.config/sparring/config.json`：

```json
{
  "review": {
    "backend": "claude",
    "fallback": "opencode",
    "timeout": 1800,
    "retries": 1,
    "log_retention_days": 7
  },
  "claude": {
    "model": null
  },
  "opencode": {
    "model": null
  }
}
```

**项目配置** `.sparring/config.json`（**默认入库**，只放团队需统一的非主观项，如超时/重试）：

```json
{
  "review": {
    "timeout": 1800,
    "retries": 1
  }
}
```

> ⚠️ **项目配置不要设 `review.backend` / `fallback` / 模型**。用什么 reviewer 后端和模型由**各开发者自己的全局配置**决定，项目级不约束（项目 config 优先级高于全局，写了会覆盖每个人的个人选择）。

**环境变量覆盖（均为可选，非必需 —— 不设也能跑）**（`SPARRING_*` 主推，`WORKFLOW_*` 兼容别名）：

```bash
export SPARRING_REVIEW_BACKEND=opencode  # → review.backend
export SPARRING_REVIEW_FALLBACK=claude   # → review.fallback
export SPARRING_REVIEW_TIMEOUT=900       # → review.timeout（临时调大；默认已是 1800）
```

> 💡 **配置里没有任何 API key。** 两个后端都跑对应 CLI 已登录的账号（`claude login` / `opencode auth login`），sparring 只负责选后端和模型，新机器只要各自登录一次 CLI。

> ⏱️ **超时以分钟计**：reviewer 是个自己跑 git、读文件的 agent，一次审查耗时以分钟计，所以 `review.timeout` 默认 1800s。3.0 之前的"按送审内容大小自适应加时"已删除——diff 不再进 prompt，也就没有按大小加时这回事，现在是扁平值。
>
> ⚠️ **重试会线性放大最坏等待时间**：失败重试时每次都会用满同一个单次超时，不会缩水。默认 `review.retries=1`（共尝试 2 次），最坏情况下一次 `sparring review` 可能等待到 **1200s（20 分钟）** 才报错。这是有意为之——重试是为了应对网络抖动/瞬时错误。如果不想等这么久，设 `review.retries=0` 关闭重试。

### 可配置字段

| key | 默认 | 说明 |
|---|---|---|
| `review.backend` | `claude` | 主后端，只能是 `claude` 或 `opencode` |
| `review.fallback` | `opencode` | 备后端；`null` = 关掉降级 |
| `review.timeout` | `1800` | 单次调用超时秒数（扁平值，不再自适应加时） |
| `review.retries` | `1` | 失败后重试次数（共尝试 retries+1 次） |
| `review.log_retention_days` | `7` | 执行日志保留天数；`0` = 完全不写日志 |
| `claude.model` | `null` | 留空 = 用 Claude Code 自己的默认模型 |
| `claude.use_proxy` | `false` | `false` 时调用前清空 `HTTP(S)_PROXY`；要靠代理才连得通就设 `true` |
| `claude.extra_args` | `null` | 附加 `claude` CLI 参数（逃生舱） |
| `opencode.model` | `null` | 留空 = 用 opencode 自己的默认模型 |
| `opencode.use_proxy` | `false` | 同 `claude.use_proxy` |
| `opencode.extra_args` | `null` | 附加 `opencode` CLI 参数（逃生舱） |

完整清单随时用 `sparring config show` 查看。

### 验证

```bash
sparring verify   # 检查 jq / git，再逐个探主/备 backend CLI 装没装好、能不能连通
```

---

## 🎫 GitHub Issue 驱动

给团队用的。通过 GitHub Issues + Project 看板管理：

```bash
/sparring:issue https://github.com/orgs/your-org/projects/3 106
```

自动完成：**认领 Issue → 看板「进行中」→ AI 讨论同步到 Issue 评论 → 完成开 PR → 移到「审查中」**

评论都带身份标记，一眼看出谁说的：

| 图标 | 角色 | 做什么 |
|---|---|---|
| 🧠 | Claude Code | 写方案、实现；作为 reviewer 时的审查意见 |
| 🛠 | opencode | 审查意见 |
| 🔧 | Workflow | 状态流转 |

---

## 🦞 多 Agent 并行（配合 ClawTeam）

Sparring 管审查质量，[ClawTeam](https://github.com/HKUDS/ClawTeam) 管多 agent 并行。组合使用：每个 agent 既能并行加速，又有质量保障。

```
ClawTeam 分 3 个任务并行
  ├── Claude #1: auth 模块  ← Sparring: Reviewer 审查
  ├── Claude #2: database  ← Sparring: Reviewer 审查
  └── Claude #3: frontend  ← Sparring: Reviewer 审查
```

```bash
# 安装 ClawTeam
pipx install clawteam

# 创建团队 + spawn worker（每个 worker 完成后跑 Sparring review）
clawteam team spawn-team my-project -d "重构用户系统" -n leader
clawteam spawn tmux claude --team my-project --agent-name auth \
  --task "实现 auth 模块。写完后运行 sparring review-code my-project 让 reviewer 审查"
clawteam board attach my-project   # 看所有 agent 同时工作
```

**Issue + Team 协同**：大 Issue 拆成子任务让多 agent 并行开发（见 [ClawTeam 完整示例](https://github.com/HKUDS/ClawTeam)）。

**自动接单**：让 Claude 定时轮询看板：

```bash
/loop 5m /sparring:issue https://github.com/orgs/your-org/projects/3
```

---

## 🧰 后台审查（可选）

review 耗时长时可后台执行：

```bash
sparring review-proposal-bg <task-id>    # 启动后台 job
sparring review-code-bg <task-id>
sparring review-status [job-id|task-id]  # 查状态
sparring review-result <job-id>          # 看结果
sparring review-cancel <job-id>          # 取消
```

---

## 🗺️ 命令速查

```bash
# 初始化
sparring setup                  # 交互式安装
sparring config init            # 生成全局配置
sparring verify                 # 检查环境

# 快速审查（不建 task，走配置的 backend；详见上面「快速审查」一节）
sparring review --range origin/main...HEAD --title "<改动主题>"   # 审一段仓库改动
echo "<结论/方案>" | sparring review --title "<主题>"             # 审一段文本
#   退出码 0=APPROVE  2=CONCERNS  1=调用错误/解析不出裁决
#   ⚠ 不再接收 diff 文本，管道进 diff 会直接报错 —— 改用 --range

# 任务
sparring create <name> <claude|cursor>
sparring propose <task-id>
sparring review-proposal <task-id>
sparring implement <task-id>
sparring review-code <task-id>
sparring approve <task-id>
sparring list
sparring status <task-id>

# Issue
sparring --project <url> issue-poll
sparring issue-claim <number>
sparring issue-comment <number> <body>
sparring issue-read <number>
sparring issue-done <number> [pr-url]
```

完整列表：`sparring help`。**兼容别名**：`workflow xxx` 仍可用（`bin/workflow` 是软链）。

---

## 📚 深入阅读

- [工作模式详解](MODES.md)
- [完整示例](EXAMPLES.md)
- [English README](README.en.md)

---

## 🤝 贡献

欢迎 Issue / PR。这个项目本身就用 Sparring 开发——你能看到主分支上每个改动都过了 sparring review。

## License

MIT
