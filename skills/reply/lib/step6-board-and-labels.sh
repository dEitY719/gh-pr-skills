#!/usr/bin/env bash
# gh-pr:reply Step 6 (and the Step 2.5 early exit) — board sync and label writes.
#
#   TARGET_HOST=<host> TARGET_REPO=<owner/repo> \
#       bash skills/reply/lib/step6-board-and-labels.sh --phase pre-gate  <PR_NUMBER> <PUSHED_FIXES>
#   TARGET_HOST=<host> TARGET_REPO=<owner/repo> \
#       bash skills/reply/lib/step6-board-and-labels.sh --phase post-gate <PR_NUMBER>
#
# Two phases because the `review-passed` gate (references/review-passed-gate.md)
# runs BETWEEN them and stays model-driven — it needs ORIGINS from Step 3 (#63):
#
#   pre-gate   PUSHED_FIXES > 0 only: board card back to `In review`, then drop
#              the now-stale `review-passed` (the reviewed commit is no longer
#              head). PUSHED_FIXES = 0 makes no API call at all.
#   post-gate  unconditionally drop `reply-pending` (dEitY719/dotfiles#1524), so
#              a label left on cannot wedge the PR out of gh-pr:merge-train.
#
# Contract: every step is soft-fail — one `[OK]` or `[WARN]` line each, and the
# script ALWAYS exits 0, bad arguments included (one `[WARN]`, nothing written).
# bash, not sh: the vendored helpers it sources use `local` and `${s:i:1}`.
#
# Regression guard: tests/reply-step6.sh

_s6_usage() {
    printf '[WARN] gh-pr:reply step6: %s — nothing written. usage: --phase pre-gate|post-gate <PR_NUMBER> [PUSHED_FIXES]\n' "$1"
    exit 0
}

[ "${1-}" = --phase ] || _s6_usage "first argument must be --phase"
PHASE="${2-}"
PR_NUMBER="${3-}"
PUSHED_FIXES="${4:-0}"
case "$PHASE" in pre-gate | post-gate) ;; *) _s6_usage "unknown phase '$PHASE'" ;; esac
case "$PR_NUMBER" in '' | *[!0-9]*) _s6_usage "PR_NUMBER '$PR_NUMBER' is not a number" ;; esac
case "$PUSHED_FIXES" in '' | *[!0-9]*) _s6_usage "PUSHED_FIXES '$PUSHED_FIXES' is not a number" ;; esac
if [ -z "${TARGET_HOST:-}" ] || [ -z "${TARGET_REPO:-}" ]; then
    _s6_usage "TARGET_HOST and TARGET_REPO must both be set (dEitY719/dotfiles#1403)"
fi
# Pin every gh call below, the helpers' included, to the host Step 1 resolved.
export GH_HOST="$TARGET_HOST"

if [ "$PHASE" = post-gate ]; then
    # REST DELETE, not `gh pr edit --remove-label`: the latter fails silently on
    # repos with a classic Projects board (dEitY719/dotfiles#326 Bug B). A 404
    # means the label was never there — the normal inline-review path, not a
    # warning (dEitY719/dotfiles#1545). `2>&1 >/dev/null`: capture stderr, drop stdout.
    if _rp_err=$(gh api -X DELETE \
            "repos/$TARGET_REPO/issues/$PR_NUMBER/labels/reply-pending" 2>&1 >/dev/null); then
        echo "[OK] \`reply-pending\` 라벨 제거됨 — merge-train 이 이 PR 을 다시 본다"
    else
        case "$_rp_err" in
            *"HTTP 404"* | *"Not Found"*)
                echo "[OK] \`reply-pending\` 라벨 없음 (라벨이 애초에 없었음 — 정상)" ;;
            *)
                echo "[WARN] \`reply-pending\` 라벨 제거 실패 — merge-train 이 이 PR 을 계속 건너뛴다: ${_rp_err}" ;;
        esac
    fi
    exit 0
fi

if [ "$PUSHED_FIXES" -eq 0 ]; then
    echo "[OK] 수정 커밋 push 없음 — 보드와 \`review-passed\` 는 그대로 둔다"
    exit 0
fi

# --- 1. Board back to `In review` --------------------------------------------
# Soft warn-and-skip loader (harness-skills#60), the six steps
# tests/plugin-root-tier5.sh §5 holds verbatim: SAVE, UNSETF, UNALIAS, EXPORT,
# LOAD, PROOF — and a failure arm that RESTORES SHELL_COMMON, never unsets it.
# `--only-from` keeps a card already at In review / Approved / Done where it is.
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" # tier 1
[ -f "$_HELPER" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
    || _HELPER="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_project_status.sh" # tier 2
_sc_was=${SHELL_COMMON+set} _sc_prev="${SHELL_COMMON-}"                          # save
unset -f _gh_project_status_sync 2>/dev/null || :
unalias _gh_project_status_sync 2>/dev/null || :
export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"                 # before the load
# shellcheck disable=SC1090  # resolved at run time by the tier ladder above
[ -r "$_HELPER" ] && . "$_HELPER"
if [ "$(command -v _gh_project_status_sync 2>/dev/null)" != _gh_project_status_sync ]; then # tier 5, soft
    if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
    printf '[WARN] no usable shell-common at %s — board sync skipped; the replies themselves are unaffected.\n' \
        "$_HELPER"
elif _gh_project_status_sync pr "$PR_NUMBER" "In review" \
        --only-from "In progress,Changes requested" \
        --repo "$TARGET_REPO"; then
    echo "[OK] PR 카드 \`In review\` 로 복귀됨"
else
    echo "[WARN] 보드 sync 실패 — 카드 수동 이동 필요할 수 있음"
fi
unset _sc_was _sc_prev

# --- 2. Drop the stale `review-passed` ---------------------------------------
# The label certifies one head commit, and this pass just moved head. Rule SSOT:
# gh_pr_edit_safe.sh header, "Verdict-label invalidation" (dEitY719/dotfiles#1563).
# `review-blocked` is NOT touched here — the gate decides it. Same soft loader
# shape, own save variables so the board loader's six-step sequence stays unique.
_DL="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"   # tier 1
[ -f "$_DL" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
    || _DL="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_pr_edit_safe.sh" # tier 2
_dl_was=${SHELL_COMMON+set} _dl_prev="${SHELL_COMMON-}"                          # save
unset -f _gh_pr_drop_label 2>/dev/null || :
unalias _gh_pr_drop_label 2>/dev/null || :
export SHELL_COMMON="${_DL%/functions/gh_pr_edit_safe.sh}"                       # before the load
# shellcheck disable=SC1090  # resolved at run time by the tier ladder above
[ -r "$_DL" ] && . "$_DL"
if [ "$(command -v _gh_pr_drop_label 2>/dev/null)" != _gh_pr_drop_label ]; then  # tier 5, soft
    if [ -n "$_dl_was" ]; then export SHELL_COMMON="$_dl_prev"; else unset SHELL_COMMON; fi
    printf "[WARN] no usable shell-common at %s — \`review-passed\` NOT dropped; remove it by hand if present.\n" \
        "$_DL"
elif _vl_err=$(_gh_pr_drop_label "$PR_NUMBER" review-passed \
        "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
    echo "[OK] \`review-passed\` 무효화됨 — head 가 전진해 이전 판정은 만료"
else
    echo "[WARN] \`review-passed\` 제거 실패 — 리뷰되지 않은 커밋에 판정이 남아 있다: ${_vl_err}"
fi
unset _dl_was _dl_prev
exit 0
