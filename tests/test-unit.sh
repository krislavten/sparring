#!/bin/bash

# Dual AI Workflow — Unit Tests
# Run: bash tests/test-unit.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOW="$PROJECT_DIR/bin/sparring"
AGENTS_DIR="$PROJECT_DIR/agents"

# Test workspace
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

# ─── Test helpers ────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✓ $desc"
        ((PASS++))
    else
        echo "  ✗ $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        ((FAIL++))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  ✓ $desc"
        ((PASS++))
    else
        echo "  ✗ $desc"
        echo "    expected to contain: $needle"
        echo "    actual: ${haystack:0:200}"
        ((FAIL++))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  ✗ $desc"
        echo "    expected NOT to contain: $needle"
        echo "    actual: ${haystack:0:200}"
        ((FAIL++))
    else
        echo "  ✓ $desc"
        ((PASS++))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -f "$path" ]]; then
        echo "  ✓ $desc"
        ((PASS++))
    else
        echo "  ✗ $desc — file not found: $path"
        ((FAIL++))
    fi
}

# Source workflow functions (need to set up env first)
source_workflow_funcs() {
    # Override dirs to use temp space
    export PROJECT_ROOT="$TMP_DIR/project"
    export WORKFLOW_DIR="$TMP_DIR/project/.workflow"
    export PLANS_DIR="$TMP_DIR/project/.workflow/plans"
    export AGENTS_DIR="$PROJECT_DIR/agents"
    mkdir -p "$PROJECT_ROOT" "$WORKFLOW_DIR" "$PLANS_DIR"

    # 隔离：指向不存在的 config 文件，避免读取用户真实 ~/.config/sparring/config.json
    export CONFIG_DIR_GLOBAL="$TMP_DIR/config-global"
    export CONFIG_FILE_GLOBAL="$CONFIG_DIR_GLOBAL/config.json"
    export CONFIG_DIR_PROJECT="$TMP_DIR/project/.sparring"
    export CONFIG_FILE_PROJECT="$CONFIG_DIR_PROJECT/config.json"

    # 清掉所有可能影响测试的 env 变量
    unset WORKFLOW_REVIEW_BACKEND WORKFLOW_REVIEW_BACKEND_FALLBACK
    unset WORKFLOW_REVIEW_TIMEOUT WORKFLOW_REVIEW_RETRIES
    unset WORKFLOW_AGENT_MODEL WORKFLOW_CODEX_MODEL WORKFLOW_CODEX_EFFORT WORKFLOW_CODEX_HOME
    unset WORKFLOW_GLM_API_KEY WORKFLOW_GLM_MODEL WORKFLOW_GLM_THINKING
    unset WORKFLOW_GLM_MAX_TOKENS WORKFLOW_GLM_TEMPERATURE WORKFLOW_GLM_API_BASE
    unset SPARRING_REVIEW_BACKEND SPARRING_REVIEW_FALLBACK SPARRING_REVIEW_TIMEOUT SPARRING_REVIEW_RETRIES
    unset SPARRING_GLM_API_KEY SPARRING_GLM_MODEL SPARRING_CURSOR_MODEL
    unset SPARRING_CLAUDE_BASE_URL SPARRING_CLAUDE_API_KEY SPARRING_CLAUDE_MODEL
    unset SPARRING_CLAUDE_CONFIG_DIR SPARRING_CLAUDE_USE_PROXY SPARRING_CLAUDE_EXTRA_ARGS

    # Source the workflow script but replace main() and set -euo to prevent issues
    eval "$(sed -e 's/^main "$@"/# main disabled for testing/' \
                 -e 's/^set -euo pipefail/# set disabled for testing/' \
                 "$WORKFLOW")"

    # source 过程会执行 CONFIG_FILE_* / PROJECT_ROOT / PLANS_DIR 等赋值，覆盖我们上面的 export
    # （bin/sparring 顶层 `PROJECT_ROOT="$(find_project_root)"` 会重新往上找 .git，
    #  在这个仓库里找到的是真实仓库根目录，而不是我们隔离用的 $TMP_DIR/project）。
    # 再次强制设置，否则 create_task 等测试会把 meta.json 写进真实仓库的 .workflow/plans/，
    # 污染仓库状态，且 `ls ... | head -1` 挑到的还可能是历史遗留的旧目录，导致断言随机失败。
    CONFIG_DIR_GLOBAL="$TMP_DIR/config-global"
    CONFIG_FILE_GLOBAL="$CONFIG_DIR_GLOBAL/config.json"
    CONFIG_DIR_PROJECT="$TMP_DIR/project/.sparring"
    CONFIG_FILE_PROJECT="$CONFIG_DIR_PROJECT/config.json"
    PROJECT_ROOT="$TMP_DIR/project"
    WORKFLOW_DIR="$TMP_DIR/project/.workflow"
    PLANS_DIR="$TMP_DIR/project/.workflow/plans"

    # 清掉可能残留的 warn 哨兵文件（避免测试间互相干扰）
    rm -f "${TMPDIR:-/tmp}/workflow-cfg-warn-$$-"* 2>/dev/null || true
}

# ─── Tests ───────────────────────────────────────────────────

echo ""
echo "=== update_meta ==="

test_update_meta_simple() {
    source_workflow_funcs
    local task_dir="$TMP_DIR/meta-test-1"
    mkdir -p "$task_dir"
    echo '{"status":"pending","steps":{"proposal":"pending"}}' > "$task_dir/meta.json"

    update_meta "$task_dir" '.status = "done"'
    local result
    result=$(jq -r '.status' "$task_dir/meta.json")
    assert_eq "simple update" "done" "$result"
}
test_update_meta_simple

test_update_meta_with_arg() {
    source_workflow_funcs
    local task_dir="$TMP_DIR/meta-test-2"
    mkdir -p "$task_dir"
    echo '{"status":"pending"}' > "$task_dir/meta.json"

    update_meta "$task_dir" --arg cid "abc-123" '.agent_chat_id = $cid'
    local result
    result=$(jq -r '.agent_chat_id' "$task_dir/meta.json")
    assert_eq "update with --arg" "abc-123" "$result"
}
test_update_meta_with_arg

test_update_meta_chained() {
    source_workflow_funcs
    local task_dir="$TMP_DIR/meta-test-3"
    mkdir -p "$task_dir"
    echo '{"steps":{"proposal":"pending","review":"pending"}}' > "$task_dir/meta.json"

    update_meta "$task_dir" '.steps.proposal = "done" | .steps.review = "approved"'
    local p r
    p=$(jq -r '.steps.proposal' "$task_dir/meta.json")
    r=$(jq -r '.steps.review' "$task_dir/meta.json")
    assert_eq "chained update — proposal" "done" "$p"
    assert_eq "chained update — review" "approved" "$r"
}
test_update_meta_chained

echo ""
echo "=== sync_to_issue ==="

test_sync_to_issue_no_issue() {
    source_workflow_funcs
    local task_dir="$TMP_DIR/sync-test-1"
    mkdir -p "$task_dir"
    echo '{"status":"pending"}' > "$task_dir/meta.json"

    # Should return 0 silently when no issue_number
    local result
    result=$(sync_to_issue "$task_dir" "Claude" "Test" "body" 2>&1)
    assert_eq "no-op when no issue_number" "" "$result"
}
test_sync_to_issue_no_issue

echo ""
echo "=== create_task ==="

test_create_task_structure() {
    source_workflow_funcs
    # Mock check_agent and init_agent_session to avoid real agent calls

    create_task "test-task" "claude" > /dev/null 2>&1

    # Find the created task dir
    local task_dir
    task_dir=$(ls -d "$PLANS_DIR"/*-test-task 2>/dev/null | head -1)

    assert_file_exists "task dir created" "$task_dir/meta.json"
    assert_file_exists "task.md created" "$task_dir/task.md"

    local executor reviewer status
    executor=$(jq -r '.executor' "$task_dir/meta.json")
    reviewer=$(jq -r '.reviewer' "$task_dir/meta.json")
    status=$(jq -r '.status' "$task_dir/meta.json")
    assert_eq "executor is claude" "claude" "$executor"
    assert_eq "reviewer is claude" "claude" "$reviewer"
    assert_eq "initial status is proposal" "proposal" "$status"
}
test_create_task_structure

test_create_task_cursor_executor() {
    source_workflow_funcs

    create_task "cursor-task" "cursor" > /dev/null 2>&1

    local task_dir
    task_dir=$(ls -d "$PLANS_DIR"/*-cursor-task 2>/dev/null | head -1)

    local executor reviewer
    executor=$(jq -r '.executor' "$task_dir/meta.json")
    reviewer=$(jq -r '.reviewer' "$task_dir/meta.json")
    assert_eq "executor is cursor" "cursor" "$executor"
    assert_eq "reviewer follows default backend(claude)" "claude" "$reviewer"
}
test_create_task_cursor_executor

test_create_task_opencode_backend() {
    source_workflow_funcs

    WORKFLOW_REVIEW_BACKEND=opencode create_task "oc-task" "claude" > /dev/null 2>&1

    local task_dir
    task_dir=$(ls -d "$PLANS_DIR"/*-oc-task 2>/dev/null | head -1)

    local reviewer
    reviewer=$(jq -r '.reviewer' "$task_dir/meta.json")
    assert_eq "reviewer follows opencode backend" "opencode" "$reviewer"
}
test_create_task_opencode_backend

echo ""
echo "=== validate_task_name ==="

test_validate_task_name_valid() {
    source_workflow_funcs
    validate_task_name "my-task-123" 2>/dev/null
    assert_eq "valid name passes" "0" "$?"
}
test_validate_task_name_valid

test_validate_task_name_invalid() {
    source_workflow_funcs
    local result
    result=$(validate_task_name "my task!" 2>&1) && status=0 || status=$?
    assert_eq "invalid name fails" "1" "$status"
}
test_validate_task_name_invalid

echo ""
echo "=== parse_project_url ==="

test_parse_org_url() {
    source_workflow_funcs
    ISSUE_PROJECT_OWNER="" ISSUE_PROJECT_NUMBER=""
    parse_project_url "https://github.com/orgs/kanyun-inc/projects/3"
    assert_eq "org URL — owner" "kanyun-inc" "$ISSUE_PROJECT_OWNER"
    assert_eq "org URL — number" "3" "$ISSUE_PROJECT_NUMBER"
}
test_parse_org_url

test_parse_user_url() {
    source_workflow_funcs
    ISSUE_PROJECT_OWNER="" ISSUE_PROJECT_NUMBER=""
    parse_project_url "https://github.com/users/kris/projects/7"
    assert_eq "user URL — owner" "kris" "$ISSUE_PROJECT_OWNER"
    assert_eq "user URL — number" "7" "$ISSUE_PROJECT_NUMBER"
}
test_parse_user_url

test_parse_invalid_url() {
    source_workflow_funcs
    local status=0
    parse_project_url "https://github.com/kanyun-inc/rush" 2>/dev/null || status=$?
    assert_eq "invalid URL fails" "1" "$status"
}
test_parse_invalid_url

test_no_project_graceful() {
    source_workflow_funcs
    ISSUE_PROJECT_OWNER="" ISSUE_PROJECT_NUMBER=""
    # get_project_item_id should return 1 silently
    local status=0
    get_project_item_id "123" 2>/dev/null || status=$?
    assert_eq "no project config — skips gracefully" "1" "$status"
}
test_no_project_graceful

echo ""
echo "=== review backend ==="

test_review_backend_default() {
    source_workflow_funcs
    unset WORKFLOW_REVIEW_BACKEND
    local backend
    backend=$(get_review_backend)
    assert_eq "default review backend" "claude" "$backend"
}
test_review_backend_default

test_review_backend_opencode() {
    source_workflow_funcs
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=opencode get_review_backend)
    assert_eq "opencode review backend" "opencode" "$backend"
}
test_review_backend_opencode

test_review_backend_invalid() {
    source_workflow_funcs
    local status=0
    WORKFLOW_REVIEW_BACKEND=foo get_review_backend 2>/dev/null || status=$?
    assert_eq "invalid backend fails" "1" "$status"
}
test_review_backend_invalid

# 已退役的后端名不能再被接受（旧 config 会被明确拒绝，不是静默降级）
test_review_backend_retired_rejected() {
    source_workflow_funcs
    local retired status
    for retired in glm codex cursor; do
        status=0
        WORKFLOW_REVIEW_BACKEND="$retired" get_review_backend 2>/dev/null || status=$?
        assert_eq "retired backend rejected: ${retired}" "1" "$status"
    done
}
test_review_backend_retired_rejected

test_review_backend_opencode_uppercase() {
    source_workflow_funcs
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=OpenCode get_review_backend)
    assert_eq "opencode backend case-insensitive" "opencode" "$backend"
}
test_review_backend_opencode_uppercase

test_review_backend_claude() {
    source_workflow_funcs
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=claude get_review_backend)
    assert_eq "claude review backend" "claude" "$backend"
}
test_review_backend_claude

test_review_backend_claude_uppercase() {
    source_workflow_funcs
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=Claude get_review_backend)
    assert_eq "claude backend case-insensitive" "claude" "$backend"
}
test_review_backend_claude_uppercase

echo ""
echo "=== fallback backend ==="

test_fallback_default() {
    source_workflow_funcs
    unset WORKFLOW_REVIEW_BACKEND_FALLBACK
    local fb
    fb=$(get_review_backend_fallback)
    assert_eq "default fallback is opencode" "opencode" "$fb"
}
test_fallback_default

test_fallback_opencode() {
    source_workflow_funcs
    local fb
    fb=$(WORKFLOW_REVIEW_BACKEND_FALLBACK=opencode get_review_backend_fallback)
    assert_eq "fallback opencode" "opencode" "$fb"
}
test_fallback_opencode

test_fallback_claude() {
    source_workflow_funcs
    local fb
    fb=$(WORKFLOW_REVIEW_BACKEND_FALLBACK=claude get_review_backend_fallback)
    assert_eq "fallback claude" "claude" "$fb"
}
test_fallback_claude

test_fallback_invalid() {
    source_workflow_funcs
    local status=0
    WORKFLOW_REVIEW_BACKEND_FALLBACK=bogus get_review_backend_fallback 2>/dev/null || status=$?
    assert_eq "invalid fallback fails" "1" "$status"
}
test_fallback_invalid

test_reviewer_label_opencode() {
    source_workflow_funcs
    local label
    label=$(reviewer_label_for_backend "opencode")
    assert_eq "opencode label" "opencode (plan)" "$label"
}
test_reviewer_label_opencode

test_reviewer_label_claude() {
    source_workflow_funcs
    local label
    label=$(reviewer_label_for_backend "claude")
    assert_eq "claude label" "Claude Code" "$label"
}
test_reviewer_label_claude

test_reviewer_name_claude() {
    source_workflow_funcs
    local name
    name=$(reviewer_name_for_backend "claude")
    assert_eq "claude name" "claude" "$name"
}
test_reviewer_name_claude

echo ""
echo "=== 后端配置默认值 ==="

test_backend_config_defaults() {
    source_workflow_funcs
    assert_eq "claude.model 默认 null→空" "" "$(_config_get claude.model)"
    assert_eq "opencode.model 默认 null→空" "" "$(_config_get opencode.model)"
    assert_eq "review.timeout 默认 1800" "1800" "$(_config_get review.timeout)"
    # 注意: jq 的 `//` 把布尔 false 和 null 都当 "empty"，故默认 false 读出来是空串。
    # 代码只比较 `== "true"`（空串视为 not-true → 清代理），行为正确，这里断言"非 true"语义。
    assert_eq "claude.use_proxy 默认非 true" "" "$(_config_get claude.use_proxy)"
    assert_eq "use_proxy=true(bool) 能读成 true" "true" \
        "$(SPARRING_CLAUDE_USE_PROXY=true _config_get claude.use_proxy)"
}
test_backend_config_defaults

echo ""
echo "=== check_backend ==="

# 假后端二进制：只用来验"在不在 PATH 里"这条分支
_make_fake_bin() {
    local name="$1"
    local dir="$TMP_DIR/fake-${name}-$RANDOM"
    mkdir -p "$dir"
    printf '#!/bin/bash\necho "1.0.0 (fake)"\n' > "$dir/$name"
    chmod +x "$dir/$name"
    echo "$dir"
}

test_check_backend_missing() {
    source_workflow_funcs
    local status=0
    ( PATH="$TMP_DIR/nonexistent-bin"; check_backend claude ) 2>/dev/null || status=$?
    assert_eq "claude 不在 PATH → 失败" "1" "$status"
}
test_check_backend_missing

test_check_backend_present() {
    source_workflow_funcs
    local dir status=0
    dir=$(_make_fake_bin opencode)
    PATH="$dir:$PATH" check_backend opencode 2>/dev/null || status=$?
    assert_eq "opencode 在 PATH → 通过" "0" "$status"
}
test_check_backend_present

test_check_backend_unknown() {
    source_workflow_funcs
    local status=0
    check_backend nope 2>/dev/null || status=$?
    assert_eq "未知 backend → 失败" "1" "$status"
}
test_check_backend_unknown

echo ""
echo "=== _call_backend 命令组装 & 运行环境 (mock 后端) ==="

# mock 后端：把 argv / 关键 env / PWD / stdin 收到的 prompt dump 到 $BACKEND_MOCK_DUMP。
# argv 每个 token 带 "ARG:" 前缀输出，这样断言可以直接 grep（避开 "--model" 被 grep 当选项）。
_make_mock_backend() {
    local name="$1"
    local dir="$TMP_DIR/mock-${name}-$RANDOM"
    mkdir -p "$dir"
    cat > "$dir/$name" <<'MOCK'
#!/bin/bash
_state() { if [ -z "${!1+x}" ]; then echo UNSET; elif [ -z "${!1}" ]; then echo EMPTY; else echo SET; fi; }
STDIN_CONTENT=$(cat)
{
  echo "PWD: $PWD"
  echo "HTTP_PROXY_STATE: $(_state HTTP_PROXY)"
  printf 'ARG:%s\n' "$@"
  echo "STDIN_BEGIN"
  echo "$STDIN_CONTENT"
} > "$BACKEND_MOCK_DUMP"
echo "APPROVE"
echo "mock verdict"
MOCK
    chmod +x "$dir/$name"
    echo "$dir"
}

test_call_backend_claude_cmd() {
    source_workflow_funcs
    local dir result dump
    dir=$(_make_mock_backend claude)
    export BACKEND_MOCK_DUMP="$TMP_DIR/dump-claude-$RANDOM.txt"
    mkdir -p "$TMP_DIR/run-cwd"
    result=$(PATH="$dir:$PATH" SPARRING_CLAUDE_MODEL="test-model" \
        HTTP_PROXY="http://127.0.0.1:7897" \
        _call_backend claude "请审查 X" "$TMP_DIR/run-cwd" 2>/dev/null)
    dump=$(cat "$BACKEND_MOCK_DUMP" 2>/dev/null)

    assert_contains "返回裁决文本" "APPROVE" "$result"
    assert_contains "非交互 print 模式" "ARG:-p" "$dump"
    assert_contains "text 输出格式" "ARG:--output-format" "$dump"
    assert_contains "预批 Bash + 只读工具" "ARG:Bash Read Grep Glob" "$dump"
    assert_contains "禁写类/联网工具" "ARG:Edit Write NotebookEdit Task WebFetch WebSearch" "$dump"
    assert_contains "传 --model" "ARG:--model" "$dump"
    assert_contains "model 值正确" "ARG:test-model" "$dump"
    assert_contains "在传入的 cwd 里跑" "PWD: $TMP_DIR/run-cwd" "$dump"
    assert_contains "清空 HTTP_PROXY" "HTTP_PROXY_STATE: EMPTY" "$dump"
    assert_contains "prompt 走 stdin：含角色约定" "严格的 code reviewer" "$dump"
    assert_contains "prompt 走 stdin：含调用方内容" "请审查 X" "$dump"
    unset BACKEND_MOCK_DUMP HTTP_PROXY
}
test_call_backend_claude_cmd

test_call_backend_opencode_cmd() {
    source_workflow_funcs
    local dir result dump
    dir=$(_make_mock_backend opencode)
    export BACKEND_MOCK_DUMP="$TMP_DIR/dump-oc-$RANDOM.txt"
    mkdir -p "$TMP_DIR/run-cwd"
    result=$(PATH="$dir:$PATH" SPARRING_OPENCODE_MODEL="prov/some-model" \
        _call_backend opencode "请审查 Y" "$TMP_DIR/run-cwd" 2>/dev/null)
    dump=$(cat "$BACKEND_MOCK_DUMP" 2>/dev/null)

    assert_contains "返回裁决文本" "APPROVE" "$result"
    assert_contains "走 run 子命令" "ARG:run" "$dump"
    assert_contains "指定 plan agent" "ARG:--agent" "$dump"
    assert_contains "agent 名是 plan" "ARG:plan" "$dump"
    assert_contains "传 -m 模型" "ARG:-m" "$dump"
    assert_contains "model 值正确" "ARG:prov/some-model" "$dump"
    assert_contains "prompt 走 stdin" "请审查 Y" "$dump"
    # plan agent 默认只读，加 --auto 会把编辑权限打开
    assert_not_contains "绝不带 --auto" "ARG:--auto" "$dump"
    unset BACKEND_MOCK_DUMP
}
test_call_backend_opencode_cmd

test_call_backend_no_model_flag_when_unset() {
    source_workflow_funcs
    local dir dump
    dir=$(_make_mock_backend opencode)
    export BACKEND_MOCK_DUMP="$TMP_DIR/dump-oc-nomodel-$RANDOM.txt"
    PATH="$dir:$PATH" _call_backend opencode "p" "$TMP_DIR" >/dev/null 2>&1
    dump=$(cat "$BACKEND_MOCK_DUMP" 2>/dev/null)
    # model 留空 = 用 CLI 自己的默认模型，不能硬塞一个 -m
    assert_not_contains "未配 model 时不传 -m" "ARG:-m" "$dump"
    unset BACKEND_MOCK_DUMP
}
test_call_backend_no_model_flag_when_unset

test_call_backend_empty_cwd_when_not_given() {
    source_workflow_funcs
    local dir dump
    dir=$(_make_mock_backend claude)
    export BACKEND_MOCK_DUMP="$TMP_DIR/dump-nocwd-$RANDOM.txt"
    PATH="$dir:$PATH" _call_backend claude "p" "" >/dev/null 2>&1
    dump=$(cat "$BACKEND_MOCK_DUMP" 2>/dev/null)
    # 不给 cwd（文本审查）时跑在临时空目录里，不能落到当前项目目录
    assert_contains "文本模式跑在临时空目录" "PWD: .*sparring-review-cwd" "$dump"
    unset BACKEND_MOCK_DUMP
}
test_call_backend_empty_cwd_when_not_given

test_call_backend_empty_output_fails() {
    source_workflow_funcs
    local dir status=0
    dir="$TMP_DIR/mock-empty-$RANDOM"
    mkdir -p "$dir"
    printf '#!/bin/bash\ncat > /dev/null\nexit 0\n' > "$dir/claude"
    chmod +x "$dir/claude"
    PATH="$dir:$PATH" _call_backend claude "p" "$TMP_DIR" >/dev/null 2>&1 || status=$?
    assert_eq "后端返回空 → 当调用错误" "1" "$status"
}
test_call_backend_empty_output_fails

echo ""
echo "=== _strip_agent_noise (裁决解析鲁棒性) ==="

test_strip_ansi_and_header() {
    source_workflow_funcs
    local raw out
    # 模拟 opencode 接 TTY 时的输出：ANSI 复位码 + "> plan · model" 头行 + 裁决前的裸 ESC
    raw=$(printf '\033[0m\n> plan · k3\n\033[0m\033[1mCONCERNS\033[0m\n\n1. 有问题\n')
    out=$(printf '%s\n' "$raw" | _strip_agent_noise)
    assert_eq "剥噪音后首行就是裁决词" "CONCERNS" "$(printf '%s\n' "$out" | head -1)"
    assert_eq "裁决能被首列严格匹配解析出" "CONCERNS" \
        "$(printf '%s\n' "$out" | grep -m1 -oE '^(APPROVE|CONCERNS)')"
    assert_contains "正文保留" "1. 有问题" "$out"
}
test_strip_ansi_and_header

test_strip_keeps_plain_text() {
    source_workflow_funcs
    local out
    out=$(printf 'APPROVE\n\n理由：改动很小\n' | _strip_agent_noise)
    assert_eq "干净输出原样通过" "APPROVE" "$(printf '%s\n' "$out" | head -1)"
    assert_contains "正文不丢" "理由：改动很小" "$out"
}
test_strip_keeps_plain_text

echo ""
echo "=== _review_run 裁决 → 退出码 ==="

_review_run_status() {
    # 用 mock 的 call_reviewer 输出跑一遍 _review_run，回退出码
    local reviewer_output="$1"
    call_reviewer() { printf '%s\n' "$reviewer_output"; }
    local status=0
    XDG_STATE_HOME="$TMP_DIR/state" _review_run "p" "" "t" text "" 1 >/dev/null 2>&1 || status=$?
    echo "$status"
}

test_review_run_approve_exit0() {
    source_workflow_funcs
    assert_eq "APPROVE → exit 0" "0" "$(_review_run_status 'APPROVE

理由')"
}
test_review_run_approve_exit0

test_review_run_concerns_exit2() {
    source_workflow_funcs
    assert_eq "CONCERNS → exit 2" "2" "$(_review_run_status 'CONCERNS

1. 有问题')"
}
test_review_run_concerns_exit2

test_review_run_verdict_after_narration() {
    source_workflow_funcs
    # agent 式 review 常在裁决前先叙述一句（实测 opencode 会），裁决词仍在某行首列
    assert_eq "叙述在前、裁决在后仍能解析" "0" "$(_review_run_status '我先看了 git diff，再核对了调用方。
APPROVE

改动没问题')"
}
test_review_run_verdict_after_narration

test_review_run_no_verdict_exit1() {
    source_workflow_funcs
    # 解析不出裁决绝不默认放行
    assert_eq "无裁决 → exit 1（不放行）" "1" "$(_review_run_status '这个改动看起来还行吧，approve 了。')"
}
test_review_run_no_verdict_exit1

test_review_run_backend_failure_propagates() {
    source_workflow_funcs
    call_reviewer() { return 1; }
    local status=0
    XDG_STATE_HOME="$TMP_DIR/state" _review_run "p" "" "t" text "" 1 >/dev/null 2>&1 || status=$?
    assert_eq "后端调用失败 → exit 1" "1" "$status"
}
test_review_run_backend_failure_propagates

echo ""
echo "=== call_reviewer fallback behavior ==="

test_call_reviewer_fallback_triggers() {
    source_workflow_funcs
    # 主 backend 失败 → 备 backend 成功 → 应返回备的结果
    _call_backend() {
        local backend="$1"
        if [[ "$backend" == "claude" ]]; then
            echo "claude failed" >&2
            return 1
        fi
        if [[ "$backend" == "opencode" ]]; then
            echo "APPROVE from opencode"
            return 0
        fi
        return 1
    }

    local result
    result=$(WORKFLOW_REVIEW_BACKEND=claude WORKFLOW_REVIEW_BACKEND_FALLBACK=opencode \
        call_reviewer "test prompt" "" 2>/dev/null)
    assert_eq "primary 失败时降级到 opencode" "APPROVE from opencode" "$result"
}
test_call_reviewer_fallback_triggers

test_call_reviewer_passes_cwd_through() {
    source_workflow_funcs
    # run_cwd 必须原样透到后端，否则快照白建了
    _call_backend() {
        echo "APPROVE cwd=$3"
        return 0
    }
    local result
    result=$(WORKFLOW_REVIEW_BACKEND=claude call_reviewer "p" "/tmp/some-snapshot" 2>/dev/null)
    assert_eq "run_cwd 透传给后端" "APPROVE cwd=/tmp/some-snapshot" "$result"
}
test_call_reviewer_passes_cwd_through

test_call_reviewer_no_fallback_fails() {
    source_workflow_funcs
    _call_backend() {
        echo "failed" >&2
        return 1
    }

    local status=0
    WORKFLOW_REVIEW_BACKEND=claude SPARRING_REVIEW_FALLBACK=" " \
        call_reviewer "p" "" >/dev/null 2>&1 || status=$?
    assert_eq "无 fallback，主失败 → 非零" "1" "$status"
}
test_call_reviewer_no_fallback_fails

test_call_reviewer_primary_success_skips_fallback() {
    source_workflow_funcs
    local fallback_called=0
    _call_backend() {
        local backend="$1"
        if [[ "$backend" == "claude" ]]; then
            echo "APPROVE from claude"
            return 0
        fi
        fallback_called=1
        return 0
    }

    local result
    result=$(WORKFLOW_REVIEW_BACKEND=claude WORKFLOW_REVIEW_BACKEND_FALLBACK=opencode \
        call_reviewer "p" "" 2>/dev/null)
    assert_eq "primary 成功就返回 primary 结果" "APPROVE from claude" "$result"
    assert_eq "primary 成功不碰 fallback" "0" "$fallback_called"
}
test_call_reviewer_primary_success_skips_fallback

test_call_reviewer_same_primary_fallback() {
    source_workflow_funcs
    _call_backend() {
        return 1
    }

    local status=0
    WORKFLOW_REVIEW_BACKEND=claude WORKFLOW_REVIEW_BACKEND_FALLBACK=claude \
        call_reviewer "p" "" >/dev/null 2>&1 || status=$?
    assert_eq "主备相同 — 不多试一次直接失败" "1" "$status"
}
test_call_reviewer_same_primary_fallback

echo ""
echo "=== _agent_attempts ==="

test_agent_attempts_default() {
    source_workflow_funcs
    local attempts
    attempts=$(SPARRING_REVIEW_RETRIES=1 _agent_attempts)
    assert_eq "RETRIES=1 → 2 次尝试" "2" "$attempts"
}
test_agent_attempts_default

test_agent_attempts_zero_retries() {
    source_workflow_funcs
    local attempts
    attempts=$(SPARRING_REVIEW_RETRIES=0 _agent_attempts)
    assert_eq "RETRIES=0 → 1 次尝试（不重试）" "1" "$attempts"
}
test_agent_attempts_zero_retries

test_agent_attempts_multi() {
    source_workflow_funcs
    local attempts
    attempts=$(SPARRING_REVIEW_RETRIES=3 _agent_attempts)
    assert_eq "RETRIES=3 → 4 次尝试" "4" "$attempts"
}
test_agent_attempts_multi

echo ""
echo "=== _config_get 四层优先级 ==="

test_config_defaults() {
    source_workflow_funcs
    # 无 global / project / env → 读默认
    local backend timeout
    backend=$(_config_get review.backend)
    timeout=$(_config_get review.timeout)
    assert_eq "默认 backend=claude" "claude" "$backend"
    assert_eq "默认 timeout=1800" "1800" "$timeout"
}
test_config_defaults

test_flat_timeout_ignores_content_size() {
    source_workflow_funcs
    # 超时是扁平的：不管送审内容多大，_agent_timeout 只认配置值
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"review":{"timeout":45}}' > "$CONFIG_FILE_GLOBAL"
    assert_eq "超时只读配置值" "45" "$(_agent_timeout)"
    rm -f "$CONFIG_FILE_GLOBAL"
    assert_eq "env 覆盖超时" "900" "$(SPARRING_REVIEW_TIMEOUT=900 _agent_timeout)"
}
test_flat_timeout_ignores_content_size

test_config_global_overrides_default() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"review":{"backend":"opencode","timeout":45}}' > "$CONFIG_FILE_GLOBAL"
    local backend timeout
    backend=$(_config_get review.backend)
    timeout=$(_config_get review.timeout)
    assert_eq "global 覆盖默认 backend" "opencode" "$backend"
    assert_eq "global 覆盖默认 timeout" "45" "$timeout"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_global_overrides_default

test_config_project_overrides_global() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL" "$CONFIG_DIR_PROJECT"
    echo '{"review":{"backend":"claude"}}' > "$CONFIG_FILE_GLOBAL"
    echo '{"review":{"backend":"opencode"}}' > "$CONFIG_FILE_PROJECT"
    local backend
    backend=$(_config_get review.backend)
    assert_eq "project 覆盖 global" "opencode" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL" "$CONFIG_FILE_PROJECT"
}
test_config_project_overrides_global

test_config_sparring_env_highest() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL" "$CONFIG_DIR_PROJECT"
    echo '{"review":{"backend":"claude"}}' > "$CONFIG_FILE_GLOBAL"
    echo '{"review":{"backend":"opencode"}}' > "$CONFIG_FILE_PROJECT"
    local backend
    backend=$(SPARRING_REVIEW_BACKEND=claude _config_get review.backend)
    assert_eq "SPARRING_* env 最高优先级" "claude" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL" "$CONFIG_FILE_PROJECT"
}
test_config_sparring_env_highest

test_config_workflow_env_fallback() {
    source_workflow_funcs
    # SPARRING_* 未设，WORKFLOW_* 应该生效
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=opencode _config_get review.backend)
    assert_eq "WORKFLOW_* 兼容别名" "opencode" "$backend"
}
test_config_workflow_env_fallback

test_config_sparring_wins_over_workflow() {
    source_workflow_funcs
    local backend
    backend=$(SPARRING_REVIEW_BACKEND=claude WORKFLOW_REVIEW_BACKEND=opencode \
        _config_get review.backend)
    assert_eq "SPARRING_* 优先于 WORKFLOW_*" "claude" "$backend"
}
test_config_sparring_wins_over_workflow

test_config_legacy_alias_fallback() {
    source_workflow_funcs
    # 历史变量：WORKFLOW_REVIEW_BACKEND_FALLBACK → review.fallback
    local fb
    fb=$(WORKFLOW_REVIEW_BACKEND_FALLBACK=claude _config_get review.fallback)
    assert_eq "WORKFLOW_REVIEW_BACKEND_FALLBACK legacy 别名" "claude" "$fb"
}
test_config_legacy_alias_fallback

test_config_malformed_file() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo 'not valid json {' > "$CONFIG_FILE_GLOBAL"
    local backend
    backend=$(_config_get review.backend 2>/dev/null)
    # 格式错的文件被忽略，应该回退到默认
    assert_eq "非法 JSON 文件回退到默认" "claude" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_malformed_file

test_config_nested_merge() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL" "$CONFIG_DIR_PROJECT"
    # global 设 claude.model，project 设 claude.extra_args → 应该合并不是覆盖
    echo '{"claude":{"model":"global-model"}}' > "$CONFIG_FILE_GLOBAL"
    echo '{"claude":{"extra_args":"--verbose"}}' > "$CONFIG_FILE_PROJECT"
    local model extra
    model=$(_config_get claude.model)
    extra=$(_config_get claude.extra_args)
    assert_eq "递归合并保留 global.claude.model" "global-model" "$model"
    assert_eq "递归合并加上 project.claude.extra_args" "--verbose" "$extra"
    rm -f "$CONFIG_FILE_GLOBAL" "$CONFIG_FILE_PROJECT"
}
test_config_nested_merge

echo ""
echo "=== config 子命令 ==="

test_config_init_global() {
    source_workflow_funcs
    rm -f "$CONFIG_FILE_GLOBAL"
    config_init >/dev/null 2>&1
    assert_file_exists "global config 创建" "$CONFIG_FILE_GLOBAL"
    # 检查 chmod 600
    local perms
    perms=$(stat -f %A "$CONFIG_FILE_GLOBAL" 2>/dev/null || stat -c %a "$CONFIG_FILE_GLOBAL" 2>/dev/null)
    assert_eq "global config chmod 600" "600" "$perms"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_init_global

test_config_init_project() {
    source_workflow_funcs
    rm -rf "$CONFIG_DIR_PROJECT"
    config_init project >/dev/null 2>&1
    assert_file_exists "project config 创建" "$CONFIG_FILE_PROJECT"
    assert_file_exists "project .gitignore 创建" "$CONFIG_DIR_PROJECT/.gitignore"
    # 项目级不该替开发者选后端/模型
    local has_backend
    has_backend=$(jq -r '.review | has("backend")' "$CONFIG_FILE_PROJECT")
    assert_eq "project config 不应设 review.backend" "false" "$has_backend"
    rm -rf "$CONFIG_DIR_PROJECT"
}
test_config_init_project

test_config_init_existing_no_force() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"review":{"backend":"opencode"}}' > "$CONFIG_FILE_GLOBAL"
    config_init >/dev/null 2>&1
    # 文件未被覆盖
    local backend
    backend=$(jq -r '.review.backend' "$CONFIG_FILE_GLOBAL")
    assert_eq "已存在时不覆盖" "opencode" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_init_existing_no_force

test_config_has_no_secret_fields() {
    source_workflow_funcs
    # 两个后端都靠各自 CLI 的登录态，sparring 配置里不该再出现任何 key/token 字段
    local secrets
    secrets=$(_config_defaults | jq -r '[paths(scalars) | join(".")] | map(select(test("api_key|token|secret"))) | length')
    assert_eq "默认配置无 secret 字段" "0" "$secrets"
}
test_config_has_no_secret_fields

test_config_init_project_preserves_gitignore() {
    # Sparring CONCERN 1: config init project 不应覆盖已有的 .gitignore
    source_workflow_funcs
    rm -rf "$CONFIG_DIR_PROJECT"
    mkdir -p "$CONFIG_DIR_PROJECT"
    cat > "$CONFIG_DIR_PROJECT/.gitignore" <<'EOF'
# 用户现有规则
*.log
tmp/
EOF
    config_init project >/dev/null 2>&1
    # 原有规则必须保留
    assert_contains "原有 *.log 规则保留" "\*\.log" "$(cat "$CONFIG_DIR_PROJECT/.gitignore")"
    assert_contains "原有 tmp/ 规则保留" "tmp/" "$(cat "$CONFIG_DIR_PROJECT/.gitignore")"
    # 新规则也追加进去
    assert_contains "新增 *.local.json 规则" "\*\.local\.json" "$(cat "$CONFIG_DIR_PROJECT/.gitignore")"
    rm -rf "$CONFIG_DIR_PROJECT"
}
test_config_init_project_preserves_gitignore

test_config_init_project_no_secrets_file_mention() {
    # Sparring CONCERN 2: .gitignore 模板不应误导用户以为 secrets.json 会被读取
    source_workflow_funcs
    rm -rf "$CONFIG_DIR_PROJECT"
    config_init project >/dev/null 2>&1
    # 不应在 config.json 或 .gitignore 里出现显式的 secrets.json 引用（避免误导）
    if grep -q "^secrets\.json$" "$CONFIG_DIR_PROJECT/.gitignore" 2>/dev/null; then
        echo "  ✗ .gitignore 仍显式提 secrets.json（误导）"
        ((FAIL++))
    else
        echo "  ✓ .gitignore 不再显式提 secrets.json"
        ((PASS++))
    fi
    # 项目 config.json 注释必须说清后端/模型由个人全局配置决定
    local comment
    comment=$(jq -r '._comment // ""' "$CONFIG_FILE_PROJECT")
    assert_contains "项目 config 注释说明不要设 backend" "review.backend" "$comment"
    rm -rf "$CONFIG_DIR_PROJECT"
}
test_config_init_project_no_secrets_file_mention

test_config_read_file_warns_once() {
    # Sparring CONCERN 3: 非法 JSON 的告警在同一进程只出现一次
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo 'not valid json {' > "$CONFIG_FILE_GLOBAL"
    # 调用多次 _config_get，触发多次读
    local err_output
    err_output=$({ _config_get review.backend; _config_get review.timeout; _config_get claude.model; } 2>&1 >/dev/null)
    local warn_count
    warn_count=$(echo "$err_output" | grep -c "配置文件格式错误")
    assert_eq "非法 JSON 只告警一次" "1" "$warn_count"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_read_file_warns_once

echo ""
echo "=== commands/ frontmatter ==="

test_commands_frontmatter() {
    for cmd_file in "$PROJECT_DIR"/commands/*.md; do
        local name
        name=$(basename "$cmd_file")
        local has_frontmatter
        has_frontmatter=$(head -1 "$cmd_file")
        assert_eq "$name has frontmatter" "---" "$has_frontmatter"

        local has_description
        has_description=$(grep -c "^description:" "$cmd_file" || true)
        assert_eq "$name has description" "1" "$has_description"
    done
}
test_commands_frontmatter

echo ""
echo "=== workflow help ==="

test_help_runs() {
    local output
    output=$(bash "$WORKFLOW" help 2>&1)
    assert_contains "help shows setup" "setup" "$output"
    assert_contains "help shows workflow commands" "review-proposal" "$output"
    assert_contains "help shows background review command" "review-proposal-bg" "$output"
    assert_contains "help shows review job status command" "review-status" "$output"
    assert_contains "help shows issue commands" "issue-poll" "$output"
}
test_help_runs

echo ""
echo "=== sparring verify (syntax only) ==="

test_syntax() {
    bash -n "$WORKFLOW" 2>&1
    assert_eq "sparring script syntax valid" "0" "$?"

    if [[ -f "$PROJECT_DIR/bin/setup" ]]; then
        bash -n "$PROJECT_DIR/bin/setup" 2>&1
        assert_eq "setup script syntax valid" "0" "$?"
    fi
}
test_syntax

echo ""
echo "=== sparring / workflow 兼容别名 ==="

test_workflow_symlink_exists() {
    assert_file_exists "bin/workflow 软链存在" "$PROJECT_DIR/bin/workflow"
    # 必须是软链，而不是文件副本
    if [[ -L "$PROJECT_DIR/bin/workflow" ]]; then
        echo "  ✓ bin/workflow 是软链（防止重复代码）"
        ((PASS++))
    else
        echo "  ✗ bin/workflow 应该是软链，不是文件"
        ((FAIL++))
    fi
}
test_workflow_symlink_exists

test_workflow_and_sparring_same_output() {
    # 调两个命令的 help，输出应该一致
    local out_sparring out_workflow
    out_sparring=$(bash "$PROJECT_DIR/bin/sparring" help 2>&1 | wc -l | tr -d ' ')
    out_workflow=$(bash "$PROJECT_DIR/bin/workflow" help 2>&1 | wc -l | tr -d ' ')
    assert_eq "workflow 软链和 sparring 输出行数一致" "$out_sparring" "$out_workflow"
}
test_workflow_and_sparring_same_output

test_help_shows_sparring_usage() {
    local output
    output=$(bash "$WORKFLOW" help 2>&1)
    assert_contains "help 标题用 Sparring" "Sparring" "$output"
    assert_contains "help 用法提示 sparring" "sparring <command>" "$output"
    assert_contains "help 提到 workflow 兼容别名" "兼容别名" "$output"
}
test_help_shows_sparring_usage

test_setup_exec_uses_resolve_script_dir() {
    # Sparring CONCERN 1 源码断言：sparring 的 setup dispatch 必须用 _resolve_script_dir
    # 不能用 $(cd "$(dirname "$0")" && pwd)/setup（会把 global symlink 目录当根）
    # 做法：直接扫源码，不 exec 真 setup（避免污染环境、消耗 API 配额）
    local setup_line
    setup_line=$(grep -E 'setup\).*exec bash' "$WORKFLOW" | head -1)
    if echo "$setup_line" | grep -q '_resolve_script_dir.*bin/setup'; then
        echo "  ✓ setup exec 使用 _resolve_script_dir（支持全局软链调用）"
        ((PASS++))
    else
        echo "  ✗ setup exec 未使用 _resolve_script_dir"
        echo "    line: $setup_line"
        ((FAIL++))
    fi
}
test_setup_exec_uses_resolve_script_dir

test_setup_rejects_non_tty() {
    # bin/setup 没有 TTY 时应立刻 exit 2，不能误触发完整 setup
    local output status=0
    output=$(bash "$PROJECT_DIR/bin/setup" </dev/null 2>&1) || status=$?
    assert_eq "非 TTY 时 setup exit 2" "2" "$status"
    assert_contains "错误信息提示 TTY 要求" "TTY" "$output"
}
test_setup_rejects_non_tty

test_setup_help_quick_path() {
    # sparring setup --help 必须是 quick path，不进入交互流程
    local output status=0
    output=$(bash "$PROJECT_DIR/bin/setup" --help </dev/null 2>&1) || status=$?
    assert_eq "setup --help 正常退出" "0" "$status"
    assert_contains "setup --help 打印用法" "用法" "$output"
    # 确保没打 verify 或 install 相关副作用信息
    if echo "$output" | grep -qE "安装|验证|检查"; then
        # 允许列出功能步骤中提到，但不应有实际执行提示
        if echo "$output" | grep -qE "^(正在|✓|已安装)"; then
            echo "  ✗ setup --help 有执行副作用"
            ((FAIL++))
        else
            echo "  ✓ setup --help 无副作用"
            ((PASS++))
        fi
    else
        echo "  ✓ setup --help 无副作用"
        ((PASS++))
    fi
}
test_setup_help_quick_path

echo ""
echo "=== E2E 回归（来自 QA report） ==="

test_sparring_no_args_no_crash() {
    # Bug P1#1: 无参数时 bash 3.2 + set -u 崩在 set -- "${args[@]}"
    local output status=0
    output=$(bash "$WORKFLOW" </dev/null 2>&1) || status=$?
    # 空 args 时应退化到 help，不能 exit!=0 也不能含 unbound
    if echo "$output" | grep -q 'unbound variable'; then
        echo "  ✗ 无参数时仍报 unbound variable"
        ((FAIL++))
    else
        echo "  ✓ 无参数不崩（args[@] 空数组守卫生效）"
        ((PASS++))
    fi
    # 预期 command 默认 fallback 到 help，exit 0
    assert_eq "无参数 exit=0（走 help 分支）" "0" "$status"
}
test_sparring_no_args_no_crash

test_help_no_raw_ansi_literal() {
    # Bug P1#2: help 用 heredoc 输出时，'\033' 会字面量显示
    local out_file="$TMP_DIR/help-out.txt"
    bash "$WORKFLOW" help >"$out_file" 2>&1

    # 字面量 \033（反斜杠+033）应 0 次出现
    # grep -c 找不到会 exit 1，用 set +e 保护
    set +e
    local raw_count
    raw_count=$(grep -c '\\033' "$out_file")
    [[ -z "$raw_count" ]] && raw_count=0
    set -e 2>/dev/null || true
    assert_eq "help 输出无字面 \\\\033" "0" "$raw_count"

    # 真 ESC 字节（0x1b）应存在
    if LC_ALL=C grep -q $'\x1b\\[' "$out_file" 2>/dev/null; then
        echo "  ✓ help 含真 ESC 字节"
        ((PASS++))
    else
        echo "  ✗ help 未含 ESC 字节"
        ((FAIL++))
    fi
}
test_help_no_raw_ansi_literal

test_invalid_backend_env_rejected_early() {
    # Bug P2#3: SPARRING_REVIEW_BACKEND=<bogus> 应在 main() 入口就拒绝，exit 1
    local output status=0
    output=$(SPARRING_REVIEW_BACKEND=nonexistent bash "$WORKFLOW" config show </dev/null 2>&1) || status=$?
    assert_eq "非法 SPARRING_REVIEW_BACKEND exit=1" "1" "$status"
    assert_contains "错误信息含 backend 名字" "nonexistent" "$output"
    assert_contains "错误信息提示合法值" "claude / opencode" "$output"
}
test_invalid_backend_env_rejected_early

test_invalid_fallback_env_rejected_early() {
    local output status=0
    output=$(WORKFLOW_REVIEW_BACKEND_FALLBACK=bogus bash "$WORKFLOW" config show </dev/null 2>&1) || status=$?
    assert_eq "非法 WORKFLOW_REVIEW_BACKEND_FALLBACK exit=1" "1" "$status"
    assert_contains "错误信息含字段名" "FALLBACK" "$output"
}
test_invalid_fallback_env_rejected_early

test_config_path_env_overridable() {
    # Bug P2#6: CONFIG_DIR_GLOBAL / CONFIG_FILE_GLOBAL 环境变量应能覆盖默认路径
    local output
    output=$(CONFIG_FILE_GLOBAL=/tmp/sparring-test-override.json \
             bash "$WORKFLOW" config path </dev/null 2>&1)
    assert_contains "CONFIG_FILE_GLOBAL 注入生效" "/tmp/sparring-test-override.json" "$output"
}
test_config_path_env_overridable

test_config_init_handles_missing_parent_dir() {
    # Sparring CONCERN 2: 只注入 CONFIG_FILE_GLOBAL（父目录不存在时）
    # config init 应能创建父目录，不能因 mkdir 路径不对而失败
    local deep="$TMP_DIR/deep-nested/parent-dir/config.json"
    rm -rf "$TMP_DIR/deep-nested"
    local rc=0
    CONFIG_FILE_GLOBAL="$deep" \
    CONFIG_DIR_GLOBAL="$(dirname "$deep")" \
    bash "$WORKFLOW" config init </dev/null >/dev/null 2>&1 || rc=$?
    assert_eq "config init 嵌套父目录不存在时 exit=0" "0" "$rc"
    assert_file_exists "config 文件按 CONFIG_FILE_GLOBAL 写入" "$deep"
}
test_config_init_handles_missing_parent_dir

test_config_init_file_only_override() {
    # 用户只设 CONFIG_FILE_GLOBAL 不设 CONFIG_DIR_GLOBAL 也应能工作
    local only_file="$TMP_DIR/file-only/my-config.json"
    rm -rf "$TMP_DIR/file-only"
    local rc=0
    CONFIG_FILE_GLOBAL="$only_file" \
    bash "$WORKFLOW" config init </dev/null >/dev/null 2>&1 || rc=$?
    assert_eq "config init 仅覆盖 FILE 时 exit=0" "0" "$rc"
    assert_file_exists "config 文件按 FILE 写入" "$only_file"
}
test_config_init_file_only_override

test_config_init_help_supported() {
    # Bug P2#5: config init --help 应当打印用法，不报"未知选项"
    local output status=0
    output=$(bash "$WORKFLOW" config init --help </dev/null 2>&1) || status=$?
    assert_eq "config init --help exit=0" "0" "$status"
    assert_contains "config init --help 含用法" "sparring config" "$output"
    # 不能进入实际 init 流程（不写文件）
    if echo "$output" | grep -q '未知选项'; then
        echo "  ✗ config init --help 仍报未知选项"
        ((FAIL++))
    else
        echo "  ✓ config init --help 被正确识别"
        ((PASS++))
    fi
}
test_config_init_help_supported

test_config_cmd_help_alias() {
    # 支持 sparring config --help / sparring config -h / sparring config help
    local o1 o2 o3
    o1=$(bash "$WORKFLOW" config --help 2>&1)
    o2=$(bash "$WORKFLOW" config -h 2>&1)
    o3=$(bash "$WORKFLOW" config help 2>&1)
    assert_contains "config --help 正常" "子命令" "$o1"
    assert_contains "config -h 正常" "子命令" "$o2"
    assert_contains "config help 正常" "子命令" "$o3"
}
test_config_cmd_help_alias

test_verify_returns_nonzero_on_failure() {
    # Bug P2#4: verify 里有失败后端时，最后应 return 1，不是只打印 ✗
    # 用一个"装了但一调就失败"的假 claude 触发连通性失败；fallback 设成同一个后端，
    # verify 会跳过备份检查 → 整个用例不碰网络。
    local shim rc=0
    shim="$TMP_DIR/verify-shim-$RANDOM"
    mkdir -p "$shim"
    printf '#!/bin/bash\necho "boom" >&2\nexit 1\n' > "$shim/claude"
    chmod +x "$shim/claude"
    PATH="$shim:$PATH" \
    SPARRING_REVIEW_BACKEND=claude \
    SPARRING_REVIEW_FALLBACK=claude \
    SPARRING_REVIEW_TIMEOUT=5 \
    bash "$WORKFLOW" verify >/dev/null 2>&1 || rc=$?
    # 预期非 0（连通性必然失败）
    if [[ $rc -eq 0 ]]; then
        echo "  ✗ verify 主 backend 失败时 exit=0（应该 !=0）"
        ((FAIL++))
    else
        echo "  ✓ verify 主 backend 失败时 exit=${rc}（非 0）"
        ((PASS++))
    fi
}
test_verify_returns_nonzero_on_failure

test_resolve_script_dir_via_symlink() {
    # 软链解析必须指向 repo 根，无论从哪调
    source_workflow_funcs
    local fake_bin="$TMP_DIR/fake-chain"
    mkdir -p "$fake_bin"
    ln -sf "$PROJECT_DIR/bin/sparring" "$fake_bin/sparring"
    # 在 subshell 里模拟以软链为 $0 调用
    local resolved
    resolved=$(bash -c '
        _resolve_script_dir() {
            local src="$0"
            while [[ -L "$src" ]]; do
                local dir
                dir=$(cd -P "$(dirname "$src")" && pwd)
                src=$(readlink "$src")
                [[ "$src" != /* ]] && src="$dir/$src"
            done
            cd -P "$(dirname "$src")/.." && pwd
        }
        _resolve_script_dir
    ' "$fake_bin/sparring")
    assert_eq "通过软链 _resolve_script_dir 回到 repo 根" "$PROJECT_DIR" "$resolved"
}
test_resolve_script_dir_via_symlink

echo ""
echo "=== find_project_root (worktree 支持) ==="

test_find_project_root_in_git_repo() {
    source_workflow_funcs
    local fake_repo="$TMP_DIR/fake-repo"
    mkdir -p "$fake_repo/sub/deep"
    git -C "$fake_repo" init -q
    git -C "$fake_repo" commit --allow-empty -m "init" -q 2>/dev/null || true

    # macOS $TMPDIR is a symlink (/var/folders → /private/var/folders); resolve both sides
    local real_repo root real_root
    real_repo=$(cd "$fake_repo" && pwd -P)
    root=$(cd "$fake_repo/sub/deep" && find_project_root 2>/dev/null)
    real_root=$(cd "$root" && pwd -P)
    assert_eq "git 子目录能找到 repo 根" "$real_repo" "$real_root"
}
test_find_project_root_in_git_repo

test_find_project_root_workflow_fallback() {
    source_workflow_funcs
    # 非 git 目录，有 .workflow → fallback 到 .workflow 检测
    local non_git_dir="$TMP_DIR/not-a-repo"
    mkdir -p "$non_git_dir/.workflow"

    local root
    root=$(cd "$non_git_dir" && find_project_root 2>/dev/null)
    assert_eq ".workflow fallback 在非 git 目录生效" "$non_git_dir" "$root"
}
test_find_project_root_workflow_fallback

echo ""
echo "=== load_review_conventions ==="

test_load_review_conventions_none() {
    source_workflow_funcs
    local result
    result=$(load_review_conventions 2>/dev/null)
    assert_eq "项目/全局均无 REVIEW.md 时返回空" "" "$result"
}
test_load_review_conventions_none

test_load_review_conventions_project_level() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_PROJECT"
    printf '# 项目约定\n- 必须覆盖边界 case\n' > "$CONFIG_DIR_PROJECT/REVIEW.md"

    local result
    result=$(load_review_conventions 2>/dev/null)
    assert_contains "读到项目级 REVIEW.md" "项目约定" "$result"
}
test_load_review_conventions_project_level

test_load_review_conventions_global_fallback() {
    source_workflow_funcs
    rm -f "$CONFIG_DIR_PROJECT/REVIEW.md"   # 清掉上一个测试残留
    mkdir -p "$CONFIG_DIR_GLOBAL"
    printf '全局默认约定\n' > "$CONFIG_DIR_GLOBAL/REVIEW.md"

    local result
    result=$(load_review_conventions 2>/dev/null)
    assert_contains "无项目级时回退到全局 REVIEW.md" "全局默认约定" "$result"
}
test_load_review_conventions_global_fallback

test_load_review_conventions_project_wins() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_PROJECT" "$CONFIG_DIR_GLOBAL"
    printf '项目约定\n' > "$CONFIG_DIR_PROJECT/REVIEW.md"
    printf '全局约定\n' > "$CONFIG_DIR_GLOBAL/REVIEW.md"

    local result
    result=$(load_review_conventions 2>/dev/null)
    assert_contains "项目级 REVIEW.md 优先于全局" "项目约定" "$result"
    if echo "$result" | grep -q "全局约定"; then
        echo "  ✗ 全局内容不应出现"
        ((FAIL++))
    else
        echo "  ✓ 全局内容未混入"
        ((PASS++))
    fi
}
test_load_review_conventions_project_wins

echo ""
echo "=== --range 解析 ==="

test_range_right_ref() {
    source_workflow_funcs
    assert_eq "三点 range 取右端" "HEAD" "$(_range_right_ref 'origin/main...HEAD')"
    assert_eq "两点 range 取右端" "feature" "$(_range_right_ref 'main..feature')"
    assert_eq "带斜杠的分支名" "origin/release" "$(_range_right_ref 'main..origin/release')"
    assert_eq "tag 名" "v1.2.3" "$(_range_right_ref 'v1.0.0..v1.2.3')"
    assert_eq "右端为空 → HEAD" "HEAD" "$(_range_right_ref 'origin/main...')"
    assert_eq "两点右端为空 → HEAD" "HEAD" "$(_range_right_ref 'origin/main..')"
    # 单个 ref 不能当右端：`git diff <ref>` 比的是 ref→工作区，在快照里会是空 diff
    assert_eq "单 ref → 快照用 HEAD" "HEAD" "$(_range_right_ref 'HEAD~3')"
    assert_eq "空串 → HEAD" "HEAD" "$(_range_right_ref '')"
}
test_range_right_ref

echo ""
echo "=== worktree 快照生命周期 ==="

# 造一个有两个 commit 的临时 git 仓库
_make_fixture_repo() {
    local dir="$TMP_DIR/fixture-$RANDOM"
    mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        git init -q -b main
        printf 'line1\n' > f.txt
        git add -A && git -c user.email=t@t -c user.name=t commit -qm one
        printf 'line1\nline2\nline3\n' > f.txt
        git add -A && git -c user.email=t@t -c user.name=t commit -qm two
    ) >/dev/null 2>&1
    echo "$dir"
}

test_snapshot_create_and_cleanup() {
    source_workflow_funcs
    local repo snap
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1

    _REVIEW_SNAPSHOT=""
    _review_snapshot_create HEAD
    snap="$_REVIEW_SNAPSHOT"

    assert_eq "快照目录建出来了" "yes" "$([[ -d "$snap" ]] && echo yes || echo no)"
    assert_eq "快照里有仓库内容" "yes" "$([[ -f "$snap/f.txt" ]] && echo yes || echo no)"
    # 注意用 basename 比对：mktemp 给的是 /var/...，git worktree list 打的是解析后的 /private/var/...
    local snap_id
    snap_id=$(basename "$(dirname "$snap")")
    assert_contains "worktree 已登记" "$snap_id" "$(git worktree list)"
    # detached：不占用任何分支，审查期间主仓库照常切分支
    assert_contains "快照是 detached" "detached" "$(git worktree list | grep "$snap_id")"

    _review_snapshot_cleanup
    assert_eq "清理后目录消失" "no" "$([[ -d "$snap" ]] && echo yes || echo no)"
    assert_eq "worktree 登记也清掉" "0" "$(git worktree list | grep -c "$snap_id" || true)"
    assert_eq "清理后全局变量复位" "" "$_REVIEW_SNAPSHOT"

    cd "$PROJECT_DIR" || return 1
}
test_snapshot_create_and_cleanup

test_snapshot_cleanup_idempotent() {
    source_workflow_funcs
    local repo status=0
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1

    # 没建过快照时清理是 no-op
    _REVIEW_SNAPSHOT=""
    _review_snapshot_cleanup || status=$?
    assert_eq "没建过快照时清理不报错" "0" "$status"

    # 建了之后连续清理两次也不报错（trap + 显式清理会各调一次）
    _review_snapshot_create HEAD
    _review_snapshot_cleanup
    status=0
    _review_snapshot_cleanup || status=$?
    assert_eq "重复清理不报错" "0" "$status"

    cd "$PROJECT_DIR" || return 1
}
test_snapshot_cleanup_idempotent

test_snapshot_create_bad_ref_fails() {
    source_workflow_funcs
    local repo status=0
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1
    _REVIEW_SNAPSHOT=""
    _review_snapshot_create "no-such-ref" 2>/dev/null || status=$?
    assert_eq "ref 不存在 → 建快照失败" "1" "$status"
    assert_eq "失败时不留下半个快照" "" "$_REVIEW_SNAPSHOT"
    cd "$PROJECT_DIR" || return 1
}
test_snapshot_create_bad_ref_fails

test_range_changed_lines() {
    source_workflow_funcs
    local repo
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1
    # 第二个 commit：加了 2 行（line2/line3），改的是同一个文件
    assert_eq "统计 range 总变更行数" "2" "$(_range_changed_lines 'HEAD~1...HEAD')"
    cd "$PROJECT_DIR" || return 1
}
test_range_changed_lines

echo ""
echo "=== review 输入形态（diff 硬拒 / 参数冲突）==="

test_review_rejects_diff_git_stdin() {
    source_workflow_funcs
    local out status=0
    out=$(printf 'diff --git a/x.py b/x.py\nindex 111..222 100644\n--- a/x.py\n+++ b/x.py\n@@ -1 +1 @@\n-a\n+b\n' \
        | review_adhoc 2>&1) || status=$?
    assert_eq "diff --git 文本被拒" "1" "$status"
    assert_contains "提示改用 --range" "\-\-range" "$out"
}
test_review_rejects_diff_git_stdin

test_review_rejects_bare_unified_diff() {
    source_workflow_funcs
    local out status=0
    # 没有 `diff --git` 头的裸 unified diff（git diff --no-prefix 之外的工具产物）
    out=$(printf -- '--- a/x.py\n+++ b/x.py\n@@ -1 +1 @@\n-a\n+b\n' | review_adhoc 2>&1) || status=$?
    assert_eq "裸 unified diff 也被拒" "1" "$status"
    assert_contains "提示改用 --range" "\-\-range" "$out"
}
test_review_rejects_bare_unified_diff

test_review_accepts_plain_text_mentioning_diff() {
    source_workflow_funcs
    # 正文里提到 diff 但不是 diff 格式 → 不该被误拒（走到调后端那步就算过关）
    call_reviewer() { echo "APPROVE"; }
    local status=0
    printf '我们讨论一下 diff 的展示方式，行首没有 diff --git 标记。\n' \
        | XDG_STATE_HOME="$TMP_DIR/state" review_adhoc >/dev/null 2>&1 || status=$?
    assert_eq "普通文本提到 diff 不被误拒" "0" "$status"
}
test_review_accepts_plain_text_mentioning_diff

test_review_empty_input_fails() {
    source_workflow_funcs
    local status=0
    printf '' | review_adhoc >/dev/null 2>&1 || status=$?
    assert_eq "空输入报错" "1" "$status"
}
test_review_empty_input_fails

test_review_range_conflicts_with_text() {
    source_workflow_funcs
    local out status=0
    out=$(review_adhoc --range HEAD~1...HEAD "一段文本" 2>&1) || status=$?
    assert_eq "--range 和文本同时给 → 报错" "1" "$status"
    assert_contains "说明冲突原因" "不能同时给" "$out"
}
test_review_range_conflicts_with_text

test_review_range_needs_git_repo() {
    source_workflow_funcs
    local out status=0
    mkdir -p "$TMP_DIR/not-a-repo"
    cd "$TMP_DIR/not-a-repo" || return 1
    out=$(review_adhoc --range HEAD~1...HEAD 2>&1 </dev/null) || status=$?
    assert_eq "非 git 仓库里用 --range → 报错" "1" "$status"
    assert_contains "提示需要 git 仓库" "git 仓库" "$out"
    cd "$PROJECT_DIR" || return 1
}
test_review_range_needs_git_repo

test_review_range_invalid_range_fails() {
    source_workflow_funcs
    local repo out status=0
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1
    out=$(review_adhoc --range no-such-ref...HEAD 2>&1 </dev/null) || status=$?
    assert_eq "非法 range → 报错" "1" "$status"
    assert_contains "指出 range 无效" "无效的 git range" "$out"
    assert_eq "报错后不留 worktree" "1" "$(git worktree list | wc -l | tr -d ' ')"
    cd "$PROJECT_DIR" || return 1
}
test_review_range_invalid_range_fails

test_review_range_runs_in_snapshot_and_cleans_up() {
    source_workflow_funcs
    local repo captured_cwd
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1

    # mock 掉后端：记录 reviewer 拿到的 cwd，确认它是快照而不是原仓库
    captured_cwd="$TMP_DIR/captured-cwd-$RANDOM"
    call_reviewer() {
        printf '%s' "$2" > "$captured_cwd"
        echo "CONCERNS"
        echo "1. mock 问题"
    }

    local status=0
    XDG_STATE_HOME="$TMP_DIR/state" review_adhoc --range HEAD~1...HEAD >/dev/null 2>&1 </dev/null || status=$?
    assert_eq "CONCERNS → exit 2" "2" "$status"

    local cwd
    cwd=$(cat "$captured_cwd" 2>/dev/null)
    assert_contains "reviewer 跑在快照目录里" "sparring-snapshot" "$cwd"
    assert_eq "reviewer 不是跑在原仓库" "no" "$([[ "$cwd" == "$repo" ]] && echo yes || echo no)"
    assert_eq "审完快照目录已删" "no" "$([[ -d "$cwd" ]] && echo yes || echo no)"
    assert_eq "审完没有残留 worktree" "1" "$(git worktree list | wc -l | tr -d ' ')"

    cd "$PROJECT_DIR" || return 1
}
test_review_range_runs_in_snapshot_and_cleans_up

test_review_range_cleans_up_on_backend_failure() {
    source_workflow_funcs
    local repo
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1

    call_reviewer() { return 1; }

    local status=0
    XDG_STATE_HOME="$TMP_DIR/state" review_adhoc --range HEAD~1...HEAD >/dev/null 2>&1 </dev/null || status=$?
    assert_eq "后端失败 → exit 1" "1" "$status"
    assert_eq "失败路径同样清掉 worktree" "1" "$(git worktree list | wc -l | tr -d ' ')"

    cd "$PROJECT_DIR" || return 1
}
test_review_range_cleans_up_on_backend_failure

test_review_range_logs_mode_and_range() {
    source_workflow_funcs
    local repo state_home line
    repo=$(_make_fixture_repo)
    cd "$repo" || return 1
    state_home="$TMP_DIR/state-range-$RANDOM"

    call_reviewer() { echo "APPROVE"; echo "没问题"; }
    XDG_STATE_HOME="$state_home" review_adhoc --range HEAD~1...HEAD --title "范围审查" \
        >/dev/null 2>&1 </dev/null

    line=$(tail -1 "$state_home/sparring/review-$(date +%Y%m%d).jsonl")
    assert_eq "mode=range" "range" "$(echo "$line" | jq -r .mode)"
    assert_eq "range 字段记录 range 字符串" "HEAD~1...HEAD" "$(echo "$line" | jq -r .range)"
    assert_eq "input_lines 记 range 变更行数" "2" "$(echo "$line" | jq -r .input_lines)"
    assert_eq "verdict=APPROVE" "APPROVE" "$(echo "$line" | jq -r .verdict)"

    cd "$PROJECT_DIR" || return 1
}
test_review_range_logs_mode_and_range

test_review_text_logs_mode_text() {
    source_workflow_funcs
    local state_home line
    state_home="$TMP_DIR/state-text-$RANDOM"
    call_reviewer() { echo "APPROVE"; }
    echo "一段结论" | XDG_STATE_HOME="$state_home" review_adhoc --title "文本审查" >/dev/null 2>&1

    line=$(tail -1 "$state_home/sparring/review-$(date +%Y%m%d).jsonl")
    assert_eq "mode=text" "text" "$(echo "$line" | jq -r .mode)"
    assert_eq "text 模式 range 为 null" "null" "$(echo "$line" | jq -r .range)"
}
test_review_text_logs_mode_text

echo ""
echo "=== _timeout_cmd ==="

test_timeout_cmd_perl_fallback() {
    source_workflow_funcs
    # PATH 限制到 /usr/bin:/bin 逼出 perl fallback（macOS 无原生 timeout）
    if PATH="/usr/bin:/bin" command -v timeout >/dev/null 2>&1 \
        || PATH="/usr/bin:/bin" command -v gtimeout >/dev/null 2>&1; then
        echo "  - 跳过：/usr/bin:/bin 下存在 timeout，无法逼出 perl fallback"
        return 0
    fi
    if ! PATH="/usr/bin:/bin" command -v perl >/dev/null 2>&1; then
        echo "  - 跳过：/usr/bin:/bin 下无 perl，fallback 不可测"
        return 0
    fi

    local rc=0
    ( PATH="/usr/bin:/bin"; _timeout_cmd 1 sleep 10 ) >/dev/null 2>&1 || rc=$?
    assert_eq "perl fallback 超时返回 124" "124" "$rc"

    # 无视 TERM 的进程也要在宽限期后被 KILL 掉，而不是拖满 sleep 时长
    rc=0
    local t0 t1
    t0=$(date +%s)
    ( PATH="/usr/bin:/bin"; _timeout_cmd 1 perl -e '$SIG{TERM} = sub {}; sleep 30' ) >/dev/null 2>&1 || rc=$?
    t1=$(date +%s)
    assert_eq "TERM 免疫进程超时返回 124" "124" "$rc"
    if (( t1 - t0 < 10 )); then
        echo "  ✓ TERM 免疫进程在宽限期内被 KILL（用时 $((t1 - t0))s）"; ((PASS++))
    else
        echo "  ✗ TERM 免疫进程拖了 $((t1 - t0))s 才结束"; ((FAIL++))
    fi

    rc=0
    ( PATH="/usr/bin:/bin"; _timeout_cmd 5 true ) || rc=$?
    assert_eq "正常退出码 0 透传" "0" "$rc"
    rc=0
    ( PATH="/usr/bin:/bin"; _timeout_cmd 5 sh -c 'exit 3' ) || rc=$?
    assert_eq "正常退出码 3 透传" "3" "$rc"
}
test_timeout_cmd_perl_fallback

echo ""
echo "=== review 执行日志 ==="

test_review_log_append_writes_jsonl() {
    source_workflow_funcs
    local state_home="$TMP_DIR/log-basic"
    XDG_STATE_HOME="$state_home" _review_log_append 2 CONCERNS 'ti"tle 带"引号' 42 7 claude primary range 'origin/main...HEAD'
    local f
    f=$(ls "$state_home/sparring"/review-*.jsonl 2>/dev/null | head -1)
    assert_file_exists "日志文件已创建（按天命名）" "$f"
    local line
    line=$(tail -1 "$f")
    assert_eq "verdict 字段" "CONCERNS" "$(echo "$line" | jq -r .verdict)"
    assert_eq "title 引号正确转义" 'ti"tle 带"引号' "$(echo "$line" | jq -r .title)"
    assert_eq "backend 字段" "claude" "$(echo "$line" | jq -r .backend)"
    assert_eq "via 字段" "primary" "$(echo "$line" | jq -r .via)"
    assert_eq "input_lines 数字" "42" "$(echo "$line" | jq -r .input_lines)"
    assert_eq "duration_s 数字" "7" "$(echo "$line" | jq -r .duration_s)"
    assert_eq "exit_code 数字" "2" "$(echo "$line" | jq -r .exit_code)"
    # 追加第二行不覆盖
    XDG_STATE_HOME="$state_home" _review_log_append 0 APPROVE t2 1 1 opencode fallback
    assert_eq "JSONL 追加不覆盖" "2" "$(wc -l < "$f" | tr -d ' ')"
}
test_review_log_append_writes_jsonl

test_review_log_bad_numbers_fallback() {
    source_workflow_funcs
    local state_home="$TMP_DIR/log-badnum"
    # 数字字段传入垃圾值也要能落一行合法 JSON，不因 jq 报错丢日志
    XDG_STATE_HOME="$state_home" _review_log_append '' ERROR t 'x' '' '' ''
    local f
    f=$(ls "$state_home/sparring"/review-*.jsonl 2>/dev/null | head -1)
    assert_file_exists "垃圾数字仍写出日志" "$f"
    assert_eq "exit_code 兜底为 1" "1" "$(tail -1 "$f" | jq -r .exit_code)"
    assert_eq "input_lines 兜底为 0" "0" "$(tail -1 "$f" | jq -r .input_lines)"
    assert_eq "backend 空值兜底 unknown" "unknown" "$(tail -1 "$f" | jq -r .backend)"
}
test_review_log_bad_numbers_fallback

test_review_log_retention_cleanup() {
    source_workflow_funcs
    local state_home="$TMP_DIR/log-retention"
    local dir="$state_home/sparring"
    mkdir -p "$dir"
    : > "$dir/review-20200101.jsonl"
    touch -mt 202001010000 "$dir/review-20200101.jsonl"
    : > "$dir/other.txt"
    touch -mt 202001010000 "$dir/other.txt"
    XDG_STATE_HOME="$state_home" _review_log_append 0 APPROVE t 1 1 claude primary
    if [[ -f "$dir/review-20200101.jsonl" ]]; then
        echo "  ✗ 超过保留期的日志应被清理"; ((FAIL++))
    else
        echo "  ✓ 超过保留期的日志被清理"; ((PASS++))
    fi
    assert_file_exists "非 review-*.jsonl 文件不受清理影响" "$dir/other.txt"
}
test_review_log_retention_cleanup

test_review_log_disabled_by_config() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"review": {"log_retention_days": 0}}' > "$CONFIG_FILE_GLOBAL"
    local state_home="$TMP_DIR/log-disabled"
    XDG_STATE_HOME="$state_home" _review_log_append 0 APPROVE t 1 1 claude primary
    if [[ -d "$state_home/sparring" ]]; then
        echo "  ✗ log_retention_days=0 时不应写任何日志"; ((FAIL++))
    else
        echo "  ✓ log_retention_days=0 完全禁用日志"; ((PASS++))
    fi
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_review_log_disabled_by_config

test_call_reviewer_state_primary() {
    source_workflow_funcs
    # mock 后端调用成功 → 状态文件应记 primary
    _call_backend() { echo "APPROVE mock"; }
    local state
    state=$(mktemp "$TMP_DIR/state.XXXXXX")
    SPARRING_BACKEND_STATE_FILE="$state" WORKFLOW_REVIEW_BACKEND=claude \
        call_reviewer "test prompt" "" >/dev/null 2>&1
    assert_eq "primary 成功记录 'claude primary'" "claude primary" "$(cat "$state")"
    unset -f _call_backend
}
test_call_reviewer_state_primary

test_call_reviewer_state_fallback() {
    source_workflow_funcs
    # mock：claude 失败、opencode 成功 → 状态文件按行保留完整尝试链，末行为实际后端
    _call_backend() { [[ "$1" == "claude" ]] && return 1; echo "APPROVE mock"; }
    local state
    state=$(mktemp "$TMP_DIR/state.XXXXXX")
    local rc=0
    SPARRING_BACKEND_STATE_FILE="$state" WORKFLOW_REVIEW_BACKEND=claude \
        WORKFLOW_REVIEW_BACKEND_FALLBACK=opencode \
        call_reviewer "test prompt" "" >/dev/null 2>&1 || rc=$?
    assert_eq "降级成功 exit 0" "0" "$rc"
    assert_eq "首行保留 primary 失败记录" "claude primary" "$(head -1 "$state")"
    assert_eq "末行为实际使用的后端" "opencode fallback" "$(tail -1 "$state")"
    unset -f _call_backend
}
test_call_reviewer_state_fallback

test_call_reviewer_state_both_fail() {
    source_workflow_funcs
    # mock：主备均失败 → 尝试链完整（claude primary + opencode fallback），不丢主后端信息
    _call_backend() { return 1; }
    local state
    state=$(mktemp "$TMP_DIR/state.XXXXXX")
    local rc=0
    SPARRING_BACKEND_STATE_FILE="$state" WORKFLOW_REVIEW_BACKEND=claude \
        WORKFLOW_REVIEW_BACKEND_FALLBACK=opencode \
        call_reviewer "test prompt" "" >/dev/null 2>&1 || rc=$?
    assert_eq "主备均失败 exit 1" "1" "$rc"
    assert_eq "尝试链共 2 行" "2" "$(wc -l < "$state" | tr -d ' ')"
    assert_eq "首行 primary" "claude primary" "$(head -1 "$state")"
    assert_eq "末行 fallback" "opencode fallback" "$(tail -1 "$state")"
    unset -f _call_backend
}
test_call_reviewer_state_both_fail

test_call_reviewer_state_unset_noop() {
    source_workflow_funcs
    # 未设状态文件（task 制路径）时 no-op，不报错
    _call_backend() { echo "APPROVE mock"; }
    local rc=0
    unset SPARRING_BACKEND_STATE_FILE
    WORKFLOW_REVIEW_BACKEND=claude call_reviewer "test prompt" "" >/dev/null 2>&1 || rc=$?
    assert_eq "无状态文件时正常工作" "0" "$rc"
    unset -f _call_backend
}
test_call_reviewer_state_unset_noop

echo ""
echo "=== 超时杀整棵进程树 ==="

# 只杀直接子进程的实现能骗过"假 backend 只 sleep 一下"的测试：主进程一死测试就绿了。
# 所以假 backend 必须派生孙进程，断言打在孙进程上——这正是最贵的那种静默挂死：
# sparring 报超时退出了，被杀的只有壳，真正烧额度的 agent 子进程还在后台跑。
# marker 用一个不会跟系统里其他 sleep 撞车的秒数，pgrep 才能精确定位。
TREE_MARKER=98765

_make_tree_backend() {
    local script="$1"
    cat > "$script" <<EOF
#!/bin/bash
# 孙进程：超时只 kill 直接子进程的话，它会活下来
sleep ${TREE_MARKER} &
sleep ${TREE_MARKER}
EOF
    chmod +x "$script"
}

_tree_survivors() {
    pgrep -f "sleep ${TREE_MARKER}" 2>/dev/null | wc -l | tr -d ' '
}

test_timeout_kills_process_tree_gnu() {
    source_workflow_funcs
    pkill -f "sleep ${TREE_MARKER}" 2>/dev/null || true
    if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
        echo "  - 跳过：本机无 GNU timeout"
        return 0
    fi
    local script="$TMP_DIR/fake-backend-tree.sh"
    _make_tree_backend "$script"

    local rc=0
    _timeout_cmd 1 "$script" >/dev/null 2>&1 || rc=$?
    assert_eq "GNU timeout 路径返回 124" "124" "$rc"
    sleep 1
    assert_eq "GNU timeout 路径：孙进程无残留" "0" "$(_tree_survivors)"
    pkill -f "sleep ${TREE_MARKER}" 2>/dev/null || true
}
test_timeout_kills_process_tree_gnu

test_timeout_kills_process_tree_perl() {
    source_workflow_funcs
    pkill -f "sleep ${TREE_MARKER}" 2>/dev/null || true
    # PATH 限制到 /usr/bin:/bin 逼出 perl fallback（没装 coreutils 的 macOS 走这条）
    if PATH="/usr/bin:/bin" command -v timeout >/dev/null 2>&1 \
        || PATH="/usr/bin:/bin" command -v gtimeout >/dev/null 2>&1; then
        echo "  - 跳过：/usr/bin:/bin 下存在 timeout，无法逼出 perl fallback"
        return 0
    fi
    if ! PATH="/usr/bin:/bin" command -v perl >/dev/null 2>&1; then
        echo "  - 跳过：/usr/bin:/bin 下无 perl，fallback 不可测"
        return 0
    fi
    local script="$TMP_DIR/fake-backend-tree-perl.sh"
    _make_tree_backend "$script"

    local rc=0
    ( PATH="/usr/bin:/bin:$PATH"; _timeout_cmd 1 "$script" ) >/dev/null 2>&1 || rc=$?
    assert_eq "perl fallback 返回 124" "124" "$rc"
    sleep 1
    assert_eq "perl fallback：孙进程无残留（setpgrp + kill 负 pid）" "0" "$(_tree_survivors)"
    pkill -f "sleep ${TREE_MARKER}" 2>/dev/null || true
}
test_timeout_kills_process_tree_perl

echo ""
echo "=== 心跳 ==="

test_heartbeat_start_stop() {
    source_workflow_funcs
    _heartbeat_start "测试后端"
    local hb_pid="$_HEARTBEAT_PID"
    if [[ -n "$hb_pid" ]] && kill -0 "$hb_pid" 2>/dev/null; then
        echo "  ✓ 心跳进程已启动"; ((PASS++))
    else
        echo "  ✗ 心跳进程没起来"; ((FAIL++))
    fi
    _heartbeat_stop
    assert_eq "停止后全局 PID 清空" "" "$_HEARTBEAT_PID"
    if kill -0 "$hb_pid" 2>/dev/null; then
        echo "  ✗ 心跳进程未被回收"; ((FAIL++))
    else
        echo "  ✓ 心跳进程已回收"; ((PASS++))
    fi
    # 幂等：重复 stop 不报错
    local rc=0
    _heartbeat_stop || rc=$?
    assert_eq "重复 stop 幂等" "0" "$rc"
}
test_heartbeat_start_stop

echo ""
echo "=== level ==="

test_normalize_level() {
    source_workflow_funcs
    assert_eq "low" "low" "$(_normalize_level low)"
    assert_eq "大小写归一" "xhigh" "$(_normalize_level XHIGH)"
    assert_eq "medium" "medium" "$(_normalize_level Medium)"
    local rc=0
    _normalize_level "ultra" >/dev/null 2>&1 || rc=$?
    assert_eq "非法 level 返回非 0" "1" "$rc"
    rc=0
    _normalize_level "" >/dev/null 2>&1 || rc=$?
    assert_eq "空 level 返回非 0" "1" "$rc"
}
test_normalize_level

test_review_level_config() {
    source_workflow_funcs
    assert_eq "默认 medium" "medium" "$(get_review_level)"
    echo '{"review":{"level":"high"}}' > "$CONFIG_FILE_GLOBAL"
    assert_eq "global 配置生效" "high" "$(get_review_level)"
    assert_eq "env 覆盖配置" "low" "$(SPARRING_REVIEW_LEVEL=low get_review_level)"
    echo '{"review":{"level":"nonsense"}}' > "$CONFIG_FILE_GLOBAL"
    local rc=0
    get_review_level >/dev/null 2>&1 || rc=$?
    assert_eq "非法配置值报错" "1" "$rc"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_review_level_config

test_level_directive_all_levels() {
    source_workflow_funcs
    local lv
    for lv in low medium high xhigh; do
        local d
        d=$(_level_directive "$lv")
        if [[ -n "$d" ]]; then
            echo "  ✓ ${lv} 有对应的强度说明"; ((PASS++))
        else
            echo "  ✗ ${lv} 没有强度说明（opencode 腿会丢掉 level 语义）"; ((FAIL++))
        fi
    done
}
test_level_directive_all_levels

echo ""
echo "=== /code-review 输出翻译 ==="

test_code_review_none_is_approve() {
    source_workflow_funcs
    local out
    out=$(_normalize_code_review_output "(none)" low)
    assert_eq "(none) → 首行 APPROVE" "APPROVE" "$(echo "$out" | head -1)"
    # 引擎输出常带尾随换行/空格
    out=$(_normalize_code_review_output "  (none)
" medium)
    assert_eq "前后空白容忍" "APPROVE" "$(echo "$out" | head -1)"
}
test_code_review_none_is_approve

test_code_review_findings_is_concerns() {
    source_workflow_funcs
    local findings="src/user.js:3 — opts 未判空，老调用方会崩
src/cart.js:16 — off 缺省时结果是 NaN"
    local out rc=0
    out=$(_normalize_code_review_output "$findings" low) || rc=$?
    assert_eq "findings 解析成功" "0" "$rc"
    assert_eq "首行 CONCERNS" "CONCERNS" "$(echo "$out" | head -1)"
    assert_contains "findings 原样透出" "src/user.js:3" "$out"
    assert_contains "第二条也在" "src/cart.js:16" "$out"
}
test_code_review_findings_is_concerns

test_code_review_multiline_finding() {
    source_workflow_funcs
    # 多行 finding 的续行不是 file:line 形态——按"每行都要匹配"判会误判成解析失败
    local findings="src/a.py:10 — 空指针
    详细说明：当输入为 None 时
    影响：500"
    local out rc=0
    out=$(_normalize_code_review_output "$findings" high) || rc=$?
    assert_eq "多行 finding 仍算 CONCERNS" "0" "$rc"
    assert_eq "首行 CONCERNS" "CONCERNS" "$(echo "$out" | head -1)"
}
test_code_review_multiline_finding

test_code_review_garbage_is_parse_error() {
    source_workflow_funcs
    local rc=0
    _normalize_code_review_output "我看了一下，感觉还行" low >/dev/null 2>&1 || rc=$?
    assert_eq "认不出的输出 → 解析失败（绝不默认放行）" "1" "$rc"
    rc=0
    _normalize_code_review_output "Error: API rate limited" low >/dev/null 2>&1 || rc=$?
    assert_eq "报错文本 → 解析失败" "1" "$rc"
}
test_code_review_garbage_is_parse_error

echo ""
echo "=== 失败原因回传 ==="

test_error_reason_record() {
    source_workflow_funcs
    local f="$TMP_DIR/reason.txt"
    SPARRING_ERROR_REASON_FILE="$f" _error_reason_record timeout
    assert_eq "原因写入文件" "timeout" "$(cat "$f")"
    # 后写覆盖先写：末次失败原因才是要报的那个
    SPARRING_ERROR_REASON_FILE="$f" _error_reason_record parse
    assert_eq "覆盖而非追加" "parse" "$(cat "$f")"
    # 未设文件时是 no-op，不报错
    local rc=0
    unset SPARRING_ERROR_REASON_FILE
    _error_reason_record crash || rc=$?
    assert_eq "未设文件时 no-op" "0" "$rc"
}
test_error_reason_record

test_review_log_level_and_reason_fields() {
    source_workflow_funcs
    local state_dir="$TMP_DIR/state-lv"
    mkdir -p "$state_dir"
    XDG_STATE_HOME="$state_dir" _review_log_append 1 ERROR "超时的活" 10 600 claude primary range "main...HEAD" high timeout
    local line
    line=$(cat "$state_dir/sparring/review-$(date +%Y%m%d).jsonl")
    assert_eq "level 字段" "high" "$(echo "$line" | jq -r '.level')"
    assert_eq "error_reason 字段" "timeout" "$(echo "$line" | jq -r '.error_reason')"
    assert_eq "mode 字段" "range" "$(echo "$line" | jq -r '.mode')"

    # 正常裁决时两个字段的形态：level 有值、error_reason 为 null
    XDG_STATE_HOME="$state_dir" _review_log_append 0 APPROVE "过了的活" 10 30 claude primary range "main...HEAD" low ""
    line=$(tail -1 "$state_dir/sparring/review-$(date +%Y%m%d).jsonl")
    assert_eq "APPROVE 时 error_reason 为 null" "null" "$(echo "$line" | jq -r '.error_reason')"
    assert_eq "APPROVE 时 level 有值" "low" "$(echo "$line" | jq -r '.level')"

    # 文本模式不记 level（没生效的值不该出现在日志里）
    XDG_STATE_HOME="$state_dir" _review_log_append 0 APPROVE "审文本" 5 3 opencode primary text "" "" ""
    line=$(tail -1 "$state_dir/sparring/review-$(date +%Y%m%d).jsonl")
    assert_eq "text 模式 level 为 null" "null" "$(echo "$line" | jq -r '.level')"
}
test_review_log_level_and_reason_fields

echo ""
echo "=== 背景 job 死 PID 改判 ==="

_write_job_json() {
    local path="$1" status="$2" pid="$3"
    jq -n --arg s "$status" --argjson p "$pid" \
        '{job_id: "rj-test-0001", task_id: "t1", review_type: "code", backend: "claude",
          status: $s, created_at: "2026-08-12T00:00:00+08:00", started_at: null,
          completed_at: null, pid: (if $p == 0 then null else $p end),
          exit_code: null, error_reason: null, review_state: null,
          review_file: null, result_file: null, log_file: null}' > "$path"
}

test_job_reap_dead_pid() {
    source_workflow_funcs
    local job="$TMP_DIR/job-dead.json"
    # 起一个进程再杀掉，拿到一个确定已死的 PID（比硬编码 PID 可靠：
    # 硬编码的号码可能被系统回收给别的进程，测试就会随机变绿）
    sleep 60 & local dead_pid=$!
    kill "$dead_pid" 2>/dev/null; wait "$dead_pid" 2>/dev/null
    _write_job_json "$job" running "$dead_pid"

    _review_job_reap "$job" 2>/dev/null
    assert_eq "running + 死 PID → failed" "failed" "$(jq -r '.status' "$job")"
    assert_eq "记 error_reason" "crash" "$(jq -r '.error_reason' "$job")"
    assert_eq "pid 置空" "null" "$(jq -r '.pid' "$job")"
    assert_eq "原 pid 搬到 final_pid" "$dead_pid" "$(jq -r '.final_pid' "$job")"
}
test_job_reap_dead_pid

test_job_reap_keeps_live_worker() {
    source_workflow_funcs
    local job="$TMP_DIR/job-live.json"
    sleep 30 & local live_pid=$!
    _write_job_json "$job" running "$live_pid"

    _review_job_reap "$job" 2>/dev/null
    assert_eq "worker 还活着就不动它" "running" "$(jq -r '.status' "$job")"
    kill "$live_pid" 2>/dev/null; wait "$live_pid" 2>/dev/null
}
test_job_reap_keeps_live_worker

test_job_reap_ignores_completed() {
    source_workflow_funcs
    # 正常完成的 job：pid 已置 null、值搬到 final_pid。
    # 只看 kill -0 会把它误判成 failed，所以必须要求 pid 非 null。
    local job="$TMP_DIR/job-done.json"
    _write_job_json "$job" completed 0
    _review_job_reap "$job" 2>/dev/null
    assert_eq "已完成的 job 不被改判" "completed" "$(jq -r '.status' "$job")"

    local job2="$TMP_DIR/job-done-running.json"
    _write_job_json "$job2" running 0
    _review_job_reap "$job2" 2>/dev/null
    assert_eq "running 但 pid 为 null 时不改判" "running" "$(jq -r '.status' "$job2")"
}
test_job_reap_ignores_completed

echo ""
echo "=== opencode 网关认证注入 ==="

test_resolve_secret() {
    source_workflow_funcs
    assert_eq "字面量原样返回" "sk-literal" "$(_resolve_secret 'sk-literal')"
    assert_eq "\$ENV_VAR 解引用" "sk-from-env" "$(SPARRING_TEST_KEY=sk-from-env _resolve_secret '$SPARRING_TEST_KEY')"
    assert_eq "未设置的 env 解成空" "" "$(_resolve_secret '$SPARRING_DEFINITELY_UNSET_VAR')"
    assert_eq "空值" "" "$(_resolve_secret '')"
}
test_resolve_secret

test_gateway_not_configured() {
    source_workflow_funcs
    echo '{"opencode":{"model":"some/model"}}' > "$CONFIG_FILE_GLOBAL"
    local m
    m=$(_opencode_gateway_setup)
    assert_eq "未配网关时 model 原样透传" "some/model" "$m"
    assert_eq "不生成临时配置" "" "$_OPENCODE_GW_CONFIG"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_gateway_not_configured

test_gateway_partial_config_ignored() {
    source_workflow_funcs
    # 配一半（有 url 没 key）不能半生效——那会变成"以为走网关、其实走用户默认账号"
    echo '{"opencode":{"model":"m1","base_url":"https://gw.example/v1"}}' > "$CONFIG_FILE_GLOBAL"
    local m
    m=$(_opencode_gateway_setup)
    assert_eq "缺 api_key 时不启用网关" "m1" "$m"
    assert_eq "缺 api_key 时无临时配置" "" "$_OPENCODE_GW_CONFIG"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_gateway_partial_config_ignored

test_gateway_generates_config() {
    source_workflow_funcs
    jq -n '{opencode: {model: "gpt-test", base_url: "https://gw.example/v1", api_key: "$SPARRING_TEST_GW_KEY"}}' \
        > "$CONFIG_FILE_GLOBAL"
    local m
    m=$(SPARRING_TEST_GW_KEY=sk-secret-from-env _opencode_gateway_setup)
    # _opencode_gateway_setup 在 $(...) 子 shell 里跑，全局变量传不回来，
    # 所以这里重跑一次拿文件路径（同样的输入，行为一致）
    SPARRING_TEST_GW_KEY=sk-secret-from-env _opencode_gateway_setup >/dev/null
    local cfg="$_OPENCODE_GW_CONFIG"

    assert_eq "model 被加上 provider 前缀" "sparring-gw/gpt-test" "$m"
    assert_file_exists "生成了临时配置文件" "$cfg"
    if [[ -f "$cfg" ]]; then
        assert_eq "provider 名" "@ai-sdk/openai-compatible" "$(jq -r '.provider["sparring-gw"].npm' "$cfg")"
        assert_eq "baseURL 写入" "https://gw.example/v1" "$(jq -r '.provider["sparring-gw"].options.baseURL' "$cfg")"
        assert_eq "api_key 从 env 解引用后写入" "sk-secret-from-env" "$(jq -r '.provider["sparring-gw"].options.apiKey' "$cfg")"
        assert_eq "model 登记在 provider 下" "gpt-test" "$(jq -r '.provider["sparring-gw"].models["gpt-test"].name' "$cfg")"
        # 密钥落盘期间不能让同机器其他用户读到
        assert_eq "临时配置权限 600" "600" "$(stat -f '%Lp' "$cfg" 2>/dev/null || stat -c '%a' "$cfg")"
        # 只写 provider 块：OPENCODE_CONFIG 是合并语义，写多了会覆盖用户自己的设置
        assert_eq "只含 provider 一个顶层键" "provider" "$(jq -r 'keys | join(",")' "$cfg")"
        rm -f "$cfg"
    fi
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_gateway_generates_config

echo ""
echo "=== 对抗式 review 方法论 ==="

test_adversarial_prompt_exists() {
    source_workflow_funcs
    local out rc=0
    out=$(_adversarial_prompt) || rc=$?
    assert_eq "方法论文件可读" "0" "$rc"
    assert_contains "含删除行为审计角度" "删除行为审计" "$out"
    assert_contains "含跨文件追踪角度" "跨文件追踪" "$out"
    assert_contains "含输出契约" "APPROVE" "$out"
    assert_contains "契约含 CONCERNS" "CONCERNS" "$out"
}
test_adversarial_prompt_exists

# ─── Summary ─────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
