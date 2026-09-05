# gh-pr:merge-train — Review verdict gate (#1564)

A PR does not enter `gh-pr:merge` unless a reviewer said so. This gate is the
consumer of two labels; it never forms an opinion of its own and never reads a
comment body.

Producer SSOT — how the labels are decided and written:
`devx-pr-review-all/references/review-verdict-label.md`.

## The decision table

Applied to every PR that survived Step 2's `_gh_pr_merge_train_filter_targets`.
Both labels come from the `labels` field that Step 2's `gh pr list --json` has
already returned — the label check itself makes no API call of its own. The
freshness check below (#1601) is the one exception: it costs at most two
`gh api` calls, and only for a PR that already carries `review-passed` alone
(the case that would otherwise proceed unverified). Since #1615 that cost is
bounded regardless of comment count — it reads page 1's `Link: ...;
rel="last"` header and, only if the PR spans more than one page, jumps
straight to the last page, instead of `--paginate` walking every page on
every tick.

| Labels present | Queue verdict |
|---|---|
| `review-blocked` (regardless of `review-passed`) | `[SKIPPED] review-blocked — reviewer verdict is blocking` |
| neither label | `[SKIPPED] review not verified — no review-passed label` |
| `review-passed` only, marker sha matches current head | stays in the queue |
| `review-passed` only, marker exists but sha MISMATCHES current head (#1601) | `[SKIPPED] review-passed label stale — head advanced without invalidation` (self-heals: drops the label) |
| `review-passed` only, no marker at all from the trusted login (#1601) | `[SKIPPED] review-passed not confirmed for this head — no freshness marker found` (label left untouched) |
| `review-passed` only, freshness lookup itself failed (#1601) | `[SKIPPED] review-passed freshness unknown — marker lookup failed, treating as unverified` (label left untouched) |

```bash
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_merge_train.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_merge_train.sh" ] || {
    printf '[gh-pr:merge-train] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_merge_train.sh"
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_edit_safe.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_edit_safe.sh" ] || {
    printf '[gh-pr:merge-train] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_edit_safe.sh"

# The one identity this whole pipeline authenticates as — the same login
# that ran devx_pr_review_all_apply_label when it posted the marker. Hoisted
# once per run in real code (train-loop.md already binds ME this way for the
# delegated-review step); `${ME:-...}` here just makes this snippet runnable
# standalone. GH_PR_MERGE_TRAIN_TRUSTED_LOGIN overrides the auto-detected
# identity for setups where the review pipeline and the merge-train dispatcher
# authenticate as different accounts (PR #1608 review, agy round-2 BLOCKER —
# see "Marker authorship" below).
ME="${GH_PR_MERGE_TRAIN_TRUSTED_LOGIN:-${ME:-$(GH_HOST="$TARGET_HOST" gh api user -q .login)}}"

if printf '%s' "$PR_JSON" | _gh_pr_merge_train_has_review_blocked_label; then
    echo "[SKIPPED] review-blocked — reviewer verdict is blocking"
elif ! printf '%s' "$PR_JSON" | _gh_pr_merge_train_has_review_passed_label; then
    echo "[SKIPPED] review not verified — no review-passed label"
else
    _gh_pr_merge_train_review_passed_stale "$N" "$TARGET_REPO" "$TARGET_HOST" "$HEAD_OID" "$ME"
    case $? in
    1)
        # MISMATCH — a marker exists but names a different head. Positive
        # proof the label is wrong for this commit, so self-heal is safe:
        # drop it here too. Best-effort — a failed drop still leaves this
        # tick's [SKIPPED] correct; it only means the next tick pays for the
        # same sha check again.
        echo "[SKIPPED] review-passed label stale — head advanced without invalidation"
        _gh_pr_drop_label "$N" review-passed "$TARGET_REPO" "$TARGET_HOST" >/dev/null 2>&1 || :
        ;;
    2)
        # ABSENT — no marker at all, but the lookup succeeded. Route as
        # unverified (never merge on it) but do NOT delete: absence alone
        # doesn't prove the label is wrong for THIS head, only that it
        # cannot be proven right — e.g. a pre-#1601 label, or a marker post
        # that itself failed. Deleting every such label the moment this
        # feature ships was flagged as an unacceptable operational cliff
        # across two independent PR #1608 review rounds (agy).
        echo "[SKIPPED] review-passed not confirmed for this head — no freshness marker found"
        ;;
    3)
        # UNDETERMINED — the lookup itself failed. Skip this tick (fail-
        # closed, same as any other unreadable state) but never delete the
        # label on the strength of a check that never completed: a network
        # blip must not destroy an otherwise-valid review-passed (PR #1608
        # review, agy round-2 BLOCKER).
        echo "[SKIPPED] review-passed freshness unknown — marker lookup failed, treating as unverified"
        ;;
    esac
fi
```

This full form — including the `HEAD_OID` freshness branch — is what Step 4's
F-3 re-check runs (`routing-table.md`), right before a specific PR is acted
on. `SKILL.md` Step 3.5's queue-build pass runs only the first two branches
(the label-only prefix) over the whole Step-2 queue, on purpose: it has
neither `$HEAD_OID` nor the budget to pay one `gh api` call per queued PR when
most of them won't be reached this tick anyway. A `review-passed` PR that
passes Step 3.5 is provisionally queued; F-3 is what actually proves the
label is still trustworthy.

`review-blocked` is tested **first**, so it wins over a stale `review-passed`
if both are somehow present. #1563's invalidation should make that
unreachable — every skill that advances a PR's head drops the stale verdict —
but a gate on a merge has to be deterministic about a state it does not
expect, not merely unlikely to meet it.

## Freshness check (#1601)

The label-presence check above answers "was this PR ever verified"; it
cannot answer "was *this* head verified", because a label carries no data of
its own. #1563 tried to keep the two in sync by having every head-advancing
skill drop the label on push — but that list can never be complete: a manual
`git push --force-with-lease` from a human's shell, a GitHub web-UI commit, or
a future tool all advance the head with no hook this repo controls. Any of
those leaves a stale `review-passed` that the presence-only check above would
happily trust.

`_gh_pr_merge_train_review_passed_stale` (`shell-common/functions/gh_pr_merge_train.sh`)
closes that gap by verifying instead of trusting: it reads the last
`<!-- review-verdict:review-passed:<sha> -->` marker POSTED BY THE PIPELINE'S
OWN LOGIN — see "Marker authorship" below — that
`devx_pr_review_all_apply_label` posted when it applied the label
(`devx-pr-review-all/references/review-verdict-label.md` → "Freshness marker
for `review-passed`") and compares that sha against `$HEAD_OID` — the current
`headRefOid`, already added to F-3's `$STATE` fetch (`routing-table.md`). No
matching marker, or one whose sha does not match, is STALE — fail-closed, the
same direction `approval-gate.md` takes for an unreadable policy: an
undetermined answer costs one skip, and a skip is trivially retried.

The function's exit code carries three states rather than a boolean — `0`
fresh, `1` stale-CONFIRMED, `2` stale-UNDETERMINED (the lookup itself
failed) — because the two "stale" cases call for different actions (see
"Confirmed vs. undetermined" below).

This still does not make the train a comment parser in the sense "What this
gate is not" forbids below: it never reads a *reviewer's* verdict line, only
a fixed machine stamp this same subsystem writes for exactly this check.

### Marker authorship (PR #1608 review, agy + codex BLOCKER)

A plain comment has no write-permission floor the way a label does — on most
repos anyone who can see the PR can comment on it. An earlier version of this
check matched the marker text from *any* commenter, which let anyone re-arm a
stale `review-passed` by hand-posting
`<!-- review-verdict:review-passed:<current-head> -->`, no label-write access
required. `_gh_pr_merge_train_review_passed_marker_sha` now takes a required
`<expected-login>` and only counts a marker from that exact GitHub login — the
one account this whole pipeline authenticates as (the same login
`train-loop.md`'s delegated-review step already resolves via
`gh api user -q .login`). Forging a trusted marker now requires the same
access as forging the label directly (label-write access, already the
accepted trust boundary this whole gate rests on — the label has no stronger
guarantee than "someone with write access said so"). A missing/invalid login
is fail-closed to "no marker" — never a fallback to trusting every commenter.

Two follow-on fixes from the round-2 review, both about *which* login counts
as trusted:

- **Bot logins.** GitHub gives an App-associated identity a login shaped
  `<name>[bot]` (`github-actions[bot]`, `dependabot[bot]`). The first cut of
  the validator rejected every bracket outright, so a pipeline that
  authenticates as any bot account could never validate a single marker —
  every `review-passed` PR would read as permanently stale (agy round-2
  BLOCKER). The validator now strips a literal trailing `[bot]` before
  applying the same `[A-Za-z0-9-]+` character check to what's left, so
  `github-actions[bot]` passes while an injection attempt (which won't end in
  exactly `[bot]`) still does not.
- **Single-identity assumption.** The whole scheme assumes one account runs
  both `gh-verify:review-all` (which posts the marker) and `gh-pr:merge-train`
  (which checks it) — true for this repo's own single-account pipeline, but
  not guaranteed for every deployment: a human running a manual review under
  their own login, or a setup with a different bot per role, would see every
  marker as untrusted forever (agy round-2 BLOCKER). `GH_PR_MERGE_TRAIN_TRUSTED_LOGIN`
  is the escape hatch — set it to the actual producer identity when it
  differs from `gh api user -q .login`'s answer in the consuming context.

### Mismatch, absence, and undetermined are three different facts (PR #1608 review, agy rounds 2 and 3)

Only ONE of the three ways a marker check can come back short of FRESH is
positive proof the label is wrong for this head. Collapsing any pair of them
into the same self-heal decision either destroys data on a guess or accepts
a real gap:

- **MISMATCH (rc 1)** — a marker from the trusted login exists, but its sha
  names a different commit. This is direct evidence: the reviewed head is
  provably not the current one (a force-push moved past it, the original
  #1601 scenario). Self-heal (drop the label) is safe here — the caller
  isn't guessing, it's acting on proof.
- **ABSENT (rc 2)** — the lookup succeeded and found no marker at all from
  the trusted login. This looks identical whether the label was applied
  before this freshness check existed, by a future skill that legitimately
  never posts the marker, or genuinely forged — there is no way to tell
  those apart from absence alone. An earlier version of this fix treated
  ABSENT the same as MISMATCH and self-healed on it too, which meant every
  `review-passed` PR open at rollout — having no marker for the simple
  reason the mechanism didn't exist when it was labeled — would have its
  label destructively stripped the moment this feature shipped. agy flagged
  exactly this as a BLOCKER independently in **both** review rounds (2 and
  3) before the distinction existed. The fix routes ABSENT PRs as unverified
  (never merges on the strength of an unconfirmed label) without touching
  the label — a plain re-review clears it exactly as cheaply as a delete-
  and-relabel cycle would have, so there is nothing to gain by deleting.
- **UNDETERMINED (rc 3)** — the lookup itself failed (network, auth, rate
  limit) or the login was invalid, so nothing was confirmed either way.
  Same treatment as ABSENT — route as unverified, never touch the label —
  for the same reason: a transient blip is not evidence, and destroying a
  possibly-valid label on a guess turns a cheap, retriable skip into
  un-recoverable damage the next successful lookup cannot undo (agy
  round-2 BLOCKER, the original motivation for splitting this rc out at
  all before ABSENT was split from it too).

`_gh_pr_merge_train_review_passed_marker_sha`'s own exit code carries the
first half of this split (`0` lookup completed / non-zero lookup failed);
`_gh_pr_merge_train_review_passed_stale` folds it into the full four-way
code above, and the caller only calls `_gh_pr_drop_label` on `1`.

Neither ABSENT nor UNDETERMINED is an F-5 attempt, and neither is ever
`[FAILED]`: a withheld verdict is a working review, not a broken train (the
same rule `report-format.md` states for the delegated-review reasons).

## Why absence is blocking

"Not reviewed" and "reviewed and passed" are different states, and a gate that
collapses them is worse than no gate: it advertises a guarantee it does not
provide. #1527's reproduction is PR #1518 — two independent blocking verdicts
posted, merged 32 minutes later, 5 BLOCKERs into `main` (#1520, PR #1522) —
and the reason the verdicts never reached the merge decision is precisely that
nothing distinguished "no signal" from "green signal".

The cost of the strict direction is bounded and visible. A PR the gate skips
is one label away from moving: a re-review issues it, or a human adds it. The
cost of the permissive direction is an unreviewed merge, which is not
recoverable by any label.

**Expect a cliff at rollout.** Every PR open when this gate lands carries no
verdict label and is `[SKIPPED]` until it is reviewed. That is the design
working, not a regression.

## Why no time backstop

`reply-pending` has a staleness window
(`_gh_pr_merge_train_reply_pending_stale_minutes`, 90 min) because it is a
*hard skip that only its writer can lift*: a session that died mid-pass would
wedge its PR forever, so the label has to expire.

These labels have the opposite shape. Absence is already the blocking state,
so there is nothing for time to release — expiring `review-passed` would only
move a PR from "verified" to "not verified", which is where an un-reviewed PR
already sits. And expiring `review-blocked` would silently promote a blocked
PR to merely unverified, then to mergeable the moment any pass label appeared.
A window here would weaken the gate, not bound it.

Do not add one.

## What this gate is not

- **Not the board `Approved` gate.** `#1513` retired that, and this does not
  revive it. The signal here is a label written by the reviewer fan-out, not a
  project-board column.
- **Not the approval gate.** `approval-gate.md` answers "does the *platform*
  require an approval, and does `gh-pr:merge` accept this `reviewDecision`".
  This answers "did the reviewers pass it". A PR must clear both; they are
  independent questions and each has its own `[SKIPPED]` reason.
- **Not a comment parser.** The train never reads *review* comment bodies —
  a reviewer's LGTM/BLOCKING prose. Parsing that lives entirely in the
  producer, and that direction is deliberate: a reviewer reformatting its
  verdict line yields `unknown` → no label → a skipped PR. Move the parsing
  here and the same reformat would silently *unlock* the gate. The #1601
  freshness check above reads a comment too, but a fixed machine-only marker
  the producer stamps for exactly this purpose, never a reviewer's own
  output — see "Freshness check" for why that line is not the one this rule
  guards.
- **Not part of `_gh_pr_merge_train_filter_targets`.** That filter drops its
  rejects silently before the queue exists, and `report-format.md` documents
  those PRs as never listed. #1564 requires a visible per-PR line, so this
  runs as a queue-level step over what the filter already passed.

## Provisioning

`_gh_pr_edit_safe_label` refuses to auto-create a missing label (#326), so
without provisioning the producer can never issue either one and every PR
skips forever. `gh-setup:label-bootstrap` provisions both from the `pipeline|` feed
in the `gh-setup-skills` sibling repo (`skills/label-bootstrap/references/gh-labels.md`), and `--prune` preserves them.

## Related

- `devx-pr-review-all/references/review-verdict-label.md` — producer SSOT
- `report-format.md` — where the two `[SKIPPED]` reasons are tabled
- `routing-table.md` — the F-3 per-PR re-check that closes the mid-run race
- `ordering.md` — the `reply-pending` label's lifecycle, the *timing* signal
  this *content* signal sits beside
