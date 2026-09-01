# gh-pr:reply — Constraints

- **Never skip a reply** — every comment from Step 2 gets one, bot comments
  (gemini-code-assist, sourcery-ai, copilot) included. Even
  "Declined: out of scope" counts; this is the core contract of the skill.
  Never dismiss a bot comment as "just a bot", and never fix silently.
- Never move the PR card to `Approved` — that column is owned by
  `gh-pr:approve` (#1350). Replies and bot reviews are `COMMENTED` and never
  change `reviewDecision`, so promoting on them lands unreviewed PRs in
  `Approved` (#1349 regression). The Step 6 `In review` recovery is the only
  board write this skill performs.
- Never close or resolve threads programmatically — leave that to the user.
- Never fix files outside the PR's diff without flagging scope creep first.
- Never `--amend`, `--no-verify`, or `--force-push`. If a history rewrite is
  needed, stop and ask.
- To mutate PR labels or body, route through `_gh_pr_edit_safe_label` /
  `_gh_pr_edit_safe_body` / `_gh_pr_drop_label`
  (`shell-common/functions/gh_pr_edit_safe.sh`) — bare `gh pr edit --add-label`
  / `--body-file` silently exits 1 on classic-Projects repos (issue #326 Bug B).
  The Step 6 `review-passed` / `review-blocked` invalidation goes through
  `_gh_pr_drop_label`, the one shared REST-DELETE primitive every
  head-advancing skill uses (#1563) — never an inlined DELETE.
- Never **add** `review-passed` or `review-blocked` by hand — no bare
  `gh pr edit --add-label`, no inlined REST POST. The Step 6 gate helper
  `_gh_pr_reply_apply_review_passed` is the only path, and it writes through
  the shared `devx_pr_review_all_write_label` primitive.
- **NF-2 — "never self-certify" — is deliberately RELAXED here, on this one
  path (#1636).** State it plainly rather than quietly: this skill now applies
  `review-passed` **from its own judgment, with no external AI CLI re-call**,
  whenever no BLOCKER-severity item is left unresolved.
  - What it replaced: #1563/#1616 required an **independent** `gh-pr:review`
    re-call to return a non-blocking verdict before the label could be
    written. That re-call was the only way to re-earn `review-passed`, and its
    cost/latency/failure rate is what repeatedly jammed `gh-pr:merge-train`
    (#1627). The user weighed the extra safety net against pipeline
    reliability and chose reliability — an explicit, recorded trade-off, not
    a drift.
  - What still verifies: the **findings are still external**.
    `gh-verify:review-all` still fans out every reviewer on every PR, still
    comments, and still owns `review-blocked`. The split is "an outside AI
    finds; `gh-pr:reply` confirms it fixed what was found" — not "no review
    happened".
  - What did NOT change (the fail-closed half): one unresolved
    BLOCKER-severity item — DECLINE or QUESTION — means no `review-passed`,
    ever. A failed label write leaves the PR unlabelled, and unlabelled still
    reads downstream as "not verified", never as a pass. `review-blocked` is
    still issued only by an external reviewer's verdict.
