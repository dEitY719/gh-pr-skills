#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_merge_train_approval_gate.sh
# gh-pr:merge-train's approval gate and gate-off delegated review
# (dEitY719/dotfiles#1519). Two kinds of thing live here:
#
#   * `_gate_probe` and the per-base probe/encode step are NOT copied: they are
#     fence-extracted at load time from the first ```bash block of
#       skills/merge-train/references/approval-gate.md
#     so the tests run the text the skill ships.
#   * `_gate_combine`, `train_pr_route`, `train_review_suppressed` and
#     `train_delegated_outcome` mirror decision TABLES (approval-gate.md
#     "Combining the two sources" / "Applying it per PR", train-loop.md
#     "Delegated review on the gate-off path" step 3) that have no code to
#     extract. gh_pr_merge_train_approval_gate.bats' drift guards grep those
#     docs for every string the mirrors print — change a row, change this file.
#
# `none` is a WHITELIST, never a fallback: a 404, a 403 carrying GitHub's
# plan-limit message, or a cleanly-parsed 2xx. Every other answer is `unknown`
# and keeps the gate on (PR dEitY719/dotfiles#1526 agy+codex review).
# shellcheck disable=SC2034,SC1091  # vars are read by the eval'd shipped blocks or the .bats; sources resolve at run time

APPROVAL_GATE_DOC="${REPO_ROOT}/skills/merge-train/references/approval-gate.md"
TRAIN_LOOP_DOC="${REPO_ROOT}/skills/merge-train/references/train-loop.md"

# ---------------------------------------------------------------------
# Stub for `gh api -i`. The real call is
#   GH_HOST="$TARGET_HOST" gh api -i "<path>"
# Tests inject one raw HTTP response per source:
#   FAKE_RULES_RESPONSE / FAKE_RULES_RC        (rules/branches/...)
#   FAKE_PROTECTION_RESPONSE / FAKE_PROTECTION_RC  (branches/.../protection)
# An empty response models "no HTTP response at all" (network failure).
# ---------------------------------------------------------------------
gh() {
    local path=
    while [ $# -gt 0 ]; do
        case "$1" in
            api | -i) ;;
            *) path="$1" ;;
        esac
        shift
    done
    # Record every probed path so tests can assert the percent-encoding the
    # doc's `@uri` step produces actually reaches the API (PR #1526 review).
    [ -n "${FAKE_PATH_LOG-}" ] && printf '%s\n' "$path" >>"$FAKE_PATH_LOG"
    case "$path" in
        *rules/branches*)
            printf '%s' "${FAKE_RULES_RESPONSE-}"
            return "${FAKE_RULES_RC-0}"
            ;;
        *protection*)
            printf '%s' "${FAKE_PROTECTION_RESPONSE-}"
            return "${FAKE_PROTECTION_RC-0}"
            ;;
    esac
    return 1
}

# Build a raw HTTP response the stub can serve. $1 status, $2 body.
train_gate_http() {
    printf 'HTTP/1.1 %s Whatever\r\nContent-Type: application/json\r\n\r\n%s' "$1" "$2"
}

# ---------------------------------------------------------------------
# The shipped classifier: approval-gate.md -> "Classify each source by HTTP
# status". Echoes `none`, `unknown`, or the required approval count (>= 1).
# ---------------------------------------------------------------------
eval "$(fence_block "$APPROVAL_GATE_DOC" 1 | sed -n '/^_gate_probe() {/,/^}/p')"

# The two jq filters, read out of the same shipped block so a test's direct
# `_gate_probe <path> "$_RULES_JQ"` call uses the doc's filter too.
_RULES_JQ=$(fence_block "$APPROVAL_GATE_DOC" 1 | sed -n "/rules\/branches/{n;s/^ *'\(.*\)')\$/\1/p;}")
_PROTECTION_JQ=$(fence_block "$APPROVAL_GATE_DOC" 1 | sed -n "/\/protection\" /{n;s/^ *'\(.*\)')\$/\1/p;}")

# ---------------------------------------------------------------------
# Mirrors approval-gate.md -> "Combining the two sources" (#1519 F-3, F-4)
# and report-format.md -> "The `approval gate:` field" (#1519 NF-1).
# Echoes "<on|off>|<header text>".
# ---------------------------------------------------------------------
_gate_combine() {
    local _base="$1" _ruleset="$2" _classic="$3"
    local _max=0 _src=''
    case "$_ruleset" in
        none | unknown) ;;
        *) _max="$_ruleset" _src=ruleset ;;
    esac
    case "$_classic" in
        none | unknown) ;;
        *) [ "$_classic" -gt "$_max" ] && { _max="$_classic" _src=protection; } ;;
    esac
    if [ "$_max" -ge 1 ]; then
        printf 'on|%s: %s approvals\n' "$_src" "$_max"
    elif [ "$_ruleset" = unknown ] || [ "$_classic" = unknown ]; then
        printf 'on|fail-closed: %s policy unreadable\n' "$_base"
    else
        printf 'off|no policy on %s\n' "$_base"
    fi
}

# One base branch end to end: the shipped probe/encode tail of the same block
# (BASE_ENC=… RULESET=… CLASSIC=…), then the mirrored combine.
train_gate_verdict() {
    local BASE="$1" TARGET_REPO=o/r TARGET_HOST=github.com BASE_ENC RULESET CLASSIC
    eval "$(fence_block "$APPROVAL_GATE_DOC" 1 | sed -n '/^BASE_ENC=/,$p')"
    _gate_combine "$BASE" "$RULESET" "$CLASSIC"
}

# ---------------------------------------------------------------------
# Mirrors approval-gate.md -> "Applying it per PR".
# $1 gate (on|off), $2 reviewDecision. Echoes proceed | delegate | skip:<reason>.
# ---------------------------------------------------------------------
train_pr_route() {
    local _gate="$1" _rd="$2"
    [ "$_rd" = "APPROVED" ] && {
        printf 'proceed\n'
        return 0
    }
    if [ "$_gate" = "on" ]; then
        printf 'skip:approval required (reviewDecision=%s)\n' "$_rd"
    elif [ -n "$_rd" ]; then
        printf 'skip:gh-pr:merge refuses reviewDecision=%s\n' "$_rd"
    else
        printf 'delegate\n'
    fi
}

# #1519 F-8: the same head was already reviewed by $ME. Returns 0 when the
# delegated review must NOT be re-run.
train_review_suppressed() {
    local _last="$1" _head="$2"
    [ -n "$_last" ] && [ "$_last" = "$_head" ]
}

# ---------------------------------------------------------------------
# Mirrors train-loop.md -> "Delegated review on the gate-off path" step 3.
# $1 board Status ("" = unreadable), $2 ran_this_tick (1|0),
# $3 skill_rc (non-zero = the gh-pr:approve call itself failed, #1519 F-9).
# ---------------------------------------------------------------------
train_delegated_outcome() {
    local _board="$1" _ran="$2" _rc="${3-0}"
    [ "$_rc" -ne 0 ] && {
        printf 'skip:self-record failed\n'
        return 0
    }
    [ "$_board" = "Approved" ] && {
        printf 'proceed\n'
        return 0
    }
    [ -z "$_board" ] && {
        printf 'skip:board unreadable — approval unconfirmed\n'
        return 0
    }
    if [ "$_ran" = "1" ]; then
        printf 'skip:self-record withheld approval (BLOCKER)\n'
    else
        printf 'skip:approval withheld (unchanged since review)\n'
    fi
}
