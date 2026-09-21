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
reply to each with the outcome — every comment, bot comments included, gets
an explicit reply; never skip one.

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

For each unaddressed comment, classify it **ACCEPT** / **ACCEPT-PARTIAL** /
**DECLINE** / **QUESTION**, then record its origin token. Read
`references/classification-and-origins.md` and follow it verbatim — the rubric,
the bot rule, and the `_gh_pr_reply_origin_line` / `ORIGINS` wire format.

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

Then run `references/step6-board-and-labels.md` verbatim, in the order it
states: the `In review` board sync and stale-verdict drop when
`PUSHED_FIXES > 0`, the `review-passed` gate, then `reply-pending` removal.

## Step 7: Report

Read `references/final-summary.md` § "Step 7 report" and follow it: the summary
table, then the ai-metrics PR comment it hands off to.

## Constraints

Read `references/constraints.md` and honour every rule in it; its
"Non-negotiables" section is the short form of this list.

## Related Skills

`gh-pr:review` posts one aggregate second-opinion comment instead of per-comment
replies · `gh-pr:approve` owns the approve / request-changes decision.
