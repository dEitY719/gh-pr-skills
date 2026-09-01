# Review Criteria — for gh-pr:approve skill

## Three comment endpoints (fetch all)

Bot tools and humans scatter feedback across three APIs. Missing one means missing comments.
`TARGET_HOST` / `TARGET_REPO` come from Step 1 (`references/arg-parsing.md`).

```bash
# Inline code review comments (line-anchored)
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/pulls/<N>/comments" --paginate

# Top-level issue-style comments on the PR conversation
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/<N>/comments" --paginate

# Review summaries (bots often put content here)
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/pulls/<N>/reviews" --paginate
```

For threading / dedup details see the sibling skill
`gh-pr-reply/references/comment-fetching.md` if installed.

## Review checklist

Work through each dimension; skip categories that don't apply to the diff.

1. **Correctness** — does the code do what the PR title/body says? Spot-check each changed hunk against the claim. For scripts, trace the happy path + one failure path.
2. **Conventions** — naming, file location, import order, error-handling idioms match the surrounding code. Check for any `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, or `.editorconfig` in the repo root or changed directories and apply those rules.
3. **Security** — input validation, shell-injection (`set -euo pipefail`, quoted expansions), hardcoded secrets, unsafe `eval`, missing authn/z checks, over-broad `sudo` usage, signed-by on apt keys, etc.
4. **Performance** — obvious N+1 patterns, unnecessary I/O inside hot loops, missing caching on expensive calls. Don't over-engineer — flag only concrete wins.
5. **Tests** — are the new paths covered? If the repo has a test suite and the PR touches logic, absence of tests is usually a BLOCKER. Docs-only or shell-bootstrap scripts can waive this with a note.
6. **Docs / comments** — public API changes without doc updates, lies in comments, stale references.
7. **Backward compatibility** — breaking API/CLI/config changes flagged in the PR body? Migration path documented?

## Re-review verification (when prior comments by ME exist)

Re-review mode is the dominant case for this skill. The contract is:
**every prior concern must be accounted for**.

1. Pull the list of prior comments/reviews by `ME` from the three endpoints.
2. For each concern, locate one of:
   - A commit in the PR that resolves it (link the short SHA in the review body).
   - A follow-up issue the author opened with a back-link to the PR.
   - A reply from the author explaining why it was declined (judge: is the reasoning acceptable?).
3. Any concern with none of the above → escalate to **BLOCKER** (unresolved prior review comment).

Do not silently let a prior concern drop. That erodes trust in the review process.

## BLOCKER vs FOLLOW-UP — where to draw the line

Ask: *"If the author merged this PR right now, would something break or regress?"*

- **Yes** → BLOCKER. Request changes. Examples: failing tests, introduced bug, security regression, API break without migration, unresolved prior review concern.
- **No, but the team would want it tracked** → FOLLOW-UP. File an issue. Examples: nice refactor, test-coverage gap on an untriggered path, doc phrasing improvement, TODO left unresolved for a future edge case, minor idiom mismatch with the rest of the codebase.
- **No and too small to track** → PRAISE or ignore. Don't file trivia as an issue — it creates noise and trains the team to ignore your issues.

When in doubt between FOLLOW-UP and ignore: file it if you can state, in one sentence, the concrete harm of leaving it. Otherwise drop it.

## Praise is part of the review

Approvals without specifics ("LGTM!") teach authors nothing. Every approval body should include ≥1 compliment anchored to a file:line or commit SHA. Examples:

- `set -euo pipefail` + `pipefail`-aware piping in `scripts/install.sh:2`
- `BASH_SOURCE` anchoring for idempotent lock files at `b665789`
- Table in `setup.md` making the lock-file convention discoverable

Generic praise ("great job!", "looks good!") is worse than none — it signals a skimmed review.

## Self-review guard

Before submitting an approving review: if the PR author's login equals
`ME`, do not call `gh pr review --approve`. GitHub rejects same-user
self-approval server-side. Use `self-pr-handling.md` for the
analysis-only, `--self-record`, or `--admin-merge` paths.
