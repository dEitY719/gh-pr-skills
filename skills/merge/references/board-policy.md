# Board Status Policy — cross-link

The full rule set for the `Approved` column lives in
`../../approve/references/board-policy.md`. This file is
a thin pointer so the merge skill can cite the SSOT without duplicating
its prose.

## TL;DR for `gh-pr:merge` callers

- The board Status is **advisory**, not a merge gate. `/gh-pr:merge`
  never reads it and never refuses on it.
- Approval enforcement is the `reviewDecision` hard stop in Step 2 only
  (`references/strategy-selection.md` → "Branch protection detection").
- `gh-pr:approve` still owns the write side: a human running
  `/gh-pr:approve` is what moves a card into `Approved`.

## Retired: Step 2-B (removed in #1513)

Step 2-B used to read the current board Status via
`_gh_project_status_query_current` and exit 2 unless it was `Approved`
(escape: `GH_PR_MERGE_SKIP_BOARD_CHECK=1`). Both the step and the env
var are gone.

Why: see `../../approve/references/board-policy.md` →
"2. Merge gate (read side) — removed in #1513" for the full rationale
(the gate was permanently un-satisfiable on `dEitY719/dotfiles`, so it
was deleted rather than left as dead policy).

## See also

- `../../approve/references/board-policy.md` — full rule
  set, why fail-closed, the write-side guard rationale.
- `shell-common/functions/gh_project_status.sh` — `Approved` write-side
  guard (unchanged by #1513).
- `shell-common/functions/gh_audit_builtin_workflows.sh` — audits that
  the "Pull request linked to issue" builtin is OFF, so the guard isn't
  invalidated by an async overwrite.
- `docs/.ssot/github-project-board.md` — column semantics SSOT.
