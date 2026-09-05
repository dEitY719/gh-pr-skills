#!/bin/sh
# VENDORED — do not edit here.
# SSOT: dEitY719/dotfiles shell-common/functions/gh_pr_merge_train.sh
# Synced 2026-09-05T10:16Z by dEitY719/harness-skills scripts/sync-shell-common-vendor.sh — re-run that script to update.
# shellcheck shell=bash
# shell-common/functions/gh_pr_merge_train.sh
# SSOT for the merge-train target filter (issue #1524).
#
# Background (issue #1524, bug B):
# The filter that decides which of your open PRs the merge train may touch used
# to exist twice — once as real `jq` inside
# `shell-common/tools/custom/pr_merge_train_cron.sh` (`_pmt_target_count`), and
# once as English prose inside `claude/skills/gh-pr-merge-train/SKILL.md`
# ("drop every PR updated within the last 11 minutes and every draft"). Prose is
# executed by an LLM, which can skip it, mis-add the minutes, or read a stale
# clock — and when it does, the train merges a PR whose deferred review-reply
# pass has not landed yet. Both call sites now call the one function below, so
# there is exactly one implementation and one place the number 11 lives.
#
# Usage:
#   _gh_pr_merge_train_quiet_minutes
#   _gh_pr_merge_train_reply_pending_stale_minutes
#   _gh_pr_merge_train_filter_targets --now <epoch-seconds> [--minutes <n>]
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_has_reply_pending_label
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_has_review_blocked_label
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_has_review_passed_label
#   _gh_pr_merge_train_record_pushed_sha <state-dir> <pr> <sha>
#   _gh_pr_merge_train_pushed_sha_matches <state-dir> <pr> <sha>
#   _gh_pr_merge_train_forget_pushed_sha <state-dir> <pr>
#   <raw gh-pr-list JSON array> | _gh_pr_merge_train_readmit_own_pushes <state-dir> <filtered-json>
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_needs_finalize
#   <gh-pr-list JSON array>       | _gh_pr_merge_train_finalize_targets
#   <rules/branches/<base> JSON>  | _gh_pr_merge_train_behind_may_merge_directly
#   <rules/branches/<base> JSON>  | _gh_pr_merge_train_base_strict_confirmed
#   <commits/<base>/check-runs JSON> | _gh_pr_merge_train_base_ci_red <ctx>...
#
# `_gh_pr_merge_train_quiet_minutes`
#   Echo the quiet period in minutes. Default 11; override with the env var
#   GH_PR_MERGE_TRAIN_QUIET_MINUTES. This is the ONE place the number is
#   hardcoded — the cron dispatcher's usage text and
#   `claude/skills/gh-pr-merge-train/references/ordering.md` both cite it.
#   11 = the 4-minute `--defer-reply` window `gh:issue-flow` Step 2.4 schedules
#   + the reply pass's own runtime + slack (D-6).
#
# `_gh_pr_merge_train_reply_pending_stale_minutes`
#   Echo how long a `reply-pending` label is believed, in minutes. Default 90;
#   override with GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES. Same shape as
#   the quiet-period function above, and the same "one place the number lives"
#   rule. 90 is sized as "longer than any healthy deferred reply pass, shorter
#   than a wedged PR is tolerable": 4 minutes of scheduled defer + a
#   `devx:pr-review-all` fan-out + a `gh:pr-reply` pass that on a heavily
#   reviewed PR walks dozens of threads, edits files, commits and pushes —
#   generously an hour — plus slack. It is ~8x the 11-minute quiet period, so
#   the two windows can never be confused for one another, and a dead session's
#   PR rejoins the train within six 15-minute cron ticks rather than never.
#
# `_gh_pr_merge_train_filter_targets`
#   Read a JSON array on stdin — the shape `gh pr list --json ...` answers with
#   — and echo the same array on stdout with every non-target element removed.
#   A surviving element is passed through UNCHANGED, every field included: the
#   dispatcher reads `number`/`updatedAt`/`isDraft` plus
#   `headRefOid`/`mergeStateStatus`/`labels` for its unchanged-queue
#   fingerprint (#1709), and the skill also needs
#   `mergeable`/`baseRefName`/`title` for the D-2 sort and the D-1 routing
#   table, so this function must never project fields away.
#
#   An element is DROPPED when any of these holds:
#     1. `.isDraft` is true               — DRAFT is a skip row in the D-1 table.
#     2. `.labels[].name` has `reply-pending` AND `.updatedAt` is newer than
#        `--now` minus the STALENESS window
#        (`_gh_pr_merge_train_reply_pending_stale_minutes`, default 90 minutes)
#                                         — a deferred `gh:pr-reply` pass is
#                                           still plausibly outstanding.
#        Labelling a PR bumps its `updatedAt`, so that stamp is also "when the
#        label was applied, at the earliest". Once it is older than the window,
#        the session that owed the removal is presumed dead and the label is
#        presumed stale: the element stops being dropped by this rule and falls
#        through to rule 3 exactly like an unlabelled PR. That fall-through IS
#        the backstop `ordering.md` D-6 promises — without it, a label nobody
#        ever removes excludes its PR from the train permanently (PR #1545
#        review, codex BLOCKER). A PR sitting exactly ON the boundary counts as
#        stale (`<=`), matching rule 3's own inclusive cutoff.
#     3. `.updatedAt` is newer than `--now` minus the quiet period, OR cannot be
#        read at all (missing / null / unparseable). The unreadable case fails
#        *closed* on purpose: `// empty` (not `// 0`) makes the `as $ts` binding
#        produce nothing and the element vanish, because `// 0` would become
#        epoch zero — `<= $cutoff` for any clock — and count an unreadable PR as
#        a target, the exact direction D-6 exists to prevent. Binding before
#        rule 2 also means an unreadable stamp can never be read as "the label
#        is stale", the same failure in the other window.
#
#   Flags:
#     --now <epoch-seconds>  REQUIRED. The caller supplies the clock reading, so
#                            this function stays pure and deterministic and the
#                            bats suite can test it without mocking `date`.
#     --minutes <n>          Override the quiet period for this call; defaults
#                            to `_gh_pr_merge_train_quiet_minutes`.
#
#   Return codes:
#     0 — filtered array on stdout (possibly `[]`).
#     1 — usage error, or stdin was empty / not parsable JSON. Nothing on
#         stdout. This is a secondary defense only: the dispatcher already ends
#         the tick when `gh pr list` itself fails, and the skill ends the run.
#
# The `reply-pending` label (issue #1524, bug A):
# The quiet period is a *time-based proxy* for "has the deferred review-reply
# pass finished", and time is a bad proxy — a slow reply pass outlives the
# window and the train merges anyway. The label is the real signal, and its
# name is a fixed literal shared by three call sites:
#   - this file      drops any PR carrying it, regardless of the quiet period,
#                    for as long as the label is fresh (see rule 2 above)
#   - devx:pr-review-all  ADDS it on the `defer` branch (Step 5)
#   - gh:pr-reply         REMOVES it when the reply pass completes (Step 6)
# The quiet period stays as the BACKSTOP: PRs opened by hand or by another tool
# never get the label, and a session that died mid-pass never removes it. That
# second case is only reachable because the label EXPIRES — the hard skip is
# bounded by the staleness window, so "the remover died" degrades to "the PR
# waits out the window", not "the PR is never merged again".
#
# `_gh_pr_merge_train_has_reply_pending_label`
#   The same "does `.labels[]` contain `reply-pending`" question, asked of ONE
#   PR object (not an array) on stdin. `_gh_pr_merge_train_filter_targets`
#   above answers it for the whole queue at Step 2; `references/routing-table.md`
#   F-3 asks it again per PR, right before acting, because a label can be
#   *added mid-run* (a deferred devx:pr-review-all pass) after Step 2 already
#   built the queue. Both call sites run this one function so the predicate
#   itself cannot drift apart the way the quiet-minutes number used to (#1524).
#
# The two verdict labels (issue #1564, umbrella #1527):
# `_gh_pr_merge_train_has_review_blocked_label` /
# `_gh_pr_merge_train_has_review_passed_label`
#   Same single-PR-object-on-stdin shape as the reply-pending predicate above,
#   asked of `review-blocked` / `review-passed`. `devx:pr-review-all` Step 3.5
#   is their ONLY writer (`devx-pr-review-all/references/review-verdict-label.md`);
#   the merge train is their only reader, and it reads NOTHING else — no
#   comment-body parsing lives here, deliberately, so a reviewer reformatting
#   its verdict line can never *unlock* the gate.
#
#   These are NOT folded into `_gh_pr_merge_train_filter_targets` above. That
#   filter drops its rejects silently, before the queue exists, and
#   `references/report-format.md` documents those PRs as never listed. #1564
#   requires the opposite: a per-PR `[SKIPPED]` line naming which of the two
#   reasons applied, in the same visibility class as the approval gate's own
#   skip. So the verdict gate is a queue-level step
#   (`references/review-verdict-gate.md`), run over what this file's array
#   filter already let through, and these predicates are what it runs.
#
#   The decision table lives in that reference; the two invariants that make
#   it deterministic are: `review-blocked` wins over a stale `review-passed`
#   if both are somehow present, and the ABSENCE of both is "not verified" —
#   a skip, never a pass. Absence-is-blocking is also why there is no
#   staleness window here to match `reply-pending`'s: that label self-expires
#   because a dead session would otherwise wedge its PR forever, whereas a
#   verdict-less PR is unwedged by one re-review or one human-added label.
#
# NOTE: This file intentionally has NO interactive guard. It is a pure
# function-defining library (no top-level side effects) sourced from two
# non-interactive contexts: the `pr_merge_train_cron.sh` cron dispatcher, and
# the `gh:pr-merge-train` skill's Bash tool calls (Claude Code runs those as
# `bash --noprofile --norc`). An interactive guard would `return 0` before
# defining either function, breaking both with `command not found` — the same
# reason the NOTE exists in gh_pr_edit_safe.sh and gh_project_status.sh
# (PR #497 / issue #720).

# D-6 quiet period, in minutes. The one hardcoded 11 in the repo.
_gh_pr_merge_train_quiet_minutes() {
    local _m="${GH_PR_MERGE_TRAIN_QUIET_MINUTES:-11}"
    case "$_m" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] GH_PR_MERGE_TRAIN_QUIET_MINUTES=%s is not a number — using 11\n' \
                "$_m" >&2
            _m=11
            ;;
    esac
    printf '%s\n' "$_m"
}

# How long a `reply-pending` label is believed, in minutes. Past this, the
# session that owed the removal is presumed dead and the label stops excluding
# its PR — see rule 2 in the header for the sizing rationale.
_gh_pr_merge_train_reply_pending_stale_minutes() {
    local _m="${GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES:-90}"
    case "$_m" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES=%s is not a number — using 90\n' \
                "$_m" >&2
            _m=90
            ;;
    esac
    printf '%s\n' "$_m"
}

_gh_pr_merge_train_filter_targets() {
    local _now="" _minutes="" _cutoff _stale_minutes _stale_cutoff _json _out

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --now)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-merge-train] --now requires an argument\n' >&2
                    return 1
                fi
                _now="$2"
                shift 2
                ;;
            --minutes)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-merge-train] --minutes requires an argument\n' >&2
                    return 1
                fi
                _minutes="$2"
                shift 2
                ;;
            *)
                printf '[gh-pr-merge-train] unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    # --now is required rather than defaulted to `date +%s`: a caller that
    # cannot read the clock must decide what that means for itself (the cron
    # dispatcher ends the tick), and a default would quietly paper over it.
    case "$_now" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] usage: _gh_pr_merge_train_filter_targets --now <epoch-seconds> [--minutes <n>]\n' >&2
            return 1
            ;;
    esac

    if [ -z "$_minutes" ]; then
        _minutes=$(_gh_pr_merge_train_quiet_minutes)
    fi
    case "$_minutes" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] --minutes must be a non-negative integer: %s\n' "$_minutes" >&2
            return 1
            ;;
    esac

    _cutoff=$((_now - _minutes * 60))

    # No `--stale-minutes` flag to match `--minutes`: nothing needs to vary the
    # staleness window per call the way the dispatcher's usage text varies the
    # quiet period, and the env override already covers operator tuning.
    _stale_minutes=$(_gh_pr_merge_train_reply_pending_stale_minutes)
    _stale_cutoff=$((_now - _stale_minutes * 60))

    _json=$(cat)
    [ -n "$_json" ] || return 1

    # `.labels[]?.name` covers both shapes `gh` answers with: the objects
    # `--json labels` returns, and an absent `labels` key (the dispatcher used
    # to omit the field entirely) — `[]?` on a missing key yields nothing, so a
    # PR list without labels simply never matches.
    #
    # `$ts` is bound BEFORE either time test so an unreadable stamp drops the
    # element outright (an `as` binding over `empty` emits nothing) instead of
    # reaching the staleness test, where a missing value must never be allowed
    # to read as "old enough to ignore the label".
    _out=$(printf '%s' "$_json" \
        | jq --argjson cutoff "$_cutoff" --argjson stale_cutoff "$_stale_cutoff" '
        [ .[]?
          | select((.isDraft // false) | not)
          | (((.updatedAt // "") | fromdateiso8601? // empty)) as $ts
          | select(
              ([ .labels[]?.name? ] | index("reply-pending") | not)
              or ($ts <= $stale_cutoff)
            )
          | select($ts <= $cutoff)
        ]
    ' 2>/dev/null) || return 1
    [ -n "$_out" ] || return 1

    printf '%s\n' "$_out"
}

# Read one PR object (the shape `gh pr view --json labels,...` answers with,
# not an array) on stdin. 0 = it carries the `reply-pending` label, 1 =
# it does not (including malformed / missing `labels`). See the header note
# above for why this exists alongside `_gh_pr_merge_train_filter_targets`
# instead of routing-table.md re-deriving the same jq expression by hand.
_gh_pr_merge_train_has_reply_pending_label() {
    jq -e '[ .labels[]?.name? ] | index("reply-pending")' >/dev/null 2>&1
}

# The two verdict-label predicates (#1564). Same contract as the sibling
# above: one PR object on stdin, 0 = the label is present, 1 = it is not
# (including malformed / missing `labels`). See the header block for why the
# gate that consumes them is a queue-level step rather than another clause in
# `_gh_pr_merge_train_filter_targets`.
_gh_pr_merge_train_has_review_blocked_label() {
    jq -e '[ .labels[]?.name? ] | index("review-blocked")' >/dev/null 2>&1
}

_gh_pr_merge_train_has_review_passed_label() {
    jq -e '[ .labels[]?.name? ] | index("review-passed")' >/dev/null 2>&1
}

# The merge-queue finalize predicate (#1707).
#
# One PR object on stdin — the shape `gh pr list --json state,labels,...`
# answers with. rc 0 = this PR is MERGED but its post-merge completion steps
# never ran, so `gh:pr-merge --finalize` still owes it a pass. rc 1 = nothing
# to do (still open, or already finalized, or malformed).
#
# Why `state == MERGED` AND `review-passed` is the signal, rather than a
# queue-side lookup: `gh:pr-merge` Step 4 drops `review-passed` as the LAST
# thing it does after a merge (`references/review-passed-cleanup.sh.md`, #1636),
# and it is the only writer of that drop. So a MERGED PR still carrying the
# label is, by construction, a PR whose completion steps did not run — which is
# exactly what happens when the merge was ENQUEUED rather than performed
# (`--auto`, #1707): `gh pr merge` returned success, the PR stayed OPEN, and
# minutes later the queue merged it with no session watching. Reusing the label
# this way costs no extra API call — the train's Step 0 sweep already has to
# list PRs — and needs no new state file to go stale.
#
# The inverse is safe too: a PR merged the ordinary immediate way had its label
# dropped in the same run, so it never matches here and is never finalized
# twice. A PR that was merged without ever earning the label (a hand-merge, a
# pre-#1636 merge) also never matches — the sweep is deliberately conservative,
# because every step it would re-run is a GitHub write.
#
# Composes with `_gh_pr_merge_train_has_review_passed_label` above rather than
# re-deriving its label-index jq, for the same reason the header's "one place
# the predicate lives" rule exists for the quiet-minutes number.
#
# `.state` is compared case-INSENSITIVELY (#1707, PR #1725): `gh pr list` and
# `gh pr view` answer `"MERGED"`, but `gh search prs` — which is what Step 0's
# sweep now calls, so that a leftover cannot age out of a `--limit` window —
# answers `"merged"`. A case-sensitive compare would make the sweep silently
# match nothing, which looks exactly like "no leftovers" and is the same class
# of invisible failure this whole predicate exists to prevent.
_gh_pr_merge_train_needs_finalize() {
    local _json
    _json=$(cat)
    printf '%s' "$_json" | jq -e '((.state // "") | ascii_upcase) == "MERGED"' \
        >/dev/null 2>&1 || return 1
    printf '%s' "$_json" | _gh_pr_merge_train_has_review_passed_label
}

# Array-level sibling of the predicate above (#1707 follow-up), same shape as
# `_gh_pr_merge_train_filter_targets`: a `gh pr list` / `gh search prs`
# `--json ...` array on stdin, the filtered array back on stdout. Step 0 of
# `gh:pr-merge-train` calls THIS, not a per-element loop over the single-PR
# predicate — a sweep would otherwise fork `jq` up to twice per element just to
# filter an array it already has in hand.
#
# Same case-insensitive `.state` compare, for the same reason (PR #1725): Step 0
# feeds this `gh search prs --merged` output, whose `state` is `"merged"`.
_gh_pr_merge_train_finalize_targets() {
    local _json _out
    _json=$(cat)
    [ -n "$_json" ] || return 1
    _out=$(printf '%s' "$_json" \
        | jq -c '[ .[]?
            | select(((.state // "") | ascii_upcase) == "MERGED")
            | select(([ .labels[]?.name? ] | index("review-passed")) != null)
          ]' 2>/dev/null) || return 1
    [ -n "$_out" ] || return 1

    printf '%s\n' "$_out"
}

# Does a merely-BEHIND PR on this base need a LOCAL rebase before it can
# merge? (#1707, `references/strict-mode-relaxation.md`.)
#
# The whole `repos/{repo}/rules/branches/{base}` response on stdin — the same
# endpoint `references/approval-gate.md`'s `_gate_probe` already reads for the
# approval count, so this answer is free if the caller keeps that body.
#
# rc 0 = strict required-status-checks is DEFINITIVELY off on this base, so
#        GitHub rebases at merge time and a BEHIND PR may go straight to
#        `gh:pr-merge`. rc 1 = everything else: strict is on, no
#        required_status_checks rule was found, or the body was unreadable.
#
# The asymmetry is deliberate and points the same way every other gate in this
# skill points. rc 1 keeps the pre-#1707 behaviour — remediate locally through
# `gh:pr-resolve-outdated` — which is merely slower, and slower is the cost
# this repo has always been willing to pay for an unread answer. Never invert
# it: reading "unknown" as "strict is off" would send a PR to a merge the
# platform then refuses, burning F-5 attempts on a deterministic refusal.
#
# Absence of a `required_status_checks` rule is rc 1 rather than rc 0 on
# purpose. "No required checks at all" does mean GitHub will not block the
# merge — but it also means the base-CI guard below has nothing to watch, so
# the safety net that justifies the shortcut is not there either. A base with
# no checks is a base this shortcut has no evidence about.
_gh_pr_merge_train_behind_may_merge_directly() {
    jq -e '[ .[]? | select(.type == "required_status_checks") ] as $r
           | ($r | length) > 0
             and all($r[]; .parameters.strict_required_status_checks_policy == false)' \
        >/dev/null 2>&1
}

# Is this base PROVABLY still fully strict? (#1707, PR #1725 codex BLOCKER.)
#
# Same stdin as the predicate above — the whole
# `repos/{repo}/rules/branches/{base}` response — but it answers a DIFFERENT
# question, and conflating the two was the bug this exists to fix.
#
# `_gh_pr_merge_train_behind_may_merge_directly` answers the ROUTING question
# ("may a BEHIND PR skip its local rebase"), where rc 1 correctly collapses
# three inputs — strict on, no rule found, body unreadable — into one safe "no".
# The Step 3.6 red-base guard needs the SAFETY-NET question instead ("does this
# base still carry the strict guarantee that made the net unnecessary"), and
# for that the collapse is wrong: an unreadable body must not read as "strict is
# on, so this base never needed the net". Before this function existed, the
# guard keyed its unreadable-base halt off `BEHIND_DIRECT = yes`, so a failed
# RULES lookup — the situation with the LEAST information — silently disabled
# the halt entirely.
#
# rc 0 = the body was readable, at least one `required_status_checks` rule was
#        found, and EVERY one of them has strict on. Only then may the caller
#        skip its unreadable-base halt: this base never relaxed strict mode, so
#        it never depended on the net.
# rc 1 = everything else — strict relaxed on any rule, no rule found, or the
#        body was unreadable. All three mean "cannot prove this base is still
#        fully strict", which is halt-eligible.
#
# Note this is NOT the boolean negation of the predicate above, and must never
# be refactored into one. Both answer rc 1 for an unreadable body and for a base
# with no `required_status_checks` rule, on purpose: each fails closed in its
# own direction (no shortcut / no exemption), and an input that is unknown is
# never evidence for either.
_gh_pr_merge_train_base_strict_confirmed() {
    jq -e '[ .[]? | select(.type == "required_status_checks") ] as $r
           | ($r | length) > 0
             and all($r[]; .parameters.strict_required_status_checks_policy == true)' \
        >/dev/null 2>&1
}

# Is the base branch's tip commit RED on a check this base actually requires?
# (#1707, `references/strict-mode-relaxation.md` — the safety net.)
#
# `repos/{repo}/commits/{base}/check-runs` on stdin; the required contexts as
# arguments (from the same rules body the predicate above reads). rc 0 = at
# least one REQUIRED check has COMPLETED with a non-green conclusion, i.e.
# positive proof that what is already on the base is broken.
#
# This is what replaces the guarantee strict mode used to give. Strict mode
# verified the rebased result BEFORE it landed; `on: push` CI verifies the
# identical checks AFTER it lands (`.github/workflows/ci.yml`, `test.yml`).
# The coverage is the same set of checks — only the timing moved — so the one
# thing left to add was somebody reading the answer. That is this.
#
# Two scoping rules, both load-bearing:
#
#   * REQUIRED contexts only. A base tip also carries check runs from
#     workflows nobody gated on (this repo's weekly `Contract + drift` audit,
#     a paths-filtered package build). Halting the train on those would wedge
#     it on a failure no PR in the queue caused and no merge can clear — the
#     unclearable-skip disease `references/approval-gate.md` documents at
#     length. An empty context list is therefore rc 1, not rc 0.
#
#   * COMPLETED runs only. A check still `in_progress` on the tip is the
#     ordinary state 30 seconds after a merge, and the train ticks every 3
#     minutes. Treating pending as red would stall the train for one full CI
#     cycle after every single merge — which is precisely the serialisation
#     removing strict mode was meant to end, reintroduced under a new name.
#     Only a concluded failure halts.
#
# Green is a whitelist (`success` / `neutral` / `skipped`), so an unfamiliar
# conclusion — `startup_failure`, or whatever GitHub adds next — halts rather
# than passing unread. A malformed or empty body is rc 1 because this
# predicate only ever answers "is there proof of red"; the caller classifies
# an unreadable response as its own fail-closed case, the way `_gate_probe`
# does, and neither concern belongs in the other.
_gh_pr_merge_train_base_ci_red() {
    [ "$#" -gt 0 ] || return 1
    jq -e '[ .check_runs[]?
             | select(.name as $n | $ARGS.positional | index($n))
             | select(.status == "completed")
             | select([(.conclusion // "")]
                      | inside(["success", "neutral", "skipped"]) | not)
           ] | length > 0' --args "$@" >/dev/null 2>&1
}

# Sha-freshness check for `review-passed` (#1601).
#
# The label alone only proves "some head was reviewed", not "THIS head was
# reviewed". Its only invalidation path is a handful of hand-wired call sites
# (`gh:pr-reply`, `gh:pr-resolve-conflict`, `gh:pr-resolve-outdated`,
# `devx:pr-review-all` Step 4) that drop the label after a push THEY made —
# any other way the head advances (a manual `git push --force-with-lease`, a
# GitHub web-UI commit, a future tool) leaves a stale `review-passed` on a
# commit nobody reviewed, and this gate would trust it. Wiring more call
# sites cannot close that gap in general: a human's local `git push` has no
# hook this repo controls. So the fix lives on the READ side instead — verify
# the label against the head it was actually issued for.
#
# `devx_pr_review_all_apply_label` (shell-common/functions/devx_pr_review_all.sh)
# is the ONLY writer of the sha marker below, posted once as a plain issue
# comment at the moment it applies `review-passed`:
#   <!-- review-verdict:review-passed:<head-sha> -->
# This is NOT the reviewer-verdict comment parsing `review-verdict-gate.md`
# forbids ("Not a comment parser") — that rule is about never re-deriving a
# LGTM/BLOCKING verdict from a reviewer CLI's free-form prose, where a
# reformat could silently unlock the gate. This marker is a fixed, machine-only
# stamp this same subsystem writes for exactly this read; nothing about a
# reviewer's output format touches it.
#
# `_gh_pr_merge_train_review_passed_marker_sha <pr> <repo> [host] <expected-login>`
#   stdout: the sha carried by the LAST such marker POSTED BY
#   `<expected-login>` among the PR's issue comments, or empty if none
#   exists. AT MOST TWO `gh api` calls, regardless of how many comment
#   pages the PR has (#1615).
#
#   Revocation (#1706): a second marker type,
#   `<!-- review-verdict:revoked:<sha> -->`, cancels an earlier
#   `review-passed` marker. Both types are matched in ONE pass and the single
#   LAST one wins BY COMMENT ORDER — not by sha. If that last marker is a
#   `revoked` one, this function prints NOTHING and returns 0: for reading
#   purposes a revocation is indistinguishable from "no marker was ever
#   posted" (a CONFIRMED absence, rc 2 out of `_stale` below — never rc 1/3).
#   The sha inside `revoked:<sha>` is audit metadata only; it is never
#   compared against anything, so a revocation naming any sha still cancels
#   the `review-passed` marker before it. Ordering, not sha, decides.
#   Revocation is not permanent: a later `review-passed` marker (a genuine
#   re-review) is then the last one and wins again. Existing markers are
#   never edited or deleted — the audit trail is append-only. Full spec:
#   `devx-pr-review-all/references/review-verdict-label.md` → "Revoking a
#   stale review-passed by hand".
#
#   Why not `--paginate` (#1615): the first cut walked EVERY comment page to
#   find the last marker, so a long-running PR cost one HTTP round trip per
#   100 comments on EVERY merge-train tick — flagged independently by three
#   reviewers on PR #1608. The endpoint is oldest-first with no "last N"
#   parameter, so instead of walking, this asks page 1 with `-i` (response
#   HEADERS on stdout ahead of the body) and reads the `Link:` header:
#     * no `Link` header at all — there is only one page, and call 1 already
#       returned its whole body. Nothing more to fetch: the common
#       small-PR case still costs exactly ONE call, same as before.
#     * `Link: ...; rel="last"` carrying `page=N` (N>1) — jump STRAIGHT to
#       page N (call 2 of 2). Pages 2..N-1 are never fetched. The marker is
#       posted by `devx_pr_review_all_apply_label` at the moment the label
#       goes on, so it is by construction among the most recent comments.
#
#   `-X GET` is REQUIRED on both calls, not cosmetic: `gh api` switches to
#   POST as soon as any `-f` parameter is present, so `-f per_page=...`
#   without it POSTs to the create-comment endpoint and dies with HTTP 422.
#
#   Return code distinguishes "confirmed absent" from "could not check" —
#   load-bearing for the caller (PR #1608 review, agy round-2 BLOCKER: see
#   `_gh_pr_merge_train_review_passed_stale` below for why the distinction
#   matters):
#     0 — the lookup itself succeeded. stdout may still be empty (no
#         matching marker exists) — that is a CONFIRMED absence.
#     1 — the lookup itself failed (network, auth, rate limit, `gh` too
#         old), or `<expected-login>` was missing/invalid so no lookup was
#         even attempted. stdout is always empty here too, but this is an
#         UNDETERMINED answer, not a confirmed absence — the caller must
#         not treat rc 0 and rc 1 the same way.
#
#   `<expected-login>` is REQUIRED and load-bearing (PR #1608 review, agy
#   BLOCKER + codex BLOCKER, independently): without an author check, this
#   function originally trusted a marker string from ANY commenter, not just
#   `devx_pr_review_all_apply_label`. Any PR participant able to leave a
#   comment — a much lower bar than the label-write access needed to attach
#   `review-passed` itself — could then post
#   `<!-- review-verdict:review-passed:<current-head> -->` by hand and defeat
#   the whole freshness check this file exists to add. Filtering to the one
#   login that actually runs this automation pipeline (the same account both
#   `devx:pr-review-all` and `gh:pr-merge-train` authenticate as) closes that:
#   forging a trusted marker now requires the same access as forging the
#   label directly, which is the pre-existing, already-accepted trust
#   boundary (label-write access already gates who can attach `review-passed`
#   at all). A missing/invalid login is treated as "lookup not attempted"
#   (rc 1) rather than falling back to trusting everyone.
#
#   The login validator accepts a plain GitHub username (`[A-Za-z0-9-]+`) or
#   that same shape with a literal `[bot]` suffix (`github-actions[bot]`,
#   `dependabot[bot]`) — the form GitHub gives App-associated identities in
#   `.user.login` (PR #1608 review, agy round-2 BLOCKER: the earlier
#   character class rejected every bracket, so a pipeline authenticating as
#   any bot account could never validate a single marker and this check
#   would fail closed on every PR, permanently). Both accepted shapes are
#   still restricted to letters, digits and hyphens underneath — a login
#   containing `"`, a backslash, or anything else that could break out of the
#   double-quoted jq filter string below is rejected either way, same as
#   before.
_gh_pr_merge_train_review_passed_marker_sha() {
    local _pr="$1" _repo="$2" _host="${3-}" _login="${4-}" \
        _jq _raw _rc _login_base _headers _bodies _link _last

    _login_base="$_login"
    case "$_login_base" in
        *'[bot]') _login_base="${_login_base%\[bot\]}" ;;
    esac
    case "$_login_base" in
        '' | *[!A-Za-z0-9-]*) return 1 ;;
    esac

    _jq=".[] | select(.user.login == \"$_login\") | .body"

    # Call 1 of at most 2. per_page=100 is the API max, so this is also the
    # cheapest way to learn the page count.
    _raw=$( (
        if [ -n "$_host" ]; then
            # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
            export GH_HOST="$_host"
        fi
        gh api -i -X GET -f per_page=100 -f page=1 \
            "repos/$_repo/issues/$_pr/comments" --jq "$_jq"
    ) 2>/dev/null )
    _rc=$?
    [ "$_rc" -eq 0 ] || return 1

    # `-i` puts the status line + headers ahead of the body, separated by one
    # blank line. gh emits the status line LF-terminated but the headers
    # CRLF-terminated, so the separator is a lone CR — strip it before
    # comparing. Split at the FIRST blank line only: a comment body may well
    # contain blank lines of its own.
    _headers=$(printf '%s\n' "$_raw" |
        awk '{ sub(/\r$/, ""); if ($0 == "") exit; print }')

    # Anchor on the header NAME: `Access-Control-Expose-Headers` lists the
    # word "Link" in its value and must not be mistaken for the real thing.
    _link=$(printf '%s\n' "$_headers" | grep -iE '^Link:' | head -n 1)
    # One Link entry per line, then keep only rel="last" and read its page.
    # `[?&]page=` deliberately does not match `per_page=` (preceded by `_`).
    _last=$(printf '%s\n' "$_link" |
        tr ',' '\n' |
        grep 'rel="last"' |
        grep -oE '[?&]page=[0-9]+' |
        head -n 1 |
        grep -oE '[0-9]+')

    if [ -n "$_last" ] && [ "$_last" -gt 1 ]; then
        # Call 2 of 2 — the LAST page directly. Pages 2..N-1 are skipped on
        # purpose (#1615); no `-i` needed, the body is all we want now.
        _bodies=$( (
            if [ -n "$_host" ]; then
                # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
                export GH_HOST="$_host"
            fi
            gh api -X GET -f per_page=100 -f "page=$_last" \
                "repos/$_repo/issues/$_pr/comments" --jq "$_jq"
        ) 2>/dev/null )
        _rc=$?
        # Same contract as a call-1 failure: UNDETERMINED, not "absent".
        [ "$_rc" -eq 0 ] || return 1
    else
        # Single-page PR: page 1's response (already fetched above) is the
        # whole PR, so reuse its body instead of a second call. Same
        # blank-line split as `_headers` above, done with the one-line `sed`
        # idiom this codebase already uses for it — see
        # claude/skills/gh-pr-merge-train/references/approval-gate.md.
        _bodies=$(printf '%s\n' "$_raw" | sed '1,/^\r\{0,1\}$/d')
    fi

    # BOTH marker types in one pass, so `tail -n 1` picks the chronologically
    # last one whichever type it is — "latest marker wins", not "latest
    # review-passed wins" (#1706). The trailing `sed` then drops a revoked
    # last marker outright (prints NOTHING, zero bytes — same as no marker at
    # all, per the documented contract above) and otherwise extracts the sha.
    printf '%s\n' "$_bodies" |
        grep -oE '<!-- review-verdict:(review-passed|revoked):[0-9a-f]+ -->' |
        tail -n 1 |
        sed -E '/:revoked:/d; s/^<!-- review-verdict:review-passed:([0-9a-f]+) -->$/\1/'

    return 0
}

# `_gh_pr_merge_train_review_passed_stale <pr> <repo> <host> <head-oid> <expected-login>`
#   rc 0 — FRESH: the last marker posted by `<expected-login>` matches
#          `<head-oid>` exactly. Proceed normally.
#   rc 1 — STALE, MISMATCH: a marker from `<expected-login>` exists, but its
#          sha does not match `<head-oid>` — positive proof the head moved
#          past the reviewed commit (the original #1601 scenario: a
#          force-push over a reviewed head). Safe for the caller to also drop
#          the label (self-heal): the mismatch is direct evidence, not a
#          guess.
#   rc 2 — STALE, ABSENT: the lookup succeeded but `<expected-login>` never
#          posted a marker at all. Route this PR as unverified THIS TICK —
#          but do NOT self-heal (drop the label). Absence alone does not
#          prove the label is wrong for this head: a PR labeled
#          `review-passed` before this freshness check existed (or by any
#          future skill that legitimately doesn't post the marker) looks
#          identical to a forged one, and destructively stripping every such
#          PR's label the moment this feature ships was flagged
#          independently by agy across two review rounds (PR #1608) as an
#          unacceptable operational cliff — a re-review clears it exactly as
#          cheaply either way, so there is nothing to gain by deleting rather
#          than merely not trusting it.
#
#          Since #1706 this is also the answer when the LAST marker from
#          `<expected-login>` is a revocation
#          (`<!-- review-verdict:revoked:<sha> -->`) rather than a
#          `review-passed` one: a revocation is deliberately
#          indistinguishable from "no marker at all" here, because both mean
#          the same thing to this check — there is no standing verdict for
#          any head. It is a confirmed absence, so it is rc 2, never rc 1
#          (nothing was proven stale) and never rc 3 (the lookup completed
#          fine). Which marker is last is decided by COMMENT ORDER alone —
#          the sha a revocation names is audit metadata and is never compared
#          against `<head-oid>` or against the earlier marker's sha. That
#          means the caller still does not self-heal: a hand-revoked
#          `review-passed` label is left attached and merely not trusted,
#          exactly like the pre-existing absent case.
#   rc 3 — STALE, UNDETERMINED: the underlying lookup itself failed (network,
#          auth, rate limit) or `<expected-login>` was invalid, so nothing
#          was confirmed either way. Route as unverified this tick (fail-
#          closed, same direction #1519's approval gate takes for "policy
#          unreadable") — never self-heal on a check that never completed
#          (PR #1608 review, agy round-2 BLOCKER: a transient blip must not
#          destroy an otherwise-valid label).
#
#   Only rc 1 carries enough evidence to justify deleting the label. rc 2 and
#   rc 3 both route the PR as unverified without touching it — the
#   difference between them is diagnostic only (did the check run at all),
#   not behavioral.
#
#   An empty OR literal-`null` `<head-oid>` is a CALLER error (the caller
#   failed to resolve `headRefOid` upstream — `jq -r '.headRefOid'` on a
#   missing/null field emits the four-character string `null`, not an empty
#   string), not evidence about the marker — it fails closed to rc 3
#   (UNDETERMINED) immediately, before even attempting the lookup. Without
#   this guard, a marker that legitimately exists would otherwise compare
#   against `null` (or empty), never match, and fall through to rc 1
#   (MISMATCH) — reporting positive proof of staleness the caller never
#   actually established, and self-healing (deleting the label) on what was
#   really its own unresolved state (agy, PR #1608 rounds 4 and 5).
_gh_pr_merge_train_review_passed_stale() {
    local _pr="$1" _repo="$2" _host="$3" _head_oid="$4" _login="$5" _marker_sha _lookup_rc

    case "$_head_oid" in
        '' | null) return 3 ;;
    esac

    _marker_sha=$(_gh_pr_merge_train_review_passed_marker_sha "$_pr" "$_repo" "$_host" "$_login")
    _lookup_rc=$?
    if [ "$_lookup_rc" -ne 0 ]; then
        return 3
    fi
    [ -n "$_marker_sha" ] && [ "$_marker_sha" = "$_head_oid" ] && return 0
    [ -n "$_marker_sha" ] && return 1
    return 2
}

# The train's own pushes — a quiet-period exemption (issue #1708).
#
# The D-6 quiet period drops any PR whose `updatedAt` is too recent, because a
# deferred `gh:pr-reply` pass (scheduled 4 minutes after the PR opens, by
# `gh:issue-flow` Step 2.4's `--defer-reply 4`) may still be inbound. That is
# the right default for work arriving from OUTSIDE the train. It is exactly
# wrong for work the train did ITSELF: a Step 4 `BEHIND`/`DIRTY` remediation
# rebases and pushes the PR, which bumps `updatedAt` to "just now", so the very
# next Step 2 queue build drops the PR the train just finished fixing — and the
# next tick repeats the whole remediation, forever. Nothing is pending on such
# a PR; there is nothing left for the quiet period to wait for.
#
# The fix is deliberately an ADDITIVE SECOND PASS, not a new clause in
# `_gh_pr_merge_train_filter_targets`. That filter is the one implementation
# this skill and `shell-common/tools/custom/pr_merge_train_cron.sh` both run
# (#1524), and the whole value of it is that the two callers cannot disagree —
# the dispatcher's cheap "is there anything worth waking a session for"
# pre-check has no business granting this exemption, since only the
# authoritative skill run records the pushes in the first place. So the filter
# stays untouched and byte-for-byte the same for both callers, and the skill
# alone re-admits, over the SAME raw list, the PRs it can prove it pushed.
#
# "Can prove it pushed" is a tiny piece of state: one file per PR under a
# caller-supplied directory (`SKILL.md` Step 2 binds it under the git common
# dir), holding the head sha the train pushed. The directory is a PARAMETER,
# never resolved internally via `git`, for the same reason `--now` is required
# above: these functions stay pure and the bats suite tests them without
# mocking anything external.
#
# `_gh_pr_merge_train_record_pushed_sha <state-dir> <pr> <sha>`
#   Write `<sha>` as "the head this train pushed for `<pr>`", creating
#   `<state-dir>` if needed. Called from `references/train-loop.md`'s
#   remediation path, right after the mandatory post-remediation re-query has
#   confirmed the new head. Best-effort: rc 1 on a usage error or an
#   unwritable state dir (one stderr line, so a broken dir is not invisible
#   forever), and the caller ignores it — a failure to record only costs the
#   exemption, never the merge.
#
# `_gh_pr_merge_train_pushed_sha_matches <state-dir> <pr> <sha>`
#   Predicate, no stdout, same shape as the label predicates above. rc 0 iff a
#   record exists for `<pr>` and equals `<sha>` exactly. rc 1 for: no record,
#   a different sha (the head moved past what the train pushed — someone
#   else's commit is on it now and the quiet period must stand), or a `<sha>`
#   that is empty or the literal string `null` (`jq -r '.headRefOid'` on a
#   missing field emits `null`, which is the caller's unresolved state, never
#   evidence — the same fail-closed reading `_gh_pr_merge_train_review_passed_stale`
#   applies to its own `<head-oid>`).
#
# `_gh_pr_merge_train_forget_pushed_sha <state-dir> <pr>`
#   Drop the record. Called after a successful merge so the state dir does not
#   grow one file per merged PR forever. Always rc 0 unless `<pr>` is invalid:
#   removing a record that was never written is not an error.
#
#   All three validate `<pr>` against `^[0-9]+$` and refuse anything else,
#   because `<pr>` becomes a path component — same fail-closed posture as the
#   login validator in `_gh_pr_merge_train_review_passed_marker_sha`.
#
# `_gh_pr_merge_train_readmit_own_pushes <state-dir> <filtered-json>`
#   The pass itself. Reads the RAW `gh pr list --json ...` array on stdin —
#   the same array `_gh_pr_merge_train_filter_targets` was given, except it
#   MUST also carry `headRefOid` (this function needs it; the shared filter
#   never reads it) — and takes that filter's own output as `<filtered-json>`.
#   Echoes `<filtered-json>` with the exempt elements APPENDED, unmodified and
#   whole (same "never project fields away" rule the filter follows). Order is
#   irrelevant: Step 2's D-2 sort runs over the union afterwards.
#
#   An element is re-admitted only when ALL of these hold:
#     1. it is not already in `<filtered-json>` — never duplicate an element
#        that survived the ordinary filter on its own;
#     2. `.isDraft` is not true — DRAFT is a skip row in the D-1 table, not a
#        quiet-period drop, so there is nothing here to release;
#     3. it does not carry `reply-pending` — the label ALWAYS wins over this
#        exemption (#1708 AC2). Simple presence, no staleness window: label
#        expiry is `_gh_pr_merge_train_filter_targets`'s own business (rule 2
#        above), and re-deriving it here would be a second definition of it.
#        The check reuses `_gh_pr_merge_train_has_reply_pending_label` rather
#        than re-writing its jq, for the same reason F-3 does;
#     4. `.updatedAt` is present and parseable. Without this check a PR the
#        shared filter dropped for its OWN fail-closed reason (rule 3 above:
#        missing/unparseable `updatedAt`, never the ordinary quiet-period
#        timing) could still be re-admitted on a sha match, silently
#        overriding a data-integrity refusal this pass has no business
#        overriding (codex, PR #1724 review, BLOCKER) — this pass may only
#        undo the ordinary timing drop, never the fail-closed one;
#     5. `.headRefOid` matches this train's recorded push for that PR.
#   In other words: the ONLY thing this pass can undo is a drop caused SOLELY
#   by the quiet period, on a head the train itself put there.
#
#   Return codes mirror the shared filter's: 0 with the array on stdout, 1 on
#   a usage error or unparsable input (nothing on stdout).
#
#   A shell loop plus a per-element `jq`, not one jq expression, because
#   conditions 3 and 4 are shell functions — jq cannot call them, and
#   re-deriving them inline is exactly the drift this file exists to prevent.

_gh_pr_merge_train_record_pushed_sha() {
    local _dir="${1-}" _pr="${2-}" _sha="${3-}"

    case "$_pr" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] refusing to record a pushed sha for a non-numeric PR: %s\n' \
                "$_pr" >&2
            return 1
            ;;
    esac
    if [ -z "$_dir" ]; then
        printf '[gh-pr-merge-train] usage: _gh_pr_merge_train_record_pushed_sha <state-dir> <pr> <sha>\n' >&2
        return 1
    fi

    if ! mkdir -p "$_dir" 2>/dev/null || ! printf '%s\n' "$_sha" >"$_dir/$_pr" 2>/dev/null; then
        printf '[gh-pr-merge-train] could not record the pushed sha for PR %s under %s — the D-6 exemption (#1708) will not apply.\n' \
            "$_pr" "$_dir" >&2
        return 1
    fi
}

_gh_pr_merge_train_pushed_sha_matches() {
    local _dir="${1-}" _pr="${2-}" _sha="${3-}" _recorded

    case "$_pr" in
        '' | *[!0-9]*) return 1 ;;
    esac
    case "$_sha" in
        '' | null) return 1 ;;
    esac
    [ -n "$_dir" ] || return 1
    [ -f "$_dir/$_pr" ] || return 1

    # `$(...)` strips the trailing newline the recorder writes.
    _recorded=$(cat "$_dir/$_pr" 2>/dev/null) || return 1
    [ "$_recorded" = "$_sha" ]
}

_gh_pr_merge_train_forget_pushed_sha() {
    local _dir="${1-}" _pr="${2-}"

    case "$_pr" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ -n "$_dir" ] || return 1

    rm -f "$_dir/$_pr" 2>/dev/null
    return 0
}

_gh_pr_merge_train_readmit_own_pushes() {
    local _dir="${1-}" _filtered="${2-}" _raw _nums _out

    if [ -z "$_dir" ] || [ -z "$_filtered" ]; then
        printf '[gh-pr-merge-train] usage: _gh_pr_merge_train_readmit_own_pushes <state-dir> <filtered-json>\n' >&2
        return 1
    fi

    _raw=$(cat)
    [ -n "$_raw" ] || return 1
    printf '%s' "$_raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1

    # The four conditions, per element. The loop runs in a subshell (it is the
    # tail of a pipeline), so it carries its verdict out as PR numbers on
    # stdout rather than by mutating a variable.
    _nums=$(printf '%s' "$_raw" | jq -c '.[]?' | while IFS= read -r _elem; do
        [ -n "$_elem" ] || continue
        _num=$(printf '%s' "$_elem" | jq -r '.number // empty' 2>/dev/null)
        case "$_num" in
            '' | *[!0-9]*)
                printf '[gh-pr-merge-train] readmit: skipping a raw element with no numeric .number\n' >&2
                continue
                ;;
        esac
        # 1. already a target on its own merit — nothing was dropped.
        printf '%s' "$_filtered" | jq -e --argjson n "$_num" \
            'any(.[]?; .number == $n)' >/dev/null 2>&1 && continue
        # 2. drafts are a D-1 skip row, not a quiet-period drop.
        printf '%s' "$_elem" | jq -e '(.isDraft // false)' >/dev/null 2>&1 && continue
        # 3. the label always wins (#1708 AC2).
        printf '%s' "$_elem" | _gh_pr_merge_train_has_reply_pending_label && continue
        # 4. only undo the ORDINARY quiet-period drop, never the shared
        # filter's own fail-closed one (missing/unparseable updatedAt).
        printf '%s' "$_elem" | jq -e '((.updatedAt // "") | fromdateiso8601?) != null' \
            >/dev/null 2>&1 || continue
        # 5. is this head the one the train itself pushed?
        _gh_pr_merge_train_pushed_sha_matches "$_dir" "$_num" \
            "$(printf '%s' "$_elem" | jq -r '.headRefOid // empty' 2>/dev/null)" || continue
        printf '%s\n' "$_num"
    done)

    # `--argjson filtered` also validates it: an unparsable argument fails the
    # whole call rather than answering with a half-built queue.
    _out=$(printf '%s' "$_raw" | jq -c --argjson filtered "$_filtered" --arg nums "$_nums" '
        ($nums | split("\n") | map(select(length > 0) | tonumber)) as $keep
        | $filtered + [ .[]? | select(.number as $n | $keep | index($n)) ]
    ' 2>/dev/null) || return 1
    [ -n "$_out" ] || return 1

    printf '%s\n' "$_out"
}

# Self-check (issue #724): catch silent breakage where this file sources
# cleanly but its public functions never get defined — an interactive-guard
# regression, a syntax error mid-file, a future rename. Both call sites treat a
# missing function as a hard failure (the dispatcher ends the tick), but the
# warning is what names the cause. rc stays 0 — sourcing must not fail.
for _gh_pmt_selfcheck_fn in \
    _gh_pr_merge_train_quiet_minutes \
    _gh_pr_merge_train_reply_pending_stale_minutes \
    _gh_pr_merge_train_filter_targets \
    _gh_pr_merge_train_has_reply_pending_label \
    _gh_pr_merge_train_has_review_blocked_label \
    _gh_pr_merge_train_has_review_passed_label \
    _gh_pr_merge_train_needs_finalize \
    _gh_pr_merge_train_finalize_targets \
    _gh_pr_merge_train_behind_may_merge_directly \
    _gh_pr_merge_train_base_strict_confirmed \
    _gh_pr_merge_train_base_ci_red \
    _gh_pr_merge_train_review_passed_marker_sha \
    _gh_pr_merge_train_review_passed_stale \
    _gh_pr_merge_train_record_pushed_sha \
    _gh_pr_merge_train_pushed_sha_matches \
    _gh_pr_merge_train_forget_pushed_sha \
    _gh_pr_merge_train_readmit_own_pushes; do
    command -v "$_gh_pmt_selfcheck_fn" >/dev/null 2>&1 && continue
    printf '[gh_pr_merge_train] BUG: %s undefined after source — the merge-train target filter will not run. See dotfiles #724 / #1524.\n' \
        "$_gh_pmt_selfcheck_fn" >&2
done
unset _gh_pmt_selfcheck_fn
:
