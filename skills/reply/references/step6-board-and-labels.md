# gh-pr:reply Step 6 — Board sync, verdict labels, `reply-pending` removal

Read from `SKILL.md` Step 6, after the fix commits have been pushed and
`PUSHED_FIXES` is set. Run the blocks below in the order given.

If `PUSHED_FIXES > 0`: sync the board back to `In review`
(`references/board-sync-in-review.sh.md`, soft-fail), then drop the now-stale
`review-passed` (`references/verdict-label-removal.sh.md`, soft-fail) — the
reviewed commit is no longer head. Both run before the gate below.

Then, unconditionally and only after Step 5 has replied to every comment: run
the `review-passed` gate exactly as `references/review-passed-gate.md`
specifies — it is the SSOT for `HEAD_SHA`/`ME` resolution, the raw-JSON
requirement, the origin-history merge, and the five-call pipeline order
(soft-fail; `gh-verify:review-all` owns `review-blocked` and never writes
`review-passed`; see `references/constraints.md` for the NF-2 rationale).
Never hand-write either label.

Then **unconditionally** run the same removal block Step 2.5 does —
`references/reply-pending-label-removal.sh.md` — so a label left on cannot
wedge the PR out of `gh-pr:merge-train` (dEitY719/dotfiles#1524).
