# Lint Guard — pre-push lint detection and execution

Used by Step 4.5 of the `gh-pr:create` skill, **before** Step 5 pushes the branch.
Source: issue #396, design SSOT in
[#384#issuecomment-4403809305](https://github.com/dEitY719/dotfiles/issues/384#issuecomment-4403809305).

## Why

Some repos rely on a pre-commit hook for lint gating; others ship a
`tox.ini` or rely on CI. When the hook is missing or skipped, broken
lint quietly slips through to CI and burns review cycles. This step
runs the project's own lint tools on the PR's changed files just before
push, surfacing failures before they hit the remote.

## Helper

The detection and execution logic is implemented in
`shell-common/functions/gh_pr_lint.sh` as `_gh_pr_lint_run <base>`.
The skill sources the file and calls the function — never inline the
detection logic in `SKILL.md`.

```bash
. "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_pr_lint.sh"
_gh_pr_lint_run "$BASE_BRANCH" || {
    printf 'gh-pr:create stopped at Step 4.5 (lint guard).\n' >&2
    exit 1
}
```

## Detection priority

The guard picks tools in this order, top-down:

1. **tox** — `tox.ini` exists and declares at least one of these envs:
   `[testenv:ruff]`, `[testenv:shellcheck]`, `[testenv:shfmt]`,
   `[testenv:actionlint]`. Runs `tox -e <list>` with only the envs that
   are actually declared.
2. **shellcheck** — `command -v shellcheck` succeeds **and** the changed
   file set contains at least one `*.sh`. Runs
   `shellcheck -x -e SC1090,SC1091 -S warning <changed-sh-files>`.
3. **actionlint** — `command -v actionlint` succeeds **and** the change
   set contains at least one `.github/workflows/*`. Runs
   `actionlint <changed-workflow-files>`.
4. **pre-commit** — `.pre-commit-config.yaml` exists and
   `command -v pre-commit` succeeds. Runs
   `pre-commit run --files <changed-files>`.

When tox runs, the individual fallbacks (shellcheck / actionlint /
pre-commit) are skipped — tox already owns the project's lint surface.
When tox is absent, fallbacks run independently and accumulate failures.

## Scope: changed files only

The guard never lints the whole repo. Files come from:

```sh
git diff --name-only "$BASE...HEAD"
```

Per-tool filtering then keeps only the relevant subset (e.g. `*.sh` for
shellcheck, `.github/workflows/*` for actionlint). This keeps the
runtime small and avoids dragging in pre-existing lint debt that the PR
did not introduce.

If the changed set is empty (e.g. cherry-pick that yields no diff), the
guard logs `no changed files vs <base> — skip` and returns 0.

## Bypass

| Env var | Effect |
|---|---|
| `GH_PR_LINT_BYPASS=1` | Skip the guard entirely. Logs `bypassed (GH_PR_LINT_BYPASS=1)` and returns 0. Use for emergency pushes when the lint debt is known and tracked elsewhere. |
| `GH_PR_LINT_TOOLS=auto` | Default — auto-detect tools per the priority list. |
| `GH_PR_LINT_TOOLS=tox,shellcheck` | Restrict to a comma-list of tools. Each named tool is still subject to its own detection rule (existence + applicable changed files). |

## Failure behaviour

On any tool's non-zero exit, the guard records a failure but continues
running remaining tools so the user sees every failure in one pass.
After all tools finish, if any failed:

1. Return 1 from `_gh_pr_lint_run`.
2. The caller (skill Step 4.5) prints
   `gh-pr:create stopped at Step 4.5 (lint guard).` and exits non-zero **before
   pushing**.
3. The user fixes the listed errors and re-runs `/gh-pr:create`, or sets
   `GH_PR_LINT_BYPASS=1` for a one-shot escape.

## Skip matrix

| Condition | Result |
|---|---|
| `GH_PR_LINT_BYPASS=1` | skip + log |
| Empty `git diff --name-only "$BASE...HEAD"` | skip + log |
| No detected tool applies (no tox.ini, no shellcheck/actionlint/pre-commit) | skip + log |
| Tool detected but its file-type filter yields zero matches | tool not run; other tools still evaluated |

## Why fail-loud over warn-only

The design discussion (#384) considered warn-only with an opt-in to
hard-fail. We picked hard-fail with an env-var escape because:

- Warn-only is silent in scrollback and easy to ignore.
- Lint failures here always block CI later — failing now saves a round
  trip with reviewers.
- The escape (`GH_PR_LINT_BYPASS=1`) is one env var away, so emergency
  pushes are still cheap.

If a user complains the guard is too aggressive, the fix is to set
`GH_PR_LINT_TOOLS=` to an empty list locally (in `~/.zprofile` or
similar) — never to soften the default.
