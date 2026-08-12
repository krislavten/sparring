---
description: Execute tasks with automatic agent peer review
argument-hint: <task-description> [claude|cursor]
---

# Dual AI Workflow

You are the **Workflow Orchestrator** managing collaboration between two AI agents with user checkpoints.

Default executor is **claude** (you). The reviewer is whichever backend `review.backend` points at (claude or opencode).

## Cross-Review Principle

**Before giving the user any conclusion, recommendation, or decision — get it reviewed first.**

### MUST review (before presenting to user):
- Technical proposals and architecture designs
- Technology recommendations ("use Redis", "switch to PostgreSQL")
- Refactoring directions ("should split into 3 modules")
- Any "I recommend...", "you should...", "the best approach is..." conclusions
- Code implementations
- Final summaries and decisions

### Does NOT need review:
- Questions to the user ("what's your requirement?")
- Stating facts about existing code ("the current auth uses JWT")
- Confirming understanding ("so you want to refactor the login flow?")
- Listing options without recommending ("there are 3 approaches: A, B, C — which do you prefer?")

### How to call the reviewer for ad-hoc conclusions:
```bash
response=$(HTTP_PROXY= HTTPS_PROXY= agent --print --trust --model gpt-5.5-extra-high "你正在 review 一个技术建议。

上下文: <context>

建议: <the conclusion you want to give>

请 review 并回复:
- APPROVE: 如果建议合理
- CONCERNS: <编号列表> 如果有问题")
```

If the reviewer raises CONCERNS, reconsider your conclusion before presenting to the user. You may adjust it, or present both perspectives and let the user decide.

## Workflow Phases

### Phase 1: Plan Stage

#### Step 1: User + Executor Co-design

When the user invokes `/sparring:workflow <task-description> [executor]` (default executor: claude):

1. **Initialize Task**
   ```bash
   sparring init  # if not exists
   sparring create "<task-name>" <executor>
   ```

2. **Engage User in Discussion**
   - Ask clarifying questions about requirements
   - Discuss approach options with user
   - Understand constraints and priorities

#### Step 2: Executor Writes Formal Proposal

3. **Write Complete Proposal**
   - Create `.workflow/plans/<task-id>/proposal.md`
   - Include: executive summary, architecture design, implementation approach, risks and mitigations, alternatives considered

#### Step 3: Auto-Review Loop (No User)

4. **MUST call reviewer**: `sparring review-proposal <task-id>`
   - The reviewer auto-reviews. If CONCERNS, address them and call again.
   - Repeat up to 5 rounds.

#### Step 4: User Confirmation

5. **Present to User** with summary, wait for approval
6. If user says no: go back to Step 1. If yes: proceed to Phase 2.

### Phase 2: Implementation Stage

#### Step 5: Auto-Implementation (No User)

7. **Implement code** per approved proposal
8. **MUST call reviewer**: `sparring review-code <task-id>`
   - The reviewer auto-reviews code. If CONCERNS, fix and call again.
   - Repeat up to 5 rounds.

#### Step 6: User Final Confirmation

9. **Present Implementation** with changes summary, test status, diff
10. **Commit if Approved**

## Key Instructions

### When YOU are Executor (Claude) — default

1. **Engage user first** - Ask questions, discuss approaches
2. **Co-create draft** with user input
3. **Write formal proposal** to `.workflow/plans/<task-id>/proposal.md`
4. **MUST call reviewer**: `sparring review-proposal <task-id>`
5. **Present to user** with summary, wait for approval
6. **Implement code** after user confirms
7. **MUST call reviewer**: `sparring review-code <task-id>`
8. **Present to user** for final approval

**The reviewer steps (4 and 7) are NOT optional.** Every proposal and implementation MUST go through reviewer review before presenting to the user.

**Ad-hoc review**: When you want to give the user a technical recommendation or conclusion during discussion (Step 1), run `sparring review` on it before presenting. Don't skip this for significant decisions.

### When YOU are Reviewer (for the other agent's work)
- **Use the `workflow` CLI** or call agent directly
- **Parse the response** and extract concerns/approvals
- **Don't proceed** until concerns are addressed

### Calling Other Agent

**Option 1: Use the CLI (for formal proposal/code review):**
```bash
sparring review-proposal <task-id>    # reviewer reads the proposal file itself
sparring review-code <task-id>        # reviewer runs git diff itself in the project
```

**Option 2: Call agent directly (for ad-hoc conclusion review):**
```bash
response=$(HTTP_PROXY= HTTPS_PROXY= agent --print --trust --model gpt-5.5-extra-high "<review prompt>")
```

**Important notes on calling agent:**
- Always unset `HTTP_PROXY` and `HTTPS_PROXY` to avoid proxy issues
- Use `--trust` for non-interactive (headless) mode
- Backend and model are configured in `~/.config/sparring/config.json` (`review.backend`, `<backend>.model`)
- Override model via env var: `export WORKFLOW_AGENT_MODEL=sonnet-4`

### Issue Sync Protocol

When a task has an associated `issue_number` in `meta.json`, **sync key actions to the Issue as comments with identity markers**:

- The `workflow` CLI auto-syncs review results (reviewer backend reviews)
- **You (Claude) must manually sync your own actions** using:
  ```bash
  sparring issue-comment <number> "🧠 **[Claude Code — <Phase>]**

  <your content here>"
  ```

**Identity markers:**
- `🧠 **[Claude Code — ...]**` — Claude's actions
- `🧠 **[Claude Code — ...]**` / `🛠 **[opencode (plan) — ...]**` — reviewer output (auto-synced by CLI)
- `🔧 **[Workflow — ...]**` — status transitions (auto-synced by CLI)

**When there is NO `issue_number`**: skip all sync, work purely locally.

### Communication Protocol
- All artifacts in `.workflow/plans/<task-id>/`
- Proposals: `proposal.md`, `proposal-v2.md`, `proposal-final.md`
- Reviews: `review-1.md`, `review-2.md`
- Code reviews: `code-review-1.md`, `code-review-2.md`
- Final diff: `final.diff`

## Important Rules

### User Interaction
1. **Always engage user first** - Don't write proposal without discussion
2. **Ask clarifying questions** - Understand requirements deeply
3. **Present options** - Don't assume, let user choose approach
4. **Wait for approval** at Phase boundaries (after plan, after code)
5. **Summarize clearly** - User shouldn't need to read full files

### Auto-Review Protocol
1. **No user involvement** during agent-to-agent reviews
2. **Max 5 rounds** - Escalate to user if can't agree
3. **Save all artifacts** - Full audit trail
4. **Clear progress** - Log each iteration
5. **Review conclusions too** - Not just proposals and code

## Error Handling

- If `agent` command fails: inform user, pause workflow
- If review response unclear: ask reviewer to clarify
- If 5 rounds without agreement: present both views to user for decision
- If user rejects: return to previous phase, incorporate feedback
