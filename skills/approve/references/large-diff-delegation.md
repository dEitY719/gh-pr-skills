# Large-Diff Explore Delegation

Step 2 of `gh-pr:approve` decides between an inline diff read and a
subagent delegation based on PR size. Large diffs would otherwise
crowd the main context and accumulate cost across chained PR reviews
in the same session.

## Threshold (single source of truth)

`THRESHOLD_LINES = 800` — the sum of `additions + deletions` from
`GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json additions,deletions`.
PRs at or above this threshold are delegated; below it, the inline path
runs unchanged.

This file is the **only** place the number may appear. `gh-pr:review`
Step 4 and its `references/ai-cli-invocation.md` branch on the same
threshold and cite this file rather than restating it, because the two
skills have to move together — changing one alone desyncs the pair
(dEitY719/gh-pr-skills#6 finding B2, dEitY719/gh-pr-skills#36).
`tests/large-diff-threshold.sh` fails if a second copy appears.
Original acceptance criterion: dEitY719/dotfiles#403, single source of truth
in `references/`.

The value was carried over from dEitY719/dotfiles#403 as a starting point, to be
tuned here once PR-size distribution data existed. It now does, and it
holds: across the 121 merged PRs of the `dEitY719/*-skills` family
(2026-09), `additions + deletions` runs p50 139, p75 422, **p90 781**,
p95 1176, max 5253. It sits on the p90 knee — 12 of 121 PRs (9.9%)
delegate. That is the intended shape: the inline path stays on the hot
path for the nine PRs in ten that cannot crowd the context, and the
long tail that can is the part that pays the dispatch. Re-measure
before moving it:

```sh
gh pr list -R <repo> --state merged --limit 100 \
  --json additions,deletions --jq '.[] | .additions + .deletions'
```

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
