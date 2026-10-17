#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_merge_train_queue.sh
# The merge-queue path (dEitY719/dotfiles#1707, PR dEitY719/dotfiles#1725).
# Moved from dEitY719/dotfiles tests/bats/functions/_fixtures/ by
# dEitY719/dotfiles#2219 — the half that tests the skill text; the predicates'
# own tests (_gh_pr_merge_train_{needs_finalize,finalize_targets,
# behind_may_merge_directly,base_strict_confirmed,base_ci_red}) stay with their
# SSOT in dotfiles. Every helper below evals a shipped ```bash fence, never a copy:
#
#   * merge_step3_auto   fence 1 of skills/merge/references/merge-queue.md
#   * merge_step3_5      fence 2 of the same file
#   * train_step3_6      the fence of skills/merge-train/references/strict-mode-relaxation.md
#   * train_step0        the fence of skills/merge-train/references/finalize-sweep.md
#
# The train fences load lib/vendor/shell-common through their own tier ladder
# (tier 2, CLAUDE_PLUGIN_ROOT=$REPO_ROOT). The test's `gh` shell function
# stands in for every API call.
# shellcheck disable=SC2034,SC1091  # vars are read by the eval'd shipped blocks or the .bats

QUEUE_DOC="${REPO_ROOT}/skills/merge/references/merge-queue.md"
RELAX_DOC="${REPO_ROOT}/skills/merge-train/references/strict-mode-relaxation.md"
SWEEP_DOC="${REPO_ROOT}/skills/merge-train/references/finalize-sweep.md"

# Usage: _queue_eval <doc> <fence#> — eval the shipped block in a subshell with
# the caller's variables bound and the vendored shell-common reachable.
_queue_eval() {
    local _b
    _b=$(fence_block "$1" "$2")
    (
        unset SHELL_COMMON
        CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
        eval "$_b"
    )
}

# Usage: merge_step3_auto <pr> <repo> <host> <strategy-flag>
merge_step3_auto() {
    local PR_NUMBER="$1" TARGET_REPO="$2" TARGET_HOST="$3" STRATEGY_FLAG="$4"
    _queue_eval "$QUEUE_DOC" 1
}

# Usage: merge_step3_5 <pr> <repo> <host>
# The block prints nothing for MERGED (continue to Step 4); this helper then
# runs the Steps 4+5 stand-in so the tests can observe WHETHER it ran.
merge_step3_5() {
    local PR_NUMBER="$1" TARGET_REPO="$2" TARGET_HOST="$3" _out
    _out=$(_queue_eval "$QUEUE_DOC" 2) || return
    if [ -z "$_out" ]; then
        merge_finalize_sequence "$PR_NUMBER"
    else
        printf '%s\n' "$_out"
    fi
}

# Stand-in for the Steps 4+5 completion sequence. Records that it ran.
merge_finalize_sequence() {
    printf 'finalize:%s\n' "$1" >>"${FINALIZE_LOG:-/dev/null}"
    printf '[OK] PR #%s merged (rebase)\n' "$1"
}

# Usage: train_step3_6 <base> <rules-body> <checks-body>
# An empty body makes that `gh api` call fail; anything else is answered as-is.
# Echoes whatever verdict line the block prints, then `BEHIND_DIRECT=<yes|no>`.
train_step3_6() {
    local BASE="$1" TARGET_REPO=acme/widget TARGET_HOST=github.com
    STUB_RULES="$2" STUB_CHECKS="$3"
    # shellcheck disable=SC2317  # called by the eval'd block
    gh() {
        case "$*" in
        *rules/branches/*) [ -n "$STUB_RULES" ] && printf '%s' "$STUB_RULES" ;;
        *check-runs*) [ -n "$STUB_CHECKS" ] && printf '%s' "$STUB_CHECKS" ;;
        *) return 1 ;;
        esac
    }
    (
        unset SHELL_COMMON
        CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
        eval "$(fence_block "$RELAX_DOC" 1)"
        printf 'BEHIND_DIRECT=%s\n' "$BEHIND_DIRECT"
    )
}

# Usage: train_step0 <gh-search-json> — prints the PR numbers the sweep finalizes.
train_step0() {
    local TARGET_REPO=acme/widget TARGET_HOST=github.com
    STUB_SEARCH="$1"
    # shellcheck disable=SC2317  # called by the eval'd block
    gh() {
        printf 'gh %s\n' "$*" >>"${GH_LOG:-/dev/null}"
        printf '%s' "$STUB_SEARCH"
    }
    _queue_eval "$SWEEP_DOC" 1
}
