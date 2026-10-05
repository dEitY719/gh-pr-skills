# gh-pr:commit — Positional Args and GitHub Target (dEitY719/dotfiles#1403, dEitY719/dotfiles#1405)

Step 1 parses the positionals and resolves the host and repo from the chosen
remote's URL in the same message that inspects the working tree, then exports
them for Step 5.

## Positional args (dEitY719/dotfiles#1405)

`/gh-pr:commit [issue-number] [remote]` — a positional made only of digits is the
issue number, any other positional is the remote name. `/gh-pr:commit 123`,
`/gh-pr:commit upstream`, `/gh-pr:commit 123 upstream` all work; bare `/gh-pr:commit` is
unchanged. Remote defaults to `origin`.

## Bind the target

If `git remote get-url "$REMOTE"` fails, stop with the available-remotes list
(`git remote -v`) and `Error: remote '<name>' not found. Available remotes:` —
never fall back to `origin` silently, which masks typos and posts metrics to
the wrong repo (same Failure rule as
`gh-issue-implement/references/repo-resolution.md`).

The binding lives in `lib/github-target.sh` (relative to `skills/commit/`);
`SKILL.md` Step 1 holds the guarded call. Contract:

| | |
|---|---|
| Input | `[remote]` (default `origin`) |
| stdout | one `export SHELL_COMMON=… GH_HOST=… TARGET_REPO=… TARGET_HOST=… REMOTE=…` line, values single-quoted, for the caller to `eval` |
| Loader | HARD tier ladder: tier 1 `$DOTFILES_ROOT` (default `$HOME/dotfiles`), tier 2 guarded `$CLAUDE_PLUGIN_ROOT/lib/vendor`, no cwd tier, tier 5 stops |
| Exit | `0` bound; `1` no usable shell-common or unknown remote — stdout stays empty, so nothing half-bound is ever eval'd |

`tests/commit-lib.sh` is the offline guard.

Every `gh` call in Step 5 is then
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"`.

## Why

A bare `gh` follows gh CLI's own `gh repo set-default`, not git's `$REMOTE`; on
a dual-host login (github.com + GHES) that posts to the wrong server with no
error. `export` is what carries the host into `gh_project_status.sh`, which
calls `gh` on its own — and it is what makes `/gh-pr:commit <N> upstream` sync
`upstream`'s board rather than `origin`'s.
