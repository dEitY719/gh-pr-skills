# Constraints — hard rules the gh-pr:create skill must never violate

These apply across every step. If any rule would be broken, stop and ask
the user instead of proceeding.

## Force-push

Never force-push without explicit user approval. If the upstream has
diverged from local, surface the divergence and wait for the user to say
either "force push" or "rebase first" — do not pick for them.

## Base branch

The base branch is decided in Step 1a (`references/stacked-pr.md`):

1. Default branch
   (`GH_HOST="$TARGET_HOST" gh repo view "$GH_REPO" --json defaultBranchRef`)
   when the repo has no stacked-PR signals — solo / non-stacked workflow.
2. Auto-detected parent PR's head ref when the repo opts into stacked
   PRs *and* exactly one open PR is an ancestor of HEAD.
3. The user-supplied target when one of `--no-stack` / `--base <branch>`
   was passed (mutually exclusive — combining the two aborts).

Never target any base outside those three sources. In particular,
never auto-stack on a repo that does not match `is_stacked_pr_repo`,
and never silently downgrade to the default branch when the user
explicitly passed `--base`.

## Parent PR state (stacked auto-detect)

When Stage 2 of `references/stacked-pr.md` selects a parent PR for
stacking, the parent's GitHub state **must** be `OPEN`. Re-check via
`GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$GH_REPO" --json state` right
before the base branch decision is committed (see `assert_parent_pr_open`). Closed or merged parents abort
with rc=5 plus a one-line recovery hint — never silently fall back to
the default branch, since that would change the PR's meaning without
asking the user.

## AI footers

Never include `🤖 Generated with` or any "Claude Code" footer in the PR
body **unless** the repo already uses that convention in existing PRs.
Check recent merged PRs
(`GH_HOST="$TARGET_HOST" gh pr list --repo "$GH_REPO" --state merged --limit 5`)
before deciding.

## Commit coverage

Never skip commits in the Summary because "they're minor" — the commit
range `<base>..HEAD` is the contract. A 5-commit PR mentions all 5
concerns. If commits are truly trivial (e.g. typo fixes), group them but
still acknowledge them.

## Host and repo targeting (dEitY719/dotfiles#1403)

Never call `gh` without both `GH_HOST="$TARGET_HOST"` and `--repo "$GH_REPO"`,
and never derive those two from different sources — Step 1a-0 reads both from
the one `git remote get-url "$REMOTE"` URL (`$REMOTE` = the `[remote]`
positional, `origin` by default, dEitY719/dotfiles#1405). Without `--repo`, `gh` follows its
own `gh repo set-default` rather than git's remote; when the user is
authenticated to both github.com and a GHES instance and those two disagree,
`gh` queries the wrong server and **succeeds** — no error, just wrong data.
That is how an OPEN issue came back as "doesn't exist" in dEitY719/dotfiles#1403.

Never "fix" a surprising `gh` result (missing PR, missing label, unexpected
default branch) by retrying or by relaxing the target. Check the host first.

## Output discipline

The final report contains **only** the PR URL — no preamble, no summary
of what the PR does, no next-step suggestions. Reviewers open GitHub
directly.
