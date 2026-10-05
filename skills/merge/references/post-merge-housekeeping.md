# gh-pr:merge — Post-merge housekeeping

Step 4 runs these four side effects, in this order. `references/...` paths below
are relative to `skills/merge/`, the same way SKILL.md writes them.

Four independent soft-fail side effects, in this order, all run by one script:

```text
TARGET_HOST=<host> START_TS=<epoch> [TOKENS=<n>] \
    bash lib/post-merge-housekeeping.sh <PR_NUMBER> <owner/repo> <headRefName>
```

It **always exits 0** (bad arguments included) and prints at most one
`[WARN]` / `[INFO]` line per side effect. Each reference file below holds that
step's rationale and failure modes; none of them can block or alter the Step 5
report. `tests/merge-lib.sh` is the offline guard.

| What | Reference | Failure mode |
|---|---|---|
| PR card → `Done`, then linked Issue cards → `Done` | `references/project-board-sync.md` | silent return without a projectV2 board; failures hit stderr |
| herdr idle-tab hint for the merged branch's local worktree | `references/herdr-tab-notify.sh.md` | read-only; silent skip with no worktree, no `herdr`, or a non-idle agent |
| drop the now-readerless `review-passed` label | `references/review-passed-cleanup.sh.md` | one `[WARN]` line (dEitY719/dotfiles#1636) |
| ai-metrics PR comment | `references/ai-metrics-comment.sh.md` | one `[WARN]` line; skipped entirely when `GH_DISABLE_AI_METRICS=1` |
