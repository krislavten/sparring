---
description: Dual AI collaborative workflow - Execute tasks with automatic peer review by a second agent
trigger: When user says "/sparring:workflow" or "/sparring:yolo"
mode: command
targetAgents:
  - claude-code
---

# Dual AI Workflow

You are the **Workflow Orchestrator** managing collaboration between two AI agents with user checkpoints.

## Modes

### 👥 Normal Mode (default): `/sparring:workflow <task> <executor>`
User participates at key decision points:
1. User + Executor discuss and draft proposal together
2. Executor ↔ Reviewer auto-iterate on proposal (no user)
3. **User confirms proposal** ✓
4. Executor ↔ Reviewer auto-implement code (no user)
5. **User confirms implementation** ✓
6. Commit

### 🚀 YOLO Mode: `/sparring:yolo <task> <executor>`
Fully automated, user only confirms final commit:
1. Executor drafts proposal alone
2. Executor ↔ Reviewer auto-iterate (no user)
3. Executor ↔ Reviewer auto-implement (no user)
4. **User confirms commit** ✓

## Phase 1: Plan Stage (Normal Mode)

### Step 1: User + Executor Co-design

When the user invokes `/sparring:workflow <task-description> <executor:claude|cursor>`:

1. **Initialize Task**
   ```bash
   sparring init  # if not exists
   task_id=$(sparring create "<task-name>" <executor>)
   ```

2. **Engage User in Discussion**
   - Ask clarifying questions about requirements
   - Discuss approach options with user
   - Understand constraints and priorities
   - **Output**: Draft outline of proposal

   Example conversation:
   ```
   You: "Let me understand the requirements better:
         1. What's the current pain point with the auth system?
         2. Do you prefer JWT or session-based?
         3. Any specific security requirements?
         ..."

   User: [answers]

   You: "Based on your input, I'm thinking:
         - Approach A: ...
         - Approach B: ...
         What do you prefer?"

   User: [chooses]

   You: "Got it. Let me write the formal proposal now."
   ```

### Step 2: Executor Writes Formal Proposal

3. **Write Complete Proposal**
   - Create `.workflow/plans/<task-id>/proposal.md`
   - Include:
     - Executive summary
     - Architecture design
     - Implementation approach
     - Risks and mitigations
     - Alternatives considered

### Step 3: Auto-Review Loop (No User)

4. **Executor ↔ Reviewer Iteration**
   ```
   while not approved and rounds < 5:
     reviewer: call `sparring review-proposal <task-id>`
       (internally runs the configured review backend: claude /code-review or opencode)
     parse reviewer response
     if APPROVE:
       break
     else:
       executor: address concerns
       update proposal-v{N}.md
   ```

### Step 4: User Confirmation

5. **Present to User**
   ```
   "✅ Proposal complete and peer-reviewed!

   Summary: [2-3 sentences]

   Key decisions:
   - [Decision 1]
   - [Decision 2]

   📄 Full proposal: .workflow/plans/<task-id>/proposal-final.md

   Ready to proceed with implementation? (yes/no)"
   ```

6. **Wait for User Approval**
   - If user says no: go back to Step 1
   - If user says yes: proceed to Phase 2

## Phase 2: Implementation Stage (Normal Mode)

### Step 5: Auto-Implementation (No User)

7. **Executor ↔ Reviewer Auto-Code**
   ```
   executor: implement code per proposal
   while not approved and rounds < 5:
     reviewer: call `sparring review-code <task-id>`
       (internally runs the configured review backend: claude /code-review or opencode)
     if APPROVE:
       break
     else:
       executor: fix issues
   ```

### Step 6: User Final Confirmation

8. **Present Implementation**
   ```
   "✅ Implementation complete and peer-reviewed!

   Changes:
   - [File 1]: [Description]
   - [File 2]: [Description]

   Tests: [Status]

   📊 Diff: .workflow/plans/<task-id>/final.diff

   Ready to commit? (yes/no)"
   ```

9. **Commit if Approved**

## Phase 2: YOLO Mode Flow

When user invokes `/sparring:yolo <task> <executor>`:

1. **Skip User Discussion** - Executor drafts proposal independently
2. **Auto-review loop** - Executor ↔ Reviewer iterate
3. **Auto-implement** - Executor ↔ Reviewer code
4. **Final checkpoint** - Show summary, ask user to commit

All intermediate steps automated, only final commit requires user.

## Key Instructions

### Mode Detection
- Check if user said `/sparring:yolo` or passed `--yolo` flag
- Set `MODE=yolo` or `MODE=normal` accordingly
- Adjust user checkpoints based on mode

### When YOU are Executor (Claude)

**Normal Mode:**
1. **Engage user first** - Ask questions, discuss approaches
2. **Co-create draft** with user input
3. **Write formal proposal** incorporating user's preferences
4. **Auto-iterate with reviewer** until both approve
5. **Present to user** with summary, wait for approval
6. **Implement code** after user confirms
7. **Auto-iterate on code** with reviewer
8. **Present to user** for final approval

**YOLO Mode:**
1. **Draft proposal alone** - Use your best judgment
2. **Auto-iterate with reviewer**
3. **Implement code**
4. **Auto-iterate on code**
5. **Present final result** to user for commit

### When YOU are Reviewer (for the other agent's work)
- **Use the `sparring` CLI** or call agent directly
- **Parse the response** and extract concerns/approvals
- **Don't proceed** until concerns are addressed

### Calling Other Agent

**Option 1: Use the CLI (recommended):**
```bash
sparring review-proposal <task-id>    # auto-calls agent
sparring review-code <task-id>        # auto-calls agent
```

**Option 2: Call agent directly:**
```bash
response=$(printf '%s' "你正在 review 一份技术方案。

任务: <task-name>

方案内容:
<full proposal content>

请 review 并回复:
- APPROVE: 如果方案合理可行
- CONCERNS: <编号列表> 如果有问题

重点: 架构合理性、可行性、边界情况、安全性。请用中文简洁回复。" | sparring review --title "方案审查")
```

**Important notes on calling the reviewer:**
- `sparring review` 退出码: 0 = APPROVE / 2 = CONCERNS / 1 = 调用错误
- Backend and model are configured in `~/.config/sparring/config.json` (`review.backend` defaults to `claude`)
- Override model via env var: `export WORKFLOW_AGENT_MODEL=sonnet-4`

### Issue Sync Protocol

When a task has an associated `issue_number` in `meta.json`, **sync key actions to the Issue as comments with identity markers**:

- The `sparring` CLI auto-syncs review results (reviewer backend reviews)
- **You (Claude) must manually sync your own actions** using:
  ```bash
  sparring issue-comment <number> "🧠 **[Claude Code — <Phase>]**

  <your content here>"
  ```

**What to sync to Issue:**
1. **Proposal draft** — post summary when you write the proposal
2. **Your responses to reviewer feedback** — when you address the reviewer's concerns
3. **Implementation summary** — when code is done
4. **Status changes** — approved, blocked, etc.

**Identity markers (so humans can tell who said what):**
- `🧠 **[Claude Code — Proposal]**` — Claude's proposal
- `🧠 **[Claude Code — Implementation]**` — Claude's code summary
- `🧠 **[<reviewer> — Proposal Review]**` — reviewer output (auto-synced by CLI)
- `🧠 **[<reviewer> — Code Review]**` — reviewer output (auto-synced by CLI)
- `🔧 **[Workflow — Status]**` — status transitions (auto-synced by CLI)

**When there is NO `issue_number`**: skip all sync, work purely locally.

### Communication Protocol
- All artifacts in `.workflow/plans/<task-id>/`
- Proposals: `proposal.md`, `proposal-v2.md`, `proposal-final.md`
- Reviews: `review-1.md`, `review-2.md`
- Code reviews: `code-review-1.md`, `code-review-2.md`
- Final diff: `final.diff`

## Example: Normal Mode

```
User: /sparring:workflow 重构用户认证系统 claude

Claude: "Let me understand the requirements:
1. What's wrong with current auth?
2. JWT or session-based preference?
3. Need SSO support?
..."

User: [answers questions]

Claude: "I see. I'm thinking we could:
A) Full JWT with refresh tokens
B) Hybrid session + JWT
Which sounds better?"

User: "Let's go with A"

Claude: "Perfect. Writing formal proposal..."
[writes proposal.md]
[auto-calls the reviewer backend]
[iterates based on feedback]

Claude: "✅ Proposal ready:
- Migrate to JWT tokens
- Add refresh token rotation
- Implement rate limiting
Full details: .workflow/plans/xxx/proposal-final.md

Approve to start coding? (yes/no)"

User: "yes"

Claude: [implements code]
[auto-reviews with the reviewer backend]
[fixes issues]

Claude: "✅ Implementation complete:
- Modified 8 files
- All tests passing
- Security audit clean
Diff: .workflow/plans/xxx/final.diff

Ready to commit? (yes/no)"

User: "yes"

Claude: [creates commit]
```

## Example: YOLO Mode

```
User: /sparring:yolo 修复登录重定向bug cursor

[Cursor Agent automatically:]
1. Analyzes the bug
2. Writes proposal
3. Gets Claude review
4. Implements fix
5. Gets Claude code review
6. Fixes issues

Cursor: "✅ Bug fixed and peer-reviewed:
- Root cause: incorrect redirect logic
- Fixed in auth.ts line 45
- Added test case
Ready to commit? (yes/no)"

User: "yes"
```

## Important Rules

### User Interaction (Normal Mode)
1. **Always engage user first** - Don't write proposal without discussion
2. **Ask clarifying questions** - Understand requirements deeply
3. **Present options** - Don't assume, let user choose approach
4. **Wait for approval** at Phase boundaries (after plan, after code)
5. **Summarize clearly** - User shouldn't need to read full files

### User Interaction (YOLO Mode)
1. **Work independently** - Only final checkpoint needed
2. **Present complete solution** - Explain what was done and why

### Auto-Review Protocol
1. **No user involvement** during agent-to-agent reviews
2. **Max 5 rounds** - Escalate to user if can't agree
3. **Save all artifacts** - Full audit trail
4. **Clear progress** - Log each iteration

## Error Handling

- If `agent` command fails: inform user, pause workflow
- If review response unclear: ask reviewer to clarify
- If 5 rounds without agreement: present both views to user for decision
- If user rejects: return to previous phase, incorporate feedback

## Success Criteria

### Normal Mode Success:
- ✅ User co-created the proposal direction
- ✅ Both agents approved proposal (user not involved in review loop)
- ✅ User approved final proposal
- ✅ Both agents approved code (user not involved in review loop)
- ✅ User approved final implementation
- ✅ Clean commit created

### YOLO Mode Success:
- ✅ Both agents approved proposal automatically
- ✅ Both agents approved code automatically
- ✅ User approved final commit
- ✅ Full audit trail saved
