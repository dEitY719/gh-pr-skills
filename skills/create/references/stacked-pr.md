# Stacked PR Auto-Detection — Stage 1/2 logic for `gh-pr:create`

Applied in Step 1 of `gh-pr:create/SKILL.md`. Decides the PR's base branch — and
when applicable, an explicit parent PR — without making the user think
about flags. Solo / non-stacked repos (the dotfiles default) see no
behavioural change.

> SSOT for the bash bound to `is_stacked_pr_repo`,
> `parse_stacked_args`, and `find_parent_pr_candidates`. The bats
> regression suite at `tests/bats/skills/gh_pr_stacked_detect.bats`
> mirrors the same functions verbatim via
> `tests/bats/skills/_fixtures/gh_pr_stacked_detect.sh` — when this
> file changes, mirror the change there too (and vice versa).

## Design principles

1. The user types `/gh-pr:create` once. Flags exist only as escape hatches.
2. Backwards-compat is unconditional. No repo signal → auto-detect
   never fires. dotfiles solo workflow is unchanged.
3. Auto-detect can be overridden when wrong (`--no-stack`, `--base`).
4. dotfiles never mutates the parent PR body. Cross-PR rollup is the
   downstream repo's concern (e.g. AgentToolbox's
   `stacked-closes-rollup.yml` workflow).

## Auto-detect flow

```
/gh-pr:create called
   │
   ▼
[Stage 1] is_stacked_pr_repo $REPO_ROOT
   │  ├─ workflow .github/workflows/stacked-closes-rollup.yml exists?
   │  ├─ CLAUDE.md / AGENTS.md / .claude/github-integration.md
   │  │   contain "claude-enter-issue", "stacked PR", or "Depends on #"?
   │  └─ agent-toolbox/ directory exists?
   │
   ├─ rc=1 (no signal) → BASE_BRANCH=$DEFAULT_BRANCH, PARENT_PR=, exit Stage 1
   │
   └─ rc=0 (stacked repo) → Stage 2
            │
            ▼
[Stage 2] find_parent_pr_candidates $DEFAULT_BRANCH
   - lists open PRs whose head ref is an ancestor of HEAD
   - drops PRs whose head ref shares the same merge-base with HEAD as
     the default branch (such PRs add no information beyond default)
   │
   ├─ 0 candidates → BASE_BRANCH=$DEFAULT_BRANCH (root issue case)
   │
   ├─ 1 candidate  → BASE_BRANCH=<head-of-PR>, PARENT_PR=<num>
   │   prints "Stacking on PR #<num> (auto-detected)"
   │   no prompt
   │
   └─ 2+ candidates → dispatch returns rc=4 + candidate list on stderr
       (bash is non-interactive in Claude Code — `read` would hang).
       The AI executor asks the user via the platform's question
       primitive, then re-invokes `gh-pr:create` with `--base <branch>` /
       `--no-stack` based on the answer.
```

## Manual override (escape hatches)

| Flag | Semantics |
|---|---|
| `--no-stack` | skip auto-detect entirely, BASE_BRANCH=$DEFAULT_BRANCH |
| `--base <branch>` | skip auto-detect, BASE_BRANCH=<branch>, PARENT_PR= |

The two flags are mutually exclusive. Combining them → rc=2 with an
explanatory message; the skill aborts before any push.

## Stage 1 — `is_stacked_pr_repo`

```sh
# Returns 0 when the repo opts into stacked PRs, 1 otherwise.
# Signals are checked in priority order; the first match short-circuits.
is_stacked_pr_repo() {
    local _repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    [ -n "$_repo_root" ] || return 1

    # 1. Workflow file (strongest, explicit opt-in).
    [ -f "$_repo_root/.github/workflows/stacked-closes-rollup.yml" ] && return 0

    # 2. Policy doc keywords.
    local _f
    for _f in CLAUDE.md AGENTS.md .claude/github-integration.md; do
        [ -f "$_repo_root/$_f" ] || continue
        grep -qE 'claude-enter-issue|stacked[[:space:]-]?PR|Depends on #' \
            "$_repo_root/$_f" 2>/dev/null && return 0
    done

    # 3. AgentToolbox project copy signature.
    [ -d "$_repo_root/agent-toolbox" ] && return 0

    return 1
}
```

False-positive prevention: each signal must be explicit. A repo with
none of these is treated as solo / non-stacked.

## Argument parsing — `parse_stacked_args`

```sh
# Reads positional args + flags from $@. Sets globals:
#   STACK_MODE     — auto | no-stack | base
#   STACK_BASE     — branch name when STACK_MODE=base
#   ISSUE_NUMBER   — first positional integer (legacy "/gh-pr:create 123" link)
# Non-integer positionals are deliberately ignored here: that is the [remote]
# positional, already consumed by Step 1a-0 into $REMOTE (dEitY719/dotfiles#1405).
# Returns 0 on success, 2 on mutually-exclusive violation, 3 on bad value.
parse_stacked_args() {
    STACK_MODE=auto
    STACK_BASE=
    ISSUE_NUMBER=
    local _flags_seen=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --no-stack)
                _flags_seen=$((_flags_seen + 1))
                STACK_MODE=no-stack
                shift
                ;;
            --base)
                _flags_seen=$((_flags_seen + 1))
                STACK_MODE=base
                if [ $# -lt 2 ]; then
                    printf 'gh-pr:create: --base requires a branch name\n' >&2
                    return 3
                fi
                STACK_BASE="$2"
                if [ -z "${STACK_BASE-}" ]; then
                    printf 'gh-pr:create: --base requires a branch name\n' >&2
                    return 3
                fi
                shift 2
                ;;
            *)
                if [ -z "$ISSUE_NUMBER" ] &&
                    printf '%s' "$1" | grep -qE '^[1-9][0-9]*$'; then
                    ISSUE_NUMBER="$1"
                fi
                shift
                ;;
        esac
    done

    if [ "$_flags_seen" -gt 1 ]; then
        printf 'gh-pr:create: --no-stack / --base are mutually exclusive\n' >&2
        return 2
    fi

    return 0
}
```

## Stage 2 — `find_parent_pr_candidates`

```sh
# Prints "<pr-number>:<head-ref>" lines, one per ancestor open PR.
# Inputs:
#   $1  default branch name (e.g. "main")
# Helpers (overridable in tests via FAKE_* env vars):
#   _gh_pr_default_open_pr_list
#   _gh_pr_default_is_ancestor
#   _gh_pr_default_default_tip_diff_check

_gh_pr_default_open_pr_list() {
    if [ -n "${FAKE_OPEN_PRS+set}" ]; then
        printf '%s\n' "$FAKE_OPEN_PRS"
        return 0
    fi
    GH_HOST="$TARGET_HOST" gh pr list --repo "$GH_REPO" \
        --state open --json number,headRefName \
        --jq '.[] | "\(.number) \(.headRefName)"' 2>/dev/null
}

_gh_pr_default_is_ancestor() {
    local _ref="$1" _ar
    if [ -n "${FAKE_ANCESTOR_REFS+set}" ]; then
        for _ar in $FAKE_ANCESTOR_REFS; do
            [ "$_ar" = "$_ref" ] && return 0
        done
        return 1
    fi
    git merge-base --is-ancestor "$_ref" HEAD 2>/dev/null
}

_gh_pr_default_default_tip_diff_check() {
    local _ref="$1" _default_tip="$2" _r
    if [ -n "${FAKE_NONDEFAULT_REFS+set}" ]; then
        for _r in $FAKE_NONDEFAULT_REFS; do
            [ "$_r" = "$_ref" ] && return 0
        done
        return 1
    fi
    local _base_with_default _base_with_head
    _base_with_default=$(git merge-base HEAD "$_default_tip" 2>/dev/null)
    _base_with_head=$(git merge-base HEAD "$_ref" 2>/dev/null)
    [ -n "$_base_with_default" ] && [ -n "$_base_with_head" ] &&
        [ "$_base_with_head" != "$_base_with_default" ]
}

find_parent_pr_candidates() {
    local _default_branch="$1"
    # $REMOTE is the [remote] positional bound in Step 1a-0 (dEitY719/dotfiles#1405).
    local _remote="${REMOTE:-origin}"
    local _default_tip="$_remote/$_default_branch"
    local _line _pr _head _candidates

    _candidates=$(_gh_pr_default_open_pr_list)
    [ -z "$_candidates" ] && return 0

    while IFS= read -r _line; do
        [ -z "$_line" ] && continue
        _pr="${_line%% *}"
        _head="${_line#* }"
        [ "$_head" = "$_default_branch" ] && continue
        # Live mode only — fetch the head so the ancestor probe is fresh.
        if [ -z "${FAKE_OPEN_PRS+set}" ]; then
            git fetch "$_remote" "$_head" --quiet 2>/dev/null || continue
        fi
        _gh_pr_default_is_ancestor "$_remote/$_head" || continue
        _gh_pr_default_default_tip_diff_check "$_remote/$_head" "$_default_tip" || continue
        printf '%s:%s\n' "$_pr" "$_head"
    done <<EOF
$_candidates
EOF
}
```

## Parent state + stack pre-check — `assert_parent_pr_open` + `assert_parent_pr_not_stacked`

`find_parent_pr_candidates` already filters by `--state open`, but two
hazards remain:

- **TOCTOU on state** — between Stage 2 and `gh pr create` (Step 5) the
  parent can be merged or closed (dEitY719/dotfiles#614 / F-4).
- **Multi-stack drift** — if the auto-detected parent is itself stacked
  on another PR (its body carries a `Depends on #N` line), accepting it
  silently produces a 2+-deep stack. agent-toolbox declares 1-stack-only
  as an invariant (`scripts/stacked_closes_rollup.py` defers the rollup
  on multi-stack); dotfiles must match (dEitY719/dotfiles#616 / F-6).

The two guards below re-read the parent's state **and** body right
before the base branch decision is committed and abort with:

| rc | Reason |
|---|---|
| 5 | state ≠ `OPEN` — stacking requires an open parent. |
| 6 | parent body has `Depends on #N` — multi-stack refused. |

Both pieces of metadata are fetched in a **single** `gh pr view --json
state,body` call. The body is cached in `$_GH_PR_PARENT_BODY_CACHE` so
the second assertion reads it without a second API call (F-6-2: zero
additional API cost relative to the F-4 baseline).

```sh
# Combined fetch — state + body in one `gh pr view`. Output: state.
# Side effect: body is stashed in $_GH_PR_PARENT_BODY_CACHE for the
# stacked-body guard below. Overridable in tests via FAKE_PARENT_STATE
# (state-only callers; existing F-4 fixtures) and FAKE_PARENT_BODY.
_gh_pr_default_parent_state() {
    local _pr="${1:-}" _meta _delim
    if [ -n "${FAKE_PARENT_STATE+set}" ]; then
        printf '%s\n' "$FAKE_PARENT_STATE"
        return 0
    fi
    _delim=$(printf '\001')   # ASCII SOH — never appears in PR bodies
    # shellcheck disable=SC2016  # $d is a jq variable (--arg d), not shell
    _meta=$(GH_HOST="$TARGET_HOST" gh pr view "$_pr" --repo "$GH_REPO" \
        --json state,body \
        --jq --arg d "$_delim" '.state + $d + .body' 2>/dev/null)
    _GH_PR_PARENT_BODY_CACHE="${_meta#*"$_delim"}"
    printf '%s\n' "${_meta%%"$_delim"*}"
}

# Helper — returns the parent body. Prefers the cache populated by
# _gh_pr_default_parent_state above; falls back to a direct fetch (or
# FAKE_PARENT_BODY in tests) when called in isolation.
_gh_pr_default_parent_body() {
    local _pr="${1:-}"
    if [ -n "${_GH_PR_PARENT_BODY_CACHE+set}" ]; then
        printf '%s' "$_GH_PR_PARENT_BODY_CACHE"
        return 0
    fi
    if [ -n "${FAKE_PARENT_BODY+set}" ]; then
        printf '%s' "$FAKE_PARENT_BODY"
        return 0
    fi
    GH_HOST="$TARGET_HOST" gh pr view "$_pr" --repo "$GH_REPO" \
        --json body -q .body 2>/dev/null
}

# Returns 0 when state == OPEN, 5 otherwise (with recovery hint on stderr).
assert_parent_pr_open() {
    local _pr="${1:-}" _state
    _state=$(_gh_pr_default_parent_state "$_pr")
    if [ "$_state" != "OPEN" ]; then
        printf 'gh-pr:create: parent PR #%s state=%s — stacking requires OPEN parent.\n' \
            "$_pr" "${_state:-UNKNOWN}" >&2
        printf 'Next: reopen parent, or run with --no-stack.\n' >&2
        return 5
    fi
    return 0
}

# Returns 0 when the parent body has no "Depends on #N" line, 6 otherwise.
# The `^[[:space:]]*` anchor is intentional: it matches dotfiles `## Related`
# section bodies (where "Depends on #N" sits on its own line under the
# header) and agent-toolbox "\n\nDepends on #N" trailers, but deliberately
# refuses inline prose like "This change Depends on #100 indirectly" —
# matrix-10 case 6 pins that no-false-positive contract. Case-insensitive
# so variants from external tools are also caught.
assert_parent_pr_not_stacked() {
    local _pr="${1:-}" _body
    _body=$(_gh_pr_default_parent_body "$_pr")
    if printf '%s' "$_body" | grep -qiE '^[[:space:]]*Depends[[:space:]]+on[[:space:]]+#[0-9]+'; then
        printf 'gh-pr:create: parent PR #%s is already stacked — multi-stack not supported.\n' \
            "$_pr" >&2
        printf 'Next: merge/squash parent first, or use --no-stack / --base <branch>.\n' >&2
        return 6
    fi
    return 0
}
```

Single API call (`gh pr view --json state,body`) per stacked-PR
invocation — 0 overhead in the solo / non-stacked path because the
helpers only run inside the 1-candidate branch of the Stage-2 dispatch.

## How Step 1 of `SKILL.md` ties it together

`TARGET_HOST` / `GH_REPO` are already bound and `GH_HOST` already exported by
Step 1a-0 when this block runs — every `gh` call below (and in the helpers
above) pins both. Without them `gh` resolves against its own
`gh repo set-default`, so on a dual-host login `DEFAULT_BRANCH` and the
candidate PR list come from a different GitHub server than the target remote
(dEitY719/dotfiles#1403). That remote is `$REMOTE` — the `[remote]` positional, `origin` by
default (dEitY719/dotfiles#1405); the ref probes above fetch and compare against it, never a
hard-coded `origin`.

```sh
parse_stacked_args "$@" || exit $?

DEFAULT_BRANCH=$(GH_HOST="$TARGET_HOST" gh repo view "$GH_REPO" \
    --json defaultBranchRef -q .defaultBranchRef.name)

case "$STACK_MODE" in
    no-stack)
        BASE_BRANCH="$DEFAULT_BRANCH" ; PARENT_PR= ;;
    base)
        BASE_BRANCH="$STACK_BASE" ; PARENT_PR= ;;
    auto)
        if is_stacked_pr_repo "$(git rev-parse --show-toplevel)"; then
            CANDIDATES=$(find_parent_pr_candidates "$DEFAULT_BRANCH")
            COUNT=$(printf '%s\n' "$CANDIDATES" | grep -c .)
            case "$COUNT" in
                0)  BASE_BRANCH="$DEFAULT_BRANCH" ; PARENT_PR= ;;
                1)
                    PARENT_PR="${CANDIDATES%%:*}"
                    BASE_BRANCH="${CANDIDATES#*:}"
                    assert_parent_pr_open "$PARENT_PR" || return $?
                    assert_parent_pr_not_stacked "$PARENT_PR" || return $?
                    printf 'Stacking on PR #%s (auto-detected)\n' "$PARENT_PR" ;;
                *)
                    # 2+ candidates — bash cannot prompt safely (Claude Code is
                    # non-interactive; `read` would hang the runtime). Print the
                    # candidate set and exit the auto branch with both vars
                    # unset; the AI executor handles the choice via the
                    # platform's question primitive (e.g. AskUserQuestion in
                    # Claude Code) and re-runs the case for `base` /
                    # `no-stack` based on the user's reply.
                    printf 'Multiple parent candidates:\n%s\n' "$CANDIDATES" >&2
                    printf 'gh-pr:create: ambiguous parent — ask user, then re-invoke with --base / --no-stack\n' >&2
                    return 4
                    ;;
            esac
        else
            BASE_BRANCH="$DEFAULT_BRANCH" ; PARENT_PR=
        fi
        ;;
esac
```

`BASE_BRANCH` flows into Step 5 (`gh pr create --base "$BASE_BRANCH"`).
`PARENT_PR`, when set, flows into the body-template "Depends on #N"
insertion documented in `pr-body-template.md`.

When the dispatch returns rc=4 (ambiguous parent), the AI executor — not
the shell — must surface the candidate list to the user via the
platform's question primitive (e.g. `AskUserQuestion` in Claude Code).
Once the user picks one, re-invoke `gh-pr:create` with the matching escape
hatch flag (`--base <branch>` or `--no-stack`). This avoids hanging on
`read` in non-interactive runtimes.

## Compatibility matrix (what the bats suite must keep covering)

| Scenario | Invocation | Expected effect |
|---|---|---|
| dotfiles solo | `/gh-pr:create` | Stage 1 fail → base=default, no prompt, no Depends footer |
| AgentToolbox parent unique | `/gh-pr:create` | Stage 1 pass + 1 cand → base=parent head, "Stacking on PR #N" |
| AgentToolbox parent ambiguous | `/gh-pr:create` | Stage 1 pass + 2+ cand → 1× prompt |
| AgentToolbox no parent | `/gh-pr:create` | Stage 1 pass + 0 cand → base=default |
| `--no-stack` override | `/gh-pr:create --no-stack` | base=default forced, no Stage 2 |
| `--base release/v2.0` | `/gh-pr:create --base release/v2.0` | arbitrary branch forced |
| Mutually-exclusive flags | `/gh-pr:create --no-stack --base main` | rc=2, abort |
| Bad `--base` value | `/gh-pr:create --base` (missing arg) | rc=3, abort |
| Parent state ≠ OPEN | `/gh-pr:create` (auto-detected parent CLOSED/MERGED) | rc=5, abort with recovery hint |
| Parent already stacked | `/gh-pr:create` (auto-detected parent body has `Depends on #N`) | rc=6, abort with recovery hint |

The 10 rows above are the regression contract — every change to the
detection logic must keep them green.

## Exit codes (Step 1a dispatch)

| rc | Meaning |
|---|---|
| 0 | Base branch resolved; proceed to Step 1b. |
| 2 | `--no-stack` and `--base` were both passed (mutually exclusive). |
| 3 | `--base` was passed without a branch value. |
| 4 | Stage 2 produced 2+ parent candidates — AI executor must ask the user. |
| 5 | Auto-detected parent PR is not `OPEN` — stacking refused. |
| 6 | Auto-detected parent PR is itself already stacked — multi-stack refused. |

rc=4 (ambiguous parent), rc=5 (parent-not-open), and rc=6
(multi-stack-refused) are semantically distinct — all three block the
dispatch, but only rc=5/6 mean "the parent is no longer a valid
stacking target". Treat them separately when wiring recovery hints.
rc=6 mirrors agent-toolbox's 1-stack-only invariant (`scripts/
stacked_closes_rollup.py` defers the rollup on multi-stack) so both
drivers refuse the same configuration symmetrically.
