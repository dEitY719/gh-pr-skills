#!/usr/bin/env bash
# gh-pr:create Step 1a — base branch via stacked-PR auto-detection.
#
#   _sp=$(TARGET_HOST=<host> GH_REPO=<owner/repo> REMOTE=<remote> \
#       bash skills/create/lib/stacked-pr.sh [N] [--no-stack] [--base <branch>]) || exit $?
#   eval "$_sp"
#
# stdout: ONE line for the caller to eval, values single-quoted —
#   BASE_BRANCH=… PARENT_PR=… ISSUE_NUMBER=… DEFAULT_BRANCH=…
#   Nothing else goes to stdout; "Stacking on PR #N" and every abort reason
#   go to stderr.
# exit (wire contract, abort without pushing on any non-zero):
#   0 resolved | 2 --no-stack + --base | 3 --base without a value
#   4 2+ parent candidates (list on stderr; ask the user, re-run with
#     --base <branch> / --no-stack) | 5 parent PR not OPEN
#   6 parent PR already stacked (multi-stack refused)
#
# Test seams (offline): FAKE_OPEN_PRS, FAKE_ANCESTOR_REFS,
# FAKE_NONDEFAULT_REFS, FAKE_PARENT_STATE, FAKE_PARENT_BODY.
# Design, flow and compatibility matrix: references/stacked-pr.md.
# Guard: tests/create-lib.sh.

# Returns 0 when the repo opts into stacked PRs, 1 otherwise.
# Signals are checked in priority order; the first match short-circuits.
is_stacked_pr_repo() {
    local _repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    [ -n "$_repo_root" ] || return 1

    # 1. Workflow file (strongest, explicit opt-in).
    [ -f "$_repo_root/.github/workflows/stacked-closes-rollup.yml" ] && return 0

    # 2. Policy doc keywords.
    local _f
    for _f in CLAUDE.md AGENTS.md .claude/github-integration.md; do
        [ -f "$_repo_root/$_f" ] || continue
        grep -qE 'claude-enter-issue|stacked[[:space:]-]?PR|Depends on #' \
            "$_repo_root/$_f" 2>/dev/null && return 0
    done

    # 3. AgentToolbox project copy signature.
    [ -d "$_repo_root/agent-toolbox" ] && return 0

    return 1
}

# Reads positional args + flags from $@. Sets globals:
#   STACK_MODE     — auto | no-stack | base
#   STACK_BASE     — branch name when STACK_MODE=base
#   ISSUE_NUMBER   — first positional integer (legacy "/gh-pr:create 123" link)
# Non-integer positionals are deliberately ignored here: that is the [remote]
# positional, already consumed by Step 1a-0 into $REMOTE (dEitY719/dotfiles#1405).
# Returns 0 on success, 2 on mutually-exclusive violation, 3 on bad value.
parse_stacked_args() {
    STACK_MODE=auto
    STACK_BASE=
    ISSUE_NUMBER=
    local _flags_seen=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --no-stack)
                _flags_seen=$((_flags_seen + 1))
                STACK_MODE=no-stack
                shift
                ;;
            --base)
                _flags_seen=$((_flags_seen + 1))
                STACK_MODE=base
                STACK_BASE="${2-}"
                if [ -z "$STACK_BASE" ]; then
                    printf 'gh-pr:create: --base requires a branch name\n' >&2
                    return 3
                fi
                shift 2
                ;;
            *)
                if [ -z "$ISSUE_NUMBER" ] &&
                    printf '%s' "$1" | grep -qE '^[1-9][0-9]*$'; then
                    ISSUE_NUMBER="$1"
                fi
                shift
                ;;
        esac
    done

    if [ "$_flags_seen" -gt 1 ]; then
        printf 'gh-pr:create: --no-stack / --base are mutually exclusive\n' >&2
        return 2
    fi

    return 0
}

# Prints "<pr-number>:<head-ref>" lines, one per ancestor open PR.
# Inputs:
#   $1  default branch name (e.g. "main")
# Helpers (overridable in tests via FAKE_* env vars):
#   _gh_pr_default_open_pr_list
#   _gh_pr_default_is_ancestor
#   _gh_pr_default_default_tip_diff_check

_gh_pr_default_open_pr_list() {
    if [ -n "${FAKE_OPEN_PRS+set}" ]; then
        printf '%s\n' "$FAKE_OPEN_PRS"
        return 0
    fi
    GH_HOST="$TARGET_HOST" gh pr list --repo "$GH_REPO" \
        --state open --json number,headRefName \
        --jq '.[] | "\(.number) \(.headRefName)"' 2>/dev/null
}

_gh_pr_default_is_ancestor() {
    local _ref="$1" _ar
    if [ -n "${FAKE_ANCESTOR_REFS+set}" ]; then
        for _ar in $FAKE_ANCESTOR_REFS; do
            [ "$_ar" = "$_ref" ] && return 0
        done
        return 1
    fi
    git merge-base --is-ancestor "$_ref" HEAD 2>/dev/null
}

_gh_pr_default_default_tip_diff_check() {
    local _ref="$1" _default_tip="$2" _r
    if [ -n "${FAKE_NONDEFAULT_REFS+set}" ]; then
        for _r in $FAKE_NONDEFAULT_REFS; do
            [ "$_r" = "$_ref" ] && return 0
        done
        return 1
    fi
    local _base_with_default _base_with_head
    _base_with_default=$(git merge-base HEAD "$_default_tip" 2>/dev/null)
    _base_with_head=$(git merge-base HEAD "$_ref" 2>/dev/null)
    [ -n "$_base_with_default" ] && [ -n "$_base_with_head" ] &&
        [ "$_base_with_head" != "$_base_with_default" ]
}

find_parent_pr_candidates() {
    local _default_branch="$1"
    # $REMOTE is the [remote] positional bound in Step 1a-0 (dEitY719/dotfiles#1405).
    local _remote="${REMOTE:-origin}"
    local _default_tip="$_remote/$_default_branch"
    local _line _pr _head _candidates

    _candidates=$(_gh_pr_default_open_pr_list)
    [ -z "$_candidates" ] && return 0

    while IFS= read -r _line; do
        [ -z "$_line" ] && continue
        _pr="${_line%% *}"
        _head="${_line#* }"
        [ "$_head" = "$_default_branch" ] && continue
        # Live mode only — fetch the head so the ancestor probe is fresh.
        if [ -z "${FAKE_OPEN_PRS+set}" ]; then
            git fetch "$_remote" "$_head" --quiet 2>/dev/null || continue
        fi
        _gh_pr_default_is_ancestor "$_remote/$_head" || continue
        _gh_pr_default_default_tip_diff_check "$_remote/$_head" "$_default_tip" || continue
        printf '%s:%s\n' "$_pr" "$_head"
    done <<EOF
$_candidates
EOF
}

# Combined fetch — state + body in one `gh pr view`. Output: state.
# Side effect: body is stashed in $_GH_PR_PARENT_BODY_CACHE for the
# stacked-body guard below. Overridable in tests via FAKE_PARENT_STATE
# (state-only callers; existing F-4 fixtures) and FAKE_PARENT_BODY.
_gh_pr_default_parent_state() {
    local _pr="${1:-}" _meta _delim
    if [ -n "${FAKE_PARENT_STATE+set}" ]; then
        printf '%s\n' "$FAKE_PARENT_STATE"
        return 0
    fi
    _delim=$(printf '\001')   # ASCII SOH — never appears in PR bodies
    # shellcheck disable=SC2016  # $d is a jq variable (--arg d), not shell
    _meta=$(GH_HOST="$TARGET_HOST" gh pr view "$_pr" --repo "$GH_REPO" \
        --json state,body \
        --jq --arg d "$_delim" '.state + $d + .body' 2>/dev/null)
    _GH_PR_PARENT_BODY_CACHE="${_meta#*"$_delim"}"
    printf '%s\n' "${_meta%%"$_delim"*}"
}

# Helper — returns the parent body. Prefers the cache populated by
# _gh_pr_default_parent_state above; falls back to a direct fetch (or
# FAKE_PARENT_BODY in tests) when called in isolation.
_gh_pr_default_parent_body() {
    local _pr="${1:-}"
    if [ -n "${_GH_PR_PARENT_BODY_CACHE+set}" ]; then
        printf '%s' "$_GH_PR_PARENT_BODY_CACHE"
        return 0
    fi
    if [ -n "${FAKE_PARENT_BODY+set}" ]; then
        printf '%s' "$FAKE_PARENT_BODY"
        return 0
    fi
    GH_HOST="$TARGET_HOST" gh pr view "$_pr" --repo "$GH_REPO" \
        --json body -q .body 2>/dev/null
}

# Returns 0 when state == OPEN, 5 otherwise (with recovery hint on stderr).
assert_parent_pr_open() {
    local _pr="${1:-}" _state
    _state=$(_gh_pr_default_parent_state "$_pr")
    if [ "$_state" != "OPEN" ]; then
        printf 'gh-pr:create: parent PR #%s state=%s — stacking requires OPEN parent.\n' \
            "$_pr" "${_state:-UNKNOWN}" >&2
        printf 'Next: reopen parent, or run with --no-stack.\n' >&2
        return 5
    fi
    return 0
}

# Returns 0 when the parent body has no "Depends on #N" line, 6 otherwise.
# The `^[[:space:]]*` anchor is intentional: it matches dotfiles `## Related`
# section bodies (where "Depends on #N" sits on its own line under the
# header) and agent-toolbox "\n\nDepends on #N" trailers, but deliberately
# refuses inline prose like "This change Depends on #100 indirectly" —
# matrix-10 case 6 pins that no-false-positive contract. Case-insensitive
# so variants from external tools are also caught.
assert_parent_pr_not_stacked() {
    local _pr="${1:-}" _body
    _body=$(_gh_pr_default_parent_body "$_pr")
    if printf '%s' "$_body" | grep -qiE '^[[:space:]]*Depends[[:space:]]+on[[:space:]]+#[0-9]+'; then
        printf 'gh-pr:create: parent PR #%s is already stacked — multi-stack not supported.\n' \
            "$_pr" >&2
        printf 'Next: merge/squash parent first, or use --no-stack / --base <branch>.\n' >&2
        return 6
    fi
    return 0
}

# --- Dispatch ("How Step 1 of SKILL.md ties it together") ---------------------
parse_stacked_args "$@" || exit $?

DEFAULT_BRANCH=$(GH_HOST="$TARGET_HOST" gh repo view "$GH_REPO" \
    --json defaultBranchRef -q .defaultBranchRef.name)

case "$STACK_MODE" in
    no-stack)
        BASE_BRANCH="$DEFAULT_BRANCH" ; PARENT_PR= ;;
    base)
        BASE_BRANCH="$STACK_BASE" ; PARENT_PR= ;;
    auto)
        if is_stacked_pr_repo "$(git rev-parse --show-toplevel)"; then
            CANDIDATES=$(find_parent_pr_candidates "$DEFAULT_BRANCH")
            COUNT=$(printf '%s\n' "$CANDIDATES" | grep -c .)
            case "$COUNT" in
                0)  BASE_BRANCH="$DEFAULT_BRANCH" ; PARENT_PR= ;;
                1)
                    PARENT_PR="${CANDIDATES%%:*}"
                    BASE_BRANCH="${CANDIDATES#*:}"
                    assert_parent_pr_open "$PARENT_PR" || exit $?
                    assert_parent_pr_not_stacked "$PARENT_PR" || exit $?
                    printf 'Stacking on PR #%s (auto-detected)\n' "$PARENT_PR" >&2 ;;
                *)
                    # 2+ candidates — bash cannot prompt safely (Claude Code is
                    # non-interactive; `read` would hang the runtime). Print the
                    # candidate set and exit the auto branch with both vars
                    # unset; the AI executor handles the choice via the
                    # platform's question primitive (e.g. AskUserQuestion in
                    # Claude Code) and re-runs the case for `base` /
                    # `no-stack` based on the user's reply.
                    printf 'Multiple parent candidates:\n%s\n' "$CANDIDATES" >&2
                    printf 'gh-pr:create: ambiguous parent — ask user, then re-invoke with --base / --no-stack\n' >&2
                    exit 4
                    ;;
            esac
        else
            BASE_BRANCH="$DEFAULT_BRANCH" ; PARENT_PR=
        fi
        ;;
esac

_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
printf 'BASE_BRANCH=%s PARENT_PR=%s ISSUE_NUMBER=%s DEFAULT_BRANCH=%s\n' \
    "$(_q "$BASE_BRANCH")" "$(_q "$PARENT_PR")" "$(_q "$ISSUE_NUMBER")" "$(_q "$DEFAULT_BRANCH")"
