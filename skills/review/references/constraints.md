# Constraints (rationale) — for gh-pr:review

The SKILL.md body lists these as terse "Never" rules; the full
rationale lives here.

- **Never submit a decision.** `gh pr review --approve` and
  `--request-changes` are out of scope. This skill collects opinions
  only; the human (or `gh-pr:approve`) decides.
- **Never reply to individual review comments.** That is `gh-pr:reply`'s
  job. This skill writes one aggregate comment per invocation.
- **Never run multiple AI CLIs in one invocation.** Single `--ai`
  value; rerun the command N times for an N-way comparison.
- **Never accept free-text `--review`.** Closed enum + KR aliases only.
  Typos exit 2 cleanly.
- **Never reformat the external AI's stdout.** The user wants raw
  output to judge for themselves.
- **Never block self-authored PRs.** No decision is submitted; the
  self-approve restriction does not apply.
- **Never edit the PR body.** Use `gh pr comment` (append) — `gh pr
  edit --body` silently exits 1 on repos with classic Projects
  attached (issue #326 Bug B). If a future iteration needs body
  mutation, route through `_gh_pr_edit_safe_body` per CLAUDE.md.
- **Never log the external CLI's stderr to a PR comment.** Stderr is
  only used to derive the error-message first line on non-zero exit.
- Honor `GH_DISABLE_AI_METRICS=1` consistently with sister skills:
  skip the entire PR comment (not just the footer).
