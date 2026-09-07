---
name: reply
description: >-
  Reply individually to every review comment on a GitHub PR — bots included —
  and apply the valid fixes. Use for /gh-pr:reply, "PR 리뷰 코멘트 확인하고 수정",
  "PR 123 코멘트 처리해", "reply to review comments". Per-comment replies, not a summary comment.
license: MIT
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "review comment evaluation + classification + targeted edits + per-comment reply; moderate analysis, not deep implementation"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:reply — Address PR Review Comments

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md`, output it
verbatim, then stop. No API calls.

## Role

Process every code-review comment on a PR: judge validity, fix valid ones,
reply to each with the outcome.

## Step 1: Resolve Target PR + Repo

Record `START_TS=$(date +%s)` immediately (elapsed tracking in Step 7).

Read `references/target-resolution.md` and follow it: positional args
`<pr-number> [remote]`, PR-number precedence (never guess "the latest PR"), the
`TARGET_REPO` + `TARGET_HOST` binding (both from the `[remote]`'s URL, never
`gh`'s default-repo heuristic), the fork tradeoff. Every later `gh` call runs as
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"` (dEitY719/dotfiles#1403, dEitY719/dotfiles#1407).

## Step 2: Fetch All Review Comments

Read `references/comment-fetching.md` for the three API endpoints, field
extraction, and dedup rule. Fetch all three; filter out already-replied
threads. Bot service notices (quota / rate-limit / outage) follow that
reference's "Bot service notices" section (service-notice classification,
single-line ack in Step 5, counted separately in Step 7).

**Step 2.5 early exit:** if this yields **zero unaddressed threads** after
dedup, first run the `reply-pending` removal block of
`references/reply-pending-label-removal.sh.md` (this exit path is why it lives
there and not inline in Step 6), then print exactly `No unaddressed review
comments — nothing to do.` and **stop**: no Steps 3–7, no ai-metrics, no push.

## Step 3: Evaluate Each Comment

For each unaddressed comment, read the referenced file (`path` at `line`)
and classify as **ACCEPT** / **ACCEPT-PARTIAL** / **DECLINE** / **QUESTION**.
Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules; see `references/reply-templates.md` for the full rubric.

Record each item's origin as `<reviewer>:<severity>:<verdict>[:<owner>/<repo>#<N>]`
into `ORIGINS` via `_gh_pr_reply_origin_line` (`references/review-passed-gate.md`
§ Step 3) — Steps 6 and 7 both read that stream, because a flat
accepted/declined count cannot tell an unresolved BLOCKER from a declined
suggestion (dEitY719/dotfiles#1616). The optional 4th field names the issue a
declined BLOCKER was escalated to (dEitY719/dotfiles#1762); it changes the
report line, never the gate's decision — escalation is not resolution.

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

Keep each fix minimal and scoped — no drive-by refactors. Group related
fixes into themed commits (one per theme, not per comment), e.g.
`fix(review): address X …`. Never `--amend` or `--no-verify`.

## Step 5: Reply to Every Comment

**Non-negotiable. Every comment from Step 2 must receive a reply, including
declined ones and bot comments.** Read `references/reply-templates.md` for
POST command shapes, the four body templates, the long-body fallback, and
the consolidated table reply. Reply in the reviewer's language.

## Step 6: Push the Fix Commits + Sync Board + Set Verdict Labels

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs. Set `PUSHED_FIXES` to the count of new
SHAs on the remote branch; no fixes / skipped push → `PUSHED_FIXES=0`.

If `PUSHED_FIXES > 0`: sync the board back to `In review`
(`references/board-sync-in-review.sh.md`, soft-fail), then drop the now-stale
`review-passed` (`references/verdict-label-removal.sh.md`, soft-fail) — the
reviewed commit is no longer head. Both run before the gate below.

Then, unconditionally and only after Step 5 has replied to every comment: run
the `review-passed` gate exactly as `references/review-passed-gate.md`
specifies — it is the SSOT for `HEAD_SHA`/`ME` resolution, the raw-JSON
requirement, the origin-history merge, and the five-call pipeline order
(soft-fail; `gh-verify:review-all` owns `review-blocked` and never writes
`review-passed`; see `references/constraints.md` for the NF-2 rationale).
Never hand-write either label.

Then **unconditionally** run the same removal block Step 2.5 does —
`references/reply-pending-label-removal.sh.md` — so a label left on cannot
wedge the PR out of `gh-pr:merge-train` (dEitY719/dotfiles#1524).

## Step 7: Report

Print the summary table per `references/final-summary.md` (Accepted / Declined /
Answered counts, the per-reviewer/severity breakdown, the `review-passed`
gate outcome line, commit SHAs, skipped comments, and the lingering
`CHANGES_REQUESTED` nudge). Then post the ai-metrics PR comment per
`references/ai-metrics-comment.sh.md` (soft-fail; skip when `GH_DISABLE_AI_METRICS=1`).

## Constraints

Read `references/constraints.md`. Non-negotiables: never promote the card to
`Approved` (owned by `gh-pr:approve`, dEitY719/dotfiles#1350), never resolve
threads programmatically, never `--amend` / `--no-verify` / force-push, and
route label/body edits through `_gh_pr_edit_safe_*`.

## Related Skills

`gh-pr:review` posts one aggregate second-opinion comment instead of per-comment
replies · `gh-pr:approve` owns the approve / request-changes decision.
