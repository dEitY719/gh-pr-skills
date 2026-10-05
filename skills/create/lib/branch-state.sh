#!/usr/bin/env bash
# gh-pr:create Step 1b (dispatch) and Step 5 (push policy) — branch state.
#
#   BASE_BRANCH=<base> REMOTE=<remote> ISSUE_NUMBER=<N|""> \
#       bash skills/create/lib/branch-state.sh dispatch
#   bash skills/create/lib/branch-state.sh push-action <cur> <upstream> <diverged|""> [remote]
#
# dispatch     decides what to do when the session sits on the base branch
#              (F-2) and, for auto-branch-*, switches to the generated branch
#              and rewinds the local base when the guard allows. Its LAST
#              stdout line is always `BRANCH_STATE=<outcome>`:
#                not-on-base | nothing-to-pr (stop: nothing to PR)
#                | auto-branch-and-rewind | auto-branch-warn-only
#              exit 0, or 1 when the generated branch already exists (HEAD is
#              then still the base branch and nothing was rewound).
# push-action  prints the Step 5 push command for the upstream state (F-1):
#              `push -u <remote> HEAD` | `push` | `STOP` (ask before force).
#
# Run the "Step 1b state gathering" probes first (references/branch-state.md);
# `git fetch "$REMOTE"` must precede `dispatch` — the rewind guard relies on it.
# Rationale, naming and outcome table: references/branch-state.md.
# Guard: tests/create-lib.sh.

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
#   $3  target remote (optional, default "origin" — the [remote] positional, dEitY719/dotfiles#1405)
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
#   $4  target remote (optional, default "origin" — the [remote] positional, dEitY719/dotfiles#1405)
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

# --- Dispatch ("How Step 1b ties it together") --------------------------------
_bs_dispatch() {
    REMOTE="${REMOTE:-origin}"
    CUR=$(git rev-parse --abbrev-ref HEAD)
    DECISION=$(gh_pr_base_branch_decision "$CUR" "$BASE_BRANCH" \
        "$(git rev-list "$REMOTE/$BASE_BRANCH..$BASE_BRANCH" 2>/dev/null)" \
        "$(git rev-list "$REMOTE/$BASE_BRANCH..HEAD" 2>/dev/null)")

    case "$DECISION" in
        not-on-base) ;;                      # normal path
        nothing-to-pr) ;;                    # nothing to PR (incl. already-pushed) — caller stops
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

    printf 'BRANCH_STATE=%s\n' "$DECISION"
}

case "${1-}" in
    dispatch)
        [ -n "${BASE_BRANCH:-}" ] || { printf 'branch-state.sh dispatch: BASE_BRANCH is unset (Step 1a binds it)\n' >&2; exit 2; }
        _bs_dispatch ;;
    push-action) shift; gh_pr_push_action "$@" ;;
    *) printf 'usage: branch-state.sh dispatch | push-action <cur> <upstream> <diverged> [remote]\n' >&2; exit 2 ;;
esac
