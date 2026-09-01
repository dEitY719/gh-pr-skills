# gh-pr:create — Accepted Options

| Argument | Description | Default |
|----------|-------------|---------|
| `[N]` (positional) | Legacy `/gh-pr:create 123` form — overrides issue auto-detection. All-digit positional. | — |
| `[remote]` (positional) | Git remote that owns the PR. Non-digit positional (#1405). Drives both the `gh` target (host + `--repo`) and the git plumbing: `git fetch <remote>`, `<remote>/$BASE_BRANCH` ranges, `git push -u <remote> HEAD`. Unknown remote → stop with `git remote -v`, never a silent `origin` fallback. | `origin` |
| `--no-stack` | Force a non-stacked PR even when stacked-PR signals fire. | off |
| `--base <branch>` | Explicit base branch; bypasses stacked-PR detection. | repo default |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `GH_PR_LINT_BYPASS=1` (env) | Skip Step 4.5 lint guard. | off |
| `DOTFILES_ROOT` (env) | Root used to source `gh_pr_lint.sh`. | `$HOME/dotfiles` |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

Positional order does not matter: a positional made only of digits is `[N]`,
any other positional is `[remote]` — `/gh-pr:create 123`, `/gh-pr:create upstream` and
`/gh-pr:create 123 upstream` all parse (#1405).

`--no-stack` and `--base` are mutually exclusive — see Step 1a exit codes.
Auto-detected parent PR must be `OPEN` — refuses (rc=5) otherwise.
