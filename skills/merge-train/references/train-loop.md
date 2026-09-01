# gh-pr:merge-train — The per-PR loop (F-2 … F-6)

One PR at a time. Merge it, or give up on it, **before** touching the next one
(F-2). Never two in flight — a parallel train would race its own merges into
each other's base.

## The loop

For each PR `N` in the Step 2 queue order:

1. **Re-query state** (F-3). The previous merge invalidated whatever Step 2
   read. `gh pr view` per `routing-table.md`.
2. **Approval gate** — look this PR's own `baseRefName` up in the per-base
   cache Step 3 built (`approval-gate.md`: read once per *distinct base*, not
   once per run — rulesets are branch-scoped). Gate on and `reviewDecision !=
   APPROVED` → `[SKIPPED] approval required`, next PR. Gate **off** but
   `reviewDecision` non-empty and not `APPROVED` → also `[SKIPPED]`, naming the
   value — see "Gates `gh-pr:merge` owns" for why that check cannot be skipped.
   **Step 2b — delegated review** (gate **off** and `reviewDecision == ""`
   only): run the sequence in "Delegated review on the gate-off path" below.
   It either clears the PR for step 3 or records a `[SKIPPED]` and moves on.
3. **Route** through the D-1 table.
4. **Remediate** with the atom skill the row names, if any. For the `BEHIND`
   and `DIRTY` rows that means the scratch-worktree sequence below, not a bare
   `Skill(...)` call.
5. **Re-query and re-route.** An atom returning success does not prove the PR
   is mergeable now.
6. **Merge** — `Skill(gh-pr:merge, "<N>")`. No strategy argument (D-4).
7. **Close the merged PR's implementation tab** — only on a successful merge,
   only when that tab is `idle`. The block is below ("Closing the merged PR's
   implementation tab").
8. **Record** the outcome and continue.

## Closing the merged PR's implementation tab (step 7, #1565)

`gh-pr:merge` Step 5 already closes this tab as part of its post-merge
verification dispatch. This is the belt-and-braces half: run it anyway, right
after a successful merge, because a tab that stays open is not a cosmetic leak.
`_iw_live_agents` in `shell-common/tools/custom/issue_watcher_cron.sh` counts a
`wt/issue-*` worktree as running whenever a herdr agent sits on it, so enough
merged-but-open tabs exhaust `_IW_MAX_PER_REPO` and issue-watcher silently
stops dispatching for that repo — the pipeline starves itself. On 2026-08-27 a
train merged 10 PRs and left all 10 tabs open.

`<head>` is the `headRefName` already in `$STATE` from step 1 — no extra API
call. Run this **only after** `gh-pr:merge` reported success; a `[SKIPPED]` or
`[FAILED]` PR still has work parked in its worktree.

```bash
# Idle-only, exactly the judgement gh-pr:merge's Step 4 herdr hint already
# makes (../../merge/references/herdr-tab-notify.sh.md): a `working` or
# `blocked` agent is a live session, and closing its tab kills work in flight.
# Everything else here is a silent skip — this runs after the merge, so it can
# never fail the PR it just merged.
if command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # "Which herdr agent is sitting on this worktree?" comes from one SSOT
    # (#1569), sourced — never re-implemented here. This block, the Step 4 hint,
    # gh-verify:post-merge-verify's dispatch and `_iw_live_agents` each carried
    # their own copy of that predicate, and the copies had already drifted:
    # the Step 4 hint matched `.cwd` by plain string equality, so it missed
    # both a session that had `cd`-ed inside its worktree and a worktree
    # reached through a symlink. A missing helper skips the close, silently,
    # like every other gate here.
    PMT_LOOKUP_LIB="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/herdr_agent_lookup.sh"
    # shellcheck source=/dev/null
    if [ -r "$PMT_LOOKUP_LIB" ] && . "$PMT_LOOKUP_LIB"; then
        PMT_WT=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/<head>" \
            '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) {print p; exit}}')
        # `herdr_agent_physical_path` resolves symlinks before comparing: `git
        # worktree list` reports the path as it was created, herdr reports where
        # the pane actually stands, and a single symlinked component makes those
        # two strings differ. `herdr_agent_tab_for_cwd` then matches BOTH `cwd`
        # (where the pane was opened) and `foreground_cwd` (where its shell
        # stands now), on a path BOUNDARY, so an agent that `cd`-ed one level
        # inside the worktree is still found while `/work/repo-11` never matches
        # `/work/repo-1`. Two agents on one worktree is abnormal — the helper
        # takes the first, ignores the rest, and warns about nothing (same rule
        # as the Step 4 hint).
        #
        # The `idle` argument keeps the status gate inside the lookup, so a tab
        # id comes back only for a closable tab and nothing has to carry a
        # status out through a delimiter. It judges that first match rather than
        # hunting for an idle one among several: closing an idle pane while its
        # sibling still works is the failure this whole step is careful about.
        # A non-zero return is either "herdr could not be asked" or "nothing
        # closable is there" — both are a silent skip here.
        if [ -n "$PMT_WT" ] &&
            PMT_TAB=$(herdr_agent_tab_for_cwd "$(herdr_agent_physical_path "$PMT_WT")" idle); then
            if herdr tab close "$PMT_TAB" >/dev/null 2>&1; then
                printf '[INFO] gh-pr:merge-train: closed implementation tab %s (%s).\n' \
                    "$PMT_TAB" "$PMT_WT"
            else
                printf '[WARN] gh-pr:merge-train: herdr tab close %s failed — continuing.\n' \
                    "$PMT_TAB"
            fi
        fi
    fi
fi
```

Closing a tab `gh-pr:merge` already closed is not a conflict: the second lookup
simply finds no agent on that path and prints nothing. The two halves are
deliberately redundant — if the Step 5 dispatch is skipped again, this one still
keeps the live count flat across a whole train.

`tests/bats/skills/gh_pr_merge_train_close_impl_tab.bats` pins both halves of
the rule (idle closes, non-idle never does) against the executable mirror
`tests/bats/skills/_fixtures/gh_pr_merge_train_close_impl_tab.sh`. Change the
block above, change that fixture.

## Delegated review on the gate-off path (step 2b, #1519 F-6 … F-9)

The gate being off means the platform asks for no approval — not that nothing
should be reviewed (`approval-gate.md` → "Why the gate being off still runs a
review"). Before merging such a PR the train runs one review and reads the
board back as its verdict.

Reached only when **the gate is off and `reviewDecision` is `""`**. Every other
combination was already decided in step 2: an `APPROVED` PR proceeds untouched,
and a non-empty non-`APPROVED` one is `[SKIPPED]` before it gets here, so a
review a human explicitly blocked is never handed to a self-record run.

```bash
# Hoisted out of the loop — bind once per run, next to TARGET_REPO / TARGET_HOST.
# Shared with F-3's freshness check (#1601, routing-table.md) — same login,
# same reason: it is the one identity a marker/self-record can be trusted from.
ME=$(GH_HOST="$TARGET_HOST" gh api user -q .login)

HEAD_OID=$(GH_HOST="$TARGET_HOST" gh pr view "$N" --repo "$TARGET_REPO" \
    --json headRefOid -q .headRefOid)
# --paginate: reviews come 30 per page, and a long-lived PR can push the
# most recent $ME review off page 1. --jq runs per page, so take the last
# match across the whole stream rather than `last` within one page.
LAST_OID=$(GH_HOST="$TARGET_HOST" gh api --paginate "repos/$TARGET_REPO/pulls/$N/reviews" \
    --jq ".[] | select(.user.login == \"$ME\") | .commit_id" | tail -n 1)
```

`$ME` is the authenticated login, not the PR author — the suppression asks
"did *this* account already review *this* head", so an empty `$ME` would make
`LAST_OID` always empty and re-run a full review every tick.

1. **Suppress a repeat review (#1519 F-8).** `LAST_OID` non-empty and equal to
   `HEAD_OID` means this exact head was already reviewed by `$ME` — skip to
   step 3 without calling anything. Otherwise run
   `Skill(gh-pr:approve, "<N> <remote> --self-record")` once. Never twice, and
   never a retry (#1519 F-7).
2. **Read the verdict (#1519 D-4)** — `_gh_project_status_query_current pr <N>
   "$TARGET_REPO"` from `shell-common/functions/gh_project_status.sh`.
3. **Decide:**

| Board Status | Reviewed this tick? | Outcome |
|---|---|---|
| `Approved` | either | proceed to step 3 — merge |
| anything else | yes, just ran | `[SKIPPED] self-record withheld approval (BLOCKER)` |
| anything else | no, suppressed by #1519 F-8 | `[SKIPPED] approval withheld (unchanged since review)` |
| unreadable | either | `[SKIPPED] board unreadable — approval unconfirmed` |
| — | the skill call itself errored | `[SKIPPED] self-record failed` (#1519 F-9) |

Reading the board **after** the suppression check is what keeps a stalled-but-
approved PR moving: a PR whose review passed on an earlier tick but whose merge
then failed on CI comes back with `Approved` still on the card, so row 1 clears
it without paying for a second review. #1519 F-8's suppression only ever produces a
`[SKIPPED]` for a PR the review actually declined.

Nothing here spends an F-5 attempt — no remediation was performed. Every row
above is `[SKIPPED]`, never `[FAILED]`: each becomes actionable the moment
someone pushes a fix (which changes `HEAD_OID` and re-arms the review) or
promotes the card by hand.

**Why inside the loop and not once over the queue.** Only PRs past the D-6
quiet period reach it, so `gh-verify:review-all`'s `--defer-reply 4`
`gh-pr:reply` has landed and CI has settled — the review sees the PR's final
state. Reviewing the whole queue up front would review code that the train's
own subsequent merges then move out from under.

**Serial by construction (D-8).** The train already processes one PR at a
time, so these reviews serialise for free — which is why `allowed-tools` still
needs no `Agent`. `gh-pr:approve` carries its own, and `Skill()` nesting
reaches it.

## Detached scratch worktree (step 4, `BEHIND` / `DIRTY` only)

`gh-flow:issue` opens each PR from the dedicated worktree that implemented the
issue, so that PR's head branch is **already checked out somewhere else** by
the time the train reaches it. `git checkout <head>` in this session would fail
with `fatal: '<branch>' is already used by worktree at '<path>'` — and even
when it succeeded it would trample the branch the operator has open in the
worktree they invoked the train from. So the train never checks the head branch
out at all: it makes a throwaway scratch worktree at that branch's tip, hands
the path to the atom, and deletes it.

Before delegating, with `<head>` = the `headRefName` already in `$STATE`:

```bash
git fetch "$REMOTE" "<head>"
GIT_COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir)
SCRATCH_DIR="${GIT_COMMON_DIR}/pr-merge-train-scratch/pr-<N>"

# Stale-leftover guard: a crashed/killed prior run, or an unresolved conflict
# handoff (see "Teardown — the one exception" below), can leave this same
# path behind. Never blindly wipe it — a leftover rebase-in-progress marker
# means a human may be resolving it by hand right now.
if [ -e "$SCRATCH_DIR" ]; then
    if [ -e "$(git -C "$SCRATCH_DIR" rev-parse --git-path rebase-merge 2>/dev/null)" ] ||
       [ -e "$(git -C "$SCRATCH_DIR" rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
        echo "[SKIPPED] scratch worktree at $SCRATCH_DIR still has an unresolved handoff — resolve manually or remove it, then re-run."
        # skip this PR (F-6) — do not touch $SCRATCH_DIR, do not proceed below.
    else
        git worktree remove --force "$SCRATCH_DIR" 2>/dev/null || rm -rf "$SCRATCH_DIR"
        git worktree prune
    fi
fi

mkdir -p "$(dirname "$SCRATCH_DIR")"
git worktree add --detach "$SCRATCH_DIR" "$REMOTE/<head>"
```

The `fetch` is not optional: this session's checkout has no reason to hold a
current `$REMOTE/<head>` — the branch was pushed from a *different* worktree.
Fetching it explicitly first is what makes `$REMOTE/<head>` below trustworthy:
with the standard clone fetch refspec (`+refs/heads/*:refs/remotes/<remote>/*`,
the default for every `git remote add` / `git clone`) a plain `git fetch
"$REMOTE" "<head>"` updates the remote-tracking ref `$REMOTE/<head>` itself,
not only `FETCH_HEAD` — skipping the fetch is what would leave that ref stale
(or absent) and have the atom force-push a rewind over commits it never saw.

`--path-format=absolute` (git 2.31+) matters here: `--git-common-dir` alone
prints a path **relative to the current working directory** in a plain
repository (`.git`, or `../../.git` two levels down) — only a linked
worktree's own `.git` file happens to store an absolute `gitdir:` target,
which is why a relative `GIT_COMMON_DIR` can look harmless while testing from
this repo's own worktree layout and still break the moment `$SCRATCH_DIR` is
read from a different working directory or a plain non-worktree checkout.

`--detach` is what makes this collide-free: the scratch worktree holds a commit,
not the branch *name*, so it never contests the checkout any other worktree
already owns. `git worktree add` failing is an ordinary remediation failure —
attempt +1 (F-5), and at 3 the PR is `[FAILED]` (F-6). It never ends the run.

Then delegate to the atom the D-1 row named, pointing it at that path:

```
Skill(gh-resolve:outdated, "<N> <remote> --worktree $SCRATCH_DIR")
Skill(gh-resolve:conflict, "<N> <remote> --worktree $SCRATCH_DIR")
```

Pass `<remote>` explicitly even when it is the default `origin` — the atoms
read it as positional 2, and omitting it would leave `--worktree` sitting in
that slot.

The atom runs every git command as `git -C "$SCRATCH_DIR" ...` and pushes with
an explicit refspec (`HEAD:refs/heads/<head>`), because a detached HEAD has no
upstream to infer. That contract is the atoms' own — see their
`references/preflight.md` / `references/rebase-flow.md`.

### Teardown — the one exception

Tear down once the atom returns, in every case **except** one:
`gh-resolve:conflict` stopping at one of its own documented stop points
(`references/conflict-handling.md` → "Stop points" — an ambiguous conflict it
refuses to auto-resolve, or a user-side abort). That stop leaves the tree
**deliberately** conflicted for a human to finish by hand — the atom's own
constraint already forbids it from deleting `--worktree`'s path itself; tearing
it down here, right after, would just relocate the same mistake into the
caller and destroy the exact state the atom promised to leave behind. In that
one case: report `$SCRATCH_DIR` in the `[FAILED]` row instead of removing it,
and skip this PR for the rest of the run — a human resumes it manually
(`git -C "$SCRATCH_DIR" ...`, per the atom's own report) or re-runs the train
once it's resolved and pushed. The stale-leftover guard above is what makes a
later run safe to encounter that surviving path again.

Every other outcome — clean success, a mechanical rebase failure
`gh-resolve:outdated` hands off with (exit 4, no human input taken yet),
or `git worktree add` itself failing — tears down unconditionally:

```bash
git worktree remove --force "$SCRATCH_DIR" ||
  { rm -rf "$SCRATCH_DIR" && git worktree prune; }
```

The failure paths are exactly the ones that would leak otherwise: a PR that
lands `[FAILED]` is retried on the next tick, and a train on a cron schedule
would accumulate one abandoned worktree per tick per stuck PR — each one a
full checkout, and each one still registered in `git worktree list`. Tearing
down only on the happy path is how that starts.

Creating, delegating, and tearing down is **one** remediation round: the round
still costs exactly one attempt, unchanged from the accounting below.

## Gates `gh-pr:merge` owns — check them here, not by calling it

`gh-pr:merge` has hard stops of its own, and the train reaches them *through*
the F-5 attempt counter. A PR that trips one is refused identically on every
attempt and on every later tick, so it burns three attempts, lands `[FAILED]`,
and stays `[FAILED]` — NF-2 forbids `gh-pr:merge-emergency`, the only thing
that would clear it. **Detect these before delegating and record `[SKIPPED]`
with the specific cause.** One of them matters here:

| `gh-pr:merge` gate | What the train must do |
|---|---|
| Step 2 `reviewDecision != APPROVED` (non-empty, non-`APPROVED` always stops, regardless of any ruleset) | `[SKIPPED] gh-pr:merge refuses reviewDecision=<value>` — see `approval-gate.md` → "Why the gate being off is not sufficient" |

Reporting that as a bare `[FAILED]` tells the reader nothing they can act on;
naming the `reviewDecision` value tells them exactly what to dismiss.

The projectV2 board Status is **not** one of these gates. `gh-pr:merge`'s
Step 2-B board check was removed in #1513, so a card sitting outside `Approved`
— which is the normal state for a PR `gh-flow:issue` just opened — is no longer
a reason to skip. Do not query the board here.

That retirement is about the board as a **policy gate**, standing in for a
platform approval the repo never granted; used that way it blocked every
self-authored PR forever. Step 2b's read is a different thing wearing the same
column: `gh-pr:approve` is the only skill that writes `Approved` (#1350) and
only promotes when it found no BLOCKER, so the train is reading the return
value of a review it just ran — not asking the board for permission. Keep the
two apart: nothing may consult the board *before* a review has been run for
this head.

## Attempt accounting (F-5)

Keep one counter per PR, starting at 0. Increment it on **each remediation
round** — one round is "call an atom skill, re-query, re-route".

- Counter reaches `3` without the PR reaching a merged state → `[FAILED]`, with
  the last failure as the reason. Move on.
- A failing atom skill still costs an attempt. A no-op atom (`gh-resolve:outdated`
  reporting "already up to date") does too — otherwise a PR that keeps being
  pushed `BEHIND` by the train's own merges could loop forever.

Why 3 and not 1: between two of this train's own merges a PR can legitimately
go `BEHIND` again, so one attempt is genuinely too few. Why not unbounded: a PR
whose conflict cannot be resolved would hold the train forever, and NF-1 means
no second train can come along and make progress instead.

## Polling (`UNKNOWN`, and `UNSTABLE` with checks still running)

Both are "wait, then look again", and both are bounded:

- **3 polls maximum**, roughly 30 seconds apart.
- `UNKNOWN` still `UNKNOWN` after 3 → `[SKIPPED] mergeability still UNKNOWN`.
- Checks still `IN_PROGRESS` after 3 → `[SKIPPED] checks still running`.

A `[SKIPPED]` here is not a failure — the state is simply not knowable yet, and
the **next tick re-evaluates it from scratch**. That is why the ceiling is low:
holding a train session open waiting on a 20-minute CI run costs more than
letting the next cron tick pick the PR up.

Polls are *not* remediation attempts and do not increment the F-5 counter — no
skill was called and nothing was changed.

## Failure handling (F-6) — skip the PR, never the train

| What failed | Consequence |
|---|---|
| `gh-resolve:*`, or the `git worktree add` that stages it | attempt +1; at 3, `[FAILED]`, next PR |
| `gh-resolve:conflict` stops at a documented stop point (ambiguous conflict, user-side abort) | `[FAILED]` naming `$SCRATCH_DIR` for manual resume; **scratch worktree is NOT removed** ("Teardown — the one exception" above); no further attempts this run; next PR |
| `gh-pr:merge` | that PR is `[FAILED]`; next PR |
| approval gate | that PR is `[SKIPPED]`; next PR |
| the step-2b delegated review (withheld, suppressed, board unreadable, or the `gh-pr:approve` call itself) | that PR is `[SKIPPED]` with the matching reason; **no attempt is spent**; next PR |
| a `gh-pr:merge` gate detected up front (`reviewDecision`) | that PR is `[SKIPPED]` with the cause named; **no attempt is spent** |
| `gh pr view` on one PR | that PR is `[SKIPPED] state unreadable`; next PR |
| `gh pr list` in Step 2 | **the run ends** — with no queue there is nothing to skip *to*, and merging without knowing state is the one thing this skill must never do |

One stuck PR must never hold the others. That is the whole point of the train
over a hand-run sequence: the human version stops at the first hard PR, and the
easy ones behind it wait for the next time someone has an hour.

## Concurrency and the outer guard

This loop assumes it is the only train on this repo. That is guaranteed by the
dispatcher, not by this skill — see `cron-dispatcher.md` (NF-1). Do not spawn
sub-agents to process PRs in parallel; the serial dependency is the design, not
a limitation to optimise away.
