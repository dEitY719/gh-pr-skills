#!/usr/bin/env bash
# gh-pr:merge Step 4 — the four post-merge side effects, in order.
#
#   TARGET_HOST=<host> START_TS=<epoch> [TOKENS=<n>] \
#       bash skills/merge/lib/post-merge-housekeeping.sh <PR_NUMBER> <owner/repo> <headRefName>
#
#   1. PR card -> Done, then linked Issue cards -> Done   (board, soft loader)
#   2. herdr idle-tab hint for the merged branch's local worktree (read-only)
#   3. drop the now-readerless `review-passed` label      (dEitY719/dotfiles#1636)
#   4. ai-metrics PR comment (skipped when GH_DISABLE_AI_METRICS=1)
#
# Contract: the merge already happened, so every step is soft — at most one
# `[WARN]` / `[INFO]` line each (board diagnostics on stderr), and the script
# ALWAYS exits 0, bad arguments included. Per-step rationale and failure
# modes: references/post-merge-housekeeping.md and the files it tables.
# bash, not sh: the herdr hint uses $'\t' and a here-string.
# Guards: tests/merge-lib.sh, tests/plugin-root-tier5.sh §5.

PR_NUMBER="${1-}"
TARGET_REPO="${2-}"
HEAD_REF="${3-}"
case "$PR_NUMBER" in
    '' | *[!0-9]*) printf '[WARN] gh-pr:merge housekeeping: PR_NUMBER %s is not a number — skipped; the merge itself succeeded.\n' "'$PR_NUMBER'"; exit 0 ;;
esac
if [ -z "$TARGET_REPO" ] || [ -z "${TARGET_HOST:-}" ]; then
    printf '[WARN] gh-pr:merge housekeeping: <owner/repo> and TARGET_HOST must both be set (dEitY719/dotfiles#1403) — skipped; the merge itself succeeded.\n'
    exit 0
fi
# The board helpers call gh themselves and take no host argument.
export GH_HOST="$TARGET_HOST"

# --- 1. Board: PR card -> Done, linked Issue cards -> Done ----------------------
# Soft warn-and-skip loader (harness-skills#60). A missing helper, or one that
# sources but defines nothing (dEitY719/dotfiles#724), skips the board sync with
# ONE warning naming the path — no longer silently (dEitY719/dotfiles#644 NF-1's
# silence hid a broken install).
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" # tier 1
[ -f "$_HELPER" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
    || _HELPER="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_project_status.sh" # tier 2
_sc_was=${SHELL_COMMON+set} _sc_prev="${SHELL_COMMON-}"                              # save
unset -f _gh_project_status_sync 2>/dev/null || :
unalias _gh_project_status_sync 2>/dev/null || :
export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"                     # before the load
# shellcheck disable=SC1090  # resolved at run time by the tier ladder above
[ -r "$_HELPER" ] && . "$_HELPER"
if [ "$(command -v _gh_project_status_sync 2>/dev/null)" = _gh_project_status_sync ]; then
    # --repo is explicit (dEitY719/dotfiles#1405) — the helper's auto-detect answers
    # `gh repo set-default`, not the remote Step 1 resolved.
    _gh_project_status_sync pr "$PR_NUMBER" "Done" --repo "$TARGET_REPO" || true
    # (2) Linked Issue cards -> Done, only behind the proof above: a missing or
    # empty helper skips the whole reconciliation (dEitY719/dotfiles#644, #724).
    for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$TARGET_REPO" 2>/dev/null || true); do
        _gh_project_status_sync issue "$_issue" "Done" \
            --only-from "Backlog,In progress,In review" --repo "$TARGET_REPO" || true
    done
else                                                                                 # tier 5, soft
    if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
    printf '[gh-pr-merge] no usable shell-common at %s — board sync skipped; the merge itself is unaffected.\n' \
        "$_HELPER" >&2
fi
unset _sc_was _sc_prev

# --- 2. herdr idle-tab hint ----------------------------------------------------
# NF-1: every gate here is a silent skip. Either tool missing (the expected
# state on any machine without the agent runner), or no worktree (the merge
# ran on a different machine) → the merge report is unaffected. The two
# builtin `command -v` gates come first so that common case never pays for
# the worktree scan below.
if command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # "Which herdr agent is sitting on this worktree?" comes from one SSOT
    # (dEitY719/dotfiles#1569), sourced — never re-implemented here. This hint used to carry the
    # weakest of the four hand-copied answers: a plain `.cwd == $wt` string
    # equality, which missed both a session that had `cd`-ed inside its worktree
    # and a worktree reached through a symlink. Adopting the shared predicate
    # WIDENS what this hint notices, on purpose; widening is safe precisely
    # because the hint is read-only (NF-2) and costs one INFO line.
    # An unreadable helper is a silent skip like every other gate.
    NOTIFY_LOOKUP_LIB="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/herdr_agent_lookup.sh"
    # shellcheck source=/dev/null
    if [ -r "$NOTIFY_LOOKUP_LIB" ] && . "$NOTIFY_LOOKUP_LIB"; then
        # F-1: locate the local worktree checked out on the merged branch.
        # substr() rather than $2 so a worktree path containing spaces still
        # resolves; --porcelain guarantees the "worktree <path>" / "branch <ref>"
        # line pairing this relies on.
        BRANCH="${HEAD_REF}"
        WT_PATH=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${BRANCH}" \
            '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) print p}' | head -1)

        # F-2: read-only agent enumeration. The lookup matches BOTH `cwd` (where
        # the pane was opened) and `foreground_cwd` (where its shell stands now),
        # on a path BOUNDARY, against the PHYSICAL path — and it takes the first
        # match, because two agents on one worktree is abnormal: ignore the rest,
        # warn about nothing (Error Cases).
        #
        # F-4: the `idle` argument puts the status gate inside the lookup, so a
        # `working`/`blocked` agent yields nothing at all — silence, not a second
        # info line — and does not even pay for the workspace lookup below. A
        # non-zero return is either "herdr could not be asked" or "nothing idle
        # is there"; this hint treats both the same, silently.
        if [ -n "$WT_PATH" ] &&
            MATCH=$(herdr_agent_match_for_cwd "$(herdr_agent_physical_path "$WT_PATH")" idle); then
            # tab_id <TAB> agent_status <TAB> workspace_id. The middle field is
            # discarded: the filter above already pinned it to `idle`.
            IFS=$'\t' read -r TAB_ID _ WS_ID <<<"$MATCH"

            # Label is cosmetic — fall back to the raw workspace id when
            # this read-only lookup fails or the workspace is unlabeled.
            WS_LABEL=$(herdr workspace list 2>/dev/null | jq -r --arg id "$WS_ID" \
                '.result.workspaces[]? | select(.workspace_id == $id) | .label // empty' 2>/dev/null | head -1)

            # F-3: exactly one line, only for an idle agent. The path printed is
            # the one `git worktree list` reported, not its resolved twin — that
            # is the spelling the human will recognise.
            printf "[INFO] herdr tab %s/%s is idle for the merged branch's worktree (%s) — consider: herdr tab close %s / session:worktree-teardown\n" \
                "${WS_LABEL:-$WS_ID}" "$TAB_ID" "$WT_PATH" "$TAB_ID"
        fi
    fi
fi

# --- 3. Drop the now-readerless `review-passed` ---------------------------------
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"                                   # tier 1
if [ ! -f "$_SC/functions/gh_pr_edit_safe.sh" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common"                                # tier 2
fi
unset -f _gh_pr_edit_safe_label 2>/dev/null || :
unalias _gh_pr_edit_safe_label 2>/dev/null || :
export SHELL_COMMON="$_SC"                                                           # before the load
# shellcheck disable=SC1091  # resolved at run time by the tier ladder above
[ -f "$_SC/functions/gh_pr_edit_safe.sh" ] && . "$_SC/functions/gh_pr_edit_safe.sh"
if [ "$(command -v _gh_pr_edit_safe_label 2>/dev/null)" != _gh_pr_edit_safe_label ]; then # tier 5, soft
    unset SHELL_COMMON
    printf '[WARN] gh-pr:merge: no usable shell-common at %s — review-passed NOT cleaned up; the merge itself succeeded.\n' "$_SC"
elif _rpc_err=$(_gh_pr_drop_label "$PR_NUMBER" review-passed \
        "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
    : # removed, or verifiably never there — both are success, stay quiet
else
    echo "[WARN] merge 후 \`review-passed\` 정리 실패 — 머지 자체는 성공: ${_rpc_err}"
fi

# --- 4. ai-metrics PR comment ---------------------------------------------------
ELAPSED=$(( ($(date +%s) - ${START_TS:-$(date +%s)}) / 60 ))
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="---
<details>
<summary>🤖 AI Metrics · 📊 ~${TOKENS:-2000} tokens · 👤 ~0.25 h · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-pr-merge -->
📊 ~${TOKENS:-2000} tokens · 👤 ~0.25 h · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-pr-merge -->

</details>
PR merge: ~$ELAPSED min" >/dev/null \
      || echo "[WARN] ai-metrics comment failed — continuing."
fi
exit 0
