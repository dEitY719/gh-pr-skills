---
name: merge
description: >-
  Merge an approved GitHub PR — rebase by default, or squash/merge — without
  asking. Use for /gh-pr:merge, "PR 51 머지해", "squash merge", "#99
  머지". Refuses un-approved PRs, failing CI, drafts, conflicts — bypass is
  gh-pr:merge-emergency.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "gh pr merge wrap with policy/preflight gate; bounded mutation, no deep reasoning"
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
  (#1403/#1407). Missing remote → list `git remote -v`, stop (no silent fallback).

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

The projectV2 board Status is **not** a merge gate (#1513) — do not read it
here. Rationale + the retired Step 2-B in `references/board-policy.md`.

## Step 3: Merge (no confirmation)

```bash
GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

Flag mapping in `references/strategy-selection.md`. If `gh` returns
"merge method is not allowed", print the repo-settings guidance from
`references/strategy-selection.md` and stop. **Never** silently switch
strategies.

## Step 4: Sync Project Board Status

Run the two post-merge board reconciliations (PR card → Done; linked Issue cards
→ Done) per `references/project-board-sync.md` — paste the snippets verbatim
(that file also holds the failure modes and gating rationale). Both helpers
auto-detect repos without a projectV2 attachment and silently return; failures
hit stderr, never block the report.

Then run the herdr idle-tab hint per `references/herdr-tab-notify.sh.md` — one
`[INFO]` line when the merged branch's local worktree still has an idle herdr
tab (soft-fail and read-only; skip entirely when there is no local worktree, no
`herdr`, or the agent is not idle — never close a tab or delete a worktree).

Then drop the now-readerless `review-passed` label per
`references/review-passed-cleanup.sh.md` — `_gh_pr_drop_label "$PR_NUMBER"
review-passed "$TARGET_REPO" "$TARGET_HOST"` (#1636, soft-fail: the merge
already succeeded, so a failed delete is one `[WARN]` line and never touches
the Step 5 report or the exit status).

After the board sync completes, post the ai-metrics PR comment per
`references/ai-metrics-comment.sh.md` (soft-fail; skip entirely when `GH_DISABLE_AI_METRICS=1`).

## Step 5: Fetch Merge SHA + Report

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in `references/strategy-selection.md` → "Final report format").

**After** the report has printed, paste this block verbatim — it is the
post-merge verification gate **and** its dispatch, in one run:

```bash
# Substitute the five values before running; every one of them is already in
# hand from Steps 1-2, so nothing here re-queries GitHub. Bind them all, even
# the ones an earlier step already set: each block runs in its own shell, and
# an unbound TARGET_REPO makes the registry lookup below answer empty — the
# silent no-dispatch #1565 is about.
PR_NUMBER=<N>                 # the merged PR
TARGET_REPO=<owner/repo>      # Step 1's single remote URL, the registry key
HEAD_BRANCH=<headRefName>     # Step 2's `gh pr view` already read it
BASE_BRANCH=<baseRefName>     # ditto — never a hardcoded `main`
REMOTE=<remote>               # the `[remote]` positional, default `origin`

# A binding mistake is also an unsubstituted placeholder (`<owner/repo>`) or a
# whitespace-only value: both pass `[ -n ]`, both silently reproduce #1576 (PR
# #1603 review, agy + codex), and neither is distinguishable from an unwatched
# repo below — name every offender; the dispatch closes tabs and rebases main.
PMV_MISSING=""
_pmv_need() {
    case "$2" in
    '' | '<'*'>') PMV_MISSING="${PMV_MISSING:+$PMV_MISSING, }$1" ;;
    *[!" "]*) ;;
    *) PMV_MISSING="${PMV_MISSING:+$PMV_MISSING, }$1" ;;
    esac
}
_pmv_need PR_NUMBER "${PR_NUMBER-}"
_pmv_need TARGET_REPO "${TARGET_REPO-}"
_pmv_need HEAD_BRANCH "${HEAD_BRANCH-}"
_pmv_need BASE_BRANCH "${BASE_BRANCH-}"
_pmv_need REMOTE "${REMOTE-}"

WATCHED_FILE="${IW_WATCHED_REPOS:-${HOME}/.agent-factory/avatars/issue-watcher/watched-repos.json}"
VERIFY_SKILL=""
if [ -n "$PMV_MISSING" ]; then
    printf '[WARN] gh-pr:merge: post-merge verification gate has unbound values (%s) — substitute all five values (no placeholders, no blanks) and re-run this block.\n' \
        "$PMV_MISSING"
elif command -v jq >/dev/null 2>&1 && [ -r "$WATCHED_FILE" ]; then
    VERIFY_SKILL=$(jq -r --arg r "$TARGET_REPO" \
        '(if type == "array" then . else (.repos // []) end) | .[] | select(.repo == $r) | .verify_skill // empty' "$WATCHED_FILE" 2>/dev/null)
fi
# Empty VERIFY_SKILL with all five values bound — repo not registered, no
# registry, or no jq, so the feature is simply unavailable — means do nothing
# at all: no output, no dispatch, and no [WARN] either. An unwatched repo
# stays byte-identical to its pre-#1511 behavior.
if [ -n "$VERIFY_SKILL" ]; then
    # gh-verify:post-merge-verify's dispatch block is READ and run here, not
    # reached via `Skill(gh-verify:post-merge-verify, ...)`: as a Skill() call
    # it ran 0/10 inside gh-pr:merge-train vs 10/10 for every pasted block, and
    # an unclosed tab starves issue-watcher's budget (#1565). Two tiers as
    # everywhere here: GH_VERIFY_ROOT's live gh-verify, else the vendored copy.
    PMV_BLOCK="${GH_VERIFY_ROOT:-}/skills/post-merge-verify/references/dispatch.sh.md"
    [ -r "$PMV_BLOCK" ] || PMV_BLOCK="${CLAUDE_PLUGIN_ROOT:-}/lib/vendor/gh-verify/post-merge-verify/dispatch.sh.md"
    # The fence marker is built with printf, never typed, so this block can sit
    # inside a fenced block of its own without closing it. Only the FIRST bash
    # fence is taken — the file's later snippets are documentation, not steps.
    PMV_FENCE=$(printf '\140\140\140')
    PMV_OK=""
    if [ -r "$PMV_BLOCK" ] && PMV_SH=$(mktemp 2>/dev/null); then
        # The staged file must not outlive this block: the sourced dispatch
        # returns early on most paths and a caller under `set -e` can leave the
        # shell mid-block, so cleanup is armed first and cleared on success.
        trap 'rm -f "$PMV_SH"' EXIT INT TERM
        awk -v f="$PMV_FENCE" \
            '$0 == f "bash" && !b { b = 1; next } $0 == f && b { exit } b' \
            "$PMV_BLOCK" >"$PMV_SH"
        # An empty extraction is this same bug in another mask (right file,
        # wrong fence); sourcing it is silent, so treat it as never staged.
        # shellcheck source=/dev/null
        if [ -s "$PMV_SH" ]; then PMV_OK=1; . "$PMV_SH"; fi
        rm -f "$PMV_SH"
        trap - EXIT INT TERM
    fi
    # A registered repo that cannot stage the dispatch is a broken install, not
    # an opt-out: loud, and never confusable with the silent unregistered skip.
    [ -n "$PMV_OK" ] || printf '[FAIL] gh-pr:merge: post-merge verification did NOT run for %s (registered) — %s is unreadable or has no bash fence. Broken install, not an opt-out: repair the gh-pr plugin or point GH_VERIFY_ROOT at a gh-verify checkout, then run /gh-verify:post-merge-verify %s by hand.\n' \
        "$TARGET_REPO" "$PMV_BLOCK" "$PR_NUMBER"
fi
```

The dispatch owns every step and every failure mode from there (all soft-fail,
so the report above stands regardless), and re-runs the same registry gate on
its own so it stays usable standalone. Detail:
the `gh-verify-skills` sibling repo (`skills/post-merge-verify/SKILL.md`).

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR; redirect to `gh-pr:merge-emergency`. Never bypass CI.
- Never swap strategy if the chosen one fails. Always `--delete-branch`.

## Related Skills

`gh-pr:approve` produces the approval this skill gates on · `gh-pr:merge-emergency`
is the admin-override path when approval cannot be obtained · `gh-verify:post-merge-verify`
owns the dispatch block Step 5 runs inline for repos registered in
`${IW_WATCHED_REPOS:-${HOME}/.agent-factory/avatars/issue-watcher/watched-repos.json}`,
and stays a standalone manual entry point
(`/gh-verify:post-merge-verify <N>`).
