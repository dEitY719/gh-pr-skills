# Parser Contract — for gh-pr:review

Step 1 delegates to `gh_pr_review_parse` in
`shell-common/functions/gh_pr_review.sh` (issue #664). That function is
the **single source of truth** for the argument surface — the flat
state machine, the closed `--review` enum, the KR-alias normalization,
the `--user` cross-AI rejection, and the exit-code mapping (0 / 1 / 2)
all live there. The bats fixture
`tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh` is now a thin
wrapper around the same function, so any drift between this contract
and the production parser is caught by
`tests/bats/skills/gh_pr_review_arg_parse.bats`.

## Argument shape

Contract this skill depends on (do not duplicate the parser here; read
`shell-common/functions/gh_pr_review.sh` for the authoritative shape):

- `--ai <codex|agy|claude|opencode|hermes>` — required.
- `--review <preset>` — closed enum; KR aliases normalize before
  dispatch.
- `--user <name>` — `--ai claude` only.
- `--no-post-comment` — skips Step 6.
- Positional `<pr-number>` (optional; auto-detect from current branch)
  and `<remote>` (default `origin`).

## KR aliases

The `--review` value is a closed enum normalized to one of `default`,
`quick`, `thorough`, `security`, `performance`. Korean aliases are
mapped to those canonical enum values inside `gh_pr_review_parse`
before dispatch — by the time Step 3 reads the preset, normalization
has already happened. Free-text values are rejected (see exit codes).

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Parse succeeded. |
| 1 | Resolution failure (e.g. unknown claude account, target/PR resolution failed). |
| 2 | Argument-surface error (missing/unknown `--ai`, `--user` with codex/agy/opencode/hermes, free-text `--review` typo). |

## Post-parse setup

- Record `START_TS=$(date +%s)` immediately so Step 6 can compute
  `ELAPSED`.
- Bind `TARGET_REPO` **and** `TARGET_HOST` from one and the same remote
  URL — the `<remote>` positional, default `origin`. This is what
  `_gh_pr_review_resolve_target_repo` already does for the repo half
  (`git remote get-url` → `_gh_parse_owner_repo_url`, no network round
  trip); the host half reads the same URL:

  ```bash
  _SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
  [ -f "$_SC/functions/gh_host.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-}/lib/vendor/shell-common"
  . "$_SC/functions/gh_host.sh"
  REMOTE_URL=$(git remote get-url "${REMOTE:-origin}") || exit 1
  TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
  TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
  export GH_HOST="$TARGET_HOST"
  export TARGET_REPO TARGET_HOST
  ```

  Never derive the repo from `gh repo view` — that answers
  `gh repo set-default`, not the remote this run resolved (#1405).
- Resolve `PR_NUMBER` from the explicit arg, or auto-detect from the
  current branch with `GH_HOST="$TARGET_HOST" gh pr view --json number -q
  .number`. Failing either → exit 1. This is the one call that takes the
  host prefix **without** `--repo`: `gh pr view --repo <slug>` with no PR
  argument is rejected outright (`argument required when using the --repo
  flag`), and the point of this call is to let `gh` read the PR off the
  current branch. `GH_HOST` still pins the server.

## Host targeting rule (issues #1403 / #1407)

Every `gh` call this skill runs carries both halves:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo <owner>/<repo>` names a repo but no host, so `gh` resolves the
slug against its own `gh repo set-default`. On a dual-host login
(github.com + GHES) that silently targets the wrong server — the review
is fetched from, or the comment posted to, a repo nobody asked for.
`export GH_HOST` in Step 1 also makes the sourced helpers in
`shell-common/functions/gh_pr_review.sh` inherit the same host; the
reference files still spell the prefix out so every example is
copy-paste safe.
