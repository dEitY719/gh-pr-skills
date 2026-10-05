# Branch State — upstream pairing + base-branch recovery for `gh-pr:create`

Applied in Step 1b of `gh-pr:create/SKILL.md`, before anything is pushed. Answers
two questions the old policy conflated:

1. **Pairing** — where does `git push` / `git pull` actually point?
   (`@{u}`). Wrong answer here silently pushes a feature branch onto the
   base branch — see `references/push-and-create.md` F-1 row.
2. **Position** — how far is HEAD behind `$REMOTE/$BASE_BRANCH`?
   (`git log HEAD.."$REMOTE/$BASE_BRANCH"`). Wrong answer here means a
   missing rebase.

`$REMOTE` is the `[remote]` positional bound in Step 1a-0 (dEitY719/dotfiles#1405); it defaults
to `origin`, which is why every function below defaults its remote parameter
to `origin` too. Wherever this file says `origin`, read "the target remote".

> The executable SSOT for `gh_pr_normalize_upstream`,
> `gh_pr_upstream_is_mispaired`, `gh_pr_push_action`, `gh_pr_commit_type`,
> `gh_pr_branch_name`, `gh_pr_base_branch_decision` and the Step 1b dispatch
> is `lib/branch-state.sh` (relative to `skills/create/`), called as
> `branch-state.sh dispatch` (Step 1b) and
> `branch-state.sh push-action <cur> <upstream> <diverged> [remote]` (Step 5).
> dotfiles' bats suite (`tests/bats/skills/gh_pr_push_policy.bats`, fixture
> `tests/bats/skills/_fixtures/gh_pr_push_policy.sh`) mirrors the same
> functions — when the script changes, mirror the change there too.

**Test-coverage boundary.** The mirroring above covers the *functions* only:
they are pure string/set logic, so bats exercises them with plain arguments.
The Step 1b dispatch (`branch-state.sh dispatch`) is **not** bats-covered
— it performs live `git switch -c` and `git branch -f` mutations, which the
fixture's no-live-git philosophy deliberately excludes, and this repo's skill
bats suites have no scratch-repo harness for branch mutation to reuse. `tests/create-lib.sh` covers it in a
throwaway scratch repo instead (on-base auto-branch + rewind, nothing-to-pr,
existing-branch refusal).

## F-1 — upstream / branch-name mismatch

`git worktree add ... -b <branch>` started from `origin/main` leaves the new
branch tracking `origin/main` (git's `branch.autoSetupMerge` default) until
the first `push -u`. That is the **normal** outcome, not a misconfiguration.
In that state:

| `push.default` | Result of a bare `git push` |
|---|---|
| `simple` (git 2.0+ default) | aborts: `fatal: The upstream branch ... does not match the name of your current branch.` |
| `upstream` | the feature branch's commits land **directly on the upstream branch** (measured: `feature -> main`) — no PR, no review, silently |

Both were reproduced on git 2.43.0 / Linux. The fix is always
`git push -u "$REMOTE" HEAD`, which re-pairs the branch.

Secondary symptom: while mispaired, `git status`'s ahead/behind is computed
against the *base* ref, so the branch can look "diverged" when what it
actually needs is a rebase. The mispair check therefore runs **before** the
divergence check — the divergence verdict is not trustworthy until the
pairing is fixed.

### Accepted trade-off (known side effect)

If a user *intentionally* tracks a differently-named remote branch (local
`fix` -> `origin/hotfix-2026-08`), `git push -u "$REMOTE" HEAD` creates a new
same-named remote branch (`origin/fix`) instead of honouring the old
tracking target. This is accepted: `gh-pr:create`'s job is "open a PR from the
current branch", and a same-named remote branch is the normal, expected
state for that. Users who want the old pairing back can restore it with
`git branch -u <remote>/<other> <branch>` after the PR is merged.

Implemented in `lib/branch-state.sh` (`gh_pr_normalize_upstream`,
`gh_pr_upstream_is_mispaired`, `gh_pr_push_action` — the `push-action`
subcommand).

## F-2 — session started on the base branch

Roughly 1 in 10 sessions starts chatting on local `main`, then edits and
commits before ever branching. Step 1b no longer stops there: it moves the
local-only commits onto a generated feature branch, rewinds the local base
branch, and continues.

**Out of scope, do not touch:** a working tree that is merely *dirty*
(uncommitted changes) on the base branch. The existing "empty range →
nothing to PR" condition already covers it, and committing is `gh-pr:commit`'s
job, not this skill's.

**Interaction with F-1:** a freshly created branch has no upstream at all,
so it lands on row 1 of the push table (`git push -u "$REMOTE" HEAD`). No
special-casing is needed — the F-1 mispair row never fires for it.

### Branch naming

Commit titles in this repo are Korean, so title-based slugify produces empty
or garbage slugs. Only the ASCII conventional-commit prefix is used:

| Condition | Branch name |
|---|---|
| Issue number resolved in Step 3 | `<type>/issue-<N>` |
| No issue number | `<type>/<YYYYMMDD>-<short-sha>` |

Both forms are ASCII-safe and deterministic. `<YYYYMMDD>` comes from the
first range commit's author date and `<short-sha>` from that same commit —
never `date +%s` or a random suffix, so the name is reproducible and
testable.

Implemented in `lib/branch-state.sh` (`gh_pr_commit_type`, `gh_pr_branch_name`).

### Rewind guard

Rewinding the local base branch is **mandatory, not optional** — this is the
step people forget. Without it the local base stays ahead of
`$REMOTE/$BASE_BRANCH` and corrupts the next session's pull/push:

```sh
git branch -f "$BASE_BRANCH" "$REMOTE/$BASE_BRANCH"
```

Auto-rewind only when this holds; otherwise warn and leave the base alone:

- `git rev-list "$REMOTE/$BASE_BRANCH..$BASE_BRANCH"` is exactly the commit
  set that moved to the new branch (no stragglers left behind).

**Why there is no separate "already pushed to the remote" condition** (it was
removed after review of PR dEitY719/dotfiles#1318): Step 1b always runs `git fetch "$REMOTE"`
*before* this decision. After that fetch, any local commit that had already
reached `$REMOTE/$BASE_BRANCH` by another path is, by definition, reachable
from `$REMOTE/$BASE_BRANCH` — so `git rev-list "$REMOTE/$BASE_BRANCH..$BASE_BRANCH"`
excludes it and the range comes back empty. That case therefore already
lands on `nothing-to-pr`, which is the same stop it needs. A dedicated
`stop-already-pushed` branch comparing `$REMOTE/$BASE_BRANCH..HEAD` against
`git rev-list "$REMOTE/$BASE_BRANCH"` was not merely redundant but *unreachable*:
the `A..B` range operator already subtracts everything reachable from `A`, so
the two sets can never intersect. Do not re-add that check.

The rewound commits are local-only, therefore `reflog`-recoverable. Print
one recovery hint right after rewinding:

```
Local '<base>' rewound to <remote>/<base>. Recover with:
  git reflog show <base>   # then: git branch -f <base> <old-sha>
```

Implemented in `lib/branch-state.sh` (`gh_pr_base_branch_decision`).

### Step 1b state gathering (run first, one message)

Using `$BASE_BRANCH` — never a hard-coded `main`, since Step 1a may have bound
it to a parent PR's head ref (`references/stacked-pr.md`) — run in a single
message: `git rev-parse --abbrev-ref HEAD`, `git status`, `git fetch origin`,
`git log --oneline "$BASE_BRANCH"..HEAD`, `git diff "$BASE_BRANCH"...HEAD`,
plus these **two separate** probes. They answer different questions; never
conflate them:

```sh
git rev-parse --symbolic-full-name @{u}        # pairing target (push/pull direction)
git log HEAD..origin/"$BASE_BRANCH" --oneline  # how far behind base (rebase needed?)
```

### How Step 1b ties it together

`branch-state.sh dispatch` (env `BASE_BRANCH`, `REMOTE`, `ISSUE_NUMBER`)
decides from `git rev-list "$REMOTE/$BASE_BRANCH..$BASE_BRANCH"` and
`..HEAD`; on `auto-branch-*` it `git switch -c`s the generated name —
**guarded**: if that branch already exists it exits 1 before any rewind, since
HEAD is still the base branch — then rewinds per the guard above and prints
the recovery hint. Its last stdout line is always `BRANCH_STATE=<outcome>`.

### Outcomes

- `not-on-base` — normal path, continue to Step 2.
- `nothing-to-pr` — stop. The `$BASE_BRANCH..HEAD` range is empty; this covers
  both "nothing committed yet" and "the commits are already on
  `origin/$BASE_BRANCH`".
- `auto-branch-and-rewind` / `auto-branch-warn-only` — a feature branch is
  created from the local-only commits, the local base branch is rewound to
  `origin/$BASE_BRANCH` when the rewind guard allows, and the run continues.

`ISSUE_NUMBER` may still be empty at this point (Step 3 resolves it from the
conversation); the fallback `<type>/<YYYYMMDD>-<short-sha>` form covers that.
`BASE_BRANCH` is whatever Step 1a bound — possibly a parent PR's head ref
(`references/stacked-pr.md`), never a hard-coded `main`. `REMOTE` is whatever
Step 1a-0 bound from the `[remote]` positional, defaulting to `origin` (dEitY719/dotfiles#1405).
Pass it as the trailing argument of `gh_pr_push_action` /
`gh_pr_upstream_is_mispaired` in Step 5 — omitting it keeps the older
`origin` behaviour from before dEitY719/dotfiles#1405.
