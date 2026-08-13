<h1 align="center">🥊 Sparring</h1>

<p align="center">
  <strong>One AI writes the code. Another AI challenges it.<br>
  Like boxing sparring partners — pushing each other until the code is ship-ready.</strong>
</p>

<p align="center">
  <a href="#-quick-start"><img src="https://img.shields.io/badge/Quick_Start-2_min-blue?style=for-the-badge" alt="Quick Start"></a>
  <a href="#-core-features"><img src="https://img.shields.io/badge/Features-4_pillars-purple?style=for-the-badge" alt="Features"></a>
  <a href="#-reviewer-backends"><img src="https://img.shields.io/badge/Backends-Claude_%7C_opencode-green?style=for-the-badge" alt="Backends"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/plugin-Claude_Code-E9DBFC?logo=anthropic&logoColor=black" alt="Claude Code">
  <img src="https://img.shields.io/badge/version-3.0.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/primary_%2B_fallback-auto--degrade-orange" alt="Fallback">
  <img src="https://img.shields.io/badge/config-JSON_%2B_env-lightgrey" alt="Config">
</p>

**In one line:** You describe the task. Claude writes the proposal and code. A second AI walks into the repo and challenges it. Human only steps in for key decisions.

Sparring is a Claude Code plugin. It pairs Claude with a designated opponent — a second AI that assumes there's a bug and tries to find it. Up to 5 rounds, until both agree.

The reviewer isn't a one-shot model call fed a blob of diff text — it's an agent. Hand it a git range and it runs `git diff` itself, opens the files it needs, greps the callers, and forms an opinion with the context in hand.

[中文](README.md)

---

## 📰 What's New

- **2026-08** · 🥊 **3.0 (breaking)**: the reviewer stopped taking diff text and became **an agent that goes into the repo itself** — `sparring review --range origin/main...HEAD` creates a read-only snapshot where the reviewer runs `git diff`, reads files, and chases callers on its own. With it: backends narrowed to `claude` + `opencode` (`cursor` / `codex` / `glm` **removed**), piping a diff in is now a hard error, and the diff-size gate and sharding advice are gone
- **2026-07** · 📓 `sparring review` execution log: one JSONL line per call, so you can tell afterwards which backend reviewed, whether it fell back, and how long it took
- **2026-06** · 🧠 New **`claude` backend**: run review via the Claude Code CLI (`claude -p`)
- **2026-05** · 🔥 New JSON config system (`~/.config/sparring/config.json` + `.sparring/config.json`) for team sharing; primary/fallback auto-degradation; repo officially renamed to `sparring` (legacy `workflow` CLI preserved as a symlink)
- **2026-04** · 🎯 Added background review jobs (run long reviews asynchronously)
- **2026-03** · Initial release: Claude + Cursor dual-AI collaboration with up to 5-round review; GitHub Issue–driven workflow (claim tasks from a Project board, sync discussions to Issue comments)

---

## 🌟 Core Features

<table>
<tr>
<td width="50%">

### 🥊 Adversarial Dual-AI Review
One AI writes. Another finds flaws. Not mutual praise — mutual pressure, like boxing sparring partners. The reviewer reads the repo for context instead of guessing from a diff. **Up to 5 rounds**, no release until both agree.

</td>
<td width="50%">

### 🎛️ Two Backends + Primary/Fallback
Choose `claude` (Claude Code CLI) or `opencode` (plan agent), or combine them as primary + fallback. When the primary CLI fails (timeout / network / process crash) the workflow auto-degrades to the fallback — no stall. Both run on whatever account their CLI is logged into; Sparring stores no API keys.

</td>
</tr>
<tr>
<td width="50%">

### ⚙️ Four-Tier Config System
**Defaults → global config → project config → env vars**. Backend and model live in your own global config; project config carries only team-wide, non-subjective settings (timeout / retries); env vars for temporary overrides. One-shot `sparring config init`.

</td>
<td width="50%">

### 📋 GitHub Issue–Driven
Claim issues from your Project board, AI discussions auto-sync to Issue comments, PR on completion. Every comment carries an identity marker (🧠 Claude Code / 🛠 opencode).

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
| Reviewer lacks context | 🙈 Squinting at a bare diff | 🔍 Reviewer opens files and greps callers itself |
| Primary backend down? | ❌ Workflow stalls | 🔄 Auto-degrades to fallback |
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

### 2. Initialize (auto-installs deps + picks a reviewer backend)

```bash
# Restart Claude Code, then:
/sparring:setup
```

### 3. Go

```bash
/sparring:workflow add rate limiting to the login endpoint
```

That's it. Claude writes the proposal → the reviewer challenges it → you approve → Claude implements → the reviewer challenges again → you ship.

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

## ⚡ Ad-hoc review: `sparring review`

No task, no workflow — just get one review. Two input shapes:

### Shape 1: review a range of repo changes (recommended)

```bash
sparring review --range origin/main...HEAD --title "login rate limiting"
sparring review --range HEAD~3..HEAD
```

`--range` runs `git worktree add --detach` to build a **read-only snapshot** of that range in a temp dir. The reviewer's working directory *is* that snapshot — it runs `git diff <range>` itself, opens whatever files it needs, greps callers, and the snapshot is deleted when it's done (on success, on failure, and when killed).

Since the diff never enters the prompt, there's **no size limit and nothing to shard**.

### Shape 2: review a conclusion or a proposal

```bash
echo "Let's use Redis for caching, because…" | sparring review --title "cache choice"
```

Text review builds no snapshot — the reviewer runs in an empty temp dir and judges the text on its own merits.

### The contract

- The first column of the output is the verdict: `APPROVE` or `CONCERNS`
- Exit codes: `0` = APPROVE, `2` = CONCERNS, `1` = call failed. **An unparseable verdict counts as an error — it never falls through to approval**
- Every call appends one JSONL line to `~/.local/state/sparring/review-YYYYMMDD.jsonl` (fields: `ts` / `title` / `mode` / `range` / `input_lines` / `backend` / `via` / `duration_s` / `exit_code` / `verdict`), kept 7 days by default (`review.log_retention_days`, `0` disables), so you can answer "which run timed out, and did it fall back?" after the fact

> ⚠️ **Diff text is no longer accepted.** `git diff ... | sparring review` fails immediately and points you at `--range` — no silent compatibility shim (detection: a stdin line starting with `diff --git ` or `--- a/`). `--range` mode also **doesn't read stdin** — in non-interactive environments stdin is often a pipe that never closes, and reading it hangs forever. Passing `--range` together with text content is an error too.

> 🔒 **What "read-only" means here**: the reviewer has Bash (it can't run `git diff` otherwise), so nothing at the tool layer stops it from writing files. The read-only property comes from being detached (no branch is touched) plus deleting the snapshot afterwards — not from filesystem permissions. The snapshot shares the main repo's `.git` object store. Don't treat it as a sandbox.

---

## 🎛️ Reviewer Backends

Two backends, freely combinable as primary + fallback. Both run on whatever account their CLI is already logged into — Sparring stores no API keys:

| Backend | How it runs | Tool permissions |
|---------|-------------|------------------|
| 🧠 `claude` | Claude Code CLI (`claude -p`, non-interactive), **default primary** | Allows `Bash` + `Read` / `Grep` / `Glob`; denies `Edit` / `Write` / `NotebookEdit` / `Task` / `WebFetch` / `WebSearch` |
| 🛠 `opencode` | `opencode run --agent plan`, **default fallback** | The plan agent has no editing ability to begin with |

> Write and network tools are denied, but Bash isn't — the reviewer needs it for `git diff` and `grep`. So "the reviewer won't touch anything" rests on the snapshot being thrown away, not on tool permissions. See the note above.

### Primary + Fallback

If the primary backend fails (timeout / network error / CLI crash), Sparring **auto-degrades** to the fallback. Workflow doesn't stall:

```
⚠ 主 backend Claude Code 调用失败，降级到 opencode (plan)...
```

(The CLI speaks Chinese: "primary backend Claude Code failed, falling back to opencode (plan)".)

**Common setups** (put these in your **global** config `~/.config/sparring/config.json` — never set a backend at project level):

```jsonc
// A) Default: Claude Code primary + opencode fallback
{ "review": { "backend": "claude", "fallback": "opencode" } }

// B) The other way around: opencode primary, Claude Code as backup
{ "review": { "backend": "opencode", "fallback": "claude" } }

// C) One backend only, no degradation
{ "review": { "backend": "claude", "fallback": null } }
```

> ⚠️ **`cursor` / `codex` / `glm` were removed in 3.0.** A config still holding one of those values **exits with an error** (no silent downgrade) — switch it to `claude` or `opencode`, or re-run `sparring config init --force`.

---

## ⚙️ Configuration

Precedence (low → high): **defaults → global → project → env vars**.

```bash
sparring config init                # create ~/.config/sparring/config.json (chmod 600)
sparring config init project        # create .sparring/config.json (team-shared, no backend/model)
sparring config show                # merged config
sparring config get review.backend  # single value
```

**Global config** `~/.config/sparring/config.json`:

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

**Project config** `.sparring/config.json` (**commit by default**, only team-wide non-subjective settings like timeout/retries):

```json
{
  "review": {
    "timeout": 1800,
    "retries": 1
  }
}
```

> ⚠️ **Never set `review.backend` / `fallback` / model in project config.** Which reviewer backend and model to use is each developer's own choice via **their own global config** — project config wins over global, so setting it there would override everyone's personal choice.

**Env var overrides** (`SPARRING_*` preferred; `WORKFLOW_*` kept for backward compat):

```bash
export SPARRING_REVIEW_BACKEND=opencode  # → review.backend
export SPARRING_REVIEW_FALLBACK=claude   # → review.fallback
export SPARRING_REVIEW_TIMEOUT=900       # → review.timeout (temporary bump; default is already 1800)
```

> 💡 **There are no API keys in the config.** Both backends use the account their own CLI is logged into (`claude login` / `opencode auth login`); Sparring only picks the backend and the model, so a new machine just needs each CLI logged in once.

> ⏱️ **Timeouts are measured in minutes**: the reviewer is an agent running git and reading files, so a single review takes minutes — hence `review.timeout` defaults to 1800s. The pre-3.0 "scale the timeout with the size of the content" behavior is gone: the diff no longer enters the prompt, so there's nothing to scale against. It's a flat value now.
>
> ⚠️ **Retries multiply the worst-case wait linearly**: each retry reuses the full per-call timeout — it's never shrunk. With the default `review.retries=1` (2 attempts total), a single `sparring review` can take up to **1200s (20 min)** before failing. This is intentional — retries exist to absorb transient network errors. Set `review.retries=0` if you'd rather fail fast.

### Config reference

| key | default | notes |
|---|---|---|
| `review.backend` | `claude` | Primary backend; only `claude` or `opencode` |
| `review.fallback` | `opencode` | Fallback backend; `null` disables degradation |
| `review.timeout` | `1800` | Per-call timeout in seconds (flat — no adaptive scaling) |
| `review.retries` | `1` | Retries after failure (total attempts = retries + 1) |
| `review.log_retention_days` | `7` | Days to keep the execution log; `0` disables logging entirely |
| `claude.model` | `null` | Empty = whatever Claude Code defaults to |
| `claude.use_proxy` | `false` | When `false`, `HTTP(S)_PROXY` is cleared before the call; set `true` if you need a proxy to reach the backend |
| `claude.extra_args` | `null` | Extra `claude` CLI args (escape hatch) |
| `opencode.model` | `null` | Empty = whatever opencode defaults to |
| `opencode.use_proxy` | `false` | Same as `claude.use_proxy` |
| `opencode.extra_args` | `null` | Extra `opencode` CLI args (escape hatch) |

Run `sparring config show` anytime to inspect the full effective config.

### Verify

```bash
sparring verify   # checks jq / git, then probes each backend CLI: installed? reachable?
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
| 🧠 | Claude Code | Proposals, implementation; review feedback when it's the reviewer |
| 🛠 | opencode | Review feedback |
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

# Ad-hoc review (no task; uses the configured backend — see "Ad-hoc review" above)
sparring review --range origin/main...HEAD --title "<what changed>"   # review repo changes
echo "<conclusion/proposal>" | sparring review --title "<topic>"      # review text
#   exit codes 0=APPROVE  2=CONCERNS  1=call error / unparseable verdict
#   ⚠ diff text is rejected — piping a diff in is a hard error; use --range

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

Issues and PRs welcome. This project itself is developed using Sparring — every change on main has been through a `sparring review`.

## License

MIT
