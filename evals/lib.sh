#!/usr/bin/env bash
# evals/lib.sh — assertion + helper functions for the eval harness.
# Sourced by evals/run.sh; not directly executable.
#
# A note on philosophy: the harness validates the bash-plumbing layer
# (file-type classification, diff-position mapping, re-review iteration
# detection, summary substance). It does not test Claude's review
# reasoning — that's covered by Test 3 (end-to-end on a real PR). Each
# check here asserts a single deterministic property of script output,
# compared by substance, never by byte-for-byte snapshot.

# Globals owned by run.sh:
#   PASS_COUNT, FAIL_COUNT (integers)
#   FAIL_MESSAGES (array)
#   REPO_ROOT
# Per-fixture, mutated inside run_fixture:
#   FIXTURE_NAME, FIXTURE_ERRORS, WORK_DIR

REVIEW_SCRIPTS="${REPO_ROOT}/plugins/echoreview/skills/review/scripts"
PLUGIN_SCRIPTS="${REPO_ROOT}/plugins/echoreview/scripts"

# fail_check MESSAGE — record a check failure for the current fixture.
fail_check() {
    FIXTURE_ERRORS+=("$1")
}

# run_script SCRIPT_NAME ENV_VARS... -- ARGS... — run a script with the
# given env vars and positional args, capturing exit + stderr. Returns
# nonzero on script failure with the captured stderr in $LAST_STDERR.
run_script() {
    local script="$1"; shift
    local -a env_assignments=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        env_assignments+=("$1")
        shift
    done
    [[ "${1:-}" == "--" ]] && shift
    local stderr_file
    stderr_file="$(mktemp)"
    if env "${env_assignments[@]}" "${REVIEW_SCRIPTS}/${script}" "$@" \
            >/dev/null 2>"$stderr_file"; then
        LAST_STDERR=""
        rm -f "$stderr_file"
        return 0
    else
        LAST_STDERR="$(cat "$stderr_file")"
        rm -f "$stderr_file"
        return 1
    fi
}

# --- check implementations ---

# check_file_type — assert file-types.json classifies $file as $expected.
check_file_type() {
    local check_json="$1"
    local file expected actual
    file=$(jq -r '.file' <<<"$check_json")
    expected=$(jq -r '.expected' <<<"$check_json")
    if [[ ! -r "${WORK_DIR}/file-types.json" ]]; then
        fail_check "file_type: file-types.json missing"
        return 1
    fi
    actual=$(jq -r --arg f "$file" '.[] | select(.file == $f) | .type' \
        "${WORK_DIR}/file-types.json")
    if [[ "$actual" != "$expected" ]]; then
        fail_check "file_type(${file}): expected '${expected}', got '${actual:-<missing>}'"
        return 1
    fi
    return 0
}

# check_file_count_with_type — assert N files in file-types.json have $type.
check_file_count_with_type() {
    local check_json="$1"
    local type expected actual
    type=$(jq -r '.expected_type' <<<"$check_json")
    expected=$(jq -r '.expected_count' <<<"$check_json")
    if [[ ! -r "${WORK_DIR}/file-types.json" ]]; then
        fail_check "file_count_with_type: file-types.json missing"
        return 1
    fi
    actual=$(jq --arg t "$type" '[.[] | select(.type == $t)] | length' \
        "${WORK_DIR}/file-types.json")
    if [[ "$actual" != "$expected" ]]; then
        fail_check "file_count_with_type(${type}): expected ${expected}, got ${actual}"
        return 1
    fi
    return 0
}

# check_only_file_types — assert ALL entries in file-types.json have
# one of the listed types (used for skip-condition fixtures).
check_only_file_types() {
    local check_json="$1"
    local allowed offenders
    allowed=$(jq -c '.allowed' <<<"$check_json")
    if [[ ! -r "${WORK_DIR}/file-types.json" ]]; then
        fail_check "only_file_types: file-types.json missing"
        return 1
    fi
    offenders=$(jq -r --argjson allowed "$allowed" '
        .[] | select(.type as $t | ($allowed | index($t)) | not) | "\(.file)=\(.type)"
    ' "${WORK_DIR}/file-types.json" | tr '\n' ' ')
    if [[ -n "$offenders" ]]; then
        fail_check "only_file_types: offenders: ${offenders}"
        return 1
    fi
    return 0
}

# check_diff_map_line — assert diff-map.json has an entry for file:line.
check_diff_map_line() {
    local check_json="$1"
    local file line key found
    file=$(jq -r '.file' <<<"$check_json")
    line=$(jq -r '.line' <<<"$check_json")
    key="${file}:${line}"
    if [[ ! -r "${WORK_DIR}/diff-map.json" ]]; then
        fail_check "diff_map_line: diff-map.json missing"
        return 1
    fi
    found=$(jq --arg k "$key" 'has($k)' "${WORK_DIR}/diff-map.json")
    if [[ "$found" != "true" ]]; then
        fail_check "diff_map_line: ${key} not in diff-map.json"
        return 1
    fi
    return 0
}

# check_review_iteration — assert review-iteration.txt equals $expected.
check_review_iteration() {
    local check_json="$1"
    local expected actual
    expected=$(jq -r '.expected' <<<"$check_json")
    if [[ ! -r "${WORK_DIR}/review-iteration.txt" ]]; then
        fail_check "review_iteration: review-iteration.txt missing"
        return 1
    fi
    actual=$(tr -d '[:space:]' < "${WORK_DIR}/review-iteration.txt")
    if [[ "$actual" != "$expected" ]]; then
        fail_check "review_iteration: expected '${expected}', got '${actual}'"
        return 1
    fi
    return 0
}

# check_summary_contains_count — assert previous-comments.md has a heading
# claiming $expected prior comments.
check_summary_contains_count() {
    local check_json="$1"
    local expected
    expected=$(jq -r '.expected' <<<"$check_json")
    if [[ ! -r "${WORK_DIR}/previous-comments.md" ]]; then
        fail_check "summary_contains_count: previous-comments.md missing"
        return 1
    fi
    if ! grep -q "Prior review comments (${expected})" \
            "${WORK_DIR}/previous-comments.md"; then
        fail_check "summary_contains_count: 'Prior review comments (${expected})' not found in previous-comments.md"
        return 1
    fi
    return 0
}

# check_summary_quotes_author — assert previous-comments.md mentions $author.
check_summary_quotes_author() {
    local check_json="$1"
    local author
    author=$(jq -r '.author' <<<"$check_json")
    if [[ ! -r "${WORK_DIR}/previous-comments.md" ]]; then
        fail_check "summary_quotes_author: previous-comments.md missing"
        return 1
    fi
    if ! grep -q "@${author}" "${WORK_DIR}/previous-comments.md"; then
        fail_check "summary_quotes_author: '@${author}' not found in previous-comments.md"
        return 1
    fi
    return 0
}

# check_summary_preserves_reply_chain — assert previous-comments.md
# records at least one non-null in_reply_to_id.
check_summary_preserves_reply_chain() {
    if [[ ! -r "${WORK_DIR}/previous-comments.md" ]]; then
        fail_check "summary_preserves_reply_chain: previous-comments.md missing"
        return 1
    fi
    if ! grep -qE 'in_reply_to_id: [0-9]+' "${WORK_DIR}/previous-comments.md"; then
        fail_check "summary_preserves_reply_chain: no 'in_reply_to_id: <n>' record found"
        return 1
    fi
    return 0
}

# check_patterns_readable — assert ./patterns.md (relative to fixture)
# parses as the expected schema: each rule has [ECHO-...], severity:,
# applies_to:, ≥1 evidence quote.
check_patterns_readable() {
    local check_json="$1"
    local expected_rules patterns_file rule_count quote_count
    expected_rules=$(jq -r '.expected_rule_count' <<<"$check_json")
    patterns_file="${WORK_DIR}/patterns.md"
    if [[ ! -r "$patterns_file" ]]; then
        fail_check "patterns_readable: patterns.md missing in fixture"
        return 1
    fi
    rule_count=$(grep -c '^### \[ECHO-' "$patterns_file" || true)
    if [[ "$rule_count" -lt "$expected_rules" ]]; then
        fail_check "patterns_readable: expected >= ${expected_rules} rules, got ${rule_count}"
        return 1
    fi
    quote_count=$(grep -c '^> \*"' "$patterns_file" || true)
    if [[ "$quote_count" -lt "$rule_count" ]]; then
        fail_check "patterns_readable: ${quote_count} evidence quotes for ${rule_count} rules (each rule needs ≥1)"
        return 1
    fi
    return 0
}

# check_patterns_header — assert ./patterns.md carries every required header
# token (e.g. "Requested:", "Window mined:", "--coverage", "weeks)"). Guards
# against a silent header-field rename, which the rule-body checks above miss.
check_patterns_header() {
    local check_json="$1"
    local patterns_file requires missing token
    patterns_file="${WORK_DIR}/patterns.md"
    if [[ ! -r "$patterns_file" ]]; then
        fail_check "patterns_header: patterns.md missing in fixture"
        return 1
    fi
    requires=$(jq -r '.requires[]' <<<"$check_json")
    missing=""
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        if ! grep -qF -- "$token" "$patterns_file"; then
            missing+="${token}; "
        fi
    done <<<"$requires"
    if [[ -n "$missing" ]]; then
        fail_check "patterns_header: missing header token(s): ${missing}"
        return 1
    fi
    return 0
}

# check_agents_resolution — assert resolve-agents.sh maps a given
# ECHOREVIEW_AGENTS value plus flag tokens to the expected mode/cap/verify.
# Unlike the other checks this drives a plugin script directly instead of
# inspecting WORK_DIR, so it carries its own inputs in the check JSON:
#   { "label", "env"?, "args"?: [..], "expected_mode", "expected_cap",
#     "expected_verify" }. Omit "env" (or set it null) to test the unset case.
check_agents_resolution() {
    local check_json="$1"
    local label em ec ev has_env expected actual
    label=$(jq -r '.label // "agents_resolution"' <<<"$check_json")
    em=$(jq -r '.expected_mode' <<<"$check_json")
    ec=$(jq -r '.expected_cap' <<<"$check_json")
    ev=$(jq -r '.expected_verify' <<<"$check_json")

    local -a flags=()
    while IFS= read -r tok; do
        flags+=("$tok")
    done < <(jq -r '(.args // [])[]' <<<"$check_json")

    has_env=$(jq -r 'if has("env") and .env != null then "yes" else "no" end' \
        <<<"$check_json")
    if [[ "$has_env" == "yes" ]]; then
        local env_val
        env_val=$(jq -r '.env' <<<"$check_json")
        actual=$(ECHOREVIEW_AGENTS="$env_val" \
            "${PLUGIN_SCRIPTS}/resolve-agents.sh" ${flags[@]+"${flags[@]}"} \
            2>/dev/null) || true
    else
        actual=$(env -u ECHOREVIEW_AGENTS \
            "${PLUGIN_SCRIPTS}/resolve-agents.sh" ${flags[@]+"${flags[@]}"} \
            2>/dev/null) || true
    fi

    printf -v expected '%s\t%s\t%s' "$em" "$ec" "$ev"
    if [[ "$actual" != "$expected" ]]; then
        fail_check "agents_resolution(${label}): expected '$(printf '%s' "$expected" | tr '\t' '|')', got '$(printf '%s' "$actual" | tr '\t' '|')'"
        return 1
    fi
    return 0
}

# dispatch_check CHECK_JSON — route to the right check function by .type.
dispatch_check() {
    local check_json="$1"
    local check_type
    check_type=$(jq -r '.type' <<<"$check_json")
    case "$check_type" in
        file_type)                       check_file_type "$check_json" ;;
        file_count_with_type)            check_file_count_with_type "$check_json" ;;
        only_file_types)                 check_only_file_types "$check_json" ;;
        diff_map_line)                   check_diff_map_line "$check_json" ;;
        review_iteration)                check_review_iteration "$check_json" ;;
        summary_contains_count)          check_summary_contains_count "$check_json" ;;
        summary_quotes_author)           check_summary_quotes_author "$check_json" ;;
        summary_preserves_reply_chain)   check_summary_preserves_reply_chain ;;
        patterns_readable)               check_patterns_readable "$check_json" ;;
        patterns_header)                 check_patterns_header "$check_json" ;;
        agents_resolution)               check_agents_resolution "$check_json" ;;
        *)
            fail_check "unknown check type: ${check_type}"
            return 1
            ;;
    esac
}

# run_fixture FIXTURE_NAME FIXTURE_PATH — orchestrate one fixture run.
run_fixture() {
    FIXTURE_NAME="$1"
    local fixture_path="$2"
    local input_dir="${fixture_path}input"
    local expected_file="${fixture_path}expected.json"
    FIXTURE_ERRORS=()

    if [[ ! -d "$input_dir" ]]; then
        echo "FAIL: ${FIXTURE_NAME}"
        echo "  - missing input/ directory at ${input_dir}"
        FAIL_MESSAGES+=("${FIXTURE_NAME}: missing input/ directory")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi
    if [[ ! -r "$expected_file" ]]; then
        echo "FAIL: ${FIXTURE_NAME}"
        echo "  - missing expected.json at ${expected_file}"
        FAIL_MESSAGES+=("${FIXTURE_NAME}: missing expected.json")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    WORK_DIR="$(mktemp -d -t echoreview-eval-XXXXXX)"
    cp -R "${input_dir}/." "$WORK_DIR/"

    # Also copy a sibling patterns.md into WORK_DIR if present (for the
    # patterns-driven fixture's check_patterns_readable).
    if [[ -r "${fixture_path}patterns.md" ]]; then
        cp "${fixture_path}patterns.md" "${WORK_DIR}/patterns.md"
    fi

    # 1. extract-context.sh — runs whenever files.txt is present.
    if [[ -f "${WORK_DIR}/files.txt" ]]; then
        if ! run_script extract-context.sh \
                "ECHOREVIEW_SKIP_FETCH=1" "WORK_DIR=${WORK_DIR}" \
                -- stub stub 0; then
            fail_check "extract-context.sh failed: ${LAST_STDERR}"
        fi
    fi

    # 2. build-diff-map.sh — runs whenever diff.patch is present.
    if [[ -f "${WORK_DIR}/diff.patch" ]]; then
        if ! run_script build-diff-map.sh \
                "WORK_DIR=${WORK_DIR}" \
                -- stub stub 0; then
            fail_check "build-diff-map.sh failed: ${LAST_STDERR}"
        fi
    fi

    # 3. fetch-comments.sh — runs whenever existing-comments.json is present.
    if [[ -f "${WORK_DIR}/existing-comments.json" ]]; then
        if ! run_script fetch-comments.sh \
                "ECHOREVIEW_SKIP_FETCH=1" "WORK_DIR=${WORK_DIR}" \
                -- stub stub 0; then
            fail_check "fetch-comments.sh failed: ${LAST_STDERR}"
        fi
    fi

    # Now run each check from expected.json.
    local check_count i check_json
    check_count=$(jq '.checks | length' "$expected_file")
    i=0
    while (( i < check_count )); do
        check_json=$(jq -c ".checks[$i]" "$expected_file")
        dispatch_check "$check_json" || true
        i=$((i + 1))
    done

    local name description
    name=$(jq -r '.name // ""' "$expected_file")
    description=$(jq -r '.description // ""' "$expected_file")

    if [[ ${#FIXTURE_ERRORS[@]} -eq 0 ]]; then
        echo "PASS: ${FIXTURE_NAME} — ${name}"
        [[ -n "$description" ]] && echo "        ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL: ${FIXTURE_NAME} — ${name}"
        [[ -n "$description" ]] && echo "        ${description}"
        local e
        for e in "${FIXTURE_ERRORS[@]}"; do
            echo "  - ${e}"
            FAIL_MESSAGES+=("${FIXTURE_NAME}: ${e}")
        done
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    rm -rf "$WORK_DIR"
}
