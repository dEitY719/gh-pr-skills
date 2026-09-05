---
name: merge-train
description: >-
  Clean up and merge your own open PRs one at a time — each routed to
  gh-resolve:outdated / :conflict / :ci-fail, then gh-pr:merge. Use for
  /gh-pr:merge-train, "열린 PR 순차로 정리하고 머지해", "머지 트레인 돌려". A single PR is gh-pr:merge, not this.
license: MIT
allowed-tools: Bash, Read, Grep, Skill
metadata:
  model_recommendation:
    tier: sonnet
    reason: "serial multi-PR orchestration; routing is deterministic but state must be re-derived per PR and two rows delegate real reasoning (conflict, CI)"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:merge-train — Sequential PR cleanup + merge

## Role

한 저장소의 열린 **본인 PR** 을 D-2 순서로 정렬해 **한 번에 1건씩** 정리·머지한다.
상태 판정과 스킬 라우팅은 결정론적이므로 이 스킬이 루프를 돌고, LLM 판단은
**충돌 해결과 CI 수정 두 지점에서만** 필요하다 — 그 둘은 원자 스킬에 위임한다.
한 PR 이 막혀도 그 PR 만 건너뛰고 train 은 계속한다.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output its
content verbatim, then stop. **No API calls.** That file tables the positionals
(`[owner/repo]`, `[remote]`) and names the atom skills the train calls.

## Step 1: Bind the GitHub target

Copy the binding block from `references/github-target.md` and run it **before
any `gh` call** — `TARGET_REPO` / `TARGET_HOST` / `GH_HOST` come from one and
the same remote URL (#1403/#1407). An explicit `owner/repo` positional pins
`TARGET_REPO` directly; the host still comes from the remote URL.

## Step 2: Collect and order the queue

```bash
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_merge_train.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_merge_train.sh" ] || { printf '[gh-pr:merge-train] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' "$_SC" >&2; return 1 2>/dev/null || exit 1; }
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_merge_train.sh"
GH_HOST="$TARGET_HOST" gh pr list --repo "$TARGET_REPO" --author @me --state open \
  --limit 50 --json number,updatedAt,isDraft,mergeable,mergeStateStatus,baseRefName,title,labels \
  | _gh_pr_merge_train_filter_targets --now "$(date +%s)"
```

`--author @me` is not optional (D-7) — never auto-merge a colleague's PR.
`_gh_pr_merge_train_filter_targets` is the **shared** filter (#1524): it drops drafts,
every PR carrying the `reply-pending` label, and every PR inside the D-6 quiet period —
the exact same function `shell-common/tools/custom/pr_merge_train_cron.sh` runs, so the
two can never disagree. **Do not re-implement or paraphrase that filter here** — run it.

Sort the surviving array `CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`, ties by
ascending PR number (D-2). Ordering, the label, and the quiet-period rationale:
`references/ordering.md`.

**`gh pr list` failure ends the run** with an empty report — never merge without state.

## Step 3: Read the approval policy per base branch

Read `required_approving_review_count` from **both** rulesets and classic
branch protection per `references/approval-gate.md`, **once per distinct
`baseRefName`**, cached per base — two calls per base, never per PR. Either
source requiring `>= 1` → gate on, unapproved PRs `[SKIPPED]`; both reporting
no policy → off (D-5). Classify by **HTTP status, not exit code**: a `403`/`404`
is "no policy", not a failed lookup, and only a genuinely undetermined answer
stays fail-closed (#1519). Even with the gate off, a non-empty non-`APPROVED`
`reviewDecision` is `[SKIPPED]` before `gh-pr:merge` is called — it would
refuse, and NF-2 forbids clearing that.

## Step 3.5: Apply the review verdict gate

Over the PRs Step 2 let through — **not** a new API call, the `labels` field
is already in hand — run the decision table in `references/review-verdict-gate.md`:
`review-blocked` (even alongside a stale `review-passed`) is
`[SKIPPED] review-blocked — reviewer verdict is blocking`; neither label is
`[SKIPPED] review not verified — no review-passed label`; `review-passed`
alone stays in the queue. Ask with
`_gh_pr_merge_train_has_review_blocked_label` /
`_gh_pr_merge_train_has_review_passed_label` (same file Step 2 sourced) — **do
not** re-derive the `jq` here, and **never** parse a review comment body: the
verdict is decided by `gh-verify:review-all`, which is the labels' only writer.

**Absence is "not verified", not "passed"** — that is the whole gate (#1527 /
#1564). Neither outcome spends an F-5 attempt and neither is ever `[FAILED]`.
There is deliberately no staleness window here, unlike `reply-pending`'s.

This pass is label-presence only, on purpose — it costs no API call. It
cannot yet tell a `review-passed` label issued for the current head apart
from a stale one; that sha-freshness check (#1601) happens once per PR, right
before it is actually acted on, at Step 4's F-3 re-query
(`references/routing-table.md`) — the same point that already re-derives
everything else Step 2/3.5 could not have seen coming.

## Step 4: Run the train — one PR at a time

For each PR in queue order, run the loop in `references/train-loop.md`:
**re-query state immediately before processing** (F-3 — the previous merge
invalidated everything behind it), route through the D-1 table
(`references/routing-table.md`), then merge with `Skill(gh-pr:merge, "<N>")`.
Gate off with an empty `reviewDecision` first runs one
`Skill(gh-pr:approve, "<N> <remote> --self-record")` and reads the board back as
its verdict — no approval, no merge.
After a **successful** merge, close that PR's implementation tab when its herdr
agent is `idle` — the block in `references/train-loop.md` → "Closing the merged
PR's implementation tab". A merged PR whose tab stays open keeps counting toward
issue-watcher's `_IW_MAX_PER_REPO` budget and starves the pipeline (#1565).
The `BEHIND` / `DIRTY` rows rebase inside a **detached scratch worktree** the
train creates and unconditionally removes per attempt (#1493). Attempts are
capped at 3 per PR (F-5); a failure skips that PR and the train continues
(F-6). Never process two PRs concurrently.

## Step 5: Report

Emit the structured `[MERGED]` / `[SKIPPED]` / `[FAILED]` report — one line per
PR with a reason — per `references/report-format.md` (F-9). Always as plain
assistant text, never via a `Bash` heredoc or `Write`.

## Constraints

- **Never call `gh-pr:merge-emergency`** (NF-2). Admin bypass is not this
  skill's path; an unmergeable PR is `[SKIPPED]` with a reason.
- **Never abort the whole train** for one PR's failure (F-6).
- **No merge strategy argument** — `gh-pr:merge`'s default rebase is what
  `required_linear_history` allows (D-4).
- **No review judgement of its own** — `gh-flow:issue` already ran
  `gh-verify:review-all`, and the gate-off path delegates to `gh-pr:approve`
  rather than deciding anything here. Step 3.5 reads that fan-out's verdict
  **label** and nothing else; parsing a review comment body here is forbidden
  (`references/review-verdict-gate.md` → "What this gate is not").
- **No ai-metrics comment.** Every atom the train calls posts its own; a
  train-level one would only duplicate them on the same PR.
- Full list: `references/constraints.md`.

## Related Skills

Atoms this train calls: `gh-resolve:outdated` · `gh-resolve:conflict`
· `gh-resolve:ci-fail` · `gh-pr:approve` (`--self-record`, gate-off path
only) · `gh-pr:merge`. Deliberately **not** called:
`gh-pr:merge-emergency` (NF-2). Upstream producer of the PRs this train drains:
`gh-flow:issue`; of the Step 3.5 verdict labels it gates on: `gh-verify:review-all`
(sole writer) and `gh-setup:label-bootstrap` (provisioning). Unattended trigger:
`shell-common/tools/custom/pr_merge_train_cron.sh` (`references/cron-dispatcher.md`).
