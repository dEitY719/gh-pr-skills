# AI Metrics Comment — gh-pr:commit Step 5 (first half)

Record AI metrics as a soft-fail step: warn on error, never block the
commit. Compute elapsed time and post a comment on the linked issue
**only** when an issue number was resolved in Step 2. When
`GH_DISABLE_AI_METRICS=1`, skip the comment entirely (board sync still
runs — issue #399).

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
# Token estimate: (char count of commit diff + message) / 4, rounded to nearest 500, min 1000
# See gh-issue-create/references/metrics-helper.md "Token Estimation" for the formula
TOKENS=$(( ( ($(git diff HEAD~1 | wc -c) / 4 / 500) + 1 ) * 500 ))
[ "$TOKENS" -lt 1000 ] && TOKENS=1000
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$ISSUE_NUMBER/comments" \
      -X POST \
      -f body="### AI Metrics — gh-commit

| 항목 | 값 |
|------|-----|
| 커밋 | $COMMIT_SHA |
| 구현 시간 (gh-issue-implement) | ~${IMPL_MIN:-?} min |
| 커밋 시간 (gh-commit) | ~$ELAPSED min |
| 토큰 | ~$TOKENS |

---
<details>
<summary>🤖 AI Metrics · 📊 ~$TOKENS tokens · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-commit -->
📊 ~$TOKENS tokens · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-commit -->

</details>"
fi
```

`$TARGET_HOST` / `$TARGET_REPO` are the pair Step 1 bound from the
`[remote]`'s URL — `$REMOTE`, which defaults to `origin` but is whatever the
`[remote]` positional named (#1405). Both are mandatory: a bare `gh api repos/.../comments` resolves against
gh CLI's own default host, so on a dual-host login the metrics comment lands
on the wrong server's issue #N — or 404s — without failing loudly (#1403).

If no issue number exists, print the metrics to stdout only and skip the
comment. On any API failure, print
`[WARN] ai-metrics comment failed — continuing.` and proceed.

> The four emoji glyphs above (`🤖 📊 👤`) are the intended ai-metrics
> footer visual design — CLAUDE.md SSOT exception (#317 F-2, PR #320,
> #367). `gh-commit` is registered in
> `skill-check/references/allowed-emoji-skills.txt` (#837).
