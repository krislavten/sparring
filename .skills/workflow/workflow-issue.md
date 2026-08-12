---
description: GitHub Issue-driven dual AI workflow - Poll issues, discuss via comments, implement with peer review
trigger: When user says "/sparring:issue"
mode: command
targetAgents:
  - claude-code
---

# GitHub Issue-Driven Dual AI Workflow

You are the **Workflow Orchestrator** that consumes GitHub Issues as a task queue. Claude is the Executor, the configured review backend is the Reviewer. Communication with the user happens via **Issue Comments**.

## Overview

```
GitHub Issue (Planning + claude-ok label)
  ↓  poll / manual trigger
Claude claims issue → status: In progress
  ↓
Normal: Discuss direction via issue comments → draft proposal → reviewer reviews proposal (≤5 rounds) → implement → reviewer reviews code (≤5 rounds) → PR
YOLO:   Draft proposal autonomously → reviewer reviews proposal (≤5 rounds) → implement → reviewer reviews code (≤5 rounds) → PR
  ↓
PR created → status: Reviewing
```

**Key difference**: Normal mode discusses direction with user via issue comments before drafting proposal. YOLO mode skips user discussion. **Both modes always have reviewer review for proposal AND code.**

## Trigger

```
/sparring:issue                     # Poll for claude-ok issues and process next one
/sparring:issue <issue-number>      # Process a specific issue
/sparring:issue poll                # One-time poll, show available issues
```

## Phase 0: Issue Discovery & Claiming

### When invoked with no specific issue:

1. **Poll for available issues**
   ```bash
   # Find issues in the project with claude-ok label and Planning status
   gh issue list --repo <repo> --label "claude-ok" --state open --json number,title,labels,assignees
   ```

2. **Filter candidates**
   - Must have `claude-ok` label
   - Must be in `Planning` status on the project board
   - Skip issues already `In progress` or with an active PR

3. **Present candidates to user (if multiple)**
   ```
   Found 3 issues ready for processing:

   #106 Chat API 路由缺少项目级权限校验 (IDOR 风险)
   #118 perf: /next/layout.tsx 的 await headers() 导致所有子路由丧失客户端导航能力
   #262 fix(web): API proxy 缺少项目级鉴权

   Which one should I work on? (number or 'all' for queue)
   ```

4. **Claim the issue**
   ```bash
   # Move to In progress on project board
   # The project field ID for Status and option ID for "In progress" need to be resolved
   gh issue edit <number> --repo <repo> --add-assignee <bot-or-self>
   ```
   Also comment on the issue to announce claiming:
   ```bash
   gh issue comment <number> --repo <repo> --body "🤖 Claude Code 已认领此任务，开始分析..."
   ```

### Detect mode:
- If issue has `yolo` label → YOLO mode
- Otherwise → Normal mode

## Phase 1: Plan Stage

### Step 1: Understand the Issue (Both Modes)

1. **Read the issue body** to understand requirements
   ```bash
   gh issue view <number> --repo <repo> --json body,title,comments
   ```

### Step 2: Direction Discussion (Normal Mode Only)

**Only in Normal mode. YOLO mode skips to Step 3.**

1. **Post direction proposal as a comment** — share your understanding and preferred approach
   ```bash
   gh issue comment <number> --repo <repo> --body "$(cat <<'EOF'
   ## 🤖 方案讨论

   我已阅读 issue 描述，我的理解和初步方案：

   **问题分析：**
   - [Understanding of the problem]

   **倾向方案：**
   - [Approach summary and reasoning]

   **需要确认：**
   1. [Question 1 — if any]
   2. [Question 2 — if any]

   请回复确认方向或调整。回复 "ok" / "可以" 我就开始正式方案设计。

   ---
   *回复后我会继续推进。*
   EOF
   )"
   ```

2. **Wait for user reply — poll issue comments**
   ```bash
   gh issue view <number> --repo <repo> --json comments --jq '.comments[-1]'
   ```
   - Poll every 30 seconds for new comments
   - Identify user replies by checking comment author (skip own comments)

3. **Multi-round discussion** (up to 5 rounds)
   - Each round: read user reply → refine understanding → post follow-up
   - When user says "ok", "approved", "go ahead", "开始吧", "可以", "没问题" → proceed to Step 3
   - After 5 rounds without clear approval → post summary and ask for explicit go/no-go

### Step 3: Draft Formal Proposal (Both Modes)

1. **Write complete technical proposal**
   - Save to `.workflow/plans/<task-id>/proposal.md`
   - In Normal mode: incorporate user's confirmed direction
   - In YOLO mode: use best judgment based on issue description

2. **Post proposal summary as issue comment**
   ```bash
   gh issue comment <number> --repo <repo> --body "$(cat <<'EOF'
   ## 📋 技术方案

   ### 概述
   [Summary]

   ### 实现步骤
   1. [Step 1]
   2. [Step 2]

   ### 影响范围
   - [File 1]: [Change description]
   - [File 2]: [Change description]

   ### 风险与缓解
   - [Risk 1]: [Mitigation]

   ---
   正在进行 AI peer review...
   EOF
   )"
   ```

### Step 4: Reviewer Reviews Proposal (Both Modes, ≤5 rounds)

**This step happens in BOTH Normal and YOLO modes.**

```
Save proposal to .workflow/plans/<task-id>/proposal.md
for round in 1..5:
  response = call the reviewer to review proposal
    (via: sparring review-proposal <task-id>)
  save to .workflow/plans/<task-id>/proposal-review-{round}.md
  if APPROVE:
    post to issue: "✅ 方案经 reviewer 审查通过 ({round} 轮)"
    break
  else:
    address the reviewer's concerns, update proposal
    save updated proposal to proposal-v{round+1}.md
if 5 rounds without approval:
  post to issue: "⚠️ 方案经过 5 轮 AI review 未达成共识，请人工介入"
  stop and wait for user input
```

## Phase 2: Implementation (Both Modes)

### Step 5: Create Branch & Implement

1. **Create feature branch**
   ```bash
   git checkout -b fix/issue-<number>  # or feat/issue-<number>
   ```

2. **Implement code per approved proposal**
   - Follow the proposal steps
   - Write tests alongside implementation
   - Run tests after each module

### Step 6: Reviewer Reviews Code (Both Modes, ≤5 rounds)

**This step happens in BOTH Normal and YOLO modes.**

```
for round in 1..5:
  response = call the reviewer to review code   # reviewer 自己跑 git diff，不用先导出
    (via: sparring review-code <task-id>)
  save to .workflow/plans/<task-id>/code-review-{round}.md
  if APPROVE:
    break
  else:
    fix issues based on the reviewer's feedback
    re-run tests
if 5 rounds without approval:
  post to issue: "⚠️ 代码经过 5 轮 AI review 未达成共识，请人工介入"
  stop and wait for user input
```

### Step 7: Post Implementation Summary

```bash
gh issue comment <number> --repo <repo> --body "$(cat <<'EOF'
## ✅ 实现完成

### 改动文件
- [File 1]: [Description]
- [File 2]: [Description]

### 测试结果
- [Test summary]

### AI Peer Review
- 方案 review (reviewer): {N} 轮通过
- 代码 review (reviewer): {M} 轮通过

正在创建 PR...
EOF
)"
```

## Phase 3: PR & Status Update

1. **Create PR**
   ```bash
   gh pr create --repo <repo> \
     --title "<type>(scope): <description>" \
     --body "$(cat <<'EOF'
   ## Summary
   Closes #<issue-number>

   [Description of changes]

   ## Changes
   - [Change 1]
   - [Change 2]

   ## Test Plan
   - [Test 1]
   - [Test 2]

   ## AI Review Trail
   - Proposal: .workflow/plans/<task-id>/proposal.md
   - Code reviews: .workflow/plans/<task-id>/code-review-*.md

   🤖 Generated with Claude Code + agent peer review
   EOF
   )"
   ```

2. **Update project board status to Reviewing**
   Use GitHub CLI or API to move the issue to "Reviewing" column.

3. **Post PR link as issue comment**
   ```bash
   gh issue comment <number> --repo <repo> --body "🔗 PR 已创建: <pr-url>，已移至 Reviewing 状态。请 review。"
   ```

## Key Instructions

### Repository Detection
- Detect repo from git remote: `git remote get-url origin`
- Parse owner/repo from the URL
- All `gh` commands use `--repo <owner>/<repo>`

### Issue Comment as Communication Channel
- **Every significant action gets a comment**: claiming, questions, proposal, implementation summary, PR link
- **Comments are the audit trail** — anyone looking at the issue can see the full history
- **Poll for replies** using `gh issue view --json comments`
- **Identify user replies** by checking comment author (skip bot's own comments)

### Identity Markers in Comments
Since all comments are posted via `gh` under the same GitHub account, **prefix every comment with an identity marker** so humans can tell who said what:

- `🧠 **[Claude Code — Proposal]**` — Claude's proposal or direction discussion
- `🧠 **[Claude Code — Implementation]**` — Claude's implementation summary
- `🧠 **[<reviewer> — Proposal Review #N]**` — reviewer proposal review (auto-synced by `sparring` CLI)
- `🧠 **[<reviewer> — Code Review #N]**` — reviewer code review (auto-synced by `sparring` CLI)
- `🔧 **[Workflow — Status]**` — automated status transitions

**Claude must always use the `🧠` prefix** when posting comments:
```bash
sparring issue-comment <number> "🧠 **[Claude Code — Proposal]**

<proposal content>"
```

**Reviewer output** is auto-synced by `sparring review-proposal` / `sparring review-code` with the reviewer icon prefix — no manual action needed.

### Waiting for User Reply
When you need user input (Normal mode), use this pattern:
1. Post your question/proposal as a comment
2. Tell the local user: "已在 issue #X 发布方案，等待回复中..."
3. Poll every 30 seconds for new comments
4. When new human comment found, read and continue
5. Max wait: notify user locally after 10 minutes of no reply

### Local + Remote Artifacts
- **Local**: `.workflow/plans/<task-id>/` — full proposal, review logs, diffs
- **Remote**: Issue comments — summaries, key decisions, links
- Both are maintained in parallel for auditability

### Project Board Status Management
Use `gh` CLI to update project board status:
- Claiming: `Planning` → `In progress`
- PR created: `In progress` → `Reviewing`
- Merged: `Reviewing` → `Done`

The project is `kanyun-inc` org project #3. Use `gh project` commands or the GraphQL API to update item status.

### Branch Naming
- Bug fix: `fix/issue-<number>-<short-description>`
- Feature: `feat/issue-<number>-<short-description>`
- Refactor: `refactor/issue-<number>-<short-description>`

### Commit Message
Follow conventional commits:
```
<type>(scope): <description>

Closes #<issue-number>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Example: Normal Mode

```
/sparring:issue 106

# Step 0: Claim
Claude: "🤖 认领 #106，开始分析..."
[comments on issue #106, board → In progress]

# Step 2: Direction discussion (Normal only)
Claude (issue comment):
  "🧠 **[Claude Code — Direction Discussion]**

   看了 issue 描述，有 3 个方案选项。我倾向方案 B (withProjectAccess 高阶函数)，
   因为它最 DRY 且与现有 middleware 模式一致。
   请确认方向。"

User (issue comment):
  "方案 B 可以，但要确保错误信息统一"

# Step 3: Draft proposal
Claude (issue comment):
  "## 📋 技术方案
   1. 创建 withProjectAccess HOF
   2. 包装 4 个缺少校验的路由
   3. 统一 403 错误格式
   正在进行 AI peer review..."

# Step 4: reviewer reviews proposal (≤5 rounds)
Claude: [calls the reviewer to review proposal]
Reviewer: "APPROVE — 方案合理"
# auto-synced by CLI: "🧠 [Claude Code — Proposal Review #1 — APPROVED] ..."
Claude (issue comment): "🧠 **[Claude Code — Status]** 方案经 reviewer 审查通过 (1 轮)"

# Step 5-6: Implement + reviewer reviews code (≤5 rounds)
Claude: [implements code on fix/issue-106 branch]
Claude: [calls the reviewer to review code × 2 rounds]
Reviewer round 1: "CONCERNS: 1. 缺少单测"
Claude: [adds tests, re-submits]
Reviewer round 2: "APPROVE"

# Step 7-8: Summary + PR
Claude (issue comment):
  "🧠 **[Claude Code — Implementation Complete]**

   - 方案 review (reviewer): 1 轮通过
   - 代码 review (reviewer): 2 轮通过
   🔗 PR #120 已创建，已移至 Reviewing。"
```

## Example: YOLO Mode

```
/sparring:issue 118

[issue #118 has 'yolo' label]

# Step 0: Claim
Claude: "🧠 **[Claude Code — Claimed]** 认领 #118 (YOLO 模式)，开始处理..."
[comments on issue, board → In progress]

# Step 3: Draft proposal (skip direction discussion)
Claude: [drafts proposal based on issue description]
Claude (issue comment): "🧠 **[Claude Code — Proposal]** 技术方案: ... 正在进行 AI peer review..."

# Step 4: reviewer reviews proposal (≤5 rounds)
Claude: [calls the reviewer × 2 rounds]
# auto-synced by CLI: "🧠 [Claude Code — Proposal Review #1] ..."
# auto-synced by CLI: "🧠 [Claude Code — Proposal Review #2 — APPROVED] ..."

# Step 5-6: Implement + reviewer reviews code (≤5 rounds)
Claude: [implements]
Claude: [calls the reviewer to review code × 1 round]
# auto-synced by CLI: "🧠 [Claude Code — Code Review #1 — APPROVED] ..."

# Step 7-8: Summary + PR
Claude (issue comment):
  "🧠 **[Claude Code — Implementation Complete]**

   - 方案 review (reviewer): 2 轮通过
   - 代码 review (reviewer): 1 轮通过
   🔗 PR #121 已创建，已移至 Reviewing。"
```

## Error Handling

- **gh CLI fails**: Inform user locally, retry once, then pause
- **Reviewer backend unreachable**: falls back to the other backend; both down → degrade to manual review, continue with implementation
- **5 review rounds without approval**: Post to issue, escalate to user
- **User doesn't reply in 10 min**: Notify locally, keep polling (don't abandon)
- **Merge conflict on branch**: Inform user, attempt rebase, ask for help if fails

## Important Rules

1. **Always comment on the issue** for every significant step — the issue is the source of truth
2. **Don't modify issue body** — only add comments
3. **Respect existing assignees** — if someone else is assigned, skip
4. **Keep comments concise** — summaries in comments, details in local `.workflow/`
5. **Max 5 rounds** for both proposal and code review
6. **Always create PR** linking back to the issue with `Closes #<number>`
