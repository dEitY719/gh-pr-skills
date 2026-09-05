# PR Comment Body Format — for gh-pr:review

The external AI's stdout is preserved **verbatim** — no reformatting,
no summarization. It is wrapped in a collapsed `<details>` block so
the PR conversation stays readable for skimmers, plus an ai-metrics
footer that matches the dotfiles SSOT (#317 / PR #320).

## Body template

```markdown
<details>
<summary>🤖 AI Review · <AI_NAME> · --review=<PRESET></summary>

<!-- ai-review:<AI_NAME>:<HEAD_SHA> -->
<verbatim stdout from external CLI>
<!-- /ai-review:<AI_NAME>:<HEAD_SHA> -->

</details>

---
<details>
<summary>🤖 AI Metrics · 📊 ~<TOKENS> tokens · 👤 ~<HUMAN_H> h · 🤖 ~<ELAPSED> min</summary>

<!-- ai-metrics:gh-pr-review -->
📊 ~<TOKENS> tokens · 👤 ~<HUMAN_H> h · 🤖 ~<ELAPSED> min
<!-- /ai-metrics:gh-pr-review -->

</details>
```

Substitutions:

| Token | Source |
|-------|--------|
| `<AI_NAME>` | The `--ai` argument value (`codex` / `agy` / `claude`). |
| `<HEAD_SHA>` | `headRefOid` from the one consolidated `gh pr view` (`_gh_pr_review_fetch_meta`). Empty → the marker falls back to the unsuffixed `<!-- ai-review:<AI_NAME> -->` form. |
| `<PRESET>` | The normalized `--review` enum (after KR-alias mapping). |
| `<TOKENS>` | Estimated prompt tokens, rounded to the nearest 500. Minimum 1 000. |
| `<HUMAN_H>` | Baseline human-review hours. See "Human time baseline" below. |
| `<ELAPSED>` | `(($(date +%s) - START_TS) / 60))`. |

## Why the marker carries the head sha (#1564)

The `ai-review` markers are not decoration — they are the **only**
machine-readable record of a lane's verdict, and `gh-verify:review-all`
harvests them to decide whether the merge train may touch this PR
(`devx-pr-review-all/references/review-verdict-label.md`, the consumer
SSOT). A verdict proves something about **one commit**, so the marker
names that commit. Without the suffix, a review posted two pushes ago is
indistinguishable from one posted against the head under review, and a
stale `review-passed` can authorize a merge of code no reviewer saw.

`devx_pr_review_all_lane_block <ai> <sha> <expected-login>` requires the
open **and**
close marker to carry the same `<ai>:<sha>` pair **and** the comment to
have been posted by `<expected-login>` (#1639 — a marker from any other
commenter is forged and ignored); a miss yields nothing,
which reads downstream as `unknown` — no label, no merge. Comments
posted before this change carry the unsuffixed form and therefore read
as `unknown` under the sha-aware path. That is the documented
fail-closed direction, not a regression: those PRs are re-reviewed, and
the fresh comment carries the tag.

## Emoji exception scope

CLAUDE.md restricts emoji to the `ai-metrics` footer block. This skill
introduces a sibling marker `<!-- ai-review:<ai>:<head-sha> -->` that
mirrors the same `<details>` + glyph pattern. Treat the new marker as a
**scoped extension** of the existing exception:

- 🤖 in `<summary>` line — allowed per this repo's `allow-emoji-paths` list in `.github/workflows/validate.yml`, which registers this file (ai-metrics/AI-review footer SSOT, CLAUDE.md #317 F-2). The dotfiles-era register `claude/skills/skill-check/references/allowed-emoji-skills.txt` is gone with the rest of `~/dotfiles/claude/skills/`; the skill itself now lives in `authoring-skills` as `skill-check`.
- All other emoji — still forbidden everywhere.

If the CLAUDE.md SSOT needs updating, do it in the same PR that lands
this skill so the rule and the artifact ship together.

## Step 6 delegation + 3-branch decision tree

Step 6 of the skill delegates body construction and posting to two
helpers in `shell-common/functions/gh_pr_review.sh`:

- `_gh_pr_review_build_comment_body` — emits the SSOT body per this
  file's "Body template" (collapsed `<details>` AI-review block +
  `<!-- ai-review:<ai>:<head-sha> -->` markers + ai-metrics footer with
  `<!-- ai-metrics:gh-pr-review -->` markers).
- `_gh_pr_review_post_comment` — wraps `gh pr comment --body-file`
  and enforces three behaviors with a single decision tree:
  1. `--no-post-comment` → print `skipped (--no-post-comment)` and
     return 0.
  2. `GH_DISABLE_AI_METRICS=1` → print
     `skipped (GH_DISABLE_AI_METRICS=1)` and return 0. The opt-out
     skips the **entire** PR comment (not just the metrics footer),
     because the AI-review body and the metrics footer ship together
     (issue #399).
  3. `gh pr comment` non-zero exit → print `[WARN] PR comment post
     failed — output retained on stdout` to stderr, emit
     `[WARN] post failed` to stdout, and still return 0 — the user
     already has the AI output on their terminal.

Token, human-h, and elapsed-minute inputs are computed by
`_gh_pr_review_estimate_tokens` and `_gh_pr_review_human_h` (per-preset
baseline from "Human time baseline" / "Token estimation" below). The
skill does not duplicate those formulas — read the shell function for
the authoritative arithmetic.

## Posting via `gh pr comment`

```sh
GH_HOST="$TARGET_HOST" gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" \
    --body-file "$BODY_FILE"
```

Use `--body-file` (not `--body "..."`) because the verbatim AI output
may contain shell metacharacters, backticks, and multi-line content.
A here-doc-built temp file isolates the substitution surface.

### Why not `gh pr edit --body`

This skill **appends a comment**, never edits the PR body. Editing
the body would clobber the author's description and (as noted in
issue #326 Bug B) silently exit 1 on repos with classic Projects
attached. `gh pr comment` has no such failure mode.

## Soft-fail on post failure

```sh
if ! GH_HOST="$TARGET_HOST" gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" \
        --body-file "$BODY_FILE"; then
    echo "[WARN] PR comment post failed — output retained on stdout"
    # exit 0 — stdout already has the AI output for the user.
fi
```

Mirrors `gh-pr-reply`'s ai-metrics soft-fail pattern: a network blip or
transient gh API error must not throw away the AI output already
streamed to the user's terminal.

## `GH_DISABLE_AI_METRICS=1` opt-out

When the env var is set, **skip the entire comment post** — including
the AI review body, not just the metrics footer. Rationale: the
metrics footer is the ai-cost contract; opting out implies the user
does not want ai-cost evidence on the PR thread. The stdout output is
unaffected.

```sh
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # PR comment skipped via GH_DISABLE_AI_METRICS — stdout still shown.
else
    GH_HOST="$TARGET_HOST" gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" \
      --body-file "$BODY_FILE" \
      || echo "[WARN] PR comment post failed — output retained on stdout"
fi
```

This matches the policy other ai-metrics-emitting skills use
(`gh-pr-reply`, `gh-pr-approve`, `gh-issue-flow`).

## Human time baseline

`<HUMAN_H>` is a rough estimate of how long a human reviewer would
spend producing the equivalent finding set. Defaults by preset:

| Preset | Baseline (h) |
|--------|--------------|
| `default` | 1.0 |
| `quick` | 0.3 |
| `thorough` | 2.5 |
| `security` | 1.5 |
| `performance` | 1.5 |

Adjust upward by 0.5 h per +500 diff lines beyond the first 500. These
are calibration starting points, not gospel — tighten when
`docs/.ssot/metrics-baseline.md` (if introduced) supersedes them.

## Token estimation

`_gh_pr_review_estimate_tokens` (`shell-common/functions/gh_pr_review.sh`)
takes a byte count and applies the pure arithmetic — divide by 4, round to
the nearest 500, floor 1000:

```sh
tokens=$((raw / 4))
tokens=$(((tokens + 250) / 500 * 500))
[ "$tokens" -lt 1000 ] && tokens=1000
```

The byte count itself is measured right after Step 3+4 builds the prompt,
not re-read at Step 6 comment-post time — the issue #1474 mitigation (the
file-vanishing root cause itself is still open; only the measurement timing
was fixed). Read the comment above `_gh_pr_review_estimate_tokens` and its
caller in `gh_pr_review.sh` for the full rationale and the exact `[WARN]`
text; this doc only tracks the arithmetic shown above.

The 4-bytes-per-token heuristic is conservative for English/Korean
mixed PR bodies. Refine when a tokenizer-backed metric becomes part
of the repo SSOT.
