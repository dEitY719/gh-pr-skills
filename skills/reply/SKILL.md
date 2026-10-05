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

Arg #1 `-h` / `--help` / `help`: print `references/help.md` verbatim, stop. No API calls.

## Role

Judge every review comment on a PR, fix the valid ones, and reply to each —
bot comments included; never skip one.

## Step 1: Resolve Target PR + Repo

Record `START_TS=$(date +%s)` immediately (elapsed tracking in Step 7).

Read `references/target-resolution.md` and follow it: positional args
`<pr-number> [remote]`, PR-number precedence (never guess "the latest PR"), the
`TARGET_REPO` + `TARGET_HOST` binding (both from the `[remote]`'s URL, never
`gh`'s default-repo heuristic), the fork tradeoff. Every later `gh` call runs as
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"` (dEitY719/dotfiles#1403, dEitY719/dotfiles#1407).

## Step 2: Fetch All Review Comments

Fetch all three endpoints in `references/comment-fetching.md` (fields, dedup);
filter out already-replied threads. Bot service notices (quota / rate-limit /
outage) follow its "Bot service notices" section (one-line ack, counted apart).

**Step 2.5 early exit:** if this yields **zero unaddressed threads** after
dedup, first run `lib/step6-board-and-labels.sh --phase post-gate` (located per
`references/step6-board-and-labels.md`), then print exactly `No unaddressed review
comments — nothing to do.` and **stop**: no Steps 3–7, no ai-metrics, no push.

## Step 3: Evaluate Each Comment

For each unaddressed comment, classify it **ACCEPT** / **ACCEPT-PARTIAL** /
**DECLINE** / **QUESTION**, then record its origin token. Read
`references/classification-and-origins.md` and follow it verbatim — the rubric,
the bot rule, and the `_gh_pr_reply_origin_line` / `ORIGINS` wire format.

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

Minimal, scoped fixes — no drive-by refactors — in themed commits (one per
theme, not per comment), e.g. `fix(review): address X …`. Never `--amend` / `--no-verify`.

## Step 5: Reply to Every Comment

**Non-negotiable. Every comment from Step 2 must receive a reply, including
declined ones and bot comments.** Read `references/reply-templates.md` for
POST command shapes, the four body templates, the long-body fallback, and
the consolidated table reply. Reply in the reviewer's language.

**Failure policy** (detail: `references/constraints.md` § "Failure policy"):
HARD stop + `[FAIL]` on a Step 1 target or Step 2 fetch failure, or a refused
Step 6 push (no label/board calls after it). A failed reply POST retries once,
then is recorded as unreplied, which makes the verdict `[FAIL]`. Board, label
and ai-metrics steps are SOFT: one `[WARN]`, continue.

## Step 6: Push the Fix Commits + Sync Board + Set Verdict Labels

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs. Set `PUSHED_FIXES` to the count of new
SHAs on the remote branch; no fixes / skipped push → `PUSHED_FIXES=0`.

Then, per `references/step6-board-and-labels.md` (locator block + order):
`lib/step6-board-and-labels.sh --phase pre-gate <N> <PUSHED_FIXES>`, the
`review-passed` gate, then `lib/step6-board-and-labels.sh --phase post-gate <N>`.

## Step 7: Report

Read `references/final-summary.md` § "Step 7 report" and follow it: first line
`[OK]`/`[FAIL]` verdict, the summary table, the ai-metrics PR comment, and a
final `Next:` line (`/gh-pr:approve <N>` when `review-passed` was applied).

## Constraints

Honour every rule in `references/constraints.md` (short form: "Non-negotiables").

## Related Skills

`gh-pr:review` posts one aggregate second-opinion comment instead of per-comment
replies · `gh-pr:approve` owns the approve / request-changes decision.
