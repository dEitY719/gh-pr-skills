# Finalize a merged PR — the post-merge completion sequence (SSOT)

Issue dEitY719/dotfiles#1707. This file defines **the order and the membership** of everything
`gh-pr:merge` does *after* a PR is actually merged. It is not a second copy of
those steps — each one already has its own SSOT file, listed below — it is the
one place that says *which* steps make up "the merge is finished" and *in what
order*, so the two callers cannot drift apart:

| Caller | When | Report line |
|---|---|---|
| `gh-pr:merge` Steps 4 + 5 | immediately, in the same run that merged the PR | `[OK] PR #<N> merged (<strategy>)` |
| `gh-pr:merge` `--finalize` | later, on a PR the **merge queue** merged with no session watching | `[FINALIZED] #<N> <title>` |

The second entry point exists because of `--auto` (dEitY719/dotfiles#1707). With a merge queue
active on the base, `gh pr merge --auto` returns success while the PR is still
`OPEN` — GitHub merges it minutes later, server-side, and nothing is running at
that moment to sync the board, post ai-metrics, drop the label or close the
implementation tab. `gh-pr:merge-train`'s Step 0 sweep finds those PRs on a
later tick (`_gh_pr_merge_train_needs_finalize`) and re-enters here.

## The sequence

Run these **in this order**. Every one is soft-fail: the merge already
happened, so nothing here may change an exit status or suppress the report.
Steps 1-4 are the one `lib/post-merge-housekeeping.sh` call in `SKILL.md`
Step 4 (`references/post-merge-housekeeping.md`); steps 5-6 are `SKILL.md`
Step 5.

| # | Step | SSOT |
|---|---|---|
| 1 | PR card → `Done`, linked Issue cards → `Done` | `references/project-board-sync.md` |
| 2 | herdr idle-tab hint (read-only, one `[INFO]` line) | `references/herdr-tab-notify.sh.md` |
| 3 | ai-metrics PR comment (skipped when `GH_DISABLE_AI_METRICS=1`) | `references/ai-metrics-comment.sh.md` |
| 4 | drop the now-readerless `review-passed` label | `references/review-passed-cleanup.sh.md` |
| 5 | fetch the merge SHA, print the report line | `references/strategy-selection.md` → "Final report format" |
| 6 | post-merge verification dispatch (registry-gated) | `references/post-merge-verify.md` |

Dropping `review-passed` is **the last GitHub write of the sequence**, after
every other housekeeping step, and that ordering is load-bearing beyond
tidiness: that label is what makes `_gh_pr_merge_train_needs_finalize` match
this PR at all. While it is on, an unfinished PR is findable; the moment it
comes off, the PR is done as far as the next tick's Step 0 sweep can tell. So
the label must not come off while a housekeeping write is still owed. Ordered
last, a run interrupted anywhere in 1-3 simply gets swept again on the next
tick — every step is idempotent enough to repeat (the board sync is a no-op on
an already-`Done` card, the label delete absorbs its own 404, the tab hint is
read-only).

Steps 5-6 run after the drop. Step 5 writes nothing, and step 6 is the one
step **outside** the resumable set: it is registry-gated and advisory, and
`/gh-verify:post-merge-verify <N>` is its manual re-entry. In
dEitY719/dotfiles the label drop came after the dispatch too (PR
dEitY719/dotfiles#1725); here the dispatch is a separate script call in
`SKILL.md` Step 5, so the drop stays inside Step 4's single call instead.

Until PR dEitY719/dotfiles#1725 the drop sat before the ai-metrics comment
while this paragraph claimed it was last. A run that died between them dropped
the label with a step still owed, and no later sweep could ever find the PR
again (codex BLOCKER on dEitY719/dotfiles#1725). Anything added to the
housekeeping in future goes **above** the label drop, never below it.

The one step that is **not** idempotent in that sense is #3: a second
ai-metrics comment would land a second footer on the same PR. That exposure is
inherent to a resumable sweep and is not what the ordering trades against — a
duplicated footer is visible and harmless, whereas a PR that no sweep can find
is silent and permanent.

## Required bindings

Identical for both entry points; all of them come from Step 1's single remote
URL plus Step 2's `gh pr view` (`references/github-target.md`, dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407):

| Variable | Source |
|---|---|
| `PR_NUMBER` | the positional |
| `TARGET_REPO` / `TARGET_HOST` | the resolved remote |
| `HEAD_REF` / `BASE_BRANCH` | `gh pr view --json headRefName,baseRefName` |
| `REMOTE` | the `[remote]` positional, default `origin` |
| `START_TS` | Step 1's `date +%s` |

`START_TS` is the one binding that differs in meaning between the two entry
points. In the immediate path it measures the merge run, which is what the
ai-metrics footer claims. In a `--finalize` pass it measures the sweep, which
is a few seconds and says nothing about the PR — so a `--finalize` run binds
`START_TS` at its own start anyway and lets the footer report that. Inventing a
retroactive duration would be worse than reporting a short one.

## What is NOT in the sequence

- **The pre-flight gates and the merge itself** (`SKILL.md` Steps 2 and 3).
  `--finalize` skips both by construction: the PR is already merged, so there
  is nothing left to gate and nothing left to merge. It verifies exactly one
  thing before running the sequence — that `state == "MERGED"` — and refuses
  otherwise, because every step here is a write that assumes a merge happened.
- **Anything conditional on the strategy.** By the time this runs, the merge
  method is history; only the report line names it.

## The `[QUEUED]` third outcome

When `--auto` was used and the post-merge `gh pr view` still reports
`state == "OPEN"`, the PR was **enqueued, not merged** — none of the six steps
above may run, because the merge they all assume has not happened yet. That is
neither success nor failure in the existing sense; it is a third outcome whose
report shape is the `[QUEUED]` block in `references/merge-queue.md` (Step 3.5) — this file is an index
over the sequence, not a second copy of that block.

The PR keeps its `review-passed` label precisely because step 4 did not run,
and that is what a later `gh-pr:merge-train` Step 0 sweep matches on.
