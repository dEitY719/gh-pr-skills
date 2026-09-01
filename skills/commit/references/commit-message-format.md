# Commit Message Format — for gh-pr:commit skill

Details of the commit message structure, footer conventions, and the HEREDOC commit command used by the `gh-pr:commit` skill.

## Structure Template

```
<type>(<scope>): <concise summary in imperative mood>

<body explaining the WHY, not the WHAT — the diff shows the what>

Closes #<N>      ← when this commit fully resolves the issue
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Rules

- **Why, not what** — the diff already shows what changed. The body explains motivation, trade-offs, and context.
- **Match the repo's conventions** — if recent commits use `feat:` / `fix:` prefixes, follow suit; if they use plain sentences, follow that. Derive style from `git log --oneline -20`.
- **Issue footer selection** — only two keywords are allowed for the skill:
  - `Closes #N` — default; when the commit fully closes the issue.
  - `Fixes #N` — preferred for bug fixes.
- **Forbidden keywords**: `Refs`, `Resolves`, `See`, `References` — the skill must never generate these.
  - Rationale: `Refs` / `See` / `References` do not trigger GitHub auto-close (breaking project-board automation), and `Resolves` violates the AgentToolbox stacked-closes-rollup policy.
- Cases where no issue footer should be added:
  - No actual issue → omit the footer. Never invent issue numbers.
  - WIP / partial progress (don't want to auto-close) → omit the footer
    and mention `(part of #N)` inline in the body instead.

## HEREDOC Commit Command

Always commit using HEREDOC to preserve multi-line formatting:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<body>

Closes #<N>
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Use single-quoted `'EOF'` to prevent shell expansion inside the message body.
