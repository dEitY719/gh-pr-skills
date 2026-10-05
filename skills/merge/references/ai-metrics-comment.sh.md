# ai-metrics Comment — post-merge PR footer (soft-fail)

Posted after the board sync (Step 4) completes. Soft-fail: on error,
print `[WARN] ai-metrics comment failed — continuing.` and proceed.
When `GH_DISABLE_AI_METRICS=1`, skip the comment entirely (issue dEitY719/dotfiles#399).

The footer glyphs (🤖 📊 👤) are intentional: the ai-metrics footer is a wire
format, so the file that specifies it has to show the real glyphs (CLAUDE.md →
"Emojis", dEitY719/dotfiles#317 / dEitY719/dotfiles#320 / dEitY719/dotfiles#367).
CI admits them by **path**, not by skill name — this file and
`lib/post-merge-housekeeping.sh` are listed under `allow-emoji-paths` in
`.github/workflows/validate.yml`. Keep them as-is, and keep the path entries in
step with any rename.

Implemented as step 4 of `lib/post-merge-housekeeping.sh` (relative to `skills/merge/`): one
`GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" -X POST`
whose body is the collapsed `<details>` footer — summary
`AI Metrics · ~${TOKENS:-2000} tokens · ~0.25 h · ~$ELAPSED min` with the three
glyphs, the `<!-- ai-metrics:gh-pr-merge -->` marker pair, and a trailing
`PR merge: ~$ELAPSED min` line. `ELAPSED` is minutes since `START_TS`.
