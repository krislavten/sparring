# 使用示例

## 示例 1: 重构认证系统（Claude 执行）

这是一个大型重构任务，涉及架构设计和多个模块的改动，适合由 Claude Code 执行。

```bash
# 1. 初始化工作流（如果还没初始化）
cd ~/develop/pilot
sparring init

# 2. 创建任务，指定 Claude 为执行者
sparring create "refactor-auth-system" claude

# 3. 编辑任务描述
vim .workflow/plans/20260316-211730-refactor-auth-system/task.md

# 4. Claude Code 编写技术方案
# 在 Claude Code 中说：
# "请为任务 20260316-211730-refactor-auth-system 编写技术方案，保存到相应目录"

# 5. reviewer 审方案（自动调用配置的 backend）
sparring review-proposal 20260316-211730-refactor-auth-system
# reviewer 自己读 proposal.md，并在项目里核实方案提到的现有代码是否如它所说
# 结果存到 .workflow/plans/<task-id>/proposal-review-1.md

# 6. 如果需要修改，Claude 更新方案，然后再次 review
# 重复直到双方满意

# 7. 批准方案
sparring approve-proposal 20260316-211730-refactor-auth-system

# 8. Claude Code 实现代码
sparring implement 20260316-211730-refactor-auth-system
# 在 Claude Code 中根据方案实现

# 9. reviewer 审代码（自己在项目里跑 git diff 看未提交改动，不用先导出 diff 文件）
sparring review-code 20260316-211730-refactor-auth-system

# 10. 如果需要修改，继续修改和 review

# 11. 最终批准
sparring approve 20260316-211730-refactor-auth-system

# 12. 提交代码
git add .
git commit -m "refactor: redesign authentication system

- Extract auth logic into separate service
- Implement JWT token refresh mechanism
- Add role-based access control
- Update API endpoints to use new auth flow

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push
```

## 示例 2: 修复登录 Bug（Cursor 执行）

这是一个具体的 bug 修复，范围明确，适合由 Cursor Agent 快速处理。

```bash
cd ~/develop/rush-app
sparring init  # 如果需要

# 创建任务，指定 Cursor 为执行者
sparring create "fix-login-redirect" cursor

# 编辑任务描述
vim .workflow/plans/20260316-213000-fix-login-redirect/task.md

# Cursor Agent 编写方案（executor = cursor）
sparring propose 20260316-213000-fix-login-redirect
# 在 Cursor 中使用 agent 编写方案

# reviewer 审方案
sparring review-proposal 20260316-213000-fix-login-redirect

# 批准并实现
sparring approve-proposal 20260316-213000-fix-login-redirect
sparring implement 20260316-213000-fix-login-redirect

# Cursor 实现代码，reviewer 审代码
sparring review-code 20260316-213000-fix-login-redirect

# 批准并提交
sparring approve 20260316-213000-fix-login-redirect
git add .
git commit -m "fix: correct login redirect behavior"
git push
```

## 示例 3: 添加新功能（选执行者）

执行者（executor）决定"谁来写代码"，跟用哪个 reviewer 后端无关：

```bash
# 不指定执行者时默认用 claude
sparring create "add-user-profile-page"

# 显式指定：
sparring create "add-user-profile-page" claude   # 重构、架构设计、原则性讨论
sparring create "add-user-profile-page" cursor   # 小改动、单点修改、具体功能
```

## 示例 4: 不建 task，直接审一段改动

已经写完代码、只想要一次审查时，不用走完整 task 流程：

```bash
# 审当前分支相对 main 的全部改动
# reviewer 会建一个只读 worktree 快照，在里面自己跑 git diff、读文件，审完删掉
sparring review --range origin/main...HEAD --title "用户资料页"

# 只审最近 3 个 commit
sparring review --range HEAD~3..HEAD

# 审一段结论或方案文本（不建快照）
echo "打算用 Redis 存 session，理由是……" | sparring review --title "session 存储选型"

# 退出码：0=APPROVE  2=CONCERNS  1=调用错误
# 拿它当脚本门禁：
sparring review --range origin/main...HEAD || { echo "review 未通过，别 push"; exit 1; }
```

> ⚠️ `git diff ... | sparring review` 这种老用法在 3.0 已经会直接报错——改用 `--range`。
> reviewer 自己进仓库看，所以没有 diff 体量上限，也不需要按文件分片。

## 常用命令组合

### 快速查看所有任务
```bash
sparring list
```

### 查看特定任务详情
```bash
sparring status <task-id>
```

### 查看任务目录中的所有文件
```bash
ls -la .workflow/plans/<task-id>/
```

### 查看方案内容
```bash
cat .workflow/plans/<task-id>/proposal.md
```

### 查看最新的 review
```bash
cat .workflow/plans/<task-id>/proposal-review-1.md
cat .workflow/plans/<task-id>/code-review-1.md
```

## 工作流技巧

### 1. 方案讨论阶段

如果 review 提出了问题，执行者应该：
- 直接修改 `proposal.md`
- 或创建 `proposal-v2.md` 保留历史版本
- 然后观察者进行新一轮 review

### 2. 代码 Review 阶段

如果代码需要修改：
- 执行者修改代码
- 直接重跑 `sparring review-code <task-id>`——reviewer 的工作目录就是项目根，会自己跑 `git diff HEAD` 看最新的未提交改动，不需要先把 diff 导出成文件
- 每轮结果自动存成 `.workflow/plans/<task-id>/code-review-<N>.md`

### 3. 保存讨论记录

可以在任务目录中创建 `discussion.md` 记录双方的讨论：

```bash
echo "## Discussion" >> .workflow/plans/<task-id>/discussion.md
echo "### Round 1" >> .workflow/plans/<task-id>/discussion.md
# 记录讨论内容
```

### 4. 团队协作

如果需要团队共享工作流记录：

```bash
# 修改 .workflow/.gitignore，允许提交
echo "# Share workflow with team" > .workflow/.gitignore
echo "!plans/" >> .workflow/.gitignore
echo "!config.json" >> .workflow/.gitignore

# 提交到项目仓库
git add .workflow/
git commit -m "docs: add workflow records for <task>"
```
