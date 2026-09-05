# gh-pr:reply Step 7 — ai-metrics PR comment

Called from `SKILL.md` Step 7, after printing the final report. Post a
PR comment with ai-metrics (soft-fail — warn on error, never block).
`COMMENT_COUNT` is the number of comments addressed in Step 5 (including
declined and bot comments). When `GH_DISABLE_AI_METRICS=1`, skip the
comment entirely (issue dEitY719/dotfiles#399).

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
HUMAN_H=$(awk -v cc="$COMMENT_COUNT" 'BEGIN { printf "%.2f", cc * 0.25 }')
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="---
<details>
<summary>🤖 AI Metrics · 📊 ~${TOKENS:-5000} tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-pr-reply -->
📊 ~${TOKENS:-5000} tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-pr-reply -->

</details>
리뷰 답변: ~$ELAPSED min · 사람: ~$HUMAN_H h ($COMMENT_COUNT comments × 0.25 h)"
fi
```

On failure: `[WARN] ai-metrics comment failed — continuing.`
