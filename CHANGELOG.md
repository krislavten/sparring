# Changelog

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
