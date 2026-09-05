# Reply Templates — for gh-pr:reply skill

Reply in the language the reviewer used. Korean reviewer → Korean reply.
Japanese reviewer → Japanese reply. English reviewer → English reply. Match
their register and tone (formal/informal) as well.

## POST command shapes

### Inline review comment (from `/pulls/<N>/comments`)

Reply in-thread using the replies sub-resource:

```bash
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/pulls/<N>/comments/<comment_id>/replies" \
  -X POST \
  -f body="<reply text>"
```

### Top-level issue comment (from `/issues/<N>/comments`)

No thread reply endpoint exists; post a new issue comment that blockquotes
the original so the context is clear. **Every line of the original must be
prefixed with `> ` individually** — a single `> ` only quotes the first
line in GitHub-flavored Markdown.

```bash
# Build a properly quoted blockquote from the original body
QUOTED=$(printf '%s\n' "$ORIGINAL_BODY" | sed 's/^/> /')

GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/<N>/comments" \
  -X POST \
  -f body="$QUOTED

<reply text>"
```

The same pattern applies when replying to a review summary from
`/pulls/<N>/reviews`: there is no per-review reply endpoint, so post a
top-level issue comment that blockquotes the review body and addresses it.

### Long-body fallback (review body > 500 chars)

Verbatim `> `-prefixed quoting becomes unreadable for long review bodies
(multi-blocker reviews routinely exceed 3 000 chars). Skip the blockquote
and lead the reply with a citation header instead — reviewers can scroll
up to read the original, and the reply stays scannable:

```bash
# Body length threshold: 500 chars. Above that, cite by id instead of quoting.
# HEADER text below is English; translate to the reviewer's language
# (e.g. Korean: "Re: 리뷰 #<review_id> — Blocker <N>건 + Suggestion <M>건").
if [ "${#ORIGINAL_BODY}" -gt 500 ]; then
  HEADER="Re: review #<review_id> — <N> Blockers + <M> Suggestions"
  GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/<N>/comments" \
    -X POST \
    -f body="$HEADER

<reply text>"
else
  # short bodies → keep the verbatim blockquote pattern above
  QUOTED=$(printf '%s\n' "$ORIGINAL_BODY" | sed 's/^/> /')
  GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/<N>/comments" \
    -X POST \
    -f body="$QUOTED

<reply text>"
fi
```

`<review_id>` is the `id` field returned by `/pulls/<N>/reviews`. `<N>` /
`<M>` counts come from the Step 3 classification (BLOCKER + Suggestion
labels are an example taxonomy — match whatever vocabulary the reviewer
used). The `HEADER` literal is a translatable template, not a fixed
English string — the top-of-file language rule overrides it. Validated
on PR `dev-team-404/AgentToolbox#655` review
`pullrequestreview-4286773211` (~3 000-char body, 7 BLOCKER + 3
Suggestion) — reviewer approved on re-review and praised the format.

## Reply body templates

### Accepted

```
Accepted. Fixed in <short-sha> — <one-line what changed>.
```

### Accepted with modification

```
Accepted with modification. Rather than <their suggestion>, I went with
<actual fix> in <short-sha> because <reason>.
```

### Declined

```
Declined. <specific reason tied to the code/context>. <optional: pointer to
docs, other PR, or file that justifies the current design>.
```

### Question answered

```
<direct answer>. <optional: link to file:line for reference>.
```

### Consolidated table reply (N ≥ 3 items in one review body)

Fires when a single review body bundles multiple independent items
(e.g. body-only review with 3+ Blockers, or a mix of Blockers and
Suggestions with no inline anchors). Posting four separate top-level
comments fragments the conversation; consolidating into one tabular
reply keeps the thread linear and lets the reviewer scan
item-by-item.

**Trigger conditions** (all must hold):

1. The source is a single `/pulls/<N>/reviews` summary or a single
   `/issues/<N>/comments` entry — NOT four separate inline comments.
2. The body contains N ≥ 3 independently actionable items
   (Blockers / Suggestions / Questions, in any mix).
3. The items are short enough that a one-line "수정" / "Resolution"
   column per row stays readable.

For N ≤ 2 items, or for inline comments anchored to specific lines,
use the per-item templates above — do NOT force a table.

**Body template** (replace `B`/`S` labels with the reviewer's
taxonomy; match the reviewer's language — the column headers, verdict
keywords, and footer label below are Korean because the AgentToolbox#655
validation reviewer was Korean-speaking; translate per top-of-file rule):

```
Re: review #<review_id> — <N> Blockers + <M> Suggestions

| # | 항목 | 판정 | 수정 |
|---|------|------|------|
| B1 | <one-line summary of blocker 1> | Accepted | <short-sha> — <what changed> |
| B2 | <one-line summary of blocker 2> | Declined | <reason tied to code> |
| ... | ... | ... | ... |
| S1 | <one-line summary of suggestion 1> | Accepted | <short-sha> — <what changed> |

전체 fix commit: <short-sha>
```

English column equivalents: `| # | Item | Verdict | Resolution |` with
footer `Aggregate fix commit: <short-sha>`. Pick the language that
matches the reviewer; do not mix.

Every row must land in exactly one of: Accepted / Accepted-w-mod /
Declined / Answered. The aggregate commit short-SHA on the trailing
line lets the reviewer jump to the diff once instead of N times.
Validated on PR `dev-team-404/AgentToolbox#655` review
`pullrequestreview-4286773211` — table reply id `4446821878`, fix
commit `1ffff97`, reviewer subsequently approved on re-review.

## Notes

- Always include the commit short-sha for Accepted / Accepted-with-modification
  replies — reviewers need a pointer to verify the fix.
- Declined replies must state a concrete reason, never a dismissive one-liner.
- Bot comments get the exact same templates — no shortcuts.

## Classification rubric

Use these four classes in Step 3 of the SKILL.md workflow. Every
unaddressed comment falls into exactly one.

- **ACCEPT** — reviewer is correct; the code should change.
- **ACCEPT-PARTIAL** — valid concern, but a different fix is better; note
  the deviation in the reply (use the "Accepted with modification" body).
- **DECLINE** — reviewer is wrong, misunderstanding the context, or the
  suggestion would regress something; must explain why in the reply.
- **QUESTION** — reviewer asked for clarification rather than a change;
  answer the question directly.

There is no fifth class. A BLOCKER you decline **because it belongs
somewhere else** is still a `DECLINE` — you file it where it belongs and
record the tracking issue in the ledger's optional 4th field:

```bash
_gh_pr_reply_origin_line agy '[BLOCKER]' DECLINE dEitY719/harness-skills#22
```

The reply itself must still say why it is declined here and name the issue it
went to, exactly like any other decline. Escalating does **not** clear the
gate: `review-passed` is still withheld and `review-blocked` still stands —
the item genuinely is unresolved in this PR. All the 4th field buys is that
the next reader can follow it. SSOT: `references/review-passed-gate.md`
-> "추적된 DECLINE 은 여전히 hold 다".

Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules — a bot nit is still a legitimate comment that deserves a reply.
