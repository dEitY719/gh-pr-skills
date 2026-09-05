# gh-pr:create — Step 4 AI Metrics Footer

Detail companion to SKILL.md Step 4. Computes the metrics block and
appends the ai-metrics footer to the PR body temp file `$BODY`.

## Inputs

- `START_TS` — bound in Step 1 (`START_TS=$(date +%s)`).
- The conventional-commit prefix from the first commit subject in the
  range (used for `HUMAN_H` baseline lookup).
- For `feat`, the **number of files changed** in `$BASE_BRANCH..HEAD`
  (used to infer size — small/medium/large).
- `GH_DISABLE_AI_METRICS` env (issue dEitY719/dotfiles#399) — when set to `1`, the
  footer is skipped entirely. The linked issue body is untouched.

## Procedure

1. `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`
2. Read `gh-issue-create/references/metrics-baseline.md` and bind
   `HUMAN_H` by issue type.
3. Read `references/metrics-helper.md` and paste the `compute_pr_tokens`
   snippet **verbatim**. Inputs: `(linked-issue body) + (commit log
   over $BASE_BRANCH..HEAD)` — **never** count `$BODY` (the drafted PR
   body) as the input. That regression produced PR dEitY719/dotfiles#325's
   `~1000 tokens` footer (issue dEitY719/dotfiles#326).
4. Append the footer:

   ```bash
   if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
       : # ai-metrics footer skipped via GH_DISABLE_AI_METRICS
   else
       printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics:gh-pr -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics:gh-pr -->\n\n</details>\n' \
         "$TOKENS" "$HUMAN_H" "$ELAPSED" "$TOKENS" "$HUMAN_H" "$ELAPSED" >> "$BODY"
   fi
   ```

   Soft-fail policy: any error during steps 1–3 warns to stderr and
   continues with placeholder values (`~?`) rather than blocking the PR.

## Emoji exception scope

The four emoji glyphs in the printf above (`<U+1F916> <U+1F4CA> <U+1F464>`) are
the ai-metrics footer exception defined in `CLAUDE.md` — the `<details>`
wrapper + `<!-- ai-metrics:gh-pr -->` block. The exception does not
extend anywhere else in this skill or its other references.
