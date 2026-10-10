# Lint Guard — pre-push lint detection and execution

Used by Step 4.5 of the `gh-pr:create` skill, **before** Step 5 pushes the branch.
Source: issue dEitY719/dotfiles#396, design SSOT in
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
`lib/lint-guard.sh <BASE_BRANCH>` (relative to `skills/create/`) loads it
through the HARD tier ladder (tier 1 `$DOTFILES_ROOT`, tier 2 guarded
`$CLAUDE_PLUGIN_ROOT/lib/vendor`, no cwd tier, tier 5 stops) and runs it.
Contract: exit `0` clean or skipped; exit `1` with
`gh-pr:create stopped at Step 4.5 (lint guard).` on stderr when lint failed,
or a tier-5 message when no usable shell-common loaded. Never inline the
detection logic in `SKILL.md`.


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
guard logs `no changed files vs <base> — skip` and returns 0 — the test gate
below does not run either.

## Test gate: `pr-gate` (dEitY719/dotfiles#2054)

After lint, `_gh_pr_lint_run` hands off to `_gh_pr_lint__pr_gate`, which runs
the repo's full tests through a `pr-gate` mise task. Repos opt in by defining
that task; repos without it are untouched. Order and conditions, as the
vendored `lib/vendor/shell-common/functions/gh_pr_lint.sh` implements them:

1. It runs only when lint did not fail. A lint failure returns 1 first.
2. It **still runs when no lint tool was detected** — "no lint" is not
   "nothing to check".
3. `GH_PR_TEST_BYPASS=1` → logs `test gate bypassed (GH_PR_TEST_BYPASS=1)`,
   returns 0.
4. Task detection: `mise task info pr-gate` succeeds, **or** the repo-root
   `mise.toml` / `.mise.toml` declares `[tasks.pr-gate]` (also the quoted
   `[tasks."pr-gate"]`). The grep covers an untrusted config, where
   `mise task info` errors: the gate then runs and mise's trust error fails
   it loudly instead of silently dropping it. No task → return 0, silently.
5. Task declared but `mise` not on `PATH` → logs
   `pr-gate declared but mise unavailable — skip`, returns 0. The gate does
   **not** block in that case.
6. Otherwise `mise run pr-gate` runs. Pass → `pr-gate passed`, 0. Non-zero →
   `pr-gate FAILED — fix the tests and re-run, or set GH_PR_TEST_BYPASS=1 to skip`
   on stderr, return 1, and Step 4.5 stops before the push like a lint
   failure does.

**`GH_PR_TEST_BYPASS=1` is not a way past red tests.** Use it only after you
ran the repo's tests yourself in this session and they passed — e.g. the
suite was just run and re-running it through mise would only repeat it. State
the bypass, and the test run that justifies it, in the report to the user.

## Bypass

| Env var | Effect |
|---|---|
| `GH_PR_LINT_BYPASS=1` | Skip the guard entirely — lint **and** the `pr-gate` test gate. Logs `bypassed (GH_PR_LINT_BYPASS=1)` and returns 0. Use for emergency pushes when the lint debt is known and tracked elsewhere. |
| `GH_PR_TEST_BYPASS=1` | Skip only the `pr-gate` test gate; lint still runs. Only after running the tests yourself, and report it (§ Test gate). |
| `GH_PR_LINT_TOOLS=auto` | Default — auto-detect tools per the priority list. |
| `GH_PR_LINT_TOOLS=tox,shellcheck` | Restrict to a comma-list of tools. Each named tool is still subject to its own detection rule (existence + applicable changed files). |

## Failure behaviour

On any tool's non-zero exit, the guard records a failure but continues
running remaining tools so the user sees every failure in one pass.
After all tools finish, if any failed (or the `pr-gate` task failed):

1. Return 1 from `_gh_pr_lint_run`.
2. The caller (skill Step 4.5) prints
   `gh-pr:create stopped at Step 4.5 (lint guard).` and exits non-zero **before
   pushing**.
3. The user fixes the listed errors and re-runs `/gh-pr:create`, or sets
   `GH_PR_LINT_BYPASS=1` for a one-shot escape (`GH_PR_TEST_BYPASS=1` for a
   pr-gate failure, under the § Test gate rule). The vendored lint message
   still names `/gh:pr` — known migration debt, CLAUDE.md item 5.

## Skip matrix

| Condition | Result |
|---|---|
| `GH_PR_LINT_BYPASS=1` | skip + log |
| Empty `git diff --name-only "$BASE...HEAD"` | skip + log |
| No detected tool applies (no tox.ini, no shellcheck/actionlint/pre-commit) | lint skip + log; `pr-gate` still evaluated |
| `GH_PR_TEST_BYPASS=1` | lint runs; `pr-gate` skip + log |
| No `pr-gate` mise task | `pr-gate` skipped silently |
| `pr-gate` declared, `mise` not installed | `pr-gate` skip + log (does not block) |
| Tool detected but its file-type filter yields zero matches | tool not run; other tools still evaluated |

## Why fail-loud over warn-only

The design discussion (dEitY719/dotfiles#384) considered warn-only with an opt-in to
hard-fail. We picked hard-fail with an env-var escape because:

- Warn-only is silent in scrollback and easy to ignore.
- Lint failures here always block CI later — failing now saves a round
  trip with reviewers.
- The escape (`GH_PR_LINT_BYPASS=1`) is one env var away, so emergency
  pushes are still cheap.

If a user complains the guard is too aggressive, the fix is to set
`GH_PR_LINT_TOOLS=` to an empty list locally (in `~/.zprofile` or
similar) — never to soften the default.
