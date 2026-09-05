# ai-metrics footer — post-review metric comment

After submitting the review (any path), post a separate PR comment with
ai-metrics. Soft-fail: warn on error, never block. When
`GH_DISABLE_AI_METRICS=1`, skip the comment entirely (issue dEitY719/dotfiles#399).

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="---
<details>
<summary>🤖 AI Metrics · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-pr-approve -->
🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-pr-approve -->

</details>
PR 리뷰: ~$ELAPSED min"
fi
```

The `tokens` and `human_h` fields are intentionally omitted: this skill
has no real measurement source for either, and the prior `${TOKENS:-5000}`
/ `human_h=1` placeholders would silently inject the same false numbers
into every aggregator (issue dEitY719/dotfiles#403). Only `ai_min` is reported.

On failure: `[WARN] ai-metrics comment failed — continuing.`
