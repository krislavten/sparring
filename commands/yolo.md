---
description: Fully automated - AI handles everything, user only confirms final commit
argument-hint: <task-description> [claude|cursor]
---

# Dual AI Workflow - YOLO Mode

Fully automated execution. You handle everything, user only confirms final commit.

## Flow

```
User: /sparring:yolo <task> <executor>
  ↓
Executor: Draft proposal independently
  ↓
Executor ↔ Reviewer: Auto-iterate (no user)
  ↓
Executor: Implement code
  ↓
Executor ↔ Reviewer: Auto-iterate (no user)
  ↓
Executor: "Done! Commit? (yes/no)"
  ↓
User: yes → Commit!
```

## Cross-Review Principle

Same as normal mode: **every conclusion, recommendation, and decision must be reviewed before presenting to the user.** In YOLO mode this includes:
- The proposal itself (via `sparring review-proposal`)
- Any key technical decisions made during implementation
- The final code (via `sparring review-code`)

## Instructions

### If YOU are the Executor (default: claude)

1. **Create task**: `sparring create "<name>"` (defaults to claude)

2. **Draft proposal independently**
   - Don't ask user for input — use your best judgment
   - Save to `.workflow/plans/<task-id>/proposal.md`

3. **MUST call reviewer**: `sparring review-proposal <task-id>`
   - If CONCERNS, address and retry. Up to 5 rounds.

4. **Implement code** — follow approved proposal, write tests

5. **MUST call reviewer**: `sparring review-code <task-id>`
   - If CONCERNS, fix and retry. Up to 5 rounds.

6. **Present final result** — summary, changes, review iterations, ask to commit

7. **If user approves**: Create commit

## When to Use YOLO

Good for: small well-defined tasks, bug fixes, routine refactoring, simple features.
Not good for: architectural changes, security-critical features, ambiguous requirements.

## Issue Sync

When a task has `issue_number` in `meta.json`, sync key steps to the Issue:

- **Reviewer output** is auto-synced by the `workflow` CLI with the reviewer icon
- **You (Claude/Executor)** must manually sync your actions:
  ```bash
  sparring issue-comment <number> "🧠 **[Claude Code — <Phase>]**

  <content>"
  ```
- Sync: proposal summary, implementation summary, final result
- **No `issue_number`?** Skip all sync, work purely locally.

## Notes

- **Speed**: Much faster than normal mode
- **Risk**: Higher - less human oversight
- **Audit**: Still full trail in `.workflow/plans/`
- **Rollback**: Easy with git if issues found later
