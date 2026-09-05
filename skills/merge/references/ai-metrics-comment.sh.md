# ai-metrics Comment — post-merge PR footer (soft-fail)

Posted after the board sync (Step 4) completes. Soft-fail: on error,
print `[WARN] ai-metrics comment failed — continuing.` and proceed.
When `GH_DISABLE_AI_METRICS=1`, skip the comment entirely (issue dEitY719/dotfiles#399).

The footer glyphs (🤖 📊 👤) are intentional — `gh-pr-merge` is on the
emoji allowlist (CLAUDE.md dEitY719/dotfiles#317/dEitY719/dotfiles#320/dEitY719/dotfiles#367). Keep them as-is.

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="---
<details>
<summary>🤖 AI Metrics · 📊 ~${TOKENS:-2000} tokens · 👤 ~0.25 h · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-pr-merge -->
📊 ~${TOKENS:-2000} tokens · 👤 ~0.25 h · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-pr-merge -->

</details>
PR merge: ~$ELAPSED min"
fi
```
