# gh-pr:merge — Strategy Selection

## Default: `rebase`

Matches the "Rebase and merge" button the user clicks on GitHub web.
Produces linear history, no merge commits, preserves individual commit
messages.

## When the repo disables a strategy

GitHub repo settings can disable strategies. If `gh pr merge` fails with
`Pull request merge method is not allowed`, stop and report:

```
PR #<N> merge failed: <strategy> is disabled on this repo.
Allowed strategies (check repo settings > General > Pull Requests):
  - Allow merge commits
  - Allow squash merging
  - Allow rebase merging
```

Do NOT silently switch strategies.

## Strategy → flag mapping

| Strategy | gh flag |
|---|---|
| rebase | `--rebase` |
| squash | `--squash` |
| merge | `--merge` |

## Pre-flight JSON fields

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json \
  number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url
```

## Hard-stop decisions

| Field | Value → Stop reason |
|---|---|
| `state` | `!= OPEN` → "PR already <closed\|merged>" |
| `isDraft` | `true` → "draft PR — mark ready first" |
| `mergeable` | `CONFLICTING` → "resolve conflicts first" |
| `reviewDecision` | `!= APPROVED` → "not approved — use /gh-pr:merge-emergency for admin bypass". **Conditional exception**: see "Branch protection detection" below — empty `reviewDecision` is accepted when the base branch has no protection rules (solo / personal repos). |
| `mergeStateStatus` | `BEHIND`/`BLOCKED`/`DIRTY` → "rebase or fix conflicts first" |
| required checks | any `FAILURE` / `IN_PROGRESS` / `QUEUED` → "CI not green — fix or wait" |

## Branch protection detection

GitHub Free on private repos disables Branch Protection Rules, and
GitHub forbids PR authors from self-approving. Together, that means
solo / personal repos produce a permanently empty `reviewDecision`
(`""`) for every PR — strict `APPROVED` enforcement would make the
skill unusable there and force users into `gh-pr-merge-emergency`,
which is reserved for audited admin bypass.

Detect protection presence:

```bash
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/branches/$BASE/protection" >/dev/null 2>&1
# exit 0 → protection PRESENT  (strict rules apply)
# non-zero → protection ABSENT (403 Free-plan or 404 not-configured)
```

Behavior table for the `reviewDecision` check:

| Protection | `reviewDecision` | Action |
|---|---|---|
| present | `APPROVED` | proceed |
| present | anything else (`""`, `REVIEW_REQUIRED`, `CHANGES_REQUESTED`) | hard stop — redirect to `gh-pr-merge-emergency` |
| absent | `APPROVED` | proceed |
| absent | `""` (empty) | proceed; print `INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.` |
| absent | `CHANGES_REQUESTED` / `REVIEW_REQUIRED` | hard stop — someone explicitly blocked this PR, protection absence does not override that |

Rationale for treating 403 and 404 the same: both mean "branch
protection is not gating this merge" from the caller's perspective.
403 means the feature is locked by plan; 404 means it is unlocked
but not configured. Either way, no rule would have required an
approval. Distinguishing them in the log adds noise without value.

## Required checks

```bash
GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO" --required
```

Any row with conclusion `FAILURE` or status `IN_PROGRESS`/`QUEUED` → stop.
Only proceed when all required checks are `SUCCESS`.

## Post-merge SHA fetch

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

If `.mergeCommit.oid` is null (API hasn't settled yet), retry once
after `sleep 1`. Still null → print the SHA as `(pending)` in the
report and include the PR URL so the user can resolve manually.

## Final report format

Lead with an explicit verdict line, then the structured key-values:

```
[OK] PR #<N> merged (<strategy>)
  Merge SHA:  <sha>
  Branch:     <headRefName> → <baseRefName> (deleted)
  URL:        <pr-url>
```

A hard stop before the merge (un-approved, conflicting, failing checks)
instead prints a `[FAIL] PR #<N> not merged — <reason>` line
and the redirect (e.g. `/gh-pr:merge-emergency`). The Merge SHA renders as
`(pending)` when GitHub has not yet computed `mergeCommit.oid`.
