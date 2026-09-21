---
name: merge-emergency
description: >-
  Admin-override a GitHub PR's branch-protection approval, forcing an audit
  trail: reason comment plus follow-up incident issue. Use for
  /gh-pr:merge-emergency, "긴급 머지", "approval 없이
  머지", "admin bypass merge". CI still gates.
license: MIT
allowed-tools: Bash, Read, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "admin bypass + audit trail (PR comment + incident issue); requires user confirmation & substantive reason validation"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:merge-emergency — Admin-Bypass Merge with Audit Trail

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output it
verbatim, then stop. No API calls. That file tables the positionals
`<PR> <reason> [remote]` and good/bad reason examples. This skill is
project-agnostic — it works in any repo where the caller has admin/merge rights,
and it is **not** a replacement for review: the written reason and the post-merge
incident issue exist to make overuse visible.

## Step 1: Parse Args + Resolve Target

Record `START_TS=$(date +%s)` for Step 5 elapsed time. Positional: `<PR> <reason> [remote]`.

Argument rules for each positional — the `remote` binding order, the `--repo` exception, and the reason-quality refusal: `references/arg-parsing.md`.

Capture `ME=$(GH_HOST="$TARGET_HOST" gh api user -q .login)`, `NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)`.

## Step 2: Pre-flight Safety Gate (parallel)

Fetch in parallel, evaluate stops **before** touching merge: PR JSON
(`number,title,author,state,isDraft,mergeable,mergeStateStatus,baseRefName,headRefName`)
and `GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO" --required`.

**Hard stops**: `state != OPEN`, draft, conflicts, or failing/pending required
checks — emergency bypasses **approval**, not **CI**. **Soft warnings**: base
`BEHIND`; no approving review.

## Step 3: Confirm with the User

Print the planned action (repo, PR, author, base/head, CI summary, reason) then
`Proceed? (yes/ok/진행/머지)`. Exact prompt: `references/audit-templates.md`.
Never auto-proceed.

## Step 4: Audit Comment + Admin Merge

Order matters — comment first so the audit survives branch deletion. (1) Post
the "PR audit comment" from `references/audit-templates.md`, capturing its URL
for Step 7. (2) `GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --admin
--squash --delete-branch`; "Must have admin rights" → **stop**, never fall back
to `--merge`/`--rebase`. (3) `GH_HOST="$TARGET_HOST" gh pr view <N> --repo
"$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid` for the merge SHA.

## Step 5: Create Post-Merge Incident Issue

Non-negotiable audit tail. File `incident: emergency merge of PR #<N> — <reason
first line>` with the body + retro checklist from `references/audit-templates.md`.
Attach an `incident` label **only if** `GH_HOST="$TARGET_HOST" gh label list --repo "$TARGET_REPO"`
confirms it exists.

Append the ai-metrics footer to the incident issue body before creating it
(required artifact — no soft-fail; honors `GH_DISABLE_AI_METRICS=1`, issue dEitY719/dotfiles#399).
Exact block: `references/audit-templates.md` -> "ai-metrics footer".

## Step 6: Sync Project Board Status

Read `references/project-board-sync.md` and push the merged PR card to `Done`.
Sync failure never blocks the audit report.

## Step 7: Report

Print the `[OK]` report exactly as `references/audit-templates.md` -> "Step 7 — success report" spells it.

Every refusal instead prints one `[FAIL] PR #<N> not merged — <why>` line and
merges nothing; a failure *after* the merge lands never says `not merged` —
Step 5's is `[FAIL] PR #<N> merged, but the incident issue could not be filed`.
Per-stop wording: `references/audit-templates.md`.

## Constraints

Never: bypass CI (approval bypass only); skip the incident issue (the audit tail
is the whole point); run without affirmative confirmation; use `--merge`/`--rebase`
to dodge a failing admin merge. Reason must be substantive — refuse
`"urgent"`/`"fix"`/`"merge now"`.

## Related Skills

`gh-pr:merge` is the normal approved-PR path; come here only when approval cannot
be obtained in time · `gh-pr:approve` is how that approval is produced.
