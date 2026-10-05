# gh-pr:reply Step 6 — Board sync, verdict labels, `reply-pending` removal

Read from `SKILL.md` Step 6, after the fix commits have been pushed and
`PUSHED_FIXES` is set. Three calls, in this order — the order is load-bearing.

The board and label writes live in one script, `lib/step6-board-and-labels.sh`
(relative to `skills/reply/`); its header is the I/O contract and
`tests/reply-step6.sh` is its offline guard. Every step in it is soft-fail: one
`[OK]` / `[WARN]` line each, always exit 0. The `review-passed` gate is **not**
in the script — it needs Step 3's `ORIGINS`, so it stays here, between the two
phases (#63).

## Locating the script

`<PHASE>` is `pre-gate` or `post-gate`; `<PUSHED_FIXES>` is only read by
`pre-gate`. `TARGET_HOST` / `TARGET_REPO` / `PR_NUMBER` are Step 1's bindings
(dEitY719/dotfiles#1403) — fill them in, Bash calls share no variables.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] &&                                               # tier 2
    [ -f "$CLAUDE_PLUGIN_ROOT/skills/reply/lib/step6-board-and-labels.sh" ]; then    # proof
    TARGET_HOST="<host>" TARGET_REPO="<owner/repo>" \
        bash "$CLAUDE_PLUGIN_ROOT/skills/reply/lib/step6-board-and-labels.sh" \
        --phase <PHASE> <PR_NUMBER> <PUSHED_FIXES>
else                                                                                 # tier 5, soft
    printf '[WARN] gh-pr:reply: no skills/reply/lib/step6-board-and-labels.sh under CLAUDE_PLUGIN_ROOT (%s) — board / label step skipped. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "${CLAUDE_PLUGIN_ROOT:-unset}"
fi
```

## 1. `--phase pre-gate`

With `PUSHED_FIXES > 0`: sync the board card back to `In review`
(`--only-from "In progress,Changes requested"`, so a card already at
`In review` / `Approved` / `Done` never moves), then drop the now-stale
`review-passed` through `_gh_pr_drop_label` — the reviewed commit is no longer
head. `review-blocked` is never touched here; the gate decides it. With
`PUSHED_FIXES = 0` the phase prints one `[OK]` line and makes no API call.

Must run **before** the gate: reversed, it would delete the label the gate just
applied. The invalidation rule's SSOT is the `gh_pr_edit_safe.sh` header,
"Verdict-label invalidation" (dEitY719/dotfiles#1563).

## 2. The `review-passed` gate

Unconditionally, and only after Step 5 has replied to every comment: run the
gate exactly as `references/review-passed-gate.md` specifies — it is the SSOT
for `HEAD_SHA`/`ME` resolution, the raw-JSON requirement, the origin-history
merge, and the five-call pipeline order (soft-fail; `gh-verify:review-all` owns
`review-blocked` and never writes `review-passed`; see
`references/constraints.md` for the NF-2 rationale). Load its helpers with
that file's own Step 3 loader block in the same Bash call. Never hand-write
either label.

## 3. `--phase post-gate`

Unconditionally drop `reply-pending` (REST DELETE; a 404 is a normal `[OK]`),
so a label left on cannot wedge the PR out of `gh-pr:merge-train`
(dEitY719/dotfiles#1524). Step 2.5's early exit runs this same phase — no
inline copy — because the `defer` branch of `gh-verify:review-all` has already
applied the label even when no reviewer commented (PR dEitY719/dotfiles#1545).
