#!/bin/sh
# VENDORED — do not edit here.
# SSOT: dEitY719/dotfiles shell-common/functions/gh_pr_reply_targeted_review.sh
# Synced 2026-09-05T10:16Z by dEitY719/harness-skills scripts/sync-shell-common-vendor.sh — re-run that script to update.
# shellcheck shell=bash
# shell-common/functions/gh_pr_reply_targeted_review.sh
# gh:pr-reply's severity gate: the per-item origin tokens (#1616) and the
# `review-passed` decision they now feed (#1636).
#
# Before #1616 the rule was one global counter pair —
# `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0`. A legitimately DECLINEd
# suggestion from a NON-blocking reviewer then pinned `review-blocked` on a
# PR whose every actual BLOCKER had been fixed (PR #1609: codex raised 2
# BLOCKERs, both fixed; agy raised 3 FOLLOW-UPs, all validly declined), and
# the only way out was a full 5-lane devx:pr-review-all re-run.
#
# #1616 replaced that with a per-reviewer / per-severity question and a cheap
# targeted `gh:pr-review --paths` re-call that had to come back non-blocking
# before `review-passed` could be applied. #1636 removes that re-call: it was
# the remaining cost and failure point, and a jammed `gh:pr-merge-train` was
# the recurring symptom.
#
# NF-2, as redefined by #1636: "never self-certify" is DELIBERATELY RELAXED on
# this one path. gh:pr-reply now applies `review-passed` from its own
# judgment — every BLOCKER-severity item ACCEPT/ACCEPT-PARTIAL, or none
# raised — with no external AI CLI in the loop. The verification link that
# remains is the division of labour: the BLOCKERs were FOUND by an external
# reviewer (devx:pr-review-all, which still fans out on every PR and still
# owns `review-blocked`); gh:pr-reply only confirms they were resolved. The
# fail-closed direction is untouched: one unresolved BLOCKER means no
# `review-passed`, ever. Full rationale and the user's explicit trade-off:
# claude/skills/gh-pr-reply/references/constraints.md and
# claude/skills/devx-pr-review-all/references/review-verdict-label.md.
#
# PR #1637's review closed two holes in that relaxation, both of which let a
# pass certify a PR the division of labour had never actually covered:
#   - The gate now reads the PR's FULL origin history, not just this pass.
#     Step 2's "already replied" dedup hides an earlier pass's DECLINEd
#     BLOCKER from every later pass, so a later pass saw an empty BLOCKER set
#     and granted `review-passed` while the blocker still stood (codex
#     BLOCKER). The history lives in the `pr-reply-origins` ledger comment
#     this file posts on every pass.
#   - The gate now refuses to certify a PR NO external reviewer ever looked
#     at. With no `ai-review` marker on the PR, the "external AI FINDS,
#     gh:pr-reply CONFIRMS" link has no finder half at all, so there is
#     nothing for this skill's judgment to confirm (agy BLOCKER).
#
# SSOT for the procedure: claude/skills/gh-pr-reply/references/review-passed-gate.md
#
# Deliberately NOT wrapped in an interactive guard: like
# devx_pr_review_all.sh, this is a pure function-defining library whose
# callers are the skill's non-interactive `bash --noprofile --norc` tool
# calls. A guard here would define nothing and the gate would never run.

if [ -n "${ZSH_VERSION-}" ]; then
    _drg_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    _drg_self="${BASH_SOURCE[0]-}"
else
    _drg_self=""
fi
_drg_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/dotfiles_root.sh"
if [ -r "$_drg_helper" ]; then
    . "$_drg_helper" || true
fi
if command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    _dotfiles_root_guard_self "$_drg_self" "gh_pr_reply_targeted_review"
else
    printf '[gh_pr_reply_targeted_review] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

# ── F-1: origin tokens ──────────────────────────────────────────────────
#
# One Step 3 classification becomes one `<reviewer>:<severity>:<verdict>`
# line. The reviewer set stays pinned to gh:pr-review's `--ai` enum even now
# that nothing re-invokes those CLIs (#1636): a closed enum is what keeps a
# typo'd reviewer name from silently becoming its own tally row, and it keeps
# the token comparable with the `ai-review` blocks on the PR.

# The BOT reviewers, tracked as a set of their own (PR #1637 review, codex
# BLOCKER). The skill's Step 3 rubric classifies `gemini-code-assist`,
# `sourcery-ai` and `copilot` comments exactly like an AI-CLI comment, so a
# bot-authored BLOCKER has to be able to enter ORIGINS — before this, it could
# not, and the gate never saw it.
#
# Deliberately NOT folded into the `--ai` enum above. These logins are only
# ever comment AUTHORS: nothing re-invokes them, because `gh:pr-review --ai`
# has no such value and never will (they are GitHub Apps that review on their
# own schedule). Conflating the two sets would make the `--ai` enum accept
# names its CLI dispatcher cannot run, i.e. a typo'd `--ai` value would look
# valid to every caller that validates against one list.
#
# Bot logins contain `-` but never `:`, so a bot reviewer field leaves the
# `reviewer:severity:verdict` delimiter and `_gh_pr_reply_origin_tally`'s awk
# `-F:` grouping working unchanged.
_gh_pr_reply_reviewer_is_bot() {
    case "$(printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]')" in
    gemini-code-assist | sourcery-ai | copilot) return 0 ;;
    esac
    return 1
}

_gh_pr_reply_origin_line() {
    local _reviewer _severity _verdict
    _reviewer=$(printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]')
    # Reviewers tag findings as `[BLOCKER]` / `[FOLLOW-UP]`; the brackets are
    # rendering, not data.
    _severity=$(printf '%s' "${2-}" | tr -d '[]' | tr '[:lower:]' '[:upper:]')
    _verdict=$(printf '%s' "${3-}" | tr '[:lower:]' '[:upper:]')

    # Either set is accepted; anything in neither is still exit 2, and the
    # message names both so a caller can tell which list it missed.
    case "$_reviewer" in
    codex | agy | claude | opencode | hermes) ;;
    *)
        if ! _gh_pr_reply_reviewer_is_bot "$_reviewer"; then
            printf '[gh-pr-reply] unknown reviewer: %s (allowed AI CLIs: codex, agy, claude, opencode, hermes; allowed bots: gemini-code-assist, sourcery-ai, copilot)\n' \
                "${1-}" >&2
            return 2
        fi
        ;;
    esac
    case "$_severity" in
    "")
        printf '[gh-pr-reply] severity must be a non-empty tag (e.g. BLOCKER, FOLLOW-UP, 블로커): %s\n' \
            "${2-}" >&2
        return 2
        ;;
    *:*)
        printf '[gh-pr-reply] severity must not contain ":" (breaks the reviewer:severity:verdict delimiter): %s\n' \
            "${2-}" >&2
        return 2
        ;;
    esac
    case "$_verdict" in
    ACCEPT | ACCEPT-PARTIAL | DECLINE | QUESTION) ;;
    *)
        printf '[gh-pr-reply] unknown verdict: %s (allowed: ACCEPT, ACCEPT-PARTIAL, DECLINE, QUESTION)\n' \
            "${3-}" >&2
        return 2
        ;;
    esac

    printf '%s:%s:%s\n' "$_reviewer" "$_severity" "$_verdict"
}

# Blocking severity = the tag that made `review-blocked` happen. Everything
# else (FOLLOW-UP, Suggestion, nit, PRAISE) is advisory and its DECLINE must
# never hold the label down — the whole point of #1616.
_gh_pr_reply_severity_is_blocking() {
    case "$(printf '%s' "${1-}" | tr -d '[]' | tr '[:lower:]' '[:upper:]')" in
    BLOCKER | BLOCKING | 블로커) return 0 ;;
    esac
    return 1
}

# Origin lines on stdin -> one summary line per reviewer, sorted by name.
# This is what Step 7's per-reviewer breakdown reports; the flat
# ACCEPTED_COUNT / DECLINED_COUNT pair it replaces could not distinguish
# "a blocker is unresolved" from "a suggestion was declined".
_gh_pr_reply_origin_tally() {
    # `sort` on the whole `reviewer:severity:verdict` line already groups
    # every reviewer's lines into one contiguous block (no two reviewer
    # names in the enum share a prefix), so a flush-on-change over sorted
    # input reports them in order without a second names[]/bubble-sort pass.
    sort | awk -F: '
        NF < 3 { next }
        function flush() {
            if (cur != "")
                printf "reviewer=%s blocking_total=%d blocking_accepted=%d nonblocking_total=%d nonblocking_declined=%d\n", \
                    cur, bt + 0, ba + 0, nt + 0, nd + 0
        }
        {
            if ($1 != cur) { flush(); cur = $1; bt = ba = nt = nd = 0 }
            if ($2 == "BLOCKER" || $2 == "BLOCKING") {
                bt++
                if ($3 == "ACCEPT" || $3 == "ACCEPT-PARTIAL") ba++
            } else {
                nt++
                if ($3 == "DECLINE") nd++
            }
        }
        END { flush() }
    '
}

# ── The origin ledger: cross-pass memory (PR #1637 review) ──────────────
#
# The gate below only ever saw the CURRENT pass's ORIGINS, and that is not
# enough to answer its own question. Step 2's "already replied" dedup filters
# a thread out of every LATER pass, so an earlier pass that DECLINEd a BLOCKER
# leaves no trace in the next pass's stream — which then reads `pass=no-blocker`
# and certifies a PR whose blocker was never fixed (codex BLOCKER).
#
# The fix follows this repo's existing convention that a posted comment IS
# durable machine-readable state: `<!-- ai-review:<ai>:<sha> -->` in
# gh_pr_review.sh, and the bare `<!-- review-verdict:review-passed:<sha> -->`
# marker comment `devx_pr_review_all_write_label` posts (the precedent for a
# comment body that is nothing but an HTML comment). Every pass writes its
# merged verdicts back as:
#
#   <!-- pr-reply-origins:<head-sha> -->
#   codex:BLOCKER:DECLINE
#   agy:FOLLOW-UP:ACCEPT
#   <!-- /pr-reply-origins:<head-sha> -->

# Origin lines on stdin -> the wrapped ledger block on stdout.
#
#   <origin lines> | _gh_pr_reply_origins_block [head-sha]
#
# Empty input prints NOTHING and returns 0 — there is nothing to remember, and
# an empty block on the PR would be noise a later pass has to skip anyway. A
# line that is not `<reviewer>:<severity>:<verdict>` is rc 2: the ledger is
# read back by machine, so garbage must never be written in the first place.
# <head-sha> may be empty, in which case the unsuffixed marker form is emitted
# — the same fallback `_gh_pr_review_build_comment_body`'s 8th argument makes.
_gh_pr_reply_origins_block() {
    local _sha="${1-}" _marker _origins _line _out=""

    _origins=$(cat)
    _marker="pr-reply-origins"
    [ -n "$_sha" ] && _marker="pr-reply-origins:$_sha"

    while IFS= read -r _line || [ -n "$_line" ]; do
        [ -n "$_line" ] || continue
        case "$_line" in
        *:*:*) ;;
        *)
            printf '[gh-pr-reply] malformed origin line (want <reviewer>:<severity>:<verdict>): %s\n' \
                "$_line" >&2
            return 2
            ;;
        esac
        _out="${_out}${_line}
"
    done <<EOF
$_origins
EOF

    [ -n "$_out" ] || return 0
    printf '<!-- %s -->\n' "$_marker"
    printf '%s' "$_out"
    printf '<!-- /%s -->\n' "$_marker"
    return 0
}

# Author filter for the two history readers below (#1639).
#
#   <raw comments JSON on stdin> | _gh_pr_reply_login_bodies <login>
#     stdout: the `.body` of every comment whose `.user.login` is exactly
#     <login>. Empty (rc 0) when nothing matches, when <login> fails
#     validation, or when stdin is not the expected JSON.
#
# A thin delegator to the canonical implementation,
# `_devx_pr_review_all_login_bodies` (devx_pr_review_all.sh) — same
# validation (plain username, or that shape with one literal trailing
# `[bot]`, mirroring `_gh_pr_merge_train_review_passed_marker_sha`), same
# `--arg`-guarded `jq` filter, same fail-closed-on-empty-or-invalid-login
# contract. Full rationale lives on that function's header; do not
# re-duplicate it here — this file used to carry its own byte-identical copy
# and the two had already drifted in indentation (#1639 cleanup). On-demand
# sources devx_pr_review_all.sh the same way `_gh_pr_reply_apply_review_passed`
# already does for `devx_pr_review_all_write_label` below, so this still works
# when `gh_pr_reply_targeted_review.sh` is sourced standalone (bats). A source
# failure fails closed — empty output, never "match every author" — exactly
# like an invalid login would.
_gh_pr_reply_login_bodies() {
    if ! command -v _devx_pr_review_all_login_bodies >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh" 2>/dev/null || :
    fi
    if ! command -v _devx_pr_review_all_login_bodies >/dev/null 2>&1; then
        cat >/dev/null
        return 0
    fi
    _devx_pr_review_all_login_bodies "${1-}"
}

# Raw PR comments JSON on stdin (the array
# `gh api repos/<repo>/issues/<pr>/comments` answers with, each element
# carrying `.user.login` and `.body`) -> the origin lines of the LAST COMPLETE
# ledger block POSTED BY <expected-login>, one per line.
#
#   _gh_pr_reply_history_origins <expected-login>
#
# <expected-login> is REQUIRED and load-bearing (#1639). This ledger is
# `gh:pr-reply`'s cross-pass memory of which BLOCKERs were ACCEPTed and which
# were DECLINEd, and it gates whether the pass self-applies `review-passed`.
# Until this parameter existed the function was handed pre-extracted body
# text with the author already discarded, so a `<!-- pr-reply-origins -->`
# block from ANY commenter counted — and commenting is a far lower bar than
# the label-write access `review-passed` itself needs. An outsider could
# forge a ledger claiming every BLOCKER was ACCEPTed and unlock the gate, or
# forge a DECLINE and pin the label off forever. Only this pipeline's own
# login writes the ledger (`_gh_pr_reply_origins_block` -> the pass's own
# comment), so scoping the read to it costs nothing and restores the trust
# boundary. A missing/invalid login yields NO origins — which downstream
# reads as "no history", the fail-closed direction — never a fallback to
# trusting every author. Same validator and rationale as
# `_gh_pr_merge_train_review_passed_marker_sha` (PR #1608); see
# claude/skills/gh-pr-merge-train/references/review-verdict-gate.md
# § "Marker authorship".
#
# The contract deliberately mirrors `devx_pr_review_all_lane_block`: the last
# complete block wins (a later pass supersedes an earlier one) and an
# unterminated block is never harvested (a truncated comment must not hand
# back half a history). Both marker forms match — sha-suffixed and unsuffixed
# — because freshness is NOT what this reader wants: a BLOCKER declined
# against an older head is still declined today, and gating the history on the
# current sha would re-open exactly the hole the ledger closes.
#
# Lines inside the block that do not look like `<reviewer>:<severity>:<verdict>`
# are dropped silently rather than failing: the ledger lives in an ordinary PR
# comment, and a human replying inside it (or GitHub reflowing it) must not be
# able to turn the next pass's gate into a hard error.
_gh_pr_reply_history_origins() {
    local _line
    _gh_pr_reply_login_bodies "${1-}" |
    awk '
        # "\001" is the "marker absent on this line" sentinel: unlike
        # lane_block, an EMPTY tag is a legitimate match here (the unsuffixed
        # marker form), so absence cannot be signalled by returning "".
        function tagof(line, pre, plen,   p, rest, e) {
            p = index(line, pre)
            if (p == 0) return "\001"
            rest = substr(line, p + plen)
            e = index(rest, " -->")
            if (e == 0) return "\001"
            return substr(rest, 1, e - 1)
        }
        function wanted(t) {
            if (t == "\001") return 0
            return (t == "" || substr(t, 1, 1) == ":")
        }
        BEGIN {
            # `beg`/`fin`, not `open`/`close`: `close` is an awk built-in and
            # using it as a variable is a syntax error in POSIX awk.
            beg = "<!-- pr-reply-origins"
            fin = "<!-- /pr-reply-origins"
            blen = length(beg)
            flen = length(fin)
        }
        {
            # A collapsed block — open and close on the same line — has to be
            # handled before the open-tag rule `next`s past it, the same
            # ordering bug PR #1573 found in lane_block.
            bp = index($0, beg)
            if (bp > 0) {
                bt = tagof($0, beg, blen)
                if (wanted(bt)) {
                    rest = substr($0, bp + blen + length(bt) + 4)
                    fp = index(rest, fin)
                    if (fp > 0 && wanted(tagof(rest, fin, flen))) {
                        last = substr(rest, 1, fp - 1)
                        next
                    }
                    collecting = 1
                    buf = ""
                    next
                }
            }
            if (collecting && wanted(tagof($0, fin, flen))) {
                collecting = 0
                last = buf
                next
            }
            if (collecting) { buf = buf $0 "\n" }
        }
        END { printf "%s", last }
    ' | while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
        *:*:*) printf '%s\n' "$_line" ;;
        esac
    done
}

# Raw PR comments JSON on stdin (same shape `_gh_pr_reply_history_origins`
# takes). rc 0 = an `ai-review` block posted by <expected-login> is present on
# this PR; rc 1 = none is.
#
#   _gh_pr_reply_history_has_review <expected-login> [head-sha]
#
# <head-sha>, when non-empty, additionally requires the marker to name THAT
# sha — "this exact head was reviewed", not merely "this PR was reviewed at
# some point" (PR #1703 review, BLOCKER 3). Callers that carry independent
# fresh evidence (Step 6, whose ORIGINS was classified against the current
# head) may omit it; the caller that has NONE — Step 2.5's zero-comment path,
# where ORIGINS is empty by construction and history is the only evidence —
# must pass it, or a PR whose head advanced past the last external review
# would be certified for a head no reviewer has ever seen.
#
# <expected-login> is REQUIRED (#1639) for the same reason as its sibling
# above, and matters MORE here, not less: this probe is the only thing
# standing between "no external review ever ran" and a self-applied
# `review-passed`. Matching `<!-- ai-review:` from any commenter meant a
# single hand-posted comment carrying that string manufactured the evidence
# the gate is asking for. The marker is written by `gh:pr-review` Step 6
# running under this pipeline's own login, so scoping the probe to that login
# is exactly the claim the gate wants to make. A missing/invalid login finds
# nothing -> rc 1 -> the PR is left UNLABELLED, the fail-closed direction the
# note below already relies on.
#
# This is the evidence probe for the second hole PR #1637's review found (agy
# BLOCKER): with an EMPTY ORIGINS stream the gate read `pass=no-blocker` and
# self-applied `review-passed` even when no external review had ever run (no
# CLI installed, `devx:pr-review-all` never invoked). #1636 relaxed NF-2 on the
# strength of a division of labour — external AI FINDS the blockers,
# gh:pr-reply confirms they were RESOLVED — and with no finder there is no
# division of labour left to lean on.
#
# Known limitation, accepted deliberately: `gh:pr-review`'s large-diff
# delegation path does not stamp the marker (a known bug, out of #1636's
# scope), and a bot-only review (gemini-code-assist et al.) posts no
# `ai-review` marker either. Both therefore read as "no evidence" and leave
# the PR UNLABELLED — the fail-closed direction, since downstream has always
# read "no label" as "not verified".
_gh_pr_reply_history_has_review() {
    local _bodies _sha="${2-}"
    # Read whole rather than `grep -q`: an early exit would hand EPIPE to a
    # piped producer, and this reads a comment dump that is already in memory.
    # The author filter runs FIRST — checking for the marker before scoping to
    # the trusted login would be the bug this parameter exists to fix.
    _bodies=$(_gh_pr_reply_login_bodies "${1-}")
    if [ -n "$_sha" ]; then
        # Marker shape is `<!-- ai-review:<ai>:<sha> -->`. The reviewer field
        # is matched as "no colon" so the sha cannot be satisfied by a colon
        # further left in the same comment. A sha is hex, so it carries no
        # regex metacharacter of its own.
        printf '%s\n' "$_bodies" |
            grep -q -e "<!-- ai-review:[^:]*:$_sha -->" || return 1
        return 0
    fi
    case "$_bodies" in
    *'<!-- ai-review:'*) return 0 ;;
    esac
    return 1
}

# Merge the ledger's history with this pass's classifications.
#
#   <this pass's origin lines> | _gh_pr_reply_origins_merge "<history origins>"
#
# Prints every history line whose REVIEWER does not appear in this pass,
# followed by this pass's lines verbatim and in order.
#
# The supersede rule is per-REVIEWER, not per-line, and that is the whole
# design. Without any supersede, a DECLINEd BLOCKER would pin `review-passed`
# off the PR forever with no way to ever clear it — the reviewer could concede
# the point in the next round and the label would still be stuck. With a
# per-reviewer supersede the escape hatch is exactly the right one: the
# reviewer re-raises the item in a later round, gh:pr-reply re-classifies it,
# and that fresh classification replaces the stale one. A reviewer who says
# nothing this pass keeps its history entries, so silence never clears a
# blocker.
#
# A malformed line in EITHER input is rc 2 — the same reason
# `_gh_pr_reply_origins_block` refuses to write one.
_gh_pr_reply_origins_merge() {
    local _history="${1-}" _this _line _rev _revs=" " _keep="" _out=""

    _this=$(cat)

    # This pass first: its reviewer set is what filters the history below.
    while IFS= read -r _line || [ -n "$_line" ]; do
        [ -n "$_line" ] || continue
        case "$_line" in
        *:*:*) ;;
        *)
            printf '[gh-pr-reply] malformed origin line (want <reviewer>:<severity>:<verdict>): %s\n' \
                "$_line" >&2
            return 2
            ;;
        esac
        _rev="${_line%%:*}"
        case "$_revs" in
        *" $_rev "*) ;;
        *) _revs="${_revs}${_rev} " ;;
        esac
        _out="${_out}${_line}
"
    done <<EOF
$_this
EOF

    while IFS= read -r _line || [ -n "$_line" ]; do
        [ -n "$_line" ] || continue
        case "$_line" in
        *:*:*) ;;
        *)
            printf '[gh-pr-reply] malformed origin line (want <reviewer>:<severity>:<verdict>): %s\n' \
                "$_line" >&2
            return 2
            ;;
        esac
        _rev="${_line%%:*}"
        case "$_revs" in
        *" $_rev "*) continue ;;
        esac
        _keep="${_keep}${_line}
"
    done <<EOF
$_history
EOF

    printf '%s%s' "$_keep" "$_out"
    return 0
}

# Post the merged origin lines back to the PR as the ledger comment.
#
#   <merged origin lines> | _gh_pr_reply_post_origins_ledger <pr> <repo> [host] [head-sha]
#
# Called on EVERY pass, including a pass that holds — the hold case is exactly
# when the next pass needs to be told, and a ledger written only on the pass
# path would remember nothing but the outcomes that need no memory.
#
# GH_HOST is pinned inside the subshell the same way
# `devx_pr_review_all_write_label` does it (#1403 / #1407). Soft-fail: rc 0 on
# every outcome, because a missing ledger degrades the NEXT pass (it re-reads
# a shorter history) rather than this one — but never silently, since that
# next pass then needs the reviewer to re-raise the item.
_gh_pr_reply_post_origins_ledger() {
    local _pr="${1-}" _repo="${2-}" _host="${3-}" _sha="${4-}"
    local _block _brc=0 _rc=0

    if [ -z "$_pr" ] || [ -z "$_repo" ]; then
        cat >/dev/null
        printf '[gh-pr-reply] usage: _gh_pr_reply_post_origins_ledger <pr> <repo> [host] [head-sha]\n' >&2
        return 2
    fi

    # `|| _brc=$?`, not a bare assignment: this file is sourced into callers
    # that may have `set -e` armed, where a rc 2 from the builder would abort
    # the caller instead of reaching the WARN below.
    _block=$(_gh_pr_reply_origins_block "$_sha") || _brc=$?
    if [ "$_brc" -ne 0 ]; then
        printf '[WARN] origin 원장 기록 실패 — 다음 pass 가 이번 판정을 못 본다(BLOCKER 재분류 필요)\n'
        return 0
    fi
    if [ -z "$_block" ]; then
        printf '[OK] 기록할 origin 없음 — 원장 생략\n'
        return 0
    fi

    (
        if [ -n "$_host" ]; then
            # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
            export GH_HOST="$_host"
        fi
        gh api -X POST "repos/$_repo/issues/$_pr/comments" -f "body=$_block"
    ) >/dev/null 2>&1 || _rc=$?

    if [ "$_rc" -eq 0 ]; then
        printf '[OK] origin 원장 기록됨 — 다음 pass 가 이 pass 의 판정을 본다\n'
    else
        printf '[WARN] origin 원장 기록 실패 — 다음 pass 가 이번 판정을 못 본다(BLOCKER 재분류 필요)\n'
    fi
    return 0
}

# ── F-2: the `review-passed` gate (issue #1636) ─────────────────────────
#
#   <origin lines> | _gh_pr_reply_review_passed_gate [<external-review-evidence>]
#
# Prints exactly one token:
#   pass=no-blocker              no BLOCKER-severity item was raised at all
#   pass=blockers-resolved:<n>   all <n> BLOCKER items are ACCEPT/ACCEPT-PARTIAL
#   hold=unresolved-blocker:<r>  <r> has a BLOCKER that is not resolved
#   hold=no-external-review      no external reviewer ever looked at this PR
#
# The origin stream is expected to be the MERGED one (this pass's lines plus
# the ledger history `_gh_pr_reply_origins_merge` kept) — feeding it only this
# pass's lines re-opens the cross-pass hole (PR #1637 review, codex BLOCKER).
#
# `<external-review-evidence>` is `yes` when the PR carries an `ai-review`
# block (`_gh_pr_reply_history_has_review`). It is FAIL-CLOSED by default:
# omitted, empty, or any other value means "no evidence", because a caller
# that forgot to probe must not be handed a certification it did not earn
# (PR #1637 review, agy BLOCKER).
#
# Evaluation order matters: the per-line BLOCKER loop runs FIRST, so a PR with
# both an unresolved blocker and no evidence reports the blocker — it names a
# reviewer and an actionable item, where the evidence token only says "run a
# review". Both are holds, so the label outcome is identical either way.
#
# This replaces #1616's `_gh_pr_reply_targeted_lane_decide`, which answered a
# narrower question ("may we spend one scoped gh:pr-review re-call?") and
# needed the caller to supply `BLOCKING_REVIEWERS` off the PR's `ai-review`
# blocks. #1636 removed the re-call, so the gate no longer needs that set:
# the question is simply "did this pass leave an unresolved BLOCKER?".
#
# Two consequences of dropping the reviewer set, both deliberate:
#   - A pass with NO blocking items is `pass=no-blocker`, not "unresolved".
#     Under #1616 the same input read as unresolved because the caller had
#     already asserted that some reviewer blocked; with no such assertion,
#     "nobody raised a BLOCKER" is the ordinary clean-PR case and treating it
#     as a hold would leave every clean PR unlabelled forever.
#   - The FIRST unresolved BLOCKER decides, and its reviewer is named. One
#     unresolved item is enough — this is the fail-closed half of NF-2 and it
#     is untouched by the relaxation.
#
# Blocking severity comes from `_gh_pr_reply_severity_is_blocking`, so the
# Korean `블로커` tag counts here even though `_gh_pr_reply_origin_tally`'s
# awk only groups the ASCII spellings — counting MORE items as blocking is
# the safe direction for a gate that authorizes `review-passed`.
_gh_pr_reply_review_passed_gate() {
    local _evidence="${1-}"
    local _origins _line _rev _rest _sev _verd _blocking=0

    # Read stdin whole before deciding: an early `return` mid-loop would leave
    # a piped producer facing EPIPE.
    _origins=$(cat)

    while IFS= read -r _line || [ -n "$_line" ]; do
        [ -n "$_line" ] || continue
        case "$_line" in
        *:*:*) ;;
        *)
            printf '[gh-pr-reply] malformed origin line (want <reviewer>:<severity>:<verdict>): %s\n' \
                "$_line" >&2
            return 2
            ;;
        esac
        _rev="${_line%%:*}"
        _rest="${_line#*:}"
        _sev="${_rest%%:*}"
        _verd=$(printf '%s' "${_rest#*:}" | tr '[:lower:]' '[:upper:]')

        _gh_pr_reply_severity_is_blocking "$_sev" || continue
        _blocking=$((_blocking + 1))
        case "$_verd" in
        ACCEPT | ACCEPT-PARTIAL) ;;
        *)
            printf 'hold=unresolved-blocker:%s\n' "$_rev"
            return 0
            ;;
        esac
    done <<EOF
$_origins
EOF

    # Only now, with no unresolved blocker to name, does the evidence question
    # decide. Anything other than a literal `yes` is "no evidence".
    case "$_evidence" in
    yes) ;;
    *)
        printf 'hold=no-external-review\n'
        return 0
        ;;
    esac

    if [ "$_blocking" -eq 0 ]; then
        printf 'pass=no-blocker\n'
    else
        printf 'pass=blockers-resolved:%s\n' "$_blocking"
    fi
    return 0
}

# ── The Step 7 line ─────────────────────────────────────────────────────
#
# Renders one gate token. Reporting is the ONLY thing this function does; the
# label is written by `_gh_pr_reply_apply_review_passed` below, which prints
# this line only once the write actually succeeded.
_gh_pr_reply_review_passed_report() {
    local _token="${1-}" _who
    case "$_token" in
    pass=no-blocker)
        printf '[OK] 미해결 BLOCKER 없음(BLOCKER 항목 자체가 없음) — review-passed 적용 (외부 재검토 없음, #1636)\n'
        ;;
    pass=blockers-resolved:*)
        printf '[OK] BLOCKER %s건 전부 해소 — review-blocked 해제, review-passed 적용 (외부 재검토 없음, #1636)\n' \
            "${_token#pass=blockers-resolved:}"
        ;;
    hold=unresolved-blocker:*)
        _who="${_token#hold=unresolved-blocker:}"
        printf '[BLOCKED] %s 의 블로커가 미해결 — review-passed 미부여, review-blocked 유지\n' "$_who"
        ;;
    hold=no-external-review)
        printf '[BLOCKED] 외부 리뷰 근거(ai-review 마커) 없음 — review-passed 미부여 (#1636 의 분업 전제 미충족)\n'
        ;;
    *)
        printf '[gh-pr-reply] unknown report token: %s\n' "$_token" >&2
        return 2
        ;;
    esac
    return 0
}

# ── Applying `review-passed` from gh:pr-reply's own judgment (#1636) ─────
#
#   <merged origin lines> | _gh_pr_reply_apply_review_passed <pr> <repo> [host] [head-sha] [external-review-evidence]
#
# The 5th positional is forwarded verbatim to the gate, evidence default and
# all — a caller that omits it gets `hold=no-external-review` and writes
# nothing, which is the fail-closed direction (PR #1637 review, agy BLOCKER).
# EVERY `hold=*` token takes the same path: report, write nothing, rc 0.
#
# Runs the gate, and on `pass=` writes `review-passed` through the shared
# `devx_pr_review_all_write_label` primitive — the same drop-opposite / safe-add
# / #1601-freshness-marker path `devx:pr-review-all` has always used. NOT
# through `devx_pr_review_all_apply_label`: that one takes a stream of reviewer
# verdict tokens, and synthesizing a fake `lgtm` line to feed it would dress
# gh:pr-reply's own judgment up as a reviewer CLI's opinion. The relaxation is
# meant to be visible in the code, not disguised (#1636).
#
# Prints one `[OK]`/`[BLOCKED]`/`[WARN]` line (plus the marker WARN on the one
# path that can produce it). Soft-fail: rc 0 for every labelling outcome — an
# unlabelled PR reads downstream as "not verified", which is the same contract
# as before. Only a usage error is rc 2.
_gh_pr_reply_apply_review_passed() {
    local _pr="${1-}" _repo="${2-}" _host="${3-}" _head_sha="${4-}" _evidence="${5-}"
    local _token _write _ok_line _fail_line

    if [ -z "$_pr" ] || [ -z "$_repo" ]; then
        cat >/dev/null
        printf '[gh-pr-reply] usage: _gh_pr_reply_apply_review_passed <pr> <repo> [host] [head-sha] [external-review-evidence]\n' >&2
        return 2
    fi

    _token=$(_gh_pr_reply_review_passed_gate "$_evidence") || return $?

    case "$_token" in
    hold=*)
        _gh_pr_reply_review_passed_report "$_token"
        return 0
        ;;
    esac

    if ! command -v devx_pr_review_all_write_label >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh" 2>/dev/null || :
    fi
    if ! command -v devx_pr_review_all_write_label >/dev/null 2>&1; then
        printf '[WARN] devx_pr_review_all_write_label 사용 불가 — PR #%s 무라벨 유지\n' "$_pr"
        return 0
    fi

    _write=$(devx_pr_review_all_write_label review-passed "$_pr" "$_repo" "$_host" "$_head_sha")
    # Reporting is shared with `devx_pr_review_all_apply_label`'s write path
    # (`devx_pr_review_all_report_write_result`, devx_pr_review_all.sh) — only
    # the `ok`/generic-failure lines differ between the two callers, which is
    # what the two trailing arguments supply.
    _ok_line=$(_gh_pr_reply_review_passed_report "$_token")
    _fail_line=$(printf '[WARN] PR #%s review-passed 적용 실패 — 미검증으로 취급' "$_pr")
    devx_pr_review_all_report_write_result "$_write" "$_pr" "$_repo" review-passed \
        "$_ok_line" "$_fail_line"
    return 0
}

# Self-check (issue #724): the skill sources this file in non-interactive
# bash. A syntax error or a rename would leave the gate silently undefined,
# which reads as "no decision" — and a caller that cannot decide must not
# fall back to the old global rule.
for _gprtr_selfcheck_fn in \
    _gh_pr_reply_origin_line \
    _gh_pr_reply_reviewer_is_bot \
    _gh_pr_reply_severity_is_blocking \
    _gh_pr_reply_origin_tally \
    _gh_pr_reply_origins_block \
    _gh_pr_reply_history_origins \
    _gh_pr_reply_history_has_review \
    _gh_pr_reply_origins_merge \
    _gh_pr_reply_post_origins_ledger \
    _gh_pr_reply_review_passed_gate \
    _gh_pr_reply_review_passed_report \
    _gh_pr_reply_apply_review_passed; do
    command -v "$_gprtr_selfcheck_fn" >/dev/null 2>&1 && continue
    printf '[gh_pr_reply_targeted_review] BUG: %s undefined after source — the #1636 review-passed gate will not run.\n' \
        "$_gprtr_selfcheck_fn" >&2
done
unset _gprtr_selfcheck_fn
:
