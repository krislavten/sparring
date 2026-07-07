<h1 align="center">🥊 Sparring</h1>

<p align="center">
  <strong>AI 写代码，另一个 AI 找茬。<br>
  像拳击陪练一样，互相推动变强——直到代码值得上线。</strong>
</p>

<p align="center">
  <a href="#-快速开始"><img src="https://img.shields.io/badge/Quick_Start-2_min-blue?style=for-the-badge" alt="Quick Start"></a>
  <a href="#-核心特性"><img src="https://img.shields.io/badge/Features-4_pillars-purple?style=for-the-badge" alt="Features"></a>
  <a href="#-审查后端"><img src="https://img.shields.io/badge/Backends-Cursor_%7C_Codex_%7C_GLM_%7C_Claude-green?style=for-the-badge" alt="Backends"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/plugin-Claude_Code-E9DBFC?logo=anthropic&logoColor=black" alt="Claude Code">
  <img src="https://img.shields.io/badge/version-2.1.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/primary_%2B_fallback-auto--degrade-orange" alt="Fallback">
  <img src="https://img.shields.io/badge/config-JSON_%2B_env-lightgrey" alt="Config">
</p>

**一句话：** 你描述任务，Claude 写方案+代码，Cursor/Codex/GLM 找茬，人类只在关键节点拍板。

Sparring 是 Claude Code 的插件。它给 Claude 配一个"对手"——专门挑毛病的第二个 AI，以"假设有 bug，找到它"的心态审查方案和代码。最多 5 轮，直到双方一致。

[English](README.en.md)

---

## 📰 What's New

- **2026-06** · 🧠 新增 **`claude` 后端**：用 Claude Code CLI（`claude -p`）跑 review，并支持**换后端模型**——把 Claude Code 指向 GLM / DeepSeek 等 Anthropic 兼容端点。内置 reviewer 上下文隔离（空 cwd + 独立 config dir）+ 禁全部工具，杜绝 `CLAUDE.md` 污染与递归
- **2026-05** · 🔥 支持**智谱 GLM** 作为第三个审查后端，配合主/备降级机制；新增 JSON 配置系统（`~/.config/sparring/config.json` + `.sparring/config.json`），支持团队共享；仓库正式更名为 `sparring`（旧 `workflow` 命令保留为软链兼容）
- **2026-04** · 🎯 新增 **Codex CLI** 后端 + 后台 review job（长耗时 review 可异步跑）
- **2026-03** · 首发：Claude + Cursor 双 AI 协作 + 最多 5 轮 review 机制；GitHub Issue 驱动工作流（从 Project 看板接任务，讨论自动同步到 Issue 评论）

---

## 🌟 核心特性

<table>
<tr>
<td width="50%">

### 🥊 双 AI 对抗式审查
一个 AI 写，另一个 AI 找茬。不是互相夸奖，是像拳击陪练那样互相逼出更好的输出。**最多 5 轮**，直到双方一致才放行。

</td>
<td width="50%">

### 🎛️ 四后端可选 + 主备降级
`cursor` / `codex` / `glm` / `claude` 任选，还能配主+备。主 backend CLI 调用失败时（超时 / 网络错 / 进程异常退出）自动切备，工作流不阻塞。

</td>
</tr>
<tr>
<td width="50%">

### ⚙️ 四层配置系统
**内置默认 → 全局 config → 项目 config → 环境变量**。API key、backend、模型放全局（各开发者自己，chmod 600）；项目 config 只放团队需统一的非主观项（超时/重试），不约束用谁/什么模型审查；临时覆盖走 env。一键 `sparring config init` 初始化。

</td>
<td width="50%">

### 📋 GitHub Issue 驱动
从 Project 看板认领 Issue，AI 讨论自动同步到 Issue 评论，完成后开 PR。全程带身份标记（🧠 Claude / 🤖 Cursor / 🧪 Codex / 🌟 GLM），协作过程可追溯。

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
| Cursor/Codex 挂了 | ❌ 工作流卡住 | 🔄 自动降级到备用 backend |
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

### 2. 初始化（自动装依赖 + 选模型）

```bash
# 退出 Claude Code 后重新打开
/sparring:setup
```

### 3. 开干

```bash
/sparring:workflow 给登录接口加 rate limiting
```

就这样。Claude 写方案 → Cursor 找茬 → 你确认 → Claude 实现 → Cursor 再找茬 → 你合并。

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

## 🎛️ 审查后端

四种 backend，可自由组合主备：

| Backend | 账号 | 特点 | 推荐场景 |
|---------|------|------|---------|
| 🌟 `glm` | 智谱按量付费 | **默认后端**，国产、API key 就能用 | 日常主力 / 无订阅 |
| 🤖 `cursor` | Cursor 订阅 | `gpt-5.5-extra-high` | 有 Cursor 订阅时可用 |
| 🧪 `codex` | OpenAI 订阅 | Codex CLI，reasoning 可调 | Codex 额度充足 |
| 🧠 `claude` | Claude Code CLI | 用 `claude -p` 跑 review；可**换后端模型**（原生 Claude / GLM / DeepSeek...） | 想用 Claude Code harness，或拿它驱动第三方模型 |

### 主 + 备降级

主 backend 调用失败（超时 / 网络错 / CLI 异常）时**自动切到备**，工作流不阻塞：

```
⚠ 主 backend Cursor Agent 调用失败，降级到 GLM...
```

**典型组合**（写进你**全局**配置 `~/.config/sparring/config.json`，按个人偏好；项目级不要设 backend）：

```jsonc
// A) 纯 GLM（默认，无订阅也能跑，按量付费）
{ "review": { "backend": "glm" } }

// B) GLM 主 + Claude Code 备（本机已登录 Claude Code 时可选加个兜底）
{ "review": { "backend": "glm", "fallback": "claude" } }

// C) Cursor 主 + GLM 备（有 Cursor 订阅时可用）
{ "review": { "backend": "cursor", "fallback": "glm" } }

// D) Codex 主 + GLM 备（Codex 额度省着用）
{ "review": { "backend": "codex", "fallback": "glm" } }

// E) Claude Code（原生，用本机已登录的 Claude）
{ "review": { "backend": "claude" },
  "claude": { "model": "claude-opus-4-8" } }
```

### 🧠 `claude` 后端：用 Claude Code 跑第三方模型

`claude` 后端通过 **Claude Code CLI（`claude -p` 非交互模式）** 执行 review。除了用原生 Claude，还能把后端模型**换成 GLM / DeepSeek 等**——机制是设 `claude.base_url` + `api_key` + `model` 指向各家的 **Anthropic 兼容端点**：

```jsonc
// Claude Code 跑 GLM
{ "review": { "backend": "claude" },
  "claude": {
    "base_url": "https://open.bigmodel.cn/api/anthropic",
    "api_key": "<glm-key>",
    "model": "glm-5.2"
  } }

// Claude Code 跑 DeepSeek，GLM 原生兜底
{ "review": { "backend": "claude", "fallback": "glm" },
  "claude": {
    "base_url": "https://api.deepseek.com/anthropic",
    "api_key": "<deepseek-key>",
    "model": "deepseek-chat"
  } }
```

工作机制与隔离（重要）：

- **原生 Claude**：`base_url` 留空，复用本机已登录的 Claude Code（OAuth 订阅或 `ANTHROPIC_API_KEY`），零额外配置。
- **第三方模型**：设 `base_url`（非空时 `api_key` **必填**）→ 注入 `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_MODEL`，并显式清空 `ANTHROPIC_API_KEY` 防本机残留 key 抢鉴权报 401。
- **上下文隔离**：reviewer 一律在 `mktemp` 空目录里运行（隔断项目 `CLAUDE.md`）；第三方路径再用全新空 `CLAUDE_CONFIG_DIR`（隔断全局 `CLAUDE.md` + 残留登录态）。**原生路径**会加载 `~/.claude/CLAUDE.md`——`verify` 会告警，可设 `claude.config_dir` 指向一个「已登录但无 CLAUDE.md」的目录彻底隔离。
- **禁全部工具**：`-p` 默认拒权 + `--disallowedTools` 兜底 → reviewer 只输出纯文本裁决，物理上跑不了 Bash/Task，递归不可能。
- **代理**：国产端点（GLM/DeepSeek）默认清空 `HTTP(S)_PROXY`（走代理会失败）；原生 Anthropic 墙内需要时设 `claude.use_proxy: true`。

---

## ⚙️ 配置系统

四层优先级（低→高）：**内置默认 → 全局 → 项目 → 环境变量**。

```bash
sparring config init              # 生成 ~/.config/sparring/config.json（chmod 600，存 api_key）
sparring config init project      # 生成 .sparring/config.json（团队共享非主观项，不放 backend/模型/key）
sparring config show              # 看合并后的配置（key 自动掩码）
sparring config get glm.api_key   # 取单值（敏感字段掩码）
```

**全局配置** `~/.config/sparring/config.json`（含 api_key，不入库）：

```json
{
  "review": {
    "backend": "glm",
    "fallback": null,
    "timeout": 120,
    "retries": 1
  },
  "glm": {
    "api_key": "<id.secret>",
    "model": "glm-5.1"
  }
}
```

**项目配置** `.sparring/config.json`（**默认入库**，只放团队需统一的非主观项，如超时/重试）：

```json
{
  "review": {
    "timeout": 120,
    "retries": 1
  }
}
```

> ⚠️ **项目配置不要设 `review.backend` / `fallback` / 模型 / `api_key`**。用什么 reviewer 后端和模型由**各开发者自己的全局配置**决定，项目级不约束（项目 config 优先级高于全局，写了会覆盖每个人的个人选择）；api_key 更不能入库。

**环境变量覆盖（均为可选，非必需 —— 不设也能跑，key 走全局 config）**（`SPARRING_*` 主推，`WORKFLOW_*` 兼容别名）：

```bash
export SPARRING_REVIEW_BACKEND=glm       # → review.backend
export SPARRING_GLM_API_KEY=<id.secret>  # → glm.api_key
export SPARRING_REVIEW_TIMEOUT=180       # → review.timeout（示例：临时手动调更大；默认起始值已是 120，一般不需要手动设）
```

> 💡 **API key 默认放全局 config 即可，不依赖任何环境变量。** `sparring config init` 生成 `~/.config/sparring/config.json`（chmod 600），填入 `glm.api_key` 后所有命令（含 `sparring review`、`review-code` 等）自动读取，新机器/新用户也只需各自 init 一次。`SPARRING_GLM_API_KEY` 环境变量仅作可选临时覆盖（如 CI / 临时换 key），**不是必需**。

> ⏱️ **大 diff 超时自适应**：`review.timeout` 只是单次调用超时的起始值（默认 120s）。实际单次调用超时会按送审内容大小自动加时——每 10000 字节 +30s，最多加 480s（单次封顶 600s），大改动 / 大 diff 不再需要手动调大 `SPARRING_REVIEW_TIMEOUT` 才能跑完。
>
> ⚠️ **重试会线性放大最坏等待时间**：失败重试时每次都会用满同一个（已自适应加时的）单次超时，不会缩水。默认 `review.retries=1`（共尝试 2 次），大 diff 单次超时封顶 600s 时，最坏情况下一次 `sparring review` 可能等待到 **1200s（20 分钟）** 才报错。这是有意为之——重试是为了应对网络抖动/瞬时错误，缩短重试预算只会让大 diff 的重试必然失败。如果不想等这么久，可以设 `review.retries=0` 关闭重试，或结合铁律里"reviewer 卡住"的判断自行决定何时放弃等待。

### 可配置字段

| key | 默认 | 说明 |
|---|---|---|
| `review.backend` | `glm` | 主后端：`cursor` / `codex` / `glm` / `claude` |
| `review.fallback` | `null` | 备后端（可选） |
| `review.timeout` | `120` | 单次调用超时秒数起始值（会按内容大小再自适应加时，见上） |
| `review.retries` | `1` | 失败后重试次数（共尝试 retries+1 次） |
| `cursor.model` | 读 `agents/cursor.md` | Cursor 模型 |
| `codex.model` | 读 codex config | Codex 模型 |
| `codex.effort` | `null` | `none\|minimal\|low\|medium\|high\|xhigh` |
| `codex.home` | `/tmp/workflow-codex-home-<user>` | Codex 本地状态目录 |
| `glm.api_key` | **必填** | [申请](https://open.bigmodel.cn/usercenter/apikeys) |
| `glm.model` | `glm-5.1` | 智谱模型 |
| `glm.thinking` | `disabled` | 开 `enabled` 质量更高但慢 |
| `glm.max_tokens` | `8192` | 开 thinking 时建议调到 `65536` |
| `glm.temperature` | `0.3` | review 场景不需要太高 |
| `glm.api_base` | 官方 URL | 可换自建网关 |
| `claude.model` | `null` | 后端模型；原生留空走已登录账号，第三方填如 `glm-5.2` / `deepseek-chat` |
| `claude.base_url` | `null` | 设了即「第三方模型」路径，指向各家 Anthropic 兼容端点；留空 = 原生 Claude |
| `claude.api_key` | 第三方路径**必填** | 第三方端点 token（→ `ANTHROPIC_AUTH_TOKEN`）；原生路径走 OAuth 不需要 |
| `claude.config_dir` | `null` | `CLAUDE_CONFIG_DIR`，隔离 reviewer 配置；第三方路径默认每次全新空目录 |
| `claude.use_proxy` | `false` | 是否保留 `HTTP(S)_PROXY`；国产端点须 `false`，原生 Anthropic 墙内可 `true` |
| `claude.extra_args` | `null` | 附加 `claude` CLI 参数（逃生舱） |

完整清单随时用 `sparring config show` 查看。

### 验证

```bash
sparring verify   # 检查主/备 backend 连通性 + 模型 + key 掩码
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
| 🧠 | Claude Code | 写方案、实现 |
| 🤖 | Cursor Agent | 审查意见 |
| 🧪 | Codex CLI | 审查意见 |
| 🌟 | GLM | 审查意见 |
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

# 快速审查（不建 task；审一段结论/方案/diff，走配置的 backend）
sparring review [--title <主题>] [<内容>]      # 内容从参数和/或 stdin 传入（可并用）
git diff origin/main...HEAD | sparring review --title "<改动主题>"
#   退出码 0=APPROVE  2=CONCERNS  1=调用错误/解析不出裁决
#   diff 输入自带体量门禁：denylist 剔除 lockfile/构建产物/.env 等文件段后，
#   超预算（默认 400 行，防 reviewer 超时跑飞）直接拒绝并提示按文件分片。
#   --max-diff-lines <N>（0=不限）/ --exclude <glob> / --no-default-excludes
#   config: review.max_diff_lines、review.exclude（数组）；纯文本结论不受影响
git diff origin/main...HEAD -- src/core | sparring review --title "core 分片"

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

欢迎 Issue / PR。这个项目本身就用 Sparring 开发——你能看到主分支上每个改动都过了 Cursor/Codex review。

## License

MIT
