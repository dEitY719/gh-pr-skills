# gh-pr:create — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | issue-number, remote-name, or `-h`/`--help`/`help` | auto-detected | Link PR to this GitHub issue via `Closes #N` (or `Fixes #N` for bug fixes) in the body |
| 2 | remote-name or issue-number | `origin` | Git remote the PR is pushed to and opened on (dEitY719/dotfiles#1405) |

**Positional parsing rule (dEitY719/dotfiles#1405):** a positional consisting only of digits is
the issue number; any other positional is the remote name. Order does not
matter — `/gh-pr:create 123`, `/gh-pr:create upstream`, `/gh-pr:create 123 upstream` all parse. The
remote drives both the `gh` target (host + `--repo`) and the git plumbing
(`git fetch <remote>`, `<remote>/<base>` ranges, `git push -u <remote> HEAD`).
An unknown remote stops the skill with the `git remote -v` list — there is no
silent fallback to `origin`.

## Stacked-PR flags (mutually exclusive)

| Flag | Effect |
|---|---|
| `--no-stack` | force base = repo default branch, skip auto-detect |
| `--base <branch>` | force base = `<branch>` (any branch name) |

Auto-detect (default) is a no-op on solo / non-stacked repos. See
"Behavior" below for what triggers it.

## Usage

- `/gh-pr:create` — push the current branch if needed, then open a PR.
  Resolves base via auto-detect (default branch on solo repos).
- `/gh-pr:create 123` — same, force-link to issue `#123`.
- `/gh-pr:create upstream` — push and open the PR on `upstream` instead of `origin`.
- `/gh-pr:create 123 upstream` — both (this is what `gh-flow:issue <N> upstream`
  passes down, dEitY719/dotfiles#1405).
- `/gh-pr:create --no-stack` — auto-detect off, base = default branch.
- `/gh-pr:create --base release/v2.0` — auto-detect off, custom base branch.
- `/gh-pr:create -h` / `--help` / `help` — print this help.

## Behavior

Auto-detect fires only when **both** conditions hold:

1. The repo opts into stacked PRs (one of: workflow file
   `.github/workflows/stacked-closes-rollup.yml`, the keywords
   `claude-enter-issue` / `stacked PR` / `Depends on #` in
   `CLAUDE.md` / `AGENTS.md` / `.claude/github-integration.md`, or an
   `agent-toolbox/` directory).
2. There is exactly one open PR whose head ref is an ancestor of HEAD
   *and* yields a more recent merge-base than the default branch.

Otherwise the base falls back to the repo default branch — solo /
non-stacked repos (the dotfiles default) see no behavioural change.

## Examples

```
# dotfiles solo (auto-detect inactive — no signals)
$ /gh-pr:create                        →  base=main, no Depends footer

# Working in a stacked-PR repo, parent unique
$ /gh-pr:create                        →  "Stacking on PR #201 (auto-detected)"
                                   base=feat/parent-branch
                                   body has "Depends on #201"

# Auto-detect was wrong — escape hatch
$ /gh-pr:create --no-stack             →  base=main forced
$ /gh-pr:create --base release/v2.0    →  base=release/v2.0
```

## What the skill does

1. Parses args (`[N]` / `[remote]` / `--no-stack` / `--base`), then resolves
   the base branch via the stacked-PR auto-detect flow (see
   `references/stacked-pr.md`). Fetches `<remote>` to make sure the range
   is computed against up-to-date refs.
2. Reads **all** commits in `<base>..HEAD` — the PR body must cover every
   commit, not only HEAD. Groups them by theme for the Summary.
3. Resolves the linked issue using the same precedence as `gh-pr:commit`:
   explicit arg → recent chat → commit footers → none.
4. Drafts title + body per `references/pr-body-template.md`, matching the
   language dominant in existing commits (Korean commits → Korean PR).
   When stacked on a parent PR, inserts `Depends on #N` in the body.
5. Pushes the branch (`git push -u <remote> HEAD` if no upstream or
   mispaired, `git push` if ahead). Diverged upstream → stops and asks;
   never force-pushes on its own.
6. Creates the PR via
   `GH_HOST=<host> gh pr create --repo <owner>/<repo> --assignee @me --base "$BASE_BRANCH"`
   using a `mktemp` body file. Always self-assigns. Host and repo are both
   read from `<remote>`'s URL (`origin` unless `[remote]` says otherwise), so a
   `gh` logged into both github.com and a GHES instance cannot open the PR on
   the wrong server (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1405).
7. Applies labels derived from conventional-commit types (feat, fix, docs,
   etc.) plus scope labels — but only labels that **already exist** in the
   repo. Never creates new labels.
8. Prints only `PR created: <url>`.

## What the skill will NOT do

- Force-push without explicit user approval.
- Run auto-stack detection on a repo without stacked-PR signals — solo
  repos always default to the repo's default branch.
- Combine `--no-stack` / `--base` (mutually exclusive, rc=2 abort).
- Fall back to `origin` when the named `[remote]` does not exist — it stops
  and prints `git remote -v` instead.
- Mutate parent PR bodies — cross-PR rollup is the downstream repo's
  job (e.g. AgentToolbox `stacked-closes-rollup.yml`).
- Include the `🤖 Generated with Claude Code` footer unless the repo
  already uses that convention in existing PRs.
- Skip "minor" commits in the Summary — the range is the contract.
- Create new labels — only applies labels that exist.
- Open a PR when the branch has no commits ahead of base, or when you're
  currently on the base branch (stops with guidance instead).

## Good vs. bad invocation

- **Good**: Feature branch with 3 commits, `/gh-pr:create` — body covers all 3,
  links any `#N` in chat, returns the URL.
- **Good**: `/gh-pr:create 42` after a hotfix — body includes `Closes #42`.
- **Good**: AgentToolbox stacked work, `/gh-pr:create` — auto-detects parent
  PR and inserts `Depends on #N`.
- **Good**: Hotfix landing on a release branch, `/gh-pr:create --base release/v2.0`.
- **Bad**: running on `main` — skill stops with "create a feature branch first".
- **Bad**: running with an empty `<base>..HEAD` — skill stops with "nothing to PR".
- **Bad**: `/gh-pr:create --no-stack --base main` — flags are mutually
  exclusive, skill aborts before push.
