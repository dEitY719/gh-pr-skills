# gh-pr:merge-train — Queue ordering and the quiet period (D-2, D-3, D-6)

## D-2 — clean first, dirty last

Sort key, highest priority first:

| Rank | `mergeStateStatus` |
|---|---|
| 1 | `CLEAN` |
| 2 | `BEHIND` |
| 3 | `UNSTABLE` |
| 4 | `DIRTY` |

Ties break on **ascending PR number**, so the order is stable across ticks and
an older PR never starves behind a newer one at the same rank.

`UNKNOWN` PRs sort with `BEHIND` (rank 2) as a placeholder — the poll in the
loop resolves them to a real status before anything acts on them, and giving
them their own rank would only encode a guess.

### Why dirty last — the non-obvious part

The intuition says "clear the hard one first, while you still have energy".
That is wrong here, and the reason is mechanical:

> **Every merge invalidates every PR still in the queue.** So the LLM work must
> happen as late as possible.

Resolve `DIRTY` first and each subsequent merge can re-conflict it — the same
file, resolved again, against a base that has moved. Resolve it **last** and it
is resolved exactly once, against the **final** base. One expensive operation
instead of N.

The secondary effect is a real benefit too, not just consolation: the cheap PRs
are already merged by the time the train reaches the one that might defeat it.
A train that dies on the last PR still delivered everything ahead of it.

## D-3 — clean up just-in-time, one PR at a time

Do **not** pre-clean the whole queue and then merge down the list. With four
PRs, pre-cleaning costs:

```
rebase #1 #2 #3 #4      (4)
merge  #1  -> #2 #3 #4 are BEHIND again
rebase #2 #3 #4         (3)
merge  #2  -> #3 #4 are BEHIND again
rebase #3 #4            (2)
...
```

Cleaning immediately before each merge costs one rebase per PR — four total,
with none of them thrown away. This is exactly why **F-3's re-query is
mandatory**: the state you read when you built the queue is stale by the time
you reach the second PR, and acting on it would route the PR down the wrong row
of the D-1 table.

Treat the Step 2 queue as an **ordering**, not as a state snapshot.

## D-6 — the 11-minute quiet period

Drop every PR whose `updatedAt` is within `11` minutes of now. The number lives
in exactly one place — `_gh_pr_merge_train_quiet_minutes` in
`shell-common/functions/gh_pr_merge_train.sh` (overridable with
`GH_PR_MERGE_TRAIN_QUIET_MINUTES`) — and the `11` written here is a citation of
it, not a second definition.

This is a condition that only unattended running creates. `gh-flow:issue`
Step 2.4 calls `gh-verify:review-all` with `--defer-reply 4`, which **schedules
`gh-pr:reply` four minutes after the PR is opened**. A train that merges inside
that window merges a PR that has not yet received its review replies or its
`/simplify` fixes — they land on a branch that no longer has anywhere to go.

A human running the train by hand never hit this, because the minutes passed
naturally while they looked at the PRs. Cron has no such pause.

`11 = 4` (the scheduled defer) `+` the reply pass's own runtime `+` slack.

### `reply-pending` — the hard skip; the quiet period is only the backstop

The quiet period is a **time-based proxy** for the question that actually
matters: *has the deferred review-reply pass finished?* Time is a bad proxy. A
reply pass slower than 11 minutes outlives the window, and the train merges a
PR whose replies and `/simplify` fixes are still in flight — which is what
happened to PR #1522 (issue #1524, bug A).

So there is now a real signal, checked **regardless of the quiet period**:

| Signal | Set by | Cleared by |
|---|---|---|
| `reply-pending` label | `gh-verify:review-all` Step 5, `defer` branch | `gh-pr:reply` Step 6, unconditionally |

A PR carrying `reply-pending` is not a train target however far outside the
11-minute quiet period it sits.

#### Its sibling signal: the verdict labels (#1564)

`reply-pending` answers *when* — has the reply pass finished. It says nothing
about *what the reviewers concluded*. That second question is answered by a
different pair of labels, on a different schedule, in a different step:

| Signal | Set by | Cleared by |
|---|---|---|
| `review-blocked` / `review-passed` | `gh-verify:review-all` Step 3.5 (the only writer) | `_gh_pr_drop_label` on any head advance (#1563); the opposite label on a re-review |

The train reads them in Step 3.5, not here: they are **not** part of
`_gh_pr_merge_train_filter_targets`, because a PR they stop must appear in the
report with a reason rather than vanish before the queue exists. Table,
rationale, and the reason strings: `references/review-verdict-gate.md`. Unlike
`reply-pending`, these labels have **no staleness window** — absence is
already the blocking state, so there is nothing for time to release.

#### The label expires — 90 minutes, then the quiet period takes over

The hard skip is **bounded**, and the bound is what makes the backstop below
real rather than aspirational. The window is
`_gh_pr_merge_train_reply_pending_stale_minutes` — default `90` minutes,
overridable with `GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES`, defined in
the same `shell-common/functions/gh_pr_merge_train.sh` as the quiet period, and
the `90` written here is a citation of it, not a second definition.

Measured against the same `updatedAt` the quiet period reads: adding a label
bumps a PR's `updatedAt`, so that stamp is "when the label landed" at the
earliest — no separate clock is needed.

| `reply-pending` | `updatedAt` age | Verdict |
|---|---|---|
| yes | `< 90 min` | **dropped** — a deferred reply pass is still plausibly running |
| yes | `>= 90 min` | label is **stale**; falls through to the ordinary quiet-period check |
| no | — | ordinary quiet-period check |

`90` is sized as *longer than any healthy deferred reply pass, shorter than a
wedged PR is tolerable*: 4 minutes of scheduled defer + a `gh-verify:review-all`
fan-out + a `gh-pr:reply` pass that on a heavily reviewed PR walks dozens of
threads, edits, commits and pushes — generously an hour — plus slack. It is
~8x the quiet period, so the two windows can never be mistaken for each other.

Without the bound, a label nobody ever removes excludes its PR from the train
**forever** (PR #1545 review, codex BLOCKER). With it, "the remover died"
degrades to "the PR waits out 90 minutes" — at most six 15-minute cron ticks.

So the quiet period stays on as the **backstop** for the two cases the label
cannot cover:

1. PRs opened by hand or by another tool, which never got the label at all.
2. A session that died between adding the label and removing it. Its PR is held
   for the staleness window and then judged by the quiet period like any other
   — the label is not allowed to be the only gate, and it is not allowed to be
   a permanent one. (A stuck label is still cleared by hand, or by the next
   `gh-pr:reply` run on that PR; expiry only stops it from wedging the train.)

### One filter, two callers — not a coincidence

`shell-common/tools/custom/pr_merge_train_cron.sh` and this skill call the
**literal same function**, `_gh_pr_merge_train_filter_targets` in
`shell-common/functions/gh_pr_merge_train.sh` (issue #1524). Before that fix
the dispatcher had the filter as real `jq` and this skill had it as prose, so
the prose half could be — and was — silently skipped by the LLM executing it.
They cannot drift now: there is one implementation.

The two calls still exist for different reasons. The dispatcher answers "is
there anything worth waking a session for", cheaply, before spending a claude
session on a queue that would come out empty. This skill re-runs the filter
**authoritatively**, because minutes pass between that count and the moment
each PR is actually processed, and a PR can be touched — or labelled — again
in between. Same code, later clock.
