# gh-pr:merge-train — Constraints

## Never call `gh-pr:merge-emergency` (NF-2)

Not for a `BLOCKED` PR, not for a missing approval, not "just this once because
the ruleset lookup failed". That skill forces an audit trail — a reason comment
plus a follow-up incident issue — because it is meant for exceptions a human
decided to make. A loop calling it on schedule produces a stream of incident
issues that describe nothing, and trains the reader to ignore them.

An unmergeable PR is `[SKIPPED]` with a reason. A human can then run the
emergency skill deliberately, which is the only way it means anything.

## Never abort the whole train for one PR (F-6)

Any single PR's failure — remediation, merge, unreadable state, blocked by
policy — skips that PR only. The only thing that ends the run is losing the
queue itself (a failed `gh pr list`), because then there is nothing to skip to.

## Never merge without knowing state

A failed `gh pr list` ends the run with an empty report. A failed per-PR
`gh pr view` skips that PR. In no path does the train act on a guess about
mergeability.

## Never process two PRs at once

The serial dependency is the design (D-8): each merge invalidates the rest of
the queue, so a parallel train would be racing its own merges into each other's
base. Do not dispatch sub-agents per PR.

## Never pass a merge strategy

`required_linear_history` forbids merge commits, and rebase is `gh-pr:merge`'s
default, so the train passes no strategy argument at all (D-4). Passing one
explicitly would be a second place for the policy to drift out of sync with the
repo's actual settings.

## Never form a review judgement of its own

`gh-flow:issue` Step 2.4 already ran `gh-verify:review-all` on every PR this
train drains, and GitHub forbids approving your own PR — with `--author @me`,
every PR here is yours, so no approving review is obtainable at all.

**The one delegated exception (#1519 D-3).** When the approval gate reads
*off*, no platform rule is asking for a review, and merging on that basis
alone would put unexamined code on the base branch. In that one case the train
runs `Skill(gh-pr:approve, "<N> <remote> --self-record")` once and reads the
board back as its verdict (`train-loop.md` → "Delegated review on the gate-off
path"). That is not this skill reviewing: the judgement, the BLOCKER
classification, and the board write all belong to `gh-pr:approve`, and the
train only routes on the answer. The constraint it preserves is the real one —
**the train never decides whether a PR is good.**

It also does not duplicate Step 2.4: a self-record review runs at most once per
head (`#1519 F-8`), and only on PRs the platform leaves ungated.

**Step 3.5's verdict gate is not an exception to this either (#1564).** It
reads two labels — `review-blocked` / `review-passed` — and applies a fixed
table. The judgement they encode was made by `gh-verify:review-all`, their only
writer. The train must **never** parse a review comment body to reach the same
conclusion: keeping the parse in the producer means a reviewer reformatting
its verdict line yields no label and a skipped PR, whereas parsing here would
let the same reformat silently *unlock* the gate
(`review-verdict-gate.md` → "What this gate is not").

## Never write ai-metrics from the train

Every atom the train calls (`gh-pr:merge`, `gh-resolve:conflict`, …) posts
its own ai-metrics comment where its SSOT says to, each behind its own
`GH_DISABLE_AI_METRICS=1` guard. A train-level comment would land a second
footer on the same PR describing the same work. The train's output is the
Step 5 report, and that goes to the operator (or the cron log), not to GitHub.

Corollary: **this skill makes no writes to GitHub of its own.** Every mutation
it causes happens inside an atom skill that already owns that mutation's rules.

## Never bypass a gate that belongs to `gh-pr:merge`

`gh-pr:merge` refuses a PR whose `reviewDecision` is a non-empty non-`APPROVED`
value (its Step 2). That is repo policy expressed downstream, and the train's
answer is to detect the condition **before** delegating and record
`[SKIPPED] <cause>`. Never spend attempts discovering it, because the refusal
is deterministic and NF-2 leaves no way to clear the `[FAILED]` it would
produce (`train-loop.md`).

More generally: if `gh-pr:merge` grows a gate back, the train's job is to
report it, never to export an env var that silences it. Deciding to stand
outside a control someone configured is a human's call, made once and
deliberately; a loop doing it on schedule is the same failure NF-2 forbids in
the emergency-merge direction.

## Never let a PR loop forever

Three remediation attempts per PR (F-5), three polls per wait (train-loop.md).
Both ceilings exist because NF-1 means no second train can come along and make
progress while this one is stuck.

## Never widen the author scope

`--author @me` (D-7). A colleague's PR is out of scope for an unattended merge,
regardless of how mergeable it looks.
