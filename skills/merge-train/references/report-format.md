# gh-pr:merge-train — Final report (F-9)

Always printed, including when the run ended early or merged nothing. Plain
assistant text — never a `Bash` heredoc, never `Write` (dEitY719/dotfiles#1270).

## Format

```
== merge train: <owner/repo> ==
queue: <n> PR(s)  ·  approval gate: <verdict>  ·  quiet period: 11m

[MERGED]  #1466  refactor(issue-watcher): simplify   (BEHIND -> resolve-outdated -> merged)
[MERGED]  #1467  fix(gh-pr-reply): ...               (CLEAN -> merged)
[SKIPPED] #1462  test(issue-watcher): ...            checks still running (3 polls)
[SKIPPED] #1470  fix(y): ...                         review-blocked — reviewer verdict is blocking
[FAILED]  #1469  feat(x): ...                        conflict unresolved after 3 attempts

merged 2 · skipped 2 · failed 1
```

Rules:

- **One line per PR**, in the order the train processed them — not the order
  `gh pr list` returned them. The processing order is itself information (D-2).
- Every non-`[MERGED]` line **must carry a reason**. `[SKIPPED] #1462` with no
  reason is a bug in the report, not a terse style.
- `[MERGED]` lines name the **route taken**, so a reader can tell a PR that
  merged straight through from one that needed two remediations.
- PRs excluded before the queue was built (drafts, `reply-pending`, inside the
  quiet period, not `--author @me`) are **not** listed — they were never
  candidates. Mention them only as a count, if at all.
- A PR that entered the queue and *then* picked up `reply-pending` (the label
  can be added mid-run) is a normal `[SKIPPED]` line with
  `reply-pending — review reply not yet complete` as its reason.
- PRs the **verdict gate** rejects (Step 3.5) *are* listed, one line each with
  their reason. They differ from the pre-queue exclusions above: those were
  never candidates, whereas a verdict-gated PR is a candidate a reviewer
  stopped, and hiding that would hide the gate's whole output (dEitY719/dotfiles#1564).

## The `approval gate:` field (dEitY719/dotfiles#1519 NF-1)

Exactly one of three strings, from `approval-gate.md`'s combine table:

| Header | Means |
|---|---|
| `off (no policy on <base>)` | neither rulesets nor classic protection require an approval on this base — the delegated review supplies the signal instead |
| `on (<source>: <n> approvals)` | `<source>` is `ruleset` or `protection`; the strictest count wins |
| `on (fail-closed: <base> policy unreadable)` | the policy is genuinely undetermined (5xx, 401, network) — **not** a 403/404. Stating it here shows once, at the top, why every unapproved PR below was skipped, instead of repeating it per line |

Distinguishing the three is the point, not decoration. dEitY719/dotfiles#1519's symptom was a
header reading `on (fail-closed: ruleset unreadable)` on a free-plan repo where
no ruleset can exist — a bug that looked, for its whole lifetime, exactly like
a transient API problem. A header that cannot tell "undetermined" from "there
is nothing to determine" hides the next instance of it just as well.

Mixed-base queues carry one clause per distinct base, `·`-separated. The base
is already the clause prefix there, so it drops out of the string itself:
`approval gate: main=off (no policy) · release/2026.08=on (ruleset: 1 approvals)`.

## Status vocabulary

| Status | Meaning | Typical reason |
|---|---|---|
| `[MERGED]` | the PR is merged | — |
| `[SKIPPED]` | not merged, **and expected to be retriable** next tick | `checks still running`, `mergeability still UNKNOWN`, `approval required (reviewDecision=<value>)`, `gh-pr:merge refuses reviewDecision=<value>`, `policy unreadable — approval assumed required`, `BLOCKED: <rule>`, `draft`, plus the two verdict-gate reasons and the four delegated-review reasons tabled below |
| `[FAILED]` | not merged, **and something actually went wrong** | `conflict unresolved after 3 attempts`, `gh-pr:merge failed: <message>`, `CI fix failed after 3 attempts` |

Two of those reasons — `gh-pr:merge refuses reviewDecision=<value>` and
`policy unreadable` — name a gate that lives **downstream**, in `gh-pr:merge`
(its Step 2 `reviewDecision` hard stop) or in a policy that could not be read.
They are `[SKIPPED]`, never `[FAILED]`, and they are recorded **without
delegating** — see
`train-loop.md` → "Gates `gh-pr:merge` owns". A PR refused by one of them is
refused identically every time, so letting it reach `gh-pr:merge` would spend
three F-5 attempts to produce a `[FAILED]` that NF-2 leaves no way to clear.
Naming the `reviewDecision` value is what makes the line actionable: the reader
knows which review to dismiss.

Two come from the Step 3.5 verdict gate (`review-verdict-gate.md`), and they
are the only place the report distinguishes "a reviewer said no" from "no
reviewer has said anything":

| Reason | What happened | Cleared by |
|---|---|---|
| `review-blocked — reviewer verdict is blocking` | a `gh-verify:review-all` lane returned a blocking verdict on this head | `gh-pr:reply` completing its reply-all pass (drops the label unconditionally, dEitY719/dotfiles#1634), or a re-review |
| `review not verified — no review-passed label` | no verdict label at all — the PR has not been shown to pass review | a `gh-verify:review-all` pass, or a human adding the label |

Neither spends an F-5 attempt, and neither is ever `[FAILED]`. The second is
the expected state of every PR that was already open when the gate landed, and
of any PR whose head advanced since its last review (dEitY719/dotfiles#1563 drops the stale
`review-passed` on every push) — a `[SKIPPED]` here is the gate working, not a
wedge. Unlike `reply-pending`, these reasons have **no staleness window**: see
`review-verdict-gate.md` → "Why no time backstop".

Four more come from the step-2b delegated review
(`train-loop.md` → "Delegated review on the gate-off path"), and the wording
distinguishes what a reader has to do about each:

| Reason | What happened | Cleared by |
|---|---|---|
| `self-record withheld approval (BLOCKER)` | the review ran this tick and found a blocker | pushing a fix (new head re-arms the review) |
| `approval withheld (unchanged since review)` | the same head was already reviewed and declined — **not re-reviewed**, by design (dEitY719/dotfiles#1519 F-8) | pushing a fix, or promoting the card by hand |
| `board unreadable — approval unconfirmed` | the review's verdict could not be read back | the next tick, usually |
| `self-record failed` | `gh-pr:approve` itself errored (dEitY719/dotfiles#1519 F-9) | the next tick |

None of the four spends an F-5 attempt, and none is ever `[FAILED]`: a
withheld approval is a working review, not a broken train.

The `[SKIPPED]` / `[FAILED]` split is the load-bearing part of this output. A
cron log full of `[SKIPPED] checks still running` is a healthy train waiting on
CI; a cron log full of `[FAILED]` is a train that needs a human. Collapsing the
two would hide the second inside the first — the exact failure mode of an
unattended loop nobody reads.

## Early-exit shapes

- `gh pr list` failed → print the header, then
  `run ended: gh pr list failed — refusing to merge without knowing state`, and
  no PR lines.
- Queue empty after filtering → header plus `queue: 0 PR(s)` and
  `nothing to do`. Not an error; the dispatcher normally prevents this from
  even starting a session.
