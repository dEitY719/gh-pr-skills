# Fetching Review Material — for gh-pr:review

Read from `SKILL.md` Step 4, to choose between the inline diff and
large-diff delegation and to build `PROMPT_FILE`.

Decide path: if `--paths <path>` (repeatable) was given, always take the
**inline** `gh pr diff` path regardless of PR size — the diff is filtered by
path in `_gh_pr_review_build_prompt`, so a scoped run never routes through
large-diff delegation, and a scope matching no file exits 1 rather than
reviewing an empty diff (dEitY719/dotfiles#1616). Otherwise decide by diff size
(`gh pr view --json additions,deletions`): at or above the threshold in
`../approve/references/large-diff-delegation.md` → follow it; else inline
`gh pr diff`. Append the diff per `references/ai-cli-invocation.md` and write
`(prompt + diff)` to `PROMPT_FILE`.

Never hardcode or reuse a `PROMPT_FILE`; derive it from
`_gh_pr_review_mktemp_prompt "$ai" "$PR_NUMBER"` and do the write plus Step 5
dispatch in the same Bash tool call. Then `rm -f "$PROMPT_FILE"`.
