<h1 align="center">🥊 Sparring</h1>

<p align="center">
  <strong>One AI writes the code. Another AI challenges it.<br>
  Like boxing sparring partners — pushing each other until the code is ship-ready.</strong>
</p>

<p align="center">
  <a href="#-quick-start"><img src="https://img.shields.io/badge/Quick_Start-2_min-blue?style=for-the-badge" alt="Quick Start"></a>
  <a href="#-core-features"><img src="https://img.shields.io/badge/Features-4_pillars-purple?style=for-the-badge" alt="Features"></a>
  <a href="#-reviewer-backends"><img src="https://img.shields.io/badge/Backends-Cursor_%7C_Codex_%7C_GLM_%7C_Claude-green?style=for-the-badge" alt="Backends"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/plugin-Claude_Code-E9DBFC?logo=anthropic&logoColor=black" alt="Claude Code">
  <img src="https://img.shields.io/badge/version-2.1.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/primary_%2B_fallback-auto--degrade-orange" alt="Fallback">
  <img src="https://img.shields.io/badge/config-JSON_%2B_env-lightgrey" alt="Config">
</p>

**In one line:** You describe the task. Claude writes the proposal and code. Cursor / Codex / GLM challenges it. Human only steps in for key decisions.

Sparring is a Claude Code plugin. It pairs Claude with a designated opponent — a second AI that assumes there's a bug and tries to find it. Up to 5 rounds, until both agree.

[中文](README.md)

---

## 📰 What's New

- **2026-06** · 🧠 New **`claude` backend**: run review via the Claude Code CLI (`claude -p`), and **swap the backend model** — point Claude Code at GLM / DeepSeek and other Anthropic-compatible endpoints. Ships with reviewer context isolation (empty cwd + dedicated config dir) + all-tools-disabled, eliminating `CLAUDE.md` pollution and recursion
- **2026-05** · 🔥 **Zhipu GLM** joins as a third reviewer backend with primary/fallback auto-degradation; new JSON config system (`~/.config/sparring/config.json` + `.sparring/config.json`) for team sharing; repo officially renamed to `sparring` (legacy `workflow` CLI preserved as a symlink)
- **2026-04** · 🎯 Added **Codex CLI** backend + background review jobs (run long reviews asynchronously)
- **2026-03** · Initial release: Claude + Cursor dual-AI collaboration with up to 5-round review; GitHub Issue–driven workflow (claim tasks from a Project board, sync discussions to Issue comments)

---

## 🌟 Core Features

<table>
<tr>
<td width="50%">

### 🥊 Adversarial Dual-AI Review
One AI writes. Another finds flaws. Not mutual praise — mutual pressure, like boxing sparring partners. **Up to 5 rounds**, no release until both agree.

</td>
<td width="50%">

### 🎛️ Four Backends + Primary/Fallback
Choose `cursor` / `codex` / `glm` / `claude`, or combine them as primary + fallback. When the primary CLI fails (timeout / network / process crash) the workflow auto-degrades to the fallback — no stall.

</td>
</tr>
<tr>
<td width="50%">

### ⚙️ Four-Tier Config System
**Defaults → global config → project config → env vars**. API keys in global (chmod 600), backend choice in project (team-shared), temp overrides via env. One-shot `sparring config init`.

</td>
<td width="50%">

### 📋 GitHub Issue–Driven
Claim issues from your Project board, AI discussions auto-sync to Issue comments, PR on completion. Every comment carries an identity marker (🧠 Claude / 🤖 Cursor / 🧪 Codex / 🌟 GLM).

</td>
</tr>
</table>

---

## 🤔 Why Sparring

AI writes code fast — but mistakes slip through: hallucinated APIs, missed edges, subtle regressions. Line-by-line human review doesn't scale.

|  | Without Sparring | With Sparring |
|---|---|---|
| AI's every conclusion | Goes straight to you | Vetted by a second AI first |
| Missed edge cases | 🤷 Caught in PR review | 🛡️ Caught during review loop |
| Looks-right-but-broken | 😬 Discovered in production | 🎯 "Assume there's a bug" mindset catches it |
| Cursor / Codex down? | ❌ Workflow stalls | 🔄 Auto-degrades to fallback |
| Single-perspective blind spots | — | ✅ Always two viewpoints, lower blind-spot risk |

**Result**: more reliable AI output, less manual review, lower cognitive load.

---

## 🚀 Quick Start

### 1. Install the plugin

```bash
# Inside Claude Code
/plugin marketplace add krislavten/sparring
/plugin install sparring@sparring
```

### 2. Initialize (auto-installs deps + selects models)

```bash
# Restart Claude Code, then:
/sparring:setup
```

### 3. Go

```bash
/sparring:workflow add rate limiting to the login endpoint
```

That's it. Claude writes the proposal → Cursor challenges → you approve → Claude implements → Cursor challenges again → you ship.

---

## 🎮 Three Modes

| Mode | Command | Use case |
|------|---------|----------|
| 💬 **Normal** | `/sparring:workflow <task>` | You discuss the approach first; AI pair handles review automatically; you ship |
| 🚀 **YOLO** | `/sparring:yolo <task>` | Fully automated, you only confirm the final commit. Small changes / clear scope |
| 🎫 **Issue** | `/sparring:issue <project-url> [number]` | Task from a GitHub Issue; discussions sync to Issue comments |

---

## 🔁 How It Works

```
   You describe the task
            ↓
  ┌──────────────────────┐
  │ Claude writes proposal│
  └──────────┬───────────┘
             ↓
  ┌──────────────────────┐    CONCERNS
  │ Reviewer challenges it │─────────┐
  └──────────┬───────────┘         ↓
             ↓ APPROVE         Claude revises
             ↓                  (up to 5 rounds)
         You approve
             ↓
  ┌──────────────────────┐
  │ Claude implements code│
  └──────────┬───────────┘
             ↓
  ┌──────────────────────┐    CONCERNS
  │ Reviewer challenges it │─────────┐
  └──────────┬───────────┘         ↓
             ↓ APPROVE         Claude fixes
             ↓                  (up to 5 rounds)
     You approve & ship
```

**Cross-review principle**: Before giving you **any** conclusion or recommendation, Claude runs it past the reviewer first. "Let's use Redis for caching" → reviewer challenges → Claude confirms or adjusts → then tells you.

---

## 🎛️ Reviewer Backends

Four backends, freely combinable as primary + fallback:

| Backend | Account | Notes | Best for |
|---------|---------|-------|---------|
| 🤖 `cursor` | Cursor subscription | Default, `gpt-5.5-extra-high` | Daily driver |
| 🧪 `codex` | OpenAI subscription | Codex CLI, tunable reasoning | Codex quota to burn |
| 🌟 `glm` | Zhipu pay-as-you-go | Just needs an API key | Fallback / no subscription |
| 🧠 `claude` | Claude Code CLI | Runs review via `claude -p`; can **swap the backend model** (native Claude / GLM / DeepSeek...) | Use the Claude Code harness, or drive a third-party model with it |

### Primary + Fallback

If the primary backend fails (timeout / network error / CLI crash), Sparring **auto-degrades** to the fallback. Workflow doesn't stall:

```
⚠ Primary backend Cursor Agent failed, falling back to GLM...
```

**Common setups**:

```jsonc
// A) Cursor primary + GLM fallback (recommended — survives Cursor outages)
{ "review": { "backend": "cursor", "fallback": "glm" } }

// B) Codex primary + GLM fallback (preserve Codex quota)
{ "review": { "backend": "codex", "fallback": "glm" } }

// C) GLM only (no subscription, pay-as-you-go)
{ "review": { "backend": "glm" } }

// D) Claude Code (native — uses your logged-in Claude)
{ "review": { "backend": "claude" },
  "claude": { "model": "claude-opus-4-8" } }
```

### 🧠 `claude` backend: run third-party models through Claude Code

The `claude` backend runs review via the **Claude Code CLI (`claude -p`)**. Beyond native Claude, you can **swap the backend model to GLM / DeepSeek / etc.** by pointing `claude.base_url` + `api_key` + `model` at each vendor's **Anthropic-compatible endpoint**:

```jsonc
// Claude Code running GLM
{ "review": { "backend": "claude" },
  "claude": {
    "base_url": "https://open.bigmodel.cn/api/anthropic",
    "api_key": "<glm-key>",
    "model": "glm-5.2"
  } }

// Claude Code running DeepSeek, native GLM as fallback
{ "review": { "backend": "claude", "fallback": "glm" },
  "claude": {
    "base_url": "https://api.deepseek.com/anthropic",
    "api_key": "<deepseek-key>",
    "model": "deepseek-chat"
  } }
```

How it works & isolation (important):

- **Native Claude**: leave `base_url` empty — reuses your logged-in Claude Code (OAuth subscription or `ANTHROPIC_API_KEY`), zero extra config.
- **Third-party model**: set `base_url` (`api_key` then **required**) → injects `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_MODEL`, and explicitly clears `ANTHROPIC_API_KEY` so a stray local key can't hijack auth and 401.
- **Context isolation**: the reviewer always runs inside an empty `mktemp` dir (blocks project `CLAUDE.md`); third-party path also uses a fresh empty `CLAUDE_CONFIG_DIR` (blocks global `CLAUDE.md` + residual login). The **native path** loads `~/.claude/CLAUDE.md` — `verify` warns about it; set `claude.config_dir` to a "logged-in but CLAUDE.md-free" dir to fully isolate.
- **All tools disabled**: `-p` default-deny + `--disallowedTools` → the reviewer only emits a plain-text verdict, physically can't run Bash/Task, so recursion is impossible.
- **Proxy**: domestic endpoints (GLM/DeepSeek) clear `HTTP(S)_PROXY` by default (a proxy breaks them); set `claude.use_proxy: true` if native Anthropic needs a proxy.

---

## ⚙️ Configuration

Precedence (low → high): **defaults → global → project → env vars**.

```bash
sparring config init              # create ~/.config/sparring/config.json (chmod 600, stores api_key)
sparring config init project      # create .sparring/config.json (team-shared, no key)
sparring config show              # merged config (keys masked)
sparring config get glm.api_key   # single value (sensitive fields masked)
```

**Global config** `~/.config/sparring/config.json` (contains api_key, do **not** commit):

```json
{
  "review": {
    "backend": "cursor",
    "fallback": "glm",
    "timeout": 60,
    "retries": 1
  },
  "glm": {
    "api_key": "<id.secret>",
    "model": "glm-5.1"
  }
}
```

**Project config** `.sparring/config.json` (**commit by default**, team-shared backend choice):

```json
{
  "review": {
    "backend": "cursor",
    "fallback": "glm"
  }
}
```

> ⚠️ **Never put `api_key` in project config** — it's tracked by git and will leak to every collaborator. Keys belong in the global config (chmod 600) or `SPARRING_GLM_API_KEY` env var.

**Env var overrides** (`SPARRING_*` preferred; `WORKFLOW_*` kept for backward compat):

```bash
export SPARRING_REVIEW_BACKEND=glm       # → review.backend
export SPARRING_GLM_API_KEY=<id.secret>  # → glm.api_key
export SPARRING_REVIEW_TIMEOUT=120       # → review.timeout
```

### Config reference

| key | default | notes |
|---|---|---|
| `review.backend` | `cursor` | Primary: `cursor` / `codex` / `glm` |
| `review.fallback` | `null` | Fallback backend (optional) |
| `review.timeout` | `60` | Per-call timeout (seconds) |
| `review.retries` | `1` | Retries after failure (total attempts = retries + 1) |
| `cursor.model` | from `agents/cursor.md` | Cursor Agent model |
| `codex.model` | from codex config | Codex model |
| `codex.effort` | `null` | `none\|minimal\|low\|medium\|high\|xhigh` |
| `codex.home` | `/tmp/workflow-codex-home-<user>` | Codex local state directory |
| `glm.api_key` | **required** | [Get one](https://open.bigmodel.cn/usercenter/apikeys) |
| `glm.model` | `glm-5.1` | Zhipu model |
| `glm.thinking` | `disabled` | `enabled` for higher quality but slower |
| `glm.max_tokens` | `8192` | bump to `65536` when thinking is enabled |
| `glm.temperature` | `0.3` | review doesn't need high creativity |
| `glm.api_base` | official URL | swap for self-hosted gateway |

Run `sparring config show` anytime to inspect the full effective config.

### Verify

```bash
sparring verify   # checks primary/fallback connectivity + model + masked key
```

---

## 🎫 GitHub Issue–Driven Mode

Built for teams using GitHub Issues + Project boards:

```bash
/sparring:issue https://github.com/orgs/your-org/projects/3 106
```

Automatic flow: **claim issue → board moves to "In progress" → AI discussions sync to Issue comments → PR opens → board moves to "Reviewing"**.

Every comment carries an identity marker:

| Icon | Role | Purpose |
|---|---|---|
| 🧠 | Claude Code | Proposals, implementation |
| 🤖 | Cursor Agent | Review feedback |
| 🧪 | Codex CLI | Review feedback |
| 🌟 | GLM | Review feedback |
| 🔧 | Workflow | Status transitions |

---

## 🦞 Multi-Agent Parallel (with ClawTeam)

Sparring handles review quality. [ClawTeam](https://github.com/HKUDS/ClawTeam) handles multi-agent orchestration. Together: each agent works in parallel with automatic peer review.

```
ClawTeam splits 3 tasks in parallel
  ├── Claude #1: auth module  ← Sparring: reviewer
  ├── Claude #2: database     ← Sparring: reviewer
  └── Claude #3: frontend     ← Sparring: reviewer
```

```bash
# Install ClawTeam
pipx install clawteam

# Create team + spawn workers (each runs Sparring review when done)
clawteam team spawn-team my-project -d "refactor user system" -n leader
clawteam spawn tmux claude --team my-project --agent-name auth \
  --task "Implement auth module. Run sparring review-code my-project when done"
clawteam board attach my-project   # watch all agents work simultaneously
```

**Issue + Team**: split large issues into parallel sub-tasks (see [ClawTeam docs](https://github.com/HKUDS/ClawTeam)).

**Auto-claim**: have Claude poll your board:

```bash
/loop 5m /sparring:issue https://github.com/orgs/your-org/projects/3
```

---

## 🧰 Background Reviews (optional)

For long-running reviews:

```bash
sparring review-proposal-bg <task-id>    # launch background job
sparring review-code-bg <task-id>
sparring review-status [job-id|task-id]  # check status
sparring review-result <job-id>          # view result
sparring review-cancel <job-id>          # cancel
```

---

## 🗺️ Command Reference

```bash
# Setup
sparring setup                  # interactive installer
sparring config init            # create global config
sparring verify                 # check environment

# Task lifecycle
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

Full list: `sparring help`. **Compat alias**: `workflow xxx` still works (`bin/workflow` is a symlink).

---

## 📚 Further Reading

- [Mode details](MODES.md)
- [Full examples](EXAMPLES.md)
- [中文 README](README.md)

---

## 🤝 Contributing

Issues and PRs welcome. This project itself is developed using Sparring — you can see every change on main has been through Cursor/Codex review.

## License

MIT
