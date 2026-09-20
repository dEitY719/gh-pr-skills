# gh-pr:reply Step 6.5 — Sync Project Board (`In review` 복귀)

Called from `SKILL.md` Step 6.5. If Step 6 actually pushed at least one
fix commit (i.e. `PUSHED_FIXES > 0`, new SHAs created on the remote
branch), push the PR card back to `In review` so reviewers see it in
their queue. Mirrors the `/gh-resolve:conflict` Step 5 pattern
(issue dEitY719/dotfiles#591) so both flows share one board-recovery surface.

Skips when `PUSHED_FIXES == 0` (all comments DECLINE / QUESTION — no
push happened, so the card lifecycle has not changed and there is
nothing to recover). The `--only-from "In progress,Changes requested"`
guard makes the call a no-op for cards already at `In review` /
`Approved` / `Done`, so re-running on an already-recovered card never
demotes status.

Soft-fail — warn on any error, never block the Step 7 report.

```bash
if [ "${PUSHED_FIXES:-0}" -gt 0 ]; then
    # Soft warn-and-skip loader (harness-skills#60). A missing helper, or one
    # that sources but defines nothing (dEitY719/dotfiles#724), skips the board
    # sync with ONE warning naming the path — no longer silently.
    _HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" # tier 1
    [ -f "$_HELPER" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
        || _HELPER="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_project_status.sh" # tier 2
    _sc_was=${SHELL_COMMON+set} _sc_prev="${SHELL_COMMON-}"                          # save
    unset -f _gh_project_status_sync 2>/dev/null || :
    unalias _gh_project_status_sync 2>/dev/null || :
    export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"                 # before the load
    [ -r "$_HELPER" ] && . "$_HELPER"
    if [ "$(command -v _gh_project_status_sync 2>/dev/null)" != _gh_project_status_sync ]; then # tier 5, soft
        if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
        printf '[gh-pr-reply] no usable shell-common at %s — board sync skipped; the replies themselves are unaffected.\n' \
            "$_HELPER" >&2
    elif _gh_project_status_sync pr "$PR_NUMBER" "In review" \
            --only-from "In progress,Changes requested" \
            --repo "$TARGET_REPO"; then
        echo "[OK] PR 카드 \`In review\` 로 복귀됨"
    else
        echo "[WARN] 보드 sync 실패 — 카드 수동 이동 필요할 수 있음"
    fi
    unset _sc_was _sc_prev
fi
```

`--repo "$TARGET_REPO"` 는 Step 1 이 해소한 remote 를 명시로 넘긴다 (dEitY719/dotfiles#1405) —
빼면 헬퍼가 `gh repo view` 로 폴백하는데, 이는 git origin 이 아니라
`gh repo set-default` 가 고른 레포를 답한다.

`GH_PROJECT_STATUS_SYNC=0` opt-out is absorbed by the helper itself.
projectV2 보드가 없는 레포는 helper 가 silent 0 반환. `--only-from`
의 missing column 은 helper 가 silently skip 하므로 `Changes requested`
컬럼 없는 보드와도 호환된다.
