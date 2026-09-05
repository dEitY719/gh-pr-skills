# `review-passed` Cleanup — post-merge label removal (soft-fail)

Runs inside Step 4 (post-merge housekeeping), after the board reconciliations
and the herdr hint. Issue #1636, F-5.

Why: `review-passed` is a claim about **one head commit of an open PR**, read
by exactly one consumer — `gh-pr:merge-train`'s Step 3.5 gate. Once the PR is
merged that consumer will never look at it again, so the label has no reader
left. Leaving it on is not dangerous, just wrong-looking: a reopened PR (or a
human scanning the closed list) sees a "verified" badge that describes a head
nobody re-checked. Since #1636 `gh-pr:reply` is the one that applies the
label, and it applies it per pass — so clearing it on merge keeps the
lifecycle closed at both ends.

This is a **cleanup, not an invalidation**: unlike the drops in
`gh-pr:reply` / `gh-resolve:conflict` / `gh-resolve:outdated`, no head
advanced here. It uses the same shared primitive anyway — `_gh_pr_drop_label`
is the single REST-DELETE implementation every skill routes through, never a
hand-inlined REST call (#1563, and #326 Bug B for the add side).

`PR_NUMBER`, `TARGET_REPO` and `TARGET_HOST` are already bound by Step 1 per
`references/github-target.md` (#1403 / #1407) — carry them forward, do not
re-resolve them.

```bash
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_edit_safe.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_edit_safe.sh" ] || {
    printf '[gh-pr:merge] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_edit_safe.sh"

if _rpc_err=$(_gh_pr_drop_label "$PR_NUMBER" review-passed \
        "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
    : # removed, or verifiably never there — both are success, stay quiet
else
    echo "[WARN] merge 후 \`review-passed\` 정리 실패 — 머지 자체는 성공: ${_rpc_err}"
fi
```

Soft-fail is the whole contract here (#1636 Error Cases): **the merge already
happened.** A failed label delete must never change the Step 5 report, never
change this skill's exit status, and never be retried in a loop — it costs one
`[WARN]` line and nothing else.

The helper absorbs a 404 ("label was not on this PR") as success after
verifying the PR's real label list, so no "does it exist?" pre-check is
needed and the common case — a PR that was merged without ever earning the
label — prints nothing at all. Only a genuine failure (permissions, 5xx,
wrong repo/host) reaches rc 1 and carries `gh`'s original error through
stderr, which is what `2>&1` captures for the WARN line.
