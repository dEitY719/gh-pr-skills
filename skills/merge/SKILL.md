---
name: merge
description: >-
  Merge an approved GitHub PR — rebase by default, or squash/merge — without
  asking. Use for /gh-pr:merge, "PR 51 머지해", "squash merge", "#99 머지".
  Refuses un-approved PRs, failing CI, drafts, conflicts — bypass is gh-pr:merge-emergency.
license: MIT
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "gh pr merge wrap with policy/preflight gate; bounded mutation, no deep reasoning. Holds only while Step 5 stays a script call — re-rate to sonnet if the dispatch is ever inlined back into SKILL.md"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:merge — Merge Approved PR (3 strategies)

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and stop
(no API calls). That file also tables the positionals
`<pr-number> [rebase|squash|merge] [remote]` and the per-strategy guidance.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

- `pr-number` — required, positive integer. Missing/invalid → usage pointer, stop.
- `strategy` — default `rebase`; one of `rebase`/`squash`/`merge`. Other → print allowed values, stop.
- `remote` — default `origin`. Bind `TARGET_REPO` **and** `TARGET_HOST` from
  that one remote URL and `export GH_HOST` per `references/github-target.md`
  (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407). Missing remote → list `git remote -v`, stop (no silent fallback).

## Step 2: Pre-flight (parallel)

Run in one message: `GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url`
and `GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO" --required`.

Then detect base-branch protection via
`GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/branches/<baseRefName>/protection"` (exit 0 →
present; 403/404 → absent). The exact protection-vs-`reviewDecision` behavior
table is in `references/strategy-selection.md` → "Branch protection detection".

**Hard stops** (full table in `references/strategy-selection.md` →
"Hard-stop decisions"): `state != OPEN`; `isDraft`; `mergeable ==
CONFLICTING`; `mergeStateStatus ∈ {BEHIND, BLOCKED, DIRTY}`; any required
check FAILURE/pending; `reviewDecision != APPROVED` → suggest
`/gh-pr:merge-emergency`. Conditional exception: protection **absent**
**AND** `reviewDecision == ""` → accept and print
`INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.`
(a non-empty non-APPROVED value still stops).

The projectV2 board Status is **not** a merge gate (dEitY719/dotfiles#1513) — do not read it
here. Rationale + the retired Step 2-B in `references/board-policy.md`.

## Step 3: Merge (no confirmation)

```bash
GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

Flag mapping in `references/strategy-selection.md`. If `gh` returns
"merge method is not allowed", print the repo-settings guidance from
`references/strategy-selection.md` and stop. **Never** silently switch
strategies.

## Step 4: Post-merge Housekeeping

Four independent soft-fail side effects, in this order. Each reference file
holds the snippet to paste verbatim plus its own rationale; none of them can
block or alter the Step 5 report.

| What | Reference | Failure mode |
|---|---|---|
| PR card → `Done`, then linked Issue cards → `Done` | `references/project-board-sync.md` | silent return without a projectV2 board; failures hit stderr |
| herdr idle-tab hint for the merged branch's local worktree | `references/herdr-tab-notify.sh.md` | read-only; silent skip with no worktree, no `herdr`, or a non-idle agent |
| drop the now-readerless `review-passed` label | `references/review-passed-cleanup.sh.md` | one `[WARN]` line (dEitY719/dotfiles#1636) |
| ai-metrics PR comment | `references/ai-metrics-comment.sh.md` | one `[WARN]` line; skipped entirely when `GH_DISABLE_AI_METRICS=1` |

## Step 5: Fetch Merge SHA + Report

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in `references/strategy-selection.md` → "Final report format").

**After** the report has printed, run the post-merge verification gate. It is a
no-op for any repo outside the issue-watcher registry; contract, the five
positionals, and every failure mode are in `references/post-merge-verify.md`.

```bash
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || {                                                # tier 5
    printf '[FAIL] gh-pr:merge: CLAUDE_PLUGIN_ROOT is unset, so the post-merge verification gate did NOT run. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first, then run /gh-verify:post-merge-verify <N> by hand.\n' >&2
    return 1 2>/dev/null || exit 1
}
sh "$CLAUDE_PLUGIN_ROOT/lib/post-merge-verify-dispatch.sh" \
    <N> <owner/repo> <headRefName> <baseRefName> <remote>
```

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR; redirect to `gh-pr:merge-emergency`. Never bypass CI.
- Never swap strategy if the chosen one fails. Always `--delete-branch`.

## Related Skills

`gh-pr:approve` produces the approval this skill gates on · `gh-pr:merge-emergency`
is the admin-override path when approval cannot be obtained · `gh-verify:post-merge-verify`
owns the dispatch block Step 5 stages via `lib/post-merge-verify-dispatch.sh`
for repos registered in
`${IW_WATCHED_REPOS:-${HOME}/.agent-factory/avatars/issue-watcher/watched-repos.json}`,
and stays a standalone manual entry point
(`/gh-verify:post-merge-verify <N>`).
