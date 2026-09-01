# gh-pr:commit — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | issue-number, remote-name, or `-h`/`--help`/`help` | auto-detected from chat | Link commit to this GitHub issue via `Closes #N` footer |
| 2 | issue-number or remote-name | `origin` | Git remote whose repo owns the issue (#1405) |

**Positional parsing rule (#1405):** a positional consisting only of digits is
the issue number; any other positional is the remote name. Order does not
matter, so `/gh-pr:commit 123`, `/gh-pr:commit upstream`, `/gh-pr:commit 123 upstream`
and `/gh-pr:commit upstream 123` all resolve correctly. The remote defaults to
`origin`; an unknown remote stops the skill with the `git remote -v` list
instead of silently falling back to `origin`.

## Usage

- `/gh-pr:commit` — inspect working tree, draft a commit, auto-detect issue
  from recent chat (`#N`, `Issue #N created`); GitHub target = `origin`
- `/gh-pr:commit 123` — same, but force `Closes #123` in the footer
- `/gh-pr:commit upstream` — same as bare, but the ai-metrics comment and board
  sync target `upstream`'s repo/host instead of `origin`'s
- `/gh-pr:commit 123 upstream` — force `Closes #123` and target `upstream`
- `/gh-pr:commit -h` / `--help` / `help` — print this help

## What the skill does

1. Runs `git status`, `git diff`, `git diff --staged`, `git log --oneline -20`
   unconditionally — the working-tree state is the source of truth.
2. Resolves the issue number (explicit all-digit arg → recent chat scan →
   none) and the target remote (non-digit arg → `origin`), then binds
   `TARGET_REPO`/`TARGET_HOST`/`GH_HOST` from that remote's URL (#1405).
3. Drafts a commit message that mimics the repo's existing style (subject
   line length, conventional-commit prefix usage, footer style).
4. Stages only files relevant to this commit (never `git add -A`).
5. Runs `git commit` via HEREDOC, including the mandatory `Co-Authored-By`
   footer. See `references/commit-message-format.md` for the exact shape.
6. Reports the short hash and subject. Linked issue number printed on a
   second line if one was resolved.

## What the skill will NOT do

- Amend an existing commit (`--amend`) — always creates a new commit.
- Skip hooks (`--no-verify`) or signing (`--no-gpg-sign`).
- Stage `.env`, `credentials.json`, or obvious-secret files — stops and warns.
- Push the commit — that is `/gh-pr:create`'s job.
- Invent an issue number when none is resolvable.
- Fall back to `origin` when the named `[remote]` does not exist — it stops
  and prints `git remote -v` instead.
- Create empty commits.
- Bundle two unrelated changes — asks to split first.

## Good vs. bad invocation

- **Good**: you made edits, type `/gh-pr:commit` — the skill picks a subject
  from the diff, links any recent `#N` from chat, commits, done.
- **Good**: `/gh-pr:commit 42` — same, but forces `Closes #42` regardless of chat.
- **Good**: `/gh-pr:commit 42 upstream` — same, but the metrics comment and board
  sync go to `upstream`'s repo (this is what `gh-flow:issue <N> upstream`
  passes down).
- **Bad**: calling this to push → use `/gh-pr:create` instead.
- **Bad**: calling this with no changes in the tree → skill stops with "nothing to commit".
