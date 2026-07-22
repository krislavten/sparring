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

echo "=== load_agent_config ==="

test_load_config_real_file() {
    source_workflow_funcs
    load_agent_config "cursor"
    assert_eq "loads model from cursor.md" "gpt-5.5-extra-high" "$AGENT_MODEL"
    assert_contains "loads system prompt" "严格的代码审查专家" "$AGENT_SYSTEM_PROMPT"
    assert_contains "prompt includes APPROVE format" "APPROVE" "$AGENT_SYSTEM_PROMPT"
    assert_contains "prompt includes CONCERNS format" "CONCERNS" "$AGENT_SYSTEM_PROMPT"
}
test_load_config_real_file

test_load_config_missing_file() {
    source_workflow_funcs
    load_agent_config "nonexistent" 2>/dev/null
    assert_eq "falls back to default model" "gpt-5.5-extra-high" "$AGENT_MODEL"
    assert_eq "empty system prompt" "" "$AGENT_SYSTEM_PROMPT"
}
test_load_config_missing_file

test_load_config_custom() {
    source_workflow_funcs
    # Create a custom agent config
    local custom_dir="$TMP_DIR/custom_agents"
    mkdir -p "$custom_dir"
    cat > "$custom_dir/test-agent.md" <<'EOF'
# Test Agent

## Model

model: opus-4.6-thinking

## System Prompt

You are a test agent.
Be helpful.
EOF
    AGENTS_DIR="$custom_dir"
    load_agent_config "test-agent"
    assert_eq "parses custom model" "opus-4.6-thinking" "$AGENT_MODEL"
    assert_contains "parses custom prompt" "test agent" "$AGENT_SYSTEM_PROMPT"

    # Restore
    AGENTS_DIR="$PROJECT_DIR/agents"
}
test_load_config_custom

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
    check_agent() { return 0; }
    init_agent_session() { return 0; }

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
    assert_eq "reviewer is glm" "glm" "$reviewer"
    assert_eq "initial status is proposal" "proposal" "$status"
}
test_create_task_structure

test_create_task_cursor_executor() {
    source_workflow_funcs
    check_agent() { return 0; }
    init_agent_session() { return 0; }

    create_task "cursor-task" "cursor" > /dev/null 2>&1

    local task_dir
    task_dir=$(ls -d "$PLANS_DIR"/*-cursor-task 2>/dev/null | head -1)

    local executor reviewer
    executor=$(jq -r '.executor' "$task_dir/meta.json")
    reviewer=$(jq -r '.reviewer' "$task_dir/meta.json")
    assert_eq "executor is cursor" "cursor" "$executor"
    assert_eq "reviewer follows default backend(glm)" "glm" "$reviewer"
}
test_create_task_cursor_executor

test_create_task_codex_backend() {
    source_workflow_funcs
    check_agent() { return 0; }
    init_agent_session() { return 0; }

    WORKFLOW_REVIEW_BACKEND=codex create_task "codex-task" "claude" > /dev/null 2>&1

    local task_dir
    task_dir=$(ls -d "$PLANS_DIR"/*-codex-task 2>/dev/null | head -1)

    local reviewer
    reviewer=$(jq -r '.reviewer' "$task_dir/meta.json")
    assert_eq "reviewer follows codex backend" "codex" "$reviewer"
}
test_create_task_codex_backend

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
    assert_eq "default review backend" "glm" "$backend"
}
test_review_backend_default

test_review_backend_codex() {
    source_workflow_funcs
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=codex get_review_backend)
    assert_eq "codex review backend" "codex" "$backend"
}
test_review_backend_codex

test_review_backend_invalid() {
    source_workflow_funcs
    local status=0
    WORKFLOW_REVIEW_BACKEND=foo get_review_backend 2>/dev/null || status=$?
    assert_eq "invalid backend fails" "1" "$status"
}
test_review_backend_invalid

test_review_backend_glm() {
    source_workflow_funcs
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=glm get_review_backend)
    assert_eq "glm review backend" "glm" "$backend"
}
test_review_backend_glm

test_review_backend_glm_uppercase() {
    source_workflow_funcs
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=GLM get_review_backend)
    assert_eq "glm backend case-insensitive" "glm" "$backend"
}
test_review_backend_glm_uppercase

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

test_fallback_unset() {
    source_workflow_funcs
    unset WORKFLOW_REVIEW_BACKEND_FALLBACK
    local fb
    fb=$(get_review_backend_fallback)
    assert_eq "no fallback when unset" "" "$fb"
}
test_fallback_unset

test_fallback_glm() {
    source_workflow_funcs
    local fb
    fb=$(WORKFLOW_REVIEW_BACKEND_FALLBACK=glm get_review_backend_fallback)
    assert_eq "fallback glm" "glm" "$fb"
}
test_fallback_glm

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

test_reviewer_label_glm() {
    source_workflow_funcs
    local label
    label=$(reviewer_label_for_backend "glm")
    assert_eq "glm label" "GLM" "$label"
}
test_reviewer_label_glm

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
echo "=== claude backend config & check ==="

test_claude_config_defaults() {
    source_workflow_funcs
    # 注意: jq 的 `//` 把布尔 false 和 null 都当 "empty"，故默认 false 读出来是空串。
    # 代码只比较 `== "true"`（空串视为 not-true → 清代理），行为正确，这里断言"非 true"语义。
    assert_eq "claude.use_proxy default is falsy (not 'true')" "" "$(_config_get claude.use_proxy)"
    assert_eq "claude.model default null→empty" "" "$(_config_get claude.model)"
    assert_eq "claude.base_url default null→empty" "" "$(_config_get claude.base_url)"
    # 用户显式设 true（布尔）应被正确读为 "true"
    assert_eq "claude.use_proxy=true(bool) reads as true" "true" \
        "$(SPARRING_CLAUDE_USE_PROXY=true _config_get claude.use_proxy)"
}
test_claude_config_defaults

# check_claude 需要 claude 在 PATH；用临时 fake 二进制隔离测试鉴权分支逻辑
_make_fake_claude() {
    local dir="$TMP_DIR/fake-claude-$RANDOM"
    mkdir -p "$dir"
    printf '#!/bin/bash\necho "1.0.0 (fake)"\n' > "$dir/claude"
    chmod +x "$dir/claude"
    echo "$dir"
}

test_check_claude_base_url_requires_key() {
    source_workflow_funcs
    local fakebin status=0
    fakebin=$(_make_fake_claude)
    # 配了 base_url 但没 api_key → 必须失败
    PATH="$fakebin:$PATH" SPARRING_CLAUDE_BASE_URL="https://x.test/anthropic" \
        check_claude 2>/dev/null || status=$?
    assert_eq "base_url without api_key fails" "1" "$status"
}
test_check_claude_base_url_requires_key

test_check_claude_base_url_with_key_ok() {
    source_workflow_funcs
    local fakebin status=0
    fakebin=$(_make_fake_claude)
    PATH="$fakebin:$PATH" SPARRING_CLAUDE_BASE_URL="https://x.test/anthropic" \
        SPARRING_CLAUDE_API_KEY="tok-123" \
        check_claude 2>/dev/null || status=$?
    assert_eq "base_url with api_key passes" "0" "$status"
}
test_check_claude_base_url_with_key_ok

test_check_claude_native_no_key_ok() {
    source_workflow_funcs
    local fakebin status=0
    fakebin=$(_make_fake_claude)
    # 原生路径（无 base_url）不强制 api_key
    PATH="$fakebin:$PATH" check_claude 2>/dev/null || status=$?
    assert_eq "native path needs no key" "0" "$status"
}
test_check_claude_native_no_key_ok

echo ""
echo "=== call_claude_agent env 注入 & 命令组装 (mock claude) ==="

# mock claude：把收到的 argv + 关键 env + PWD dump 到 $CLAUDE_MOCK_DUMP，再回 APPROVE。
# 用它验证隔离机制的核心：第三方 env 注入、清空 ANTHROPIC_API_KEY、禁工具、空 cwd 运行。
_make_mock_claude() {
    local dir="$TMP_DIR/mock-claude-$RANDOM"
    mkdir -p "$dir"
    cat > "$dir/claude" <<'MOCK'
#!/bin/bash
# 把变量状态归一为 UNSET / EMPTY / SET，避免 grep 断言碰到 [] 正则 / -- 选项坑
_state() { if [ -z "${!1+x}" ]; then echo UNSET; elif [ -z "${!1}" ]; then echo EMPTY; else echo SET; fi; }
# argv 用换行分隔，断言可逐 token 精确匹配（避开 "--model" 被 grep 当选项）
ARGV_NL=$(printf '%s\n' "$@")
{
  echo "PWD: $PWD"
  echo "BASE_URL: ${ANTHROPIC_BASE_URL:-<unset>}"
  echo "AUTH_TOKEN: ${ANTHROPIC_AUTH_TOKEN:-<unset>}"
  echo "MODEL_ENV: ${ANTHROPIC_MODEL:-<unset>}"
  echo "API_KEY_STATE: $(_state ANTHROPIC_API_KEY)"
  echo "HTTP_PROXY_STATE: $(_state HTTP_PROXY)"
  echo "CONFIG_DIR: ${CLAUDE_CONFIG_DIR:-<unset>}"
  echo "HAS_MODEL_FLAG: $(echo "$ARGV_NL" | grep -qx -- '--model' && echo yes || echo no)"
  echo "MODEL_FLAG_VAL: $(echo "$ARGV_NL" | grep -A1 -x -- '--model' | tail -1)"
  echo "HAS_DISALLOWED: $(echo "$ARGV_NL" | grep -qx -- '--disallowedTools' && echo yes || echo no)"
  echo "HAS_PRINT: $(echo "$ARGV_NL" | grep -qx -- '-p' && echo yes || echo no)"
} > "$CLAUDE_MOCK_DUMP"
cat > /dev/null 2>&1 || true
echo "APPROVE"
echo "mock verdict"
MOCK
    chmod +x "$dir/claude"
    echo "$dir"
}

test_call_claude_thirdparty_injection() {
    source_workflow_funcs
    local mockdir result dump
    mockdir=$(_make_mock_claude)
    export CLAUDE_MOCK_DUMP="$TMP_DIR/dump-3p-$RANDOM.txt"
    # 故意预置一个"残留真 key" + 代理，验证第三方路径会把它们清掉
    result=$(PATH="$mockdir:$PATH" \
        SPARRING_CLAUDE_BASE_URL="https://x.test/anthropic" \
        SPARRING_CLAUDE_API_KEY="tok-xyz" \
        SPARRING_CLAUDE_MODEL="deepseek-chat" \
        ANTHROPIC_API_KEY="leaked-real-key" \
        HTTP_PROXY="http://127.0.0.1:7897" \
        call_claude_agent "请审查这段代码" 2>/dev/null)
    dump=$(cat "$CLAUDE_MOCK_DUMP" 2>/dev/null)
    assert_contains "returns mock verdict" "APPROVE" "$result"
    assert_contains "injects ANTHROPIC_BASE_URL" "BASE_URL: https://x.test/anthropic" "$dump"
    assert_contains "injects ANTHROPIC_AUTH_TOKEN" "AUTH_TOKEN: tok-xyz" "$dump"
    assert_contains "injects ANTHROPIC_MODEL" "MODEL_ENV: deepseek-chat" "$dump"
    assert_contains "clears残留 ANTHROPIC_API_KEY 为空" "API_KEY_STATE: EMPTY" "$dump"
    assert_contains "passes model flag" "HAS_MODEL_FLAG: yes" "$dump"
    assert_contains "model flag value correct" "MODEL_FLAG_VAL: deepseek-chat" "$dump"
    assert_contains "passes disallowedTools flag" "HAS_DISALLOWED: yes" "$dump"
    assert_contains "print mode flag present" "HAS_PRINT: yes" "$dump"
    assert_contains "clears HTTP_PROXY 为空" "HTTP_PROXY_STATE: EMPTY" "$dump"
    assert_contains "runs in isolated temp cwd" "sparring-claude-cwd" "$dump"
    assert_contains "third-party uses ephemeral config dir" "sparring-claude-cfg" "$dump"
    unset CLAUDE_MOCK_DUMP ANTHROPIC_API_KEY HTTP_PROXY
}
test_call_claude_thirdparty_injection

test_call_claude_native_no_thirdparty_env() {
    source_workflow_funcs
    local mockdir result dump
    mockdir=$(_make_mock_claude)
    export CLAUDE_MOCK_DUMP="$TMP_DIR/dump-native-$RANDOM.txt"
    # 原生路径（无 base_url）→ 不注入第三方 env，config dir 复用 ~/.claude
    result=$(PATH="$mockdir:$PATH" SPARRING_CLAUDE_MODEL="claude-opus-4-8" \
        call_claude_agent "请审查这段代码" 2>/dev/null)
    dump=$(cat "$CLAUDE_MOCK_DUMP" 2>/dev/null)
    assert_contains "returns mock verdict" "APPROVE" "$result"
    assert_contains "native: no ANTHROPIC_BASE_URL" "BASE_URL: <unset>" "$dump"
    assert_contains "native: no ANTHROPIC_AUTH_TOKEN" "AUTH_TOKEN: <unset>" "$dump"
    assert_contains "native: config_dir 复用 ~/.claude" "CONFIG_DIR: $HOME/.claude" "$dump"
    assert_contains "native: 仍禁工具" "HAS_DISALLOWED: yes" "$dump"
    assert_contains "native: 仍空 cwd 隔离" "sparring-claude-cwd" "$dump"
    unset CLAUDE_MOCK_DUMP
}
test_call_claude_native_no_thirdparty_env

echo ""
echo "=== call_reviewer fallback behavior ==="

test_call_reviewer_fallback_triggers() {
    source_workflow_funcs
    # 主 backend 失败 → 备 backend 成功 → 应返回备的结果
    _call_backend() {
        local backend="$1"
        if [[ "$backend" == "cursor" ]]; then
            echo "cursor failed" >&2
            return 1
        fi
        if [[ "$backend" == "glm" ]]; then
            echo "APPROVE from glm"
            return 0
        fi
        return 1
    }

    local result
    result=$(WORKFLOW_REVIEW_BACKEND=cursor WORKFLOW_REVIEW_BACKEND_FALLBACK=glm \
        call_reviewer "test prompt" "" 2>/dev/null)
    assert_eq "fallback to glm on primary failure" "APPROVE from glm" "$result"
}
test_call_reviewer_fallback_triggers

test_call_reviewer_no_fallback_fails() {
    source_workflow_funcs
    _call_backend() {
        echo "failed" >&2
        return 1
    }

    local status=0
    WORKFLOW_REVIEW_BACKEND=cursor call_reviewer "p" "" >/dev/null 2>&1 || status=$?
    assert_eq "no fallback, main fails → return non-zero" "1" "$status"
}
test_call_reviewer_no_fallback_fails

test_call_reviewer_primary_success_skips_fallback() {
    source_workflow_funcs
    local fallback_called=0
    _call_backend() {
        local backend="$1"
        if [[ "$backend" == "cursor" ]]; then
            echo "APPROVE from cursor"
            return 0
        fi
        fallback_called=1
        return 0
    }

    local result
    result=$(WORKFLOW_REVIEW_BACKEND=cursor WORKFLOW_REVIEW_BACKEND_FALLBACK=glm \
        call_reviewer "p" "" 2>/dev/null)
    assert_eq "primary success returns primary result" "APPROVE from cursor" "$result"
    assert_eq "fallback not invoked on primary success" "0" "$fallback_called"
}
test_call_reviewer_primary_success_skips_fallback

test_call_reviewer_same_primary_fallback() {
    source_workflow_funcs
    _call_backend() {
        return 1
    }

    local status=0
    WORKFLOW_REVIEW_BACKEND=glm WORKFLOW_REVIEW_BACKEND_FALLBACK=glm \
        call_reviewer "p" "" >/dev/null 2>&1 || status=$?
    assert_eq "same primary/fallback — fails without extra retry" "1" "$status"
}
test_call_reviewer_same_primary_fallback

echo ""
echo "=== check_glm ==="

test_check_glm_no_key() {
    source_workflow_funcs
    local status=0
    ( unset WORKFLOW_GLM_API_KEY; check_glm ) 2>/dev/null || status=$?
    assert_eq "check_glm fails without API key" "1" "$status"
}
test_check_glm_no_key

test_check_glm_with_key() {
    source_workflow_funcs
    WORKFLOW_GLM_API_KEY="fake.key" check_glm 2>/dev/null
    assert_eq "check_glm passes with API key" "0" "$?"
}
test_check_glm_with_key

echo ""
echo "=== glm response parsing (jq expression) ==="

# 防止 Sparring CONCERN 3 回归：content="" 时 jq `//` 不会回退到 reasoning_content
test_glm_jq_content_present() {
    local fixture='{"choices":[{"message":{"content":"APPROVE\n理由","reasoning_content":"思考"}}]}'
    local result
    result=$(echo "$fixture" | jq -r '.choices[0].message.content // empty')
    assert_eq "非空 content 正常返回" "APPROVE
理由" "$result"
}
test_glm_jq_content_present

test_glm_jq_empty_content_does_not_fallback_to_reasoning() {
    # content="" 时，代码不应兜底到 reasoning_content（思考链不是 review 格式）
    local fixture='{"choices":[{"message":{"content":"","reasoning_content":"1. 思考"}}]}'
    local result
    result=$(echo "$fixture" | jq -r '.choices[0].message.content // empty')
    # 预期空字符串（不是 "1. 思考"）
    assert_eq "content='' 不兜底到 reasoning_content" "" "$result"
}
test_glm_jq_empty_content_does_not_fallback_to_reasoning

test_glm_jq_detect_reasoning_exhausted() {
    # 当 content 空但 reasoning 非空时，测 has_reasoning 检测
    local fixture='{"choices":[{"message":{"content":"","reasoning_content":"abc"}}]}'
    local has_reasoning
    has_reasoning=$(echo "$fixture" | jq -r '(.choices[0].message.reasoning_content // "") | length > 0')
    assert_eq "检测到 reasoning 被用尽" "true" "$has_reasoning"
}
test_glm_jq_detect_reasoning_exhausted

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
    assert_eq "默认 backend=glm" "glm" "$backend"
    assert_eq "默认 timeout=120" "120" "$timeout"
}
test_config_defaults

echo ""
echo "=== _adaptive_timeout 按内容大小自适应加时 ==="

test_adaptive_timeout_no_content() {
    source_workflow_funcs
    local t
    t=$(_adaptive_timeout)
    assert_eq "不传内容退化为纯配置值" "120" "$t"
    t=$(_adaptive_timeout "")
    assert_eq "空内容同样退化为纯配置值" "120" "$t"
}
test_adaptive_timeout_no_content

test_adaptive_timeout_small_content_no_extra() {
    source_workflow_funcs
    local content t
    content=$(head -c 5000 /dev/zero | tr '\0' 'a')
    t=$(_adaptive_timeout "$content")
    assert_eq "小内容（< 1 个 step）不加时" "120" "$t"
}
test_adaptive_timeout_small_content_no_extra

test_adaptive_timeout_scales_with_size() {
    source_workflow_funcs
    local content t
    content=$(head -c 25000 /dev/zero | tr '\0' 'a')
    t=$(_adaptive_timeout "$content")
    # 25000 字节 = 2 个 10000 字节 step → +60s → 120+60=180
    assert_eq "25000 字节内容加时 60s" "180" "$t"
}
test_adaptive_timeout_scales_with_size

test_adaptive_timeout_caps_at_max_extra() {
    source_workflow_funcs
    local content t
    content=$(head -c 1000000 /dev/zero | tr '\0' 'a')
    t=$(_adaptive_timeout "$content")
    # 加时封顶 480s → 120+480=600，即使内容远超封顶阈值
    assert_eq "超大内容加时封顶 480s" "600" "$t"
}
test_adaptive_timeout_caps_at_max_extra

test_adaptive_timeout_respects_configured_base() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"review":{"timeout":45}}' > "$CONFIG_FILE_GLOBAL"
    local content t
    content=$(head -c 25000 /dev/zero | tr '\0' 'a')
    t=$(_adaptive_timeout "$content")
    # base 改成 45（非默认 120）→ 45+60=105，确认自适应叠加在配置值之上而非硬编码默认值
    assert_eq "自适应加时叠加在配置覆盖的 base 之上" "105" "$t"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_adaptive_timeout_respects_configured_base

test_config_global_overrides_default() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"review":{"backend":"glm","timeout":45}}' > "$CONFIG_FILE_GLOBAL"
    local backend timeout
    backend=$(_config_get review.backend)
    timeout=$(_config_get review.timeout)
    assert_eq "global 覆盖默认 backend" "glm" "$backend"
    assert_eq "global 覆盖默认 timeout" "45" "$timeout"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_global_overrides_default

test_config_project_overrides_global() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL" "$CONFIG_DIR_PROJECT"
    echo '{"review":{"backend":"glm"}}' > "$CONFIG_FILE_GLOBAL"
    echo '{"review":{"backend":"codex"}}' > "$CONFIG_FILE_PROJECT"
    local backend
    backend=$(_config_get review.backend)
    assert_eq "project 覆盖 global" "codex" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL" "$CONFIG_FILE_PROJECT"
}
test_config_project_overrides_global

test_config_sparring_env_highest() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL" "$CONFIG_DIR_PROJECT"
    echo '{"review":{"backend":"glm"}}' > "$CONFIG_FILE_GLOBAL"
    echo '{"review":{"backend":"codex"}}' > "$CONFIG_FILE_PROJECT"
    local backend
    backend=$(SPARRING_REVIEW_BACKEND=cursor _config_get review.backend)
    assert_eq "SPARRING_* env 最高优先级" "cursor" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL" "$CONFIG_FILE_PROJECT"
}
test_config_sparring_env_highest

test_config_workflow_env_fallback() {
    source_workflow_funcs
    # SPARRING_* 未设，WORKFLOW_* 应该生效
    local backend
    backend=$(WORKFLOW_REVIEW_BACKEND=glm _config_get review.backend)
    assert_eq "WORKFLOW_* 兼容别名" "glm" "$backend"
}
test_config_workflow_env_fallback

test_config_sparring_wins_over_workflow() {
    source_workflow_funcs
    local backend
    backend=$(SPARRING_REVIEW_BACKEND=cursor WORKFLOW_REVIEW_BACKEND=glm \
        _config_get review.backend)
    assert_eq "SPARRING_* 优先于 WORKFLOW_*" "cursor" "$backend"
}
test_config_sparring_wins_over_workflow

test_config_legacy_alias_fallback() {
    source_workflow_funcs
    # 历史变量：WORKFLOW_REVIEW_BACKEND_FALLBACK → review.fallback
    local fb
    fb=$(WORKFLOW_REVIEW_BACKEND_FALLBACK=codex _config_get review.fallback)
    assert_eq "WORKFLOW_REVIEW_BACKEND_FALLBACK legacy 别名" "codex" "$fb"
}
test_config_legacy_alias_fallback

test_config_legacy_alias_agent_model() {
    source_workflow_funcs
    local model
    model=$(WORKFLOW_AGENT_MODEL=opus-4.7 _config_get cursor.model)
    assert_eq "WORKFLOW_AGENT_MODEL legacy 别名" "opus-4.7" "$model"
}
test_config_legacy_alias_agent_model

test_config_malformed_file() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo 'not valid json {' > "$CONFIG_FILE_GLOBAL"
    local backend
    backend=$(_config_get review.backend 2>/dev/null)
    # 格式错的文件被忽略，应该回退到默认
    assert_eq "非法 JSON 文件回退到默认" "glm" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_malformed_file

test_config_nested_merge() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL" "$CONFIG_DIR_PROJECT"
    # global 设 glm.api_key，project 设 glm.model → 应该合并不是覆盖
    echo '{"glm":{"api_key":"global-key"}}' > "$CONFIG_FILE_GLOBAL"
    echo '{"glm":{"model":"glm-4-plus"}}' > "$CONFIG_FILE_PROJECT"
    local key model
    key=$(_config_get glm.api_key)
    model=$(_config_get glm.model)
    assert_eq "递归合并保留 global.glm.api_key" "global-key" "$key"
    assert_eq "递归合并加上 project.glm.model" "glm-4-plus" "$model"
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
    # 项目配置不应包含 api_key 字段
    local has_key
    has_key=$(jq -r 'has("glm") and (.glm | has("api_key"))' "$CONFIG_FILE_PROJECT")
    assert_eq "project config 不应包含 glm.api_key" "false" "$has_key"
    rm -rf "$CONFIG_DIR_PROJECT"
}
test_config_init_project

test_config_init_existing_no_force() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"review":{"backend":"codex"}}' > "$CONFIG_FILE_GLOBAL"
    config_init >/dev/null 2>&1
    # 文件未被覆盖
    local backend
    backend=$(jq -r '.review.backend' "$CONFIG_FILE_GLOBAL")
    assert_eq "已存在时不覆盖" "codex" "$backend"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_init_existing_no_force

test_config_show_masks_key() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"glm":{"api_key":"abcd1234secretxyz"}}' > "$CONFIG_FILE_GLOBAL"
    local output
    output=$(config_show 2>&1)
    # 明文 key 不应出现
    if echo "$output" | grep -q "abcd1234secretxyz"; then
        echo "  ✗ config show 泄漏明文 key"
        ((FAIL++))
    else
        echo "  ✓ config show 不泄漏明文 key"
        ((PASS++))
    fi
    # 掩码应出现
    assert_contains "config show 显示掩码" "abcd\*\*\*" "$output"
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_show_masks_key

test_config_get_masks_api_key() {
    source_workflow_funcs
    mkdir -p "$CONFIG_DIR_GLOBAL"
    echo '{"glm":{"api_key":"abcd1234secretxyz"}}' > "$CONFIG_FILE_GLOBAL"
    local output
    output=$(config_get_cmd glm.api_key)
    if [[ "$output" == "abcd1234secretxyz" ]]; then
        echo "  ✗ config get glm.api_key 泄漏明文"
        ((FAIL++))
    else
        echo "  ✓ config get glm.api_key 掩码"
        ((PASS++))
    fi
    rm -f "$CONFIG_FILE_GLOBAL"
}
test_config_get_masks_api_key

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
    # 项目 config.json 注释必须明确说 api_key 不放这里
    local comment
    comment=$(jq -r '._comment // ""' "$CONFIG_FILE_PROJECT")
    assert_contains "项目 config 注释警告 api_key 不放这里" "api_key" "$comment"
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
    err_output=$({ _config_get review.backend; _config_get review.timeout; _config_get glm.model; } 2>&1 >/dev/null)
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
    assert_contains "错误信息提示合法值" "cursor" "$output"
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
    # 用无效 GLM API key 强制失败，backend=glm
    local rc=0
    SPARRING_REVIEW_BACKEND=glm \
    SPARRING_GLM_API_KEY=definitely-invalid-key \
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
# 跑这个测试需要真实网络（curl 会尝试）。加条件跳过：没网络或快速 CI 时不跑
if [[ "${SPARRING_TEST_SKIP_NETWORK:-}" != "1" ]]; then
    test_verify_returns_nonzero_on_failure
fi

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
echo "=== claude.mode=agent 命令组装 ==="

# mock claude 扩展版：额外 dump --add-dir 和 --disallowedTools 的值
_make_mock_claude_v2() {
    local dir="$TMP_DIR/mock-claude-v2-$RANDOM"
    mkdir -p "$dir"
    cat > "$dir/claude" <<'MOCK'
#!/bin/bash
ARGV_NL=$(printf '%s\n' "$@")
{
  echo "PWD: $PWD"
  echo "HAS_PRINT: $(echo "$ARGV_NL" | grep -qx -- '-p' && echo yes || echo no)"
  echo "HAS_DISALLOWED: $(echo "$ARGV_NL" | grep -qx -- '--disallowedTools' && echo yes || echo no)"
  echo "DISALLOWED_VAL: $(echo "$ARGV_NL" | grep -A1 -x -- '--disallowedTools' | tail -1)"
  echo "HAS_ADD_DIR: $(echo "$ARGV_NL" | grep -qx -- '--add-dir' && echo yes || echo no)"
  echo "ADD_DIR_VAL: $(echo "$ARGV_NL" | grep -A1 -x -- '--add-dir' | tail -1)"
} > "$CLAUDE_MOCK_DUMP"
cat > /dev/null 2>&1 || true
echo "APPROVE"
echo "mock ok"
MOCK
    chmod +x "$dir/claude"
    echo "$dir"
}

test_claude_diff_mode_no_add_dir() {
    source_workflow_funcs
    local mockdir dump
    mockdir=$(_make_mock_claude_v2)
    export CLAUDE_MOCK_DUMP="$TMP_DIR/dump-diff-mode-$RANDOM.txt"

    PATH="$mockdir:$PATH" call_claude_agent "审查代码" 2>/dev/null
    dump=$(cat "$CLAUDE_MOCK_DUMP" 2>/dev/null)

    assert_contains "diff 模式无 --add-dir" "HAS_ADD_DIR: no" "$dump"
    assert_contains "diff 模式有 --disallowedTools" "HAS_DISALLOWED: yes" "$dump"
    assert_contains "diff 模式 Read 在 disallowed 中" "Read" \
        "$(echo "$dump" | grep DISALLOWED_VAL)"
    unset CLAUDE_MOCK_DUMP
}
test_claude_diff_mode_no_add_dir

test_claude_agent_mode_has_add_dir() {
    source_workflow_funcs
    local mockdir dump
    mockdir=$(_make_mock_claude_v2)
    export CLAUDE_MOCK_DUMP="$TMP_DIR/dump-agent-mode-$RANDOM.txt"

    PATH="$mockdir:$PATH" SPARRING_CLAUDE_MODE=agent \
        call_claude_agent "审查代码" 2>/dev/null
    dump=$(cat "$CLAUDE_MOCK_DUMP" 2>/dev/null)

    assert_contains "agent 模式有 --add-dir" "HAS_ADD_DIR: yes" "$dump"
    assert_contains "agent 模式 --add-dir 指向 PROJECT_ROOT" "$PROJECT_ROOT" \
        "$(echo "$dump" | grep ADD_DIR_VAL)"
    local disallowed_val
    disallowed_val=$(echo "$dump" | grep DISALLOWED_VAL | sed 's/DISALLOWED_VAL: //')
    if echo "$disallowed_val" | grep -q "\bRead\b"; then
        echo "  ✗ agent 模式不应在 disallowedTools 中禁 Read"
        ((FAIL++))
    else
        echo "  ✓ agent 模式 Read 未被禁用"
        ((PASS++))
    fi
    assert_contains "agent 模式 Edit 仍被禁" "Edit" "$disallowed_val"
    assert_contains "agent 模式 Write 仍被禁" "Write" "$disallowed_val"
    unset CLAUDE_MOCK_DUMP
}
test_claude_agent_mode_has_add_dir

test_claude_agent_mode_downgrade_with_base_url() {
    source_workflow_funcs
    local mockdir dump
    mockdir=$(_make_mock_claude_v2)
    export CLAUDE_MOCK_DUMP="$TMP_DIR/dump-downgrade-$RANDOM.txt"

    # agent 模式 + base_url → 自动降级到 diff 模式
    PATH="$mockdir:$PATH" \
        SPARRING_CLAUDE_MODE=agent \
        SPARRING_CLAUDE_BASE_URL="https://x.test/anthropic" \
        SPARRING_CLAUDE_API_KEY="tok-test" \
        call_claude_agent "审查代码" 2>/dev/null
    dump=$(cat "$CLAUDE_MOCK_DUMP" 2>/dev/null)

    assert_contains "base_url 时 agent 模式降级，无 --add-dir" "HAS_ADD_DIR: no" "$dump"
    unset CLAUDE_MOCK_DUMP
}
test_claude_agent_mode_downgrade_with_base_url

# ─── review input budget（diff 门禁 + denylist）──────────────

echo ""
echo "=== review input budget ==="

# 生成一个 diff 文件段：路径 + N 行 payload
_gen_diff_section() {
    local path="$1" lines="$2" i
    echo "diff --git a/$path b/$path"
    echo "index 0000000..1111111 100644"
    echo "--- a/$path"
    echo "+++ b/$path"
    echo "@@ -0,0 +1,$lines @@"
    for ((i = 1; i <= lines; i++)); do echo "+line $i of $path"; done
}

test_diff_path_excluded() {
    source_workflow_funcs
    local -a pats=()
    while IFS= read -r p; do [[ -n "$p" ]] && pats+=("$p"); done < <(_default_diff_excludes)

    local rc
    _diff_path_excluded "pnpm-lock.yaml" "${pats[@]}" && rc=0 || rc=$?
    assert_eq "顶层 lockfile 命中 denylist" "0" "$rc"
    _diff_path_excluded "apps/web/pnpm-lock.yaml" "${pats[@]}" && rc=0 || rc=$?
    assert_eq "嵌套 lockfile 命中 denylist" "0" "$rc"
    _diff_path_excluded ".env.local" "${pats[@]}" && rc=0 || rc=$?
    assert_eq ".env.local 命中 denylist" "0" "$rc"
    _diff_path_excluded "pkg/vendor/node_modules/x/index.js" "${pats[@]}" && rc=0 || rc=$?
    assert_eq "嵌套 node_modules 命中 denylist" "0" "$rc"
    _diff_path_excluded "src/core/review.ts" "${pats[@]}" && rc=0 || rc=$?
    assert_eq "正常源码不命中 denylist" "1" "$rc"
    _diff_path_excluded "src/environment.ts" "${pats[@]}" && rc=0 || rc=$?
    assert_eq ".env* 不误伤 environment.ts" "1" "$rc"
}
test_diff_path_excluded

test_filter_plain_text_passthrough() {
    source_workflow_funcs
    local input out rc=0
    input=$(for i in $(seq 1 500); do echo "结论第 $i 行"; done)
    out=$(printf '%s' "$input" | _review_filter_diff 400) || rc=$?
    assert_eq "纯文本超 400 行也原样通过（预算只管 diff）" "0" "$rc"
    assert_eq "纯文本内容不被改动" "$input" "$out"
}
test_filter_plain_text_passthrough

test_filter_drops_denylisted_section() {
    source_workflow_funcs
    local input out rc=0
    input=$(_gen_diff_section "src/app.ts" 10; _gen_diff_section "pnpm-lock.yaml" 50; _gen_diff_section "src/util.ts" 8)
    out=$(printf '%s' "$input" | _review_filter_diff 400 "pnpm-lock.yaml" 2>/dev/null) || rc=$?
    assert_eq "denylist 过滤正常返回" "0" "$rc"
    assert_contains "保留 src/app.ts 段" "b/src/app.ts" "$out"
    assert_contains "保留 src/util.ts 段" "b/src/util.ts" "$out"
    if echo "$out" | grep -q "pnpm-lock.yaml"; then
        echo "  ✗ lockfile 段应被剔除"; ((FAIL++))
    else
        echo "  ✓ lockfile 段被剔除"; ((PASS++))
    fi
    # 末段被排除 + 输入无结尾换行：末行也要删干净（wc -l 陷阱回归）
    local out2
    out2=$(printf '%s' "$(_gen_diff_section "src/a.ts" 3; _gen_diff_section "b.lock" 5)" \
        | _review_filter_diff 400 "*.lock" 2>/dev/null)
    if printf '%s' "$out2" | grep -q "of b.lock"; then
        echo "  ✗ 无结尾换行时末段残留"; ((FAIL++))
    else
        echo "  ✓ 无结尾换行时末段删干净"; ((PASS++))
    fi
}
test_filter_drops_denylisted_section

test_filter_budget_reject() {
    source_workflow_funcs
    local input err rc=0
    input=$(_gen_diff_section "src/big.ts" 500)
    err=$(printf '%s' "$input" | _review_filter_diff 400 2>&1 >/dev/null) || rc=$?
    assert_eq "超预算拒绝 rc=1" "1" "$rc"
    assert_contains "报错含分片建议" "按文件/目录分片" "$err"
    assert_contains "报错含最大文件段" "src/big.ts" "$err"

    rc=0
    printf '%s' "$input" | _review_filter_diff 0 >/dev/null 2>&1 || rc=$?
    assert_eq "预算 0 = 不限，放行" "0" "$rc"

    # denylist 先过滤再算预算：lockfile 巨段不该触发拒绝
    rc=0
    input=$(_gen_diff_section "src/app.ts" 10; _gen_diff_section "pnpm-lock.yaml" 1000)
    printf '%s' "$input" | _review_filter_diff 400 "pnpm-lock.yaml" >/dev/null 2>&1 || rc=$?
    assert_eq "denylist 过滤后不超预算则放行" "0" "$rc"
}
test_filter_budget_reject

test_review_adhoc_budget_gate() {
    source_workflow_funcs
    local rc=0 err
    # 超预算：应在调 reviewer 之前就拒绝（不会打到网络）
    err=$(_gen_diff_section "src/huge.ts" 900 | review_adhoc --title "t" 2>&1 >/dev/null) || rc=$?
    assert_eq "review_adhoc 超预算拒绝 rc=1" "1" "$rc"
    assert_contains "review_adhoc 报错含预算提示" "max-diff-lines" "$err"

    # 全部被排除 → 明确报错而不是送空审
    rc=0
    err=$(_gen_diff_section "pnpm-lock.yaml" 20 | review_adhoc 2>&1 >/dev/null) || rc=$?
    assert_eq "全被 denylist 排除时 rc=1" "1" "$rc"
    assert_contains "全排除报错提示" "没有剩余可审内容" "$err"

    # --exclude 追加 pattern + --max-diff-lines 覆盖默认
    rc=0
    err=$(_gen_diff_section "docs/gen.md" 30 | review_adhoc --exclude 'docs/*' 2>&1 >/dev/null) || rc=$?
    assert_eq "--exclude 全排除时 rc=1" "1" "$rc"
    rc=0
    err=$(_gen_diff_section "src/a.ts" 30 | review_adhoc --max-diff-lines 10 2>&1 >/dev/null) || rc=$?
    assert_eq "--max-diff-lines 覆盖默认值" "1" "$rc"

    # --no-default-excludes: 同样的 lockfile diff 不再被 denylist 剔除，
    # 走到预算检查（超预算报错 ≠ 全排除报错，证明 denylist 被禁用）
    rc=0
    err=$(_gen_diff_section "pnpm-lock.yaml" 30 | review_adhoc --no-default-excludes --max-diff-lines 10 2>&1 >/dev/null) || rc=$?
    assert_eq "--no-default-excludes 时 lockfile 不被剔除 rc=1" "1" "$rc"
    assert_contains "--no-default-excludes 时走到预算拒绝" "超出预算" "$err"
}
test_review_adhoc_budget_gate

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
    XDG_STATE_HOME="$state_home" _review_log_append 2 CONCERNS 'ti"tle 带"引号' 42 7 glm primary
    local f
    f=$(ls "$state_home/sparring"/review-*.jsonl 2>/dev/null | head -1)
    assert_file_exists "日志文件已创建（按天命名）" "$f"
    local line
    line=$(tail -1 "$f")
    assert_eq "verdict 字段" "CONCERNS" "$(echo "$line" | jq -r .verdict)"
    assert_eq "title 引号正确转义" 'ti"tle 带"引号' "$(echo "$line" | jq -r .title)"
    assert_eq "backend 字段" "glm" "$(echo "$line" | jq -r .backend)"
    assert_eq "via 字段" "primary" "$(echo "$line" | jq -r .via)"
    assert_eq "input_lines 数字" "42" "$(echo "$line" | jq -r .input_lines)"
    assert_eq "duration_s 数字" "7" "$(echo "$line" | jq -r .duration_s)"
    assert_eq "exit_code 数字" "2" "$(echo "$line" | jq -r .exit_code)"
    # 追加第二行不覆盖
    XDG_STATE_HOME="$state_home" _review_log_append 0 APPROVE t2 1 1 codex fallback
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
    XDG_STATE_HOME="$state_home" _review_log_append 0 APPROVE t 1 1 glm primary
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
    XDG_STATE_HOME="$state_home" _review_log_append 0 APPROVE t 1 1 glm primary
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
    SPARRING_BACKEND_STATE_FILE="$state" WORKFLOW_REVIEW_BACKEND=glm \
        call_reviewer "test prompt" "" >/dev/null 2>&1
    assert_eq "primary 成功记录 'glm primary'" "glm primary" "$(cat "$state")"
    unset -f _call_backend
}
test_call_reviewer_state_primary

test_call_reviewer_state_fallback() {
    source_workflow_funcs
    # mock：glm 失败、codex 成功 → 状态文件按行保留完整尝试链，末行为实际后端
    _call_backend() { [[ "$1" == "glm" ]] && return 1; echo "APPROVE mock"; }
    local state
    state=$(mktemp "$TMP_DIR/state.XXXXXX")
    local rc=0
    SPARRING_BACKEND_STATE_FILE="$state" WORKFLOW_REVIEW_BACKEND=glm \
        WORKFLOW_REVIEW_BACKEND_FALLBACK=codex \
        call_reviewer "test prompt" "" >/dev/null 2>&1 || rc=$?
    assert_eq "降级成功 exit 0" "0" "$rc"
    assert_eq "首行保留 primary 失败记录" "glm primary" "$(head -1 "$state")"
    assert_eq "末行为实际使用的后端" "codex fallback" "$(tail -1 "$state")"
    unset -f _call_backend
}
test_call_reviewer_state_fallback

test_call_reviewer_state_both_fail() {
    source_workflow_funcs
    # mock：主备均失败 → 尝试链完整（glm primary + codex fallback），不丢主后端信息
    _call_backend() { return 1; }
    local state
    state=$(mktemp "$TMP_DIR/state.XXXXXX")
    local rc=0
    SPARRING_BACKEND_STATE_FILE="$state" WORKFLOW_REVIEW_BACKEND=glm \
        WORKFLOW_REVIEW_BACKEND_FALLBACK=codex \
        call_reviewer "test prompt" "" >/dev/null 2>&1 || rc=$?
    assert_eq "主备均失败 exit 1" "1" "$rc"
    assert_eq "尝试链共 2 行" "2" "$(wc -l < "$state" | tr -d ' ')"
    assert_eq "首行 primary" "glm primary" "$(head -1 "$state")"
    assert_eq "末行 fallback" "codex fallback" "$(tail -1 "$state")"
    unset -f _call_backend
}
test_call_reviewer_state_both_fail

test_call_reviewer_state_unset_noop() {
    source_workflow_funcs
    # 未设状态文件（task 制路径）时 no-op，不报错
    _call_backend() { echo "APPROVE mock"; }
    local rc=0
    unset SPARRING_BACKEND_STATE_FILE
    WORKFLOW_REVIEW_BACKEND=glm call_reviewer "test prompt" "" >/dev/null 2>&1 || rc=$?
    assert_eq "无状态文件时正常工作" "0" "$rc"
    unset -f _call_backend
}
test_call_reviewer_state_unset_noop

# ─── Summary ─────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
