# gh-pr:merge — Pre-flight hard stops

Step 2 reads this before it merges anything. `references/...` paths below are
relative to `skills/merge/`, the same way SKILL.md writes them.

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
