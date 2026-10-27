# Strict required-status-checks is OFF on `main` — what that bought, what it cost

> Ported from `dEitY719/dotfiles` `claude/skills/gh-pr-merge-train/references/`
> (dEitY719/dotfiles#2219). "This repo" below means `dEitY719/dotfiles`, where
> every measurement on this page was taken.

Issue dEitY719/dotfiles#1707. This is the change that actually fixed the N-serial-CI-round-trips
problem. `merge-queue-investigation.md` is the sibling page: it explains why
GitHub's **merge queue** — the mechanism this work originally set out to use —
is categorically unavailable on this repo, and what inert groundwork was
shipped against a possible future org transfer. **That page is the "why not the
queue"; this page is the "what instead".**

Unlike that page, the change described here has **already been applied** to
live infrastructure. It is not a manual step waiting for a human.

## The one field that changed

```console
$ gh api -X PUT repos/dEitY719/dotfiles/rulesets/16849266   # ruleset "main-protection"
```

`required_status_checks.parameters.strict_required_status_checks_policy`:
`true` → `false`. Nothing else in the ruleset moved. It still carries
`deletion`, `non_fast_forward`, `required_linear_history`, `pull_request`
(0 required approvals) and `required_status_checks` over the same two contexts:

```console
$ gh api repos/dEitY719/dotfiles/rules/branches/main \
    --jq '[.[] | select(.type=="required_status_checks")
                | {strict: .parameters.strict_required_status_checks_policy,
                   contexts: [.parameters.required_status_checks[].context]}]'
[{"contexts":["Lint (mise)","Shell Lint (mise)"],"strict":false}]
```

### Rollback

A PUT replaces the whole ruleset object, so re-capture the current ruleset and
edit only `strict_required_status_checks_policy` back to `true` before the PUT —
that is the only field this change touched. Bind host and repo the way every
gh-* skill's Step 1 does (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407):

```sh
TARGET_HOST=github.com
TARGET_REPO=dEitY719/dotfiles
RULESET_ID=16849266
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/rulesets/$RULESET_ID" > ruleset-before.json
# edit strict_required_status_checks_policy -> true in ruleset-before.json, then:
GH_HOST="$TARGET_HOST" gh api -X PUT "repos/$TARGET_REPO/rulesets/$RULESET_ID" \
    --input ruleset-before.json
```

## Why this was the fix, and local batch-rebasing was not

GitHub ties a required check's satisfaction to **one specific commit SHA**.
With strict on, a PR must be exactly up to date with the base before it may
merge — so every merge ahead of it in the queue invalidates it, forcing a fresh
rebase and a fresh full CI run on the new SHA. That is the entire cost the
issue measured: PR dEitY719/dotfiles#1694 rebased twice, PR dEitY719/dotfiles#1690 rebased twice, ~2-4 minutes a
cycle, N PRs ⇒ N serial CI round trips.

The issue's original suggestion — batch the rebases locally, up front — only
parallelises the **first** round. Under strict mode every PR after the first
merge still needs its own fresh rebase and its own fresh CI cycle, because the
first merge moved the base again. A small win, not the fix.

With strict off, a PR that is behind the base but has no textual conflict
against it merges immediately. GitHub performs the rebase server-side at merge
time and does not demand a fresh CI run on the rebased commit, because "must be
current" was exactly the gate strict mode was providing.

### The observable proof that it took effect

`mergeStateStatus: BEHIND` is not a fact about the branch; it is GitHub saying
"the head is out of date **and this base requires it not to be**". With strict
off, GitHub stops reporting it. Measured on this repo immediately after the
PUT, with `main` at `448f14641f65`:

| PR | its `base.sha` | up to date with `main`? | `mergeStateStatus` |
|---|---|---|---|
| dEitY719/dotfiles#1719 | `d56cc232be6e` | no | `CLEAN` |
| dEitY719/dotfiles#1718 | `89d68eee617c` | no | `CLEAN` |
| dEitY719/dotfiles#1713 | `d56cc232be6e` | no | `CLEAN` |

All three are genuinely behind and all three report `CLEAN`. Before the flip
every one of them was `BEHIND` and owed a local rebase plus a CI cycle.

## The risk this accepts — stated plainly, not buried

**The code that lands on `main` after such a merge was never itself run through
CI before landing.** What CI verified was the PR's diff against its *original*,
now-stale base. GitHub then replays that diff onto a base that has moved, and
merges the result unverified.

For independent changes this is safe, and almost everything this train drains
is independent. The failure mode it opens is narrow and real: **two PRs that
touch overlapping logic in behaviourally incompatible but textually
non-conflicting ways.** Git sees no conflict, so `mergeable` stays `MERGEABLE`,
so nothing in the pre-merge path objects — and the combination is broken.

This is the same class of staleness risk this repo has been careful about
before (dEitY719/dotfiles#1601's sha-freshness check on `review-passed`; dEitY719/dotfiles#1700, where a
`review-passed` label was destroyed by the wrong actor and could not be
recovered). The tradeoff was chosen deliberately over the safer-but-weaker
local batch rebase, **conditional on the safety net below existing.**

`DIRTY` / `CONFLICTING` is untouched by any of this. A real conflict is a real
conflict with or without strict mode, and it still routes through
`gh-resolve:conflict` first, always.

## The safety net, and exactly how far it actually reaches

### 1. `main`'s own CI already runs the identical required checks (pre-existing)

This is the load-bearing piece, and it needed no new code — only confirming.
Both required contexts are produced by workflows that trigger on **push to
`main`**, not only on `pull_request`:

| Workflow | Check | Triggers |
|---|---|---|
| `.github/workflows/ci.yml` | `Lint (mise)` | `push: [main, develop]`, `pull_request: [main, develop]` |
| `.github/workflows/test.yml` | `Shell Lint (mise)` | `push: [main, develop]`, `pull_request: [main]` |

Confirmed live on the current tip of `main`:

```console
$ gh api repos/dEitY719/dotfiles/commits/main/check-runs \
    --jq '[.check_runs[] | {name, conclusion}]'
[{"name":"Shell Lint (mise)","conclusion":"success"},
 {"name":"Lint (mise)","conclusion":"success"}, ...]
```

So the rebased result **is** verified by the same two checks that gated the PR
— after it lands rather than before. **Coverage is unchanged; only the timing
moved.** That is the honest reason removing strict mode costs less than it
looks like it should.

**Do not read that as "CI runs the tests on the merged result."** It does not,
and it did not before this change either. `Test (mise)` was removed from CI in
dEitY719/dotfiles#754: pytest and bats run in the local `pre-push` git hook
(`docs/.ssot/local-test-policy.md`), never on the runner. Both the pre-merge
gate and the post-merge gate are **lint-only**. Nothing was lost here — the two
gates are the same two checks — but a reader must not credit this net with test
coverage it has never had.

### 2. New: the train refuses to pile onto a red base

Push CI detects a bad landing but nothing acted on it, so the train would have
merged PR2 and PR3 onto a broken `main` and left three suspects for one
failure. That is the one piece worth automating, and it is Step 3.6.

The shared predicates are `_gh_pr_merge_train_behind_may_merge_directly`,
`_gh_pr_merge_train_base_strict_confirmed` and
`_gh_pr_merge_train_base_ci_red`, in
`shell-common/lib/gh_pr_merge_train.sh` (vendored at
`lib/vendor/shell-common/lib/`) beside the label predicates —
their full contracts are the comments above each. All are answered from calls
the train makes **once per distinct base branch**, never per PR, so the guard
adds no per-PR round trip. The rules body is the one
`references/approval-gate.md` already fetches for the approval count.

```bash
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"                                   # tier 1
if [ ! -f "$_SC/lib/gh_pr_merge_train.sh" ]; then
    [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || {                                            # tier 5
        printf '[gh-pr:merge-train] no shell-common under %s, and CLAUDE_PLUGIN_ROOT is unset. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
            "$_SC" >&2
        return 1 2>/dev/null || exit 1
    }
    _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common"                                # tier 2
fi
unset -f _gh_pr_merge_train_filter_targets 2>/dev/null || :
unalias _gh_pr_merge_train_filter_targets 2>/dev/null || :
export SHELL_COMMON="$_SC"                                                           # before the load
[ -f "$_SC/lib/gh_pr_merge_train.sh" ] && . "$_SC/lib/gh_pr_merge_train.sh"
[ "$(command -v _gh_pr_merge_train_filter_targets 2>/dev/null)" = _gh_pr_merge_train_filter_targets ] || { # tier 5
    unset SHELL_COMMON
    printf '[gh-pr:merge-train] %s did not load a usable shell-common. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}

BASE_ENC=$(jq -rn --arg b "$BASE" '$b|@uri')
BASE_RULES=$(GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/rules/branches/$BASE_ENC" 2>/dev/null) \
    || BASE_RULES=''
# ONE sentinel for "unreadable", not two. A failed call and a 200 carrying
# something that is not the expected array (a proxy interstitial, a truncated
# body) are equally unreadable, so both become the empty string here and every
# test below can just ask `-z`. Without this, a malformed body sails past the
# `-z` guard while every predicate reading it still answers its own fail-closed
# rc 1 — which is silence, not a halt.
printf '%s' "$BASE_RULES" | jq -e 'type == "array"' >/dev/null 2>&1 || BASE_RULES=''

# Does BEHIND still owe a local rebase on this base? (routing-table.md D-1)
BEHIND_DIRECT=no
printf '%s' "$BASE_RULES" | _gh_pr_merge_train_behind_may_merge_directly && BEHIND_DIRECT=yes

# A SEPARATE question from the one above, deliberately: can we PROVE this base
# is still fully strict, and therefore never depended on the net below? Only a
# readable body that positively confirms strict-on everywhere is an exemption.
BASE_STRICT_CONFIRMED=no
printf '%s' "$BASE_RULES" | _gh_pr_merge_train_base_strict_confirmed && BASE_STRICT_CONFIRMED=yes

# Is the base already broken?  Fail closed: an unreadable answer halts.
# An array, not a string — a context like `Lint (mise)` contains a space, and
# word-splitting it would ask about two checks that do not exist.
BASE_CONTEXTS=()
while IFS= read -r _ctx; do
    [ -n "$_ctx" ] && BASE_CONTEXTS+=("$_ctx")
done <<EOF
$(printf '%s' "$BASE_RULES" | jq -r '.[]? | select(.type == "required_status_checks")
                                          | .parameters.required_status_checks[]?.context' 2>/dev/null)
EOF

# `--paginate` (dEitY719/dotfiles#1707, codex FOLLOW-UP): the check-runs endpoint pages at 30
# per the default page size, and `gh api --paginate` on this object-shaped
# response (`{total_count, check_runs: [...]}`) merges the `check_runs` array
# across pages into one combined object rather than concatenating separate
# JSON documents — verified empirically against this repo's own `main`. A base
# with more than 30 check runs would otherwise silently drop a later, possibly
# failing required context off the one page an un-paginated call sees.
BASE_CHECKS=$(GH_HOST="$TARGET_HOST" gh api --paginate "repos/$TARGET_REPO/commits/$BASE_ENC/check-runs" 2>/dev/null) \
    || BASE_CHECKS=''
# Same normalisation, same reason: `_gh_pr_merge_train_base_ci_red` answers
# "no proof of red" for a malformed body, which must not read as "green".
printf '%s' "$BASE_CHECKS" | jq -e 'has("check_runs")' >/dev/null 2>&1 || BASE_CHECKS=''

# EITHER lookup being unreadable is an unreadable base. An empty $BASE_RULES is
# not merely "one of two answers missing": it also empties $BASE_CONTEXTS, so
# the red check below has nothing to match and a genuinely red base would read
# as green. The only exemption is a base proven still-strict.
if [ "$BASE_STRICT_CONFIRMED" = no ] && { [ -z "$BASE_RULES" ] || [ -z "$BASE_CHECKS" ]; }; then
    echo "[SKIPPED] base health unreadable on $BASE — not merging onto an unverified base"
elif printf '%s' "$BASE_CHECKS" | _gh_pr_merge_train_base_ci_red "${BASE_CONTEXTS[@]}"; then
    echo "[SKIPPED] $BASE is red — halting the merge phase until it is green"
fi
```

The exemption is keyed on `BASE_STRICT_CONFIRMED`, **not** on `BEHIND_DIRECT`,
and that distinction is the whole point (PR dEitY719/dotfiles#1725, codex BLOCKER). The rule
being preserved is unchanged: *a base that never relaxed strict mode never
depended on this net, and must not start being blocked by a lookup it never
needed.* What changed is what counts as proof of "never relaxed".
`BEHIND_DIRECT = no` is not that proof — it is the answer to a different
question (`_gh_pr_merge_train_behind_may_merge_directly`'s contract collapses
"strict is on", "no rule found" and "the body was unreadable" into one rc 1),
so keying the halt off `BEHIND_DIRECT = yes` meant a **failed RULES lookup
switched the halt off**: exactly the case with the least information got the
least protection. And when the same outage took the check-runs call with it,
`_gh_pr_merge_train_base_ci_red` on an empty body is rc 1 ("no proof of red")
by its own contract, so the `elif` stayed quiet too and the tick merged CLEAN
PRs onto a base nothing had verified — the CLEAN row never consults
`$BEHIND_DIRECT` at all (`references/routing-table.md`), so this guard was the
only thing between an API outage and an unverified merge.

`_gh_pr_merge_train_base_strict_confirmed` answers the exemption question
directly and positively: rc 0 only for a readable body in which every
`required_status_checks` rule found has strict **on**. Unreadable, no rule, or
any relaxed rule → rc 1 → halt-eligible. So the four cases are:

| `BASE_RULES` | `BASE_CHECKS` | Outcome |
|---|---|---|
| confirms strict ON everywhere | anything | exempt — no unreadable-halt (a red tip still halts on the `elif`) |
| relaxed, or no rule found | readable | proceed; red tip halts normally |
| relaxed, or no rule found | unreadable | **halt** — base health unreadable |
| unreadable | readable **or** unreadable | **halt** — cannot even name the required contexts |

"Unreadable" means the empty sentinel above, which by then covers both a failed
call and a 200 whose body is not the expected shape.

Four properties of that guard, each a deliberate limit:

- **It halts the merge phase, not one PR.** Everything queued this tick is
  `[SKIPPED]` with the base's name as the reason. Never `[FAILED]` — the next
  tick re-reads and proceeds the moment `main` is green again, so a red base
  can never become the unclearable state `approval-gate.md` warns about.
- **Required contexts only.** `main`'s tip also carries runs nobody gated on
  (the weekly `Contract + drift` audit; a paths-filtered package build).
  Halting on those would wedge the train on a failure no queued PR caused and
  no merge could clear.
- **Concluded failures only; pending is not red.** The train ticks every 3
  minutes and lint takes 1-2, so treating a still-running check as red would
  stall the train for a full CI cycle after every merge — reinstating exactly
  the serialisation this change removed, under a new name.
- **An unread answer halts; only a positively-strict base is exempt.** The two
  `gh api` calls fail together in an outage far more often than separately, and
  the failure modes of both predicates point the same way ("no proof of red",
  "no shortcut"), so nothing downstream would notice a double failure on its
  own. The halt is the only thing that does, and it is deliberately keyed on
  raw unreadability rather than on any predicate's verdict.

**What it does not do:** it cannot prevent the *first* bad merge. Nothing can,
once strict is off — that is the accepted risk, restated. What it does is turn
"N PRs merged onto a broken base" into "one bad merge, then a stop", which is
the difference between a five-minute bisect and an afternoon.

### 3. `gh-verify:post-merge-verify` — real on this repo, but advisory

`gh-pr:merge` Step 5 dispatches it, gated on the watched-repos registry
(`${IW_WATCHED_REPOS:-${HOME}/.avatars/issue-watcher/watched-repos.json}`).
**This repo is registered** — checked, not assumed:

```json
[{"repo": "dEitY719/dotfiles", "path": "/home/bwyoon/dotfiles",
  "host": "github.com", "post_merge_verify": true,
  "post_merge_verify_skill": "gh-verify:merged"}]
```

So the dispatch does fire here, and `gh-verify:merged` re-runs the repo's
own test command in a **fresh clone of the merge commit** — which is the only
thing in this whole chain that exercises bats and pytest against the merged
result at all, given dEitY719/dotfiles#754.

Weigh it honestly, though. It opens a herdr session for a human to read; it
does not block anything, it does not gate the next merge, and on the `--auto`
path it fires at finalize time rather than at merge time. It is a good
detector, not a gate. **Item 2 above is the only mechanism that changes what
the train does.**

## AC4 — the expected-mechanism argument, and what has not been measured

The claim AC4 asks about is that N PRs now cost fewer than N CI round trips.
Per-PR, after this change:

| Row | Before (strict on) | After (strict off) |
|---|---|---|
| `CLEAN` | merge | merge — unchanged |
| `BEHIND` + `MERGEABLE` | local rebase → push → **full CI cycle** → merge | GitHub rebases at merge time; **no round trip**, and GitHub no longer reports the row at all (table above) |
| `DIRTY` / `CONFLICTING` | resolve → push → full CI cycle → merge | unchanged — still one round trip, still just-in-time |

So the cost goes from N round trips to **one per genuinely conflicting PR**. A
queue of N independent PRs — the normal case for this train — now costs zero
extra CI cycles beyond the ones each PR already paid before it was queued.

**This has not been measured end to end.** Nobody has run
`gh-pr:merge-train` against a live multi-PR queue since the flip, and no number
on this page is a measurement of one. What is measured is the mechanism's
precondition: the three open PRs above really are behind `main` and really do
report `CLEAN`, which is the specific state change the whole argument rests on.
Empirical confirmation arrives on its own on the next real cron tick after this
merges — the Step 5 report will show `[MERGED]` lines without the
`gh-resolve:outdated` runs that used to precede them.
