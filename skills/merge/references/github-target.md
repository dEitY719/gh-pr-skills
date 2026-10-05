# gh-pr:merge — GitHub Target Binding (dEitY719/dotfiles#1403, dEitY719/dotfiles#1407)

Run this in Step 1, **before any `gh` call**.

## Bind the target

`remote` is the third positional (default `origin`). Resolve the repo **and**
the host from one and the same remote URL, then export the host so the helpers
this skill sources (`gh_project_status.sh`, `gh_pr_edit_safe.sh`) inherit it:

The binding lives in `lib/github-target.sh` (relative to `skills/merge/`);
`SKILL.md` Step 1 holds the guarded call. Contract:

| | |
|---|---|
| Input | `[remote]` (default `origin`) |
| stdout | one `export SHELL_COMMON=… GH_HOST=… TARGET_REPO=… TARGET_HOST=…` line, values single-quoted, for the caller to `eval` |
| Loader | HARD tier ladder: tier 1 `$DOTFILES_ROOT` (default `$HOME/dotfiles`), tier 2 guarded `$CLAUDE_PLUGIN_ROOT/lib/vendor`, no cwd tier, tier 5 stops |
| Exit | `0` bound; `1` no usable shell-common, unknown remote, or an unparsable remote URL — stdout stays empty, so nothing half-bound is ever eval'd |

`tests/plugin-root-tier5.sh` §2-4 runs it against a planted cwd copy and a PATH
imposter; `tests/merge-lib.sh` covers the binding itself.

An unknown remote stops the run with `git remote -v` — never a silent `origin`
fallback.

## Host targeting rule

Every `gh` call in this skill — `gh pr view`, `gh pr checks`, `gh pr merge`,
`gh api` — runs as:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`gh api` has no `--repo` flag: the repo goes in the path
(`repos/$TARGET_REPO/...`) and the `GH_HOST=` prefix stays.

## Why

A bare `gh` follows gh CLI's own `gh repo set-default` instead of git's
`$REMOTE`, and `--repo <owner>/<repo>` carries no host at all. On a dual-host
login (github.com + GHES) the slug then resolves against the wrong server
**without an error** — the silent misroute dEitY719/dotfiles#1403 hit. For this skill that
misroute lands on `gh pr merge --delete-branch`, the most destructive write in
the repo, so both halves are mandatory.
