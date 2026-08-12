---
description: Set up Sparring - install dependencies, choose the reviewer backend, and initialize environment
argument-hint: (no arguments needed)
---

# Sparring Setup

You are helping the user set up the Sparring environment. This is an interactive setup — ask questions, install dependencies, and configure everything step by step.

**Plugin directory**: Find your own plugin install path by checking where this command file lives. The `bin/` directory is relative to the plugin root.

## Step 1: Detect Plugin Path

```bash
# Find the plugin root (parent of commands/)
# It will be somewhere under ~/.claude/plugins/
ls ~/.claude/plugins/marketplaces/*/commands/setup.md 2>/dev/null || ls ~/.claude/plugins/cache/*/setup.md 2>/dev/null
```

Determine the plugin root directory. All paths below are relative to it:
- `bin/sparring` — the CLI tool (with `bin/workflow` as a compat symlink)
- `bin/setup` — the legacy bash setup script (not used here)

## Step 2: Check & Install Dependencies

Check each dependency. If missing, install it automatically.

### 2.1 Homebrew (macOS only)

```bash
command -v brew
```

If missing:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2.2 jq

```bash
command -v jq
```

If missing: `brew install jq`

### 2.3 GitHub CLI (gh)

```bash
command -v gh
```

If missing: `brew install gh`

After installing, check auth status:
```bash
gh auth status
```

If not logged in, ask the user: "gh 需要登录 GitHub，要现在登录吗？" If yes: `gh auth login`

### 2.4 Reviewer 后端 CLI

Sparring 的 reviewer 是个 agent：它自己进仓库跑 `git diff`、读文件。两个后端任选其一，
装两个才有降级能力。

```bash
command -v claude
command -v opencode
```

- `claude` 缺失：`npm install -g @anthropic-ai/claude-code`，之后 `claude login`
- `opencode` 缺失：按 https://opencode.ai/docs 安装，之后 `opencode auth login`

两个都没有就没法 review，必须至少装一个。两个后端都用各自 CLI 已登录的账号，
sparring 不存任何 API key。

## Step 3: Install sparring CLI

Create two symlinks so both `sparring` (main) and `workflow` (compat alias) are available globally:

```bash
# Check if already installed
command -v sparring
```

If not:
```bash
# Prefer ~/.local/bin
mkdir -p ~/.local/bin
ln -sf "<plugin-root>/bin/sparring" ~/.local/bin/sparring
ln -sf "<plugin-root>/bin/sparring" ~/.local/bin/workflow
```

Verify: `command -v sparring && command -v workflow`

## Step 4: Select Reviewer Backend

Ask the user to choose. Present these options:

```
reviewer 后端（两个都是 agent CLI，用各自已登录的账号）：

1) claude    — Claude Code CLI (推荐)
2) opencode  — opencode run --agent plan

选哪个？主后端调用失败时会自动降级到另一个。
```

## Step 5: Write Global Config

Write the choice into `~/.config/sparring/config.json`. 已有配置只改 `review.backend` /
`review.fallback` 两个字段，不要覆盖用户其他设置：

```bash
mkdir -p ~/.config/sparring
CFG=~/.config/sparring/config.json
EXISTING='{}'
[ -f "$CFG" ] && jq -e . "$CFG" >/dev/null 2>&1 && EXISTING=$(cat "$CFG")
jq -n --argjson cur "$EXISTING" --arg b "<selected-backend>" --arg f "<fallback-backend>" \
  '$cur * {review: {backend: $b, fallback: $f}}' > "$CFG"
chmod 600 "$CFG"
```

模型留空即可（用该 CLI 自己的默认模型）；要指定就设 `claude.model` / `opencode.model`。

## Step 6: Permissions (Optional)

Ask the user: "sparring 需要频繁调用 bash 命令（sparring CLI、reviewer 后端 CLI、gh CLI）。是否允许自动执行这些命令，不用每次确认？"

If yes, tell the user to run:
```
/permissions
```
And add these allow rules (or guide them through it):
- `Bash(sparring *)` — sparring CLI commands
- `Bash(workflow *)` — compat alias for legacy scripts
- `Bash(claude *)` / `Bash(opencode *)` — reviewer 后端调用
- `Bash(gh *)` — GitHub CLI calls
- `Bash(HTTP_PROXY= *)` — 后端调用时清代理

Or if they prefer full trust for this session, they can use **bypass permissions mode** in Claude Code settings.

If no, tell them: "没问题，每次执行命令时会弹出确认。"

## Step 7: Verify

Run verification:
```bash
sparring verify
```

## Step 8: Done

Tell the user:

```
Setup 完成！

开始使用：
  /sparring:workflow <任务描述>   — 普通模式
  /sparring:yolo <任务描述>       — 全自动模式
  /sparring:issue <看板URL>       — Issue 驱动模式

更多帮助: sparring help
```
