# Stacked PR Auto-Detection — Stage 1/2 logic for `gh-pr:create`

Applied in Step 1 of `gh-pr:create/SKILL.md`. Decides the PR's base branch — and
when applicable, an explicit parent PR — without making the user think
about flags. Solo / non-stacked repos (the dotfiles default) see no
behavioural change.

> The executable SSOT for `is_stacked_pr_repo`, `parse_stacked_args`,
> `find_parent_pr_candidates`, `assert_parent_pr_open`,
> `assert_parent_pr_not_stacked` and the Step 1a dispatch is
> `lib/stacked-pr.sh` (relative to `skills/create/`); this file keeps the
> design and the contract. `tests/create-lib.sh` drives the dispatch offline
> through the `FAKE_*` seams. dotfiles' bats suite
> (`tests/bats/skills/gh_pr_stacked_detect.bats`, fixture
> `tests/bats/skills/_fixtures/gh_pr_stacked_detect.sh`) mirrors the same
> functions — when the script changes, mirror the change there too.

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

Implemented in `lib/stacked-pr.sh`.

False-positive prevention: each signal must be explicit. A repo with
none of these is treated as solo / non-stacked.

## Argument parsing — `parse_stacked_args`

Implemented in `lib/stacked-pr.sh`.

## Stage 2 — `find_parent_pr_candidates`

Implemented in `lib/stacked-pr.sh`.

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

Implemented in `lib/stacked-pr.sh` (`_gh_pr_default_parent_state`,
`_gh_pr_default_parent_body`, `assert_parent_pr_open`, `assert_parent_pr_not_stacked`).

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

The dispatch is the tail of `lib/stacked-pr.sh`: `parse_stacked_args`, then
`DEFAULT_BRANCH` from `GH_HOST="$TARGET_HOST" gh repo view "$GH_REPO"`, then
the `no-stack` / `base` / `auto` case above. Inputs: the invocation's
positionals and flags as arguments; env `TARGET_HOST`, `GH_REPO`, `REMOTE`.
On success its **only** stdout is one eval-able line,
`BASE_BRANCH=… PARENT_PR=… ISSUE_NUMBER=… DEFAULT_BRANCH=…` (single-quoted);
`Stacking on PR #<N> (auto-detected)` and every abort reason go to stderr, and
the exit code is the table below.

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
