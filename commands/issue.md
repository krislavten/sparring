---
description: GitHub Issue-driven - Poll issues, discuss via comments, implement with peer review
argument-hint: <project-url> [issue-number]
---

# GitHub Issue-Driven Dual AI Workflow

You are the **Workflow Orchestrator** that consumes GitHub Issues as a task queue. Claude is the Executor, the configured review backend is the Reviewer. Communication with the user happens via **Issue Comments**.

## Project Context

**The user must provide a GitHub Project board URL** (or an issue URL) so you know which project to work with. Do NOT assume a default project.

Parse the project URL to extract owner and project number:
- `https://github.com/orgs/<owner>/projects/<number>` → owner + number
- `https://github.com/users/<owner>/projects/<number>` → owner + number

If the user provides an issue URL like `https://github.com/<owner>/<repo>/issues/<number>`, extract the repo and issue number from it.

Pass the project URL to workflow commands via `--project`:
```bash
sparring --project "<project-url>" issue-claim <number>
sparring --project "<project-url>" issue-done <number> <pr-url>
```

If no project URL is provided, issue commands still work but **project board status will not be updated** (claiming, review transitions, etc. are skipped). Always ask the user for the project URL if they haven't provided one.

## Overview

```
GitHub Issue (Planning + claude-ok label)
  ↓  poll / manual trigger
Claude claims issue → status: In progress
  ↓
Normal: Discuss direction via issue comments → draft proposal → reviewer review (≤5 rounds) → implement → reviewer review code (≤5 rounds) → PR
YOLO:   Draft proposal autonomously → reviewer review (≤5 rounds) → implement → reviewer review code (≤5 rounds) → PR
  ↓
PR created → status: Reviewing
```

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
   gh issue list --repo <repo> --label "claude-ok" --state open --json number,title,labels,assignees
   ```

2. **Filter candidates**: must have `claude-ok` label, skip issues already `In progress`

3. **Present candidates** if multiple, ask user which one

4. **Claim the issue**: move to `In progress` on project board, comment on issue

### Detect mode:
- If issue has `yolo` label → YOLO mode
- Otherwise → Normal mode

## Phase 1: Plan Stage

### Step 1: Understand the Issue (Both Modes)

Read the issue body:
```bash
gh issue view <number> --repo <repo> --json body,title,comments
```

### Step 2: Direction Discussion (Normal Mode Only)

**YOLO mode skips to Step 3.**

1. Post direction proposal as issue comment
2. Wait for user reply — poll issue comments every 30 seconds
3. Multi-round discussion (up to 5 rounds)
4. When user approves → proceed to Step 3

### Step 3: Draft Formal Proposal (Both Modes)

1. Write complete technical proposal to `.workflow/plans/<task-id>/proposal.md`
2. Post proposal summary as issue comment

### Step 4: Reviewer Reviews Proposal (Both Modes, ≤5 rounds)

```
for round in 1..5:
  call: sparring review-proposal <task-id>
  if APPROVE: break
  else: address concerns, update proposal
if 5 rounds without approval: escalate to user
```

## Phase 2: Implementation (Both Modes)

### Step 5: Create Branch & Implement

1. Create feature branch: `git checkout -b fix/issue-<number>`
2. Implement code per approved proposal
3. Write tests alongside implementation

### Step 6: Reviewer Reviews Code (Both Modes, ≤5 rounds)

```
for round in 1..5:
  call: sparring review-code <task-id>
  if APPROVE: break
  else: fix issues
if 5 rounds without approval: escalate to user
```

### Step 7: Post Implementation Summary as issue comment

## Phase 3: PR & Status Update

1. Create PR with `Closes #<issue-number>`
2. Update project board status to Reviewing
3. Post PR link as issue comment

## Key Instructions

### Repository Detection
- Detect repo from git remote: `git remote get-url origin`
- All `gh` commands use `--repo <owner>/<repo>`

### Identity Markers in Comments

Since all comments are posted via `gh` under the same GitHub account, **prefix every comment with an identity marker**:

- `🧠 **[Claude Code — Proposal]**` — Claude's proposal or direction discussion
- `🧠 **[Claude Code — Implementation]**` — Claude's implementation summary
- `🧠 **[<reviewer> — Proposal Review #N]**` — reviewer proposal review (auto-synced by CLI)
- `🧠 **[<reviewer> — Code Review #N]**` — reviewer code review (auto-synced by CLI)
- `🔧 **[Workflow — Status]**` — automated status transitions

**Claude must always use the `🧠` prefix** when posting comments:
```bash
sparring issue-comment <number> "🧠 **[Claude Code — Proposal]**

<proposal content>"
```

### Waiting for User Reply
1. Post question/proposal as comment
2. Tell local user: "已在 issue #X 发布方案，等待回复中..."
3. Poll every 30 seconds for new comments
4. Max wait: notify user locally after 10 minutes

### Branch Naming
- Bug fix: `fix/issue-<number>-<short-description>`
- Feature: `feat/issue-<number>-<short-description>`
- Refactor: `refactor/issue-<number>-<short-description>`

### Commit Message
```
<type>(scope): <description>

Closes #<issue-number>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Error Handling

- **gh CLI fails**: Inform user locally, retry once, then pause
- **Reviewer backend unreachable**: falls back to the other backend; both down → degrade to manual review, continue
- **5 review rounds without approval**: Post to issue, escalate to user
- **User doesn't reply in 10 min**: Notify locally, keep polling
- **Merge conflict**: Inform user, attempt rebase, ask for help if fails

## Important Rules

1. **Always comment on the issue** for every significant step
2. **Don't modify issue body** — only add comments
3. **Respect existing assignees** — if someone else is assigned, skip
4. **Keep comments concise** — summaries in comments, details in local `.workflow/`
5. **Max 5 rounds** for both proposal and code review
6. **Always create PR** linking back to the issue with `Closes #<number>`
