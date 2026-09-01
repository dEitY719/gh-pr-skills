# Comment Fetching — for gh-pr:reply skill

PRs expose review feedback through three distinct API endpoints — all must be
queried. Missing any one of them means missing comments (bots especially tend
to scatter content across these endpoints).

## The three endpoints

```bash
# Inline code review comments (line-anchored)
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/pulls/<N>/comments" --paginate

# Top-level issue-style comments on the PR conversation
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/<N>/comments" --paginate

# Review summaries (bots often put content here)
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/pulls/<N>/reviews" --paginate
```

## Fields to extract per comment

- `id` — comment identifier (needed for replying)
- `user.login` — author (including bots: gemini-code-assist, sourcery-ai, copilot)
- `path` — file the comment is anchored to (inline comments only)
- `line` — line number in the file (inline comments only)
- `body` — comment text
- `in_reply_to_id` — parent comment id, for threading
- `html_url` — link back to the comment on GitHub

**Keep the raw `/issues/<N>/comments` array around, not just the bodies**
(#1639). Step 6's `review-passed` gate feeds that array straight into
`_gh_pr_reply_history_origins` / `_gh_pr_reply_history_has_review`, which
decide whose `pr-reply-origins` / `ai-review` markers to trust by matching
`.user.login`. Collapsing the response to body text (`--jq '.[].body'`) throws
the author away and makes every marker forgeable by any commenter — see
`references/review-passed-gate.md` → "마커 작성자 (#1639)".

Bind it to `$COMMENT_JSON` — the exact name `references/review-passed-gate.md`
Step 6 reads it back under (PR #1641 review, agy FOLLOW-UP: the name was used
there with no definition in either this file or `SKILL.md`). It is the
unfiltered JSON array `gh api "repos/$TARGET_REPO/issues/<N>/comments"
--paginate` returns — the same fetch this section already asked for above,
saved rather than discarded once Step 2's dedup pass over it is done.

## Deduplication rule

Skip a thread only if the **latest** comment in the thread is authored by
the current user or by Claude. This allows the skill to respond when a
reviewer leaves a follow-up comment after a previous Claude reply.

Algorithm:
1. Build threads by chaining `in_reply_to_id` from each comment back to its
   root (comments with `in_reply_to_id == null`).
2. For each thread, sort descendants by `created_at`.
3. Look at the last (most recent) comment. If its `user.login` is the
   current user or Claude, skip the thread. Otherwise process it.

Exception: if the user explicitly asks to re-process, ignore this filter and
reply to everything fresh.

## Review summaries

`/pulls/<N>/reviews` entries have no line anchor and no `replies` sub-resource.
Handle each review summary as follows:

- **Actionable content** (reviewer wrote a critical concern in the summary
  body itself, not just linking to inline comments): post a new top-level
  issue comment that blockquotes the review summary and addresses it, using
  the top-level reply shape from `reply-templates.md`. For long bodies
  (>500 chars) or N ≥ 3 bundled items, see the Long-body fallback and
  Consolidated table reply templates in `reply-templates.md`.
- **Meta content** (summary just recaps the inline comments, or is a service
  notice like "your repo doesn't have access to X"): no reply needed; note
  it in the Step 7 report as "skipped (meta summary)".

Judgment: if deleting the summary would lose information not already
captured in an inline comment, it is actionable.

## Bot service notices

Bots scatter "service" output across both `/pulls/<N>/reviews` and
`/issues/<N>/comments`, so the meta-content rule above applies to BOTH
endpoints — not just reviews. Examples seen in the wild:

- gemini-code-assist quota-exhausted notice posted as a conversation
  comment (`/issues/<N>/comments`, AgentToolbox#655 run).
- sourcery-ai "rate limited" or "service unavailable" comment.
- copilot trial-expired notice.

**Classification.** A bot comment is a *service notice* when it carries no
code-review content — it announces the bot's own availability (quota,
rate-limit, outage, trial state, repo access) instead of evaluating the
diff. Code-review nits from the same bot are NOT service notices and go
through the normal Accept / Decline classification.

**Handling.** Service notices still get a reply (the politeness contract
is non-negotiable) but use a single-line ack — there is nothing to
accept, decline, or answer. Suggested ack body (translate to the
reviewer's language per the top-of-file rule in `reply-templates.md` —
the example below is English):

```
Acknowledged — service notice, no code-review content to address.
```

Korean equivalent: `확인했습니다 — 서비스 알림, 코드 리뷰 내용 없음.`
Match the reviewer's language exactly; this is a template, not a fixed
string.

Note these in the Step 7 report as `Acknowledged (bot service notice):`
so the user can see the bot was not silently ignored. Do NOT skip
silently and do NOT route them through the four-class rubric.
