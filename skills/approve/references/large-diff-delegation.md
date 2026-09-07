# Large-Diff Explore Delegation

Step 2 of `gh-pr:approve` decides between an inline diff read and a
subagent delegation based on PR size. Large diffs would otherwise
crowd the main context and accumulate cost across chained PR reviews
in the same session.

## Threshold (single source of truth)

`THRESHOLD_LINES = 4000` — the sum of `additions + deletions` from
`GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json additions,deletions`.
PRs at or above this threshold are delegated; below it, the inline path
runs unchanged.

Raised from the original 800 (dEitY719/dotfiles#403): 800 lines was cheap
enough to review inline, so that threshold paid the subagent round-trip and
fidelity loss for no benefit. 4000 still catches the diffs that actually
crowd the main context (generated code, vendored dumps, mass renames).

The number is a starting point. Tune it in this file when PR-size
distribution data justifies it. Do **not** hardcode the threshold
anywhere else (issue dEitY719/dotfiles#403 acceptance criterion: single source of
truth in references/).

## When to delegate

Pure size gate. Re-review mode does not change the decision: the
returned summary still feeds Step 3, and prior-concern mapping
happens on top of it.

## Dispatch

Invoke `Agent(subagent_type="Explore")` with this prompt template
(substitute `<N>`, `<TARGET_REPO>`, and `<TARGET_HOST>` — the subagent gets a
fresh shell, so the exported `GH_HOST` does not reach it):

> Summarize the diff for PR #<N> in repo <TARGET_REPO> for review
> classification. Run `GH_HOST=<TARGET_HOST> gh pr diff <N> --repo <TARGET_REPO>`
> (and any follow-up grep / file read needed for context). Return a short
> report (≤ 300 words) split into three sections:
>
> 1. **BLOCKER candidates** — correctness, security, regression risks.
>    Each item: `file:line` + one-line reason.
> 2. **FOLLOW-UP candidates** — non-blocking quality concerns. Each
>    item: `file:line` + one-line reason.
> 3. **PRAISE candidates** — concrete diff locations worth highlighting.
>    Each item: `file:line` + one-line reason.
>
> Do not include the full diff text. Only the classified items. If a
> section is empty, write `(none)`.

Use the returned summary as input to Step 3 classification. The
Step 4 templates and the 4a / 4b / 4c approval-path branching remain
unchanged — only the source of the classified findings differs.

## Why not delegate every PR

Small PRs would pay the subagent dispatch overhead (cold context,
extra round-trip) for no context-savings benefit. The size gate
keeps the inline path on the hot path while bounding worst-case
context growth on large reviews.
