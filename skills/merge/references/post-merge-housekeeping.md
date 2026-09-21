# gh-pr:merge — Post-merge housekeeping

Step 4 runs these four side effects, in this order. `references/...` paths below
are relative to `skills/merge/`, the same way SKILL.md writes them.

Four independent soft-fail side effects, in this order. Each reference file
holds the snippet to paste verbatim plus its own rationale; none of them can
block or alter the Step 5 report.

| What | Reference | Failure mode |
|---|---|---|
| PR card → `Done`, then linked Issue cards → `Done` | `references/project-board-sync.md` | silent return without a projectV2 board; failures hit stderr |
| herdr idle-tab hint for the merged branch's local worktree | `references/herdr-tab-notify.sh.md` | read-only; silent skip with no worktree, no `herdr`, or a non-idle agent |
| drop the now-readerless `review-passed` label | `references/review-passed-cleanup.sh.md` | one `[WARN]` line (dEitY719/dotfiles#1636) |
| ai-metrics PR comment | `references/ai-metrics-comment.sh.md` | one `[WARN]` line; skipped entirely when `GH_DISABLE_AI_METRICS=1` |
