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

Record `START_TS=$(date +%s)` immediately (Step 4 elapsed time). Argument rules — defaults and the refusal for each: `references/arg-parsing.md`. Bind
`TARGET_REPO` / `TARGET_HOST` / `GH_HOST` from the `[remote]` URL (contract: `references/github-target.md`);
every `lib/` call in this skill opens with the first three lines:

```bash
_L=""; if [ -n "${HERMES_SKILL_DIR}" ]; then _L="${HERMES_SKILL_DIR}/lib"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then _L="$CLAUDE_PLUGIN_ROOT/skills/merge/lib"; fi
[ -n "$_L" ] && [ -d "$_L" ] || { printf '[FAIL] gh-pr:merge: lib/ unresolved (%s) - export HERMES_SKILL_DIR=<skill dir> or CLAUDE_PLUGIN_ROOT=<plugin dir>\n' "${_L:-unset}" >&2; exit 1; }
_gt=$(sh "$_L/github-target.sh" "<remote>") || exit 1; eval "$_gt"
```

## Step 2: Pre-flight (parallel)

Run in one message: `GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url`
and `GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO" --required`.

Read `references/preflight-hard-stops.md` before merging: base-branch protection detection, every hard stop, and the one conditional exception, verbatim.

The projectV2 board Status is **not** a merge gate (dEitY719/dotfiles#1513) — do not read it
here. Rationale + the retired Step 2-B in `references/board-policy.md`.

## Step 3: Merge (no confirmation)

```bash
GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

Flag mapping in `references/strategy-selection.md`. If `gh` returns "merge method is not allowed",
print that file's repo-settings guidance and stop. **Never** silently switch strategies.

## Step 4: Post-merge Housekeeping

Four soft-fail side effects in one call (board → `Done`, herdr hint, `review-passed` cleanup,
ai-metrics; always exit 0 — contract: `references/post-merge-housekeeping.md`). After the Step 1 lines:
`TARGET_HOST=<host> START_TS=<ts> bash "$_L/post-merge-housekeeping.sh" <N> <owner/repo> <headRefName>`.

## Step 5: Fetch Merge SHA + Report

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in `references/strategy-selection.md` → "Final report format").

**After** the report has printed, run the post-merge verification gate — a no-op
for any repo outside the issue-watcher registry. Contract, the five positionals,
the plugin-root tiers and every failure mode: `references/post-merge-verify.md`.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] &&                                               # tier 2
    [ -f "$CLAUDE_PLUGIN_ROOT/lib/post-merge-verify-dispatch.sh" ]; then             # proof
    sh "$CLAUDE_PLUGIN_ROOT/lib/post-merge-verify-dispatch.sh" \
        <N> <owner/repo> <headRefName> <baseRefName> <remote>
elif command -v jq >/dev/null 2>&1 && jq -e --arg r <owner/repo> \
    '(if type == "array" then . else (.repos // []) end) | any(.repo == $r)' \
    "${IW_WATCHED_REPOS:-$HOME/.agent-factory/avatars/issue-watcher/watched-repos.json}" \
    >/dev/null 2>&1; then
    printf '[FAIL] gh-pr:merge: no lib/post-merge-verify-dispatch.sh under CLAUDE_PLUGIN_ROOT (%s) — verification gate did NOT run for this REGISTERED repo; see references/post-merge-verify.md, or run /gh-verify:post-merge-verify <N> by hand.\n' \
        "${CLAUDE_PLUGIN_ROOT:-<unset>}" >&2                                         # tier 5
fi
```

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR; redirect to `gh-pr:merge-emergency`. Never bypass CI.
- Never swap strategy if the chosen one fails. Always `--delete-branch`.

## Related Skills

`gh-pr:approve` produces the approval this skill gates on · `gh-pr:merge-emergency` is the admin-override
path when approval cannot be obtained · `gh-verify:post-merge-verify` owns the dispatch block Step 5 stages
via `lib/post-merge-verify-dispatch.sh` for registered repos, and stays a manual entry point (`/gh-verify:post-merge-verify <N>`).
