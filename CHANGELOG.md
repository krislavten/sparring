# Changelog

## 3.0.0 (2026-08-12)

**Breaking。** review 从「调用方把 diff 文本管道进来、单发给模型」改成「reviewer 是个 agent，自己进仓库查」。旧的 `git diff ... | sparring review` 用法会直接报错，旧配置里的 backend 值也会被拒绝，需要按下面改。

### 行为变更

- **新增 `sparring review --range <git-range>`**，如 `sparring review --range origin/main...HEAD`。执行时 `git worktree add --detach` 建一个只读快照，reviewer 的工作目录指向快照，自己跑 `git diff <range>`、按需读文件和追调用方；审完删快照（正常、失败、被 kill 都清）。
- **不再接收 diff 文本**：stdin 里出现 `diff --git ` / `--- a/` 打头的行直接报错并提示改用 `--range`，不做静默兼容。纯文本审查（审结论/方案）保留原样。
- `--range` 模式不读 stdin。非交互环境里 stdin 常是不会关闭的管道，读它会永久阻塞。
- **后端从 4 个收敛到 2 个**：`claude`（`claude -p`，放行 Bash + Read/Grep/Glob，禁 Edit/Write/NotebookEdit/Task/WebFetch/WebSearch）和 `opencode`（`opencode run --agent plan`）。cursor / codex / glm 三个后端连同 `agents/cursor.md` 一起删除。
- **默认值**：`review.backend` glm → `claude`；`review.fallback` null → `opencode`；`review.timeout` 120 → `1800`。
- **删除输入体量门禁**：`--max-diff-lines`、`--exclude`、`--no-default-excludes`、内置 denylist、400 行上限、分片建议全部移除。reviewer 自己进仓库看，prompt 里不再有 diff，也就没有体量问题。
- **删除自适应超时**：不再按送审内容大小加时，改回扁平的 `review.timeout`。
- **配置里不再有任何 API key**：两个后端都用各自 CLI 已登录的账号。`glm.*`、`claude.base_url` / `api_key` / `config_dir` / `mode` 全部删除。现在的 schema 只剩 `review.{backend,fallback,timeout,retries,log_retention_days}` + `claude.{model,use_proxy,extra_args}` + `opencode.{model,use_proxy,extra_args}`。
- **task 制 review 同步 agent 化**：`review-proposal` / `review-code` 不再把方案正文和 diff 内联进 prompt，reviewer 的工作目录 = 项目根（活树，不建快照），自己读方案文件、自己跑 `git diff`。`review-code` 之前不用再 `git diff > changes.diff`。

### 新增

- 执行日志 JSONL 增加 `mode`（`range` / `text`）和 `range` 字段；range 模式下 `input_lines` 记该 range 的总变更行数。

### 迁移

旧配置里 `review.backend` 是 `glm` / `cursor` / `codex` 的会直接报错退出（不静默降级）。改成 `claude` 或 `opencode`，或重跑 `sparring config init --force`。调用方脚本里的 `git diff ... | sparring review` 改成 `sparring review --range ...`。

### 已知边界

reviewer 在快照里有 Bash 权限，工具层面挡不住它写文件——快照的"只读"靠的是 detached（不动任何分支）+ 审完即删，不是文件系统权限。快照与主仓库共用 `.git` 对象库。

## 2.3.0 (2026-07-22)

### 新增

- `sparring review` 执行日志：每次调用追加一行 JSONL 到 `~/.local/state/sparring/review-YYYYMMDD.jsonl`（`XDG_STATE_HOME` 可覆盖），字段含 `ts` / `title` / `input_lines` / `backend`（实际使用的后端）/ `via`（primary/fallback，可见是否触发降级）/ `duration_s` / `exit_code` / `verdict`。按天分文件，写入时自动清理过期文件，默认保留 7 天（config `review.log_retention_days`，0 = 完全禁用）。日志为旁路：任何写入失败静默，不影响 review 本身。此前 ad-hoc review 输出只走 stdout 不落盘，超时/降级事后无从排查。

## 2.2.0 (2026-07-22)

对应 PR #13。**含行为变更**：`sparring review` 现在默认拒绝超过 400 行的 diff。

### 行为变更

- `sparring review` 新增 diff 行数预算门禁，默认 400 行（此前不限）。超预算直接拒绝并给出分片建议。调整方式：`--max-diff-lines <N>`（0 = 不限）或 config `review.max_diff_lines`。
- 内置 denylist 自动剔除 `.env*`、lockfile、generated 等文件段（`--no-default-excludes` 关闭；`--exclude` / config `review.exclude` 追加）。被剔除的段始终列出，不静默截断。

### 修复

- **判空 busy-loop**：`${content//[[:space:]]/}` 式判空在 bash 3.2 下对大输入（22KB diff）烧 7min46s 纯 CPU，导致 review 长期"超时跑飞"。改为 glob 单遍短路后 11ms。
- **超时兜底**：`_timeout_cmd` 改用 `timeout`/`gtimeout -k 5` 二段击杀（TERM 后 5s 补 KILL）；perl fallback 对齐 GNU 语义（TERM+2s 补 KILL、信号死亡返回 128+sig，修复旧实现把 SIGKILL 死亡误报 exit 0）。

## 2.1.0 及更早

无 changelog 记录，见 git log（#1–#12）。
