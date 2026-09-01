# Branch State — upstream pairing + base-branch recovery for `gh-pr:create`

Applied in Step 1b of `gh-pr:create/SKILL.md`, before anything is pushed. Answers
two questions the old policy conflated:

1. **Pairing** — where does `git push` / `git pull` actually point?
   (`@{u}`). Wrong answer here silently pushes a feature branch onto the
   base branch — see `references/push-and-create.md` F-1 row.
2. **Position** — how far is HEAD behind `$REMOTE/$BASE_BRANCH`?
   (`git log HEAD.."$REMOTE/$BASE_BRANCH"`). Wrong answer here means a
   missing rebase.

`$REMOTE` is the `[remote]` positional bound in Step 1a-0 (#1405); it defaults
to `origin`, which is why every function below defaults its remote parameter
to `origin` too. Wherever this file says `origin`, read "the target remote".

> SSOT for the bash bound to `gh_pr_normalize_upstream`,
> `gh_pr_upstream_is_mispaired`, `gh_pr_push_action`,
> `gh_pr_commit_type`, `gh_pr_branch_name`, and
> `gh_pr_base_branch_decision`. The bats regression suite at
> `tests/bats/skills/gh_pr_push_policy.bats` mirrors the same functions
> verbatim via `tests/bats/skills/_fixtures/gh_pr_push_policy.sh` — when
> this file changes, mirror the change there too (and vice versa).

**Test-coverage boundary.** The mirroring above covers the *functions* only:
they are pure string/set logic, so bats exercises them with plain arguments.
The "How Step 1b ties it together" dispatch block below is **not** bats-covered
— it performs live `git switch -c` and `git branch -f` mutations, which the
fixture's no-live-git philosophy deliberately excludes, and this repo's skill
bats suites have no scratch-repo harness for branch mutation to reuse. That
glue script is documentation reviewed by hand; treat edits to it with the care
that unverified code deserves.

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

```sh
# Normalises an upstream ref to "<remote>/<branch>".
# `git rev-parse --symbolic-full-name @{u}` yields "refs/remotes/origin/main";
# `--abbrev-ref` yields "origin/main". Both must compare equal.
gh_pr_normalize_upstream() {
    local _u="${1-}"
    _u="${_u#refs/remotes/}"
    printf '%s' "$_u"
}

# Returns 0 when the upstream points at a different-named branch, or at the
# right-named branch on a *different remote* than the one this run targets.
# No upstream at all → 1 (that is row 1 of the push table, not a mispair).
#   $1  upstream ref (may be empty)
#   $2  current branch name
#   $3  target remote (optional, default "origin" — the [remote] positional, #1405)
gh_pr_upstream_is_mispaired() {
    local _upstream _current="${2-}" _remote="${3:-origin}"
    _upstream=$(gh_pr_normalize_upstream "${1-}")
    [ -n "$_upstream" ] || return 1
    [ -n "$_current" ] || return 1
    [ "$_upstream" = "$_remote/$_current" ] && return 1
    return 0
}

# Prescribes the push command for the current upstream state.
#   $1  current branch name
#   $2  upstream ref ("" when the branch has no upstream)
#   $3  "diverged" when the branch and its upstream have both moved
#   $4  target remote (optional, default "origin" — the [remote] positional, #1405)
# Output: "push -u <remote> HEAD" | "push" | "STOP"
gh_pr_push_action() {
    local _current="${1-}" _upstream="${2-}" _diverged="${3-}" _remote="${4:-origin}"

    if [ -z "$(gh_pr_normalize_upstream "$_upstream")" ]; then
        printf 'push -u %s HEAD\n' "$_remote"
        return 0
    fi
    # F-1 — checked BEFORE divergence: a mispaired branch's ahead/behind is
    # measured against the wrong ref, so "diverged" cannot be trusted yet.
    if gh_pr_upstream_is_mispaired "$_upstream" "$_current" "$_remote"; then
        printf 'push -u %s HEAD\n' "$_remote"
        return 0
    fi
    if [ "$_diverged" = "diverged" ]; then
        printf 'STOP\n'
        return 0
    fi
    printf 'push\n'
}
```

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

```sh
# Parses the conventional-commit type from a commit title.
# Non-ASCII (Korean) subject text is ignored entirely — only the ASCII
# prefix is read, which is why there is no slugify step here.
# Unknown / prefix-less titles fall back to "chore".
gh_pr_commit_type() {
    local _title="${1-}" _type
    _type=$(printf '%s' "$_title" |
        sed -n 's/^\([a-z][a-z]*\)\(([^)]*)\)\{0,1\}!\{0,1\}:.*/\1/p')
    case "$_type" in
        feat|fix|refactor|perf|docs|test|chore|style|build|ci|revert) ;;
        *) _type=chore ;;
    esac
    printf '%s' "$_type"
}

# Builds the auto-created branch name.
#   $1  conventional-commit type (from gh_pr_commit_type)
#   $2  issue number ("" when unresolved)
#   $3  YYYYMMDD of the first range commit  (fallback form only)
#   $4  short sha of the first range commit (fallback form only)
gh_pr_branch_name() {
    local _type="${1-}" _issue="${2-}" _date="${3-}" _sha="${4-}"
    case "$_type" in
        feat|fix|refactor|perf|docs|test|chore|style|build|ci|revert) ;;
        *) _type=chore ;;
    esac
    if printf '%s' "$_issue" | grep -qE '^[1-9][0-9]*$'; then
        printf '%s/issue-%s\n' "$_type" "$_issue"
        return 0
    fi
    printf '%s/%s-%s\n' "$_type" "$_date" "$_sha"
}
```

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
removed after review of PR #1318): Step 1b always runs `git fetch "$REMOTE"`
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

```sh
# Normalises a whitespace/newline-separated SHA list into a sorted set.
_gh_pr_normalize_sha_set() {
    printf '%s\n' "${1-}" | tr -s '[:space:]' '\n' | grep -E '^[0-9a-fA-F]+$' | sort -u
}

# Decides what Step 1b does when the session is sitting on the base branch.
#   $1  current branch
#   $2  base branch
#   $3  SHAs from `git rev-list "$REMOTE/$BASE..$BASE"` (local-only commits)
#   $4  SHAs that would move to the new feature branch
# Output (stdout), one of:
#   not-on-base            — normal path, nothing to do here
#   nothing-to-pr          — no local-only commits (dirty tree is gh-pr:commit's job)
#   auto-branch-and-rewind — create branch, then `git branch -f` the base
#   auto-branch-warn-only  — create branch, warn, do NOT rewind the base
#
# There is deliberately no `stop-already-pushed` output. Step 1b fetches
# $REMOTE before deciding, so commits already on $REMOTE/$BASE drop out of the
# $3 range and land on `nothing-to-pr` instead — see "Rewind guard" above.
gh_pr_base_branch_decision() {
    local _current="${1-}" _base="${2-}"
    local _local_only _moved

    if [ "$_current" != "$_base" ]; then
        printf 'not-on-base\n'
        return 0
    fi

    _local_only=$(_gh_pr_normalize_sha_set "${3-}")
    _moved=$(_gh_pr_normalize_sha_set "${4-}")

    if [ -z "$_local_only" ]; then
        printf 'nothing-to-pr\n'
        return 0
    fi

    # Defensive guard for the function's general contract, not a live branch:
    # the single real call site below only runs with CUR == BASE, where
    # $REMOTE/$BASE..HEAD and $REMOTE/$BASE..$BASE are the same range, so
    # _local_only == _moved always holds and warn-only cannot fire today.
    if [ "$_local_only" = "$_moved" ]; then
        printf 'auto-branch-and-rewind\n'
    else
        printf 'auto-branch-warn-only\n'
    fi
}
```

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

```sh
REMOTE="${REMOTE:-origin}"
CUR=$(git rev-parse --abbrev-ref HEAD)
UPSTREAM=$(git rev-parse --symbolic-full-name @{u} 2>/dev/null)

DECISION=$(gh_pr_base_branch_decision "$CUR" "$BASE_BRANCH" \
    "$(git rev-list "$REMOTE/$BASE_BRANCH..$BASE_BRANCH" 2>/dev/null)" \
    "$(git rev-list "$REMOTE/$BASE_BRANCH..HEAD" 2>/dev/null)")

case "$DECISION" in
    not-on-base) ;;                      # normal path
    nothing-to-pr)       exit 0 ;;       # nothing to PR (incl. already-pushed)
    auto-branch-and-rewind|auto-branch-warn-only)
        FIRST=$(git rev-list "$REMOTE/$BASE_BRANCH..HEAD" | tail -n 1)
        NEW_BRANCH=$(gh_pr_branch_name \
            "$(gh_pr_commit_type "$(git log -1 --format=%s "$FIRST")")" \
            "$ISSUE_NUMBER" \
            "$(git log -1 --format=%ad --date=format:%Y%m%d "$FIRST")" \
            "$(git rev-parse --short "$FIRST")")
        # MUST be guarded: on failure (e.g. $NEW_BRANCH already exists from a
        # partial earlier run) HEAD is still the base branch, and rewinding it
        # below would yank commits out from under the user's feet.
        if ! git switch -c "$NEW_BRANCH"; then
            printf "error: branch '%s' already exists — resolve manually (git branch -D '%s', or pick a different issue), then re-run.\n" \
                "$NEW_BRANCH" "$NEW_BRANCH" >&2
            exit 1
        fi
        if [ "$DECISION" = "auto-branch-and-rewind" ]; then
            git branch -f "$BASE_BRANCH" "$REMOTE/$BASE_BRANCH"
            printf "Local '%s' rewound to %s/%s. Recover with:\n" \
                "$BASE_BRANCH" "$REMOTE" "$BASE_BRANCH"
            printf '  git reflog show %s\n' "$BASE_BRANCH"
        else
            printf "warning: local '%s' still holds commits that did not move — not rewinding.\n" \
                "$BASE_BRANCH" >&2
        fi
        ;;
esac
```

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
Step 1a-0 bound from the `[remote]` positional, defaulting to `origin` (#1405).
Pass it as the trailing argument of `gh_pr_push_action` /
`gh_pr_upstream_is_mispaired` in Step 5 — omitting it keeps the pre-#1405
`origin` behaviour.
