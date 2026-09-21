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
the same remote URL (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407). An explicit `owner/repo` positional pins
`TARGET_REPO` directly; the host still comes from the remote URL.

## Step 2: Collect and order the queue

Paste the queue-collection snippet from `references/ordering.md` → "Step 2 —
queue collection" verbatim: it sources shell-common and pipes `gh pr list
--author @me` through the shared `_gh_pr_merge_train_filter_targets` filter —
never re-implement or paraphrase that filter, and never drop `--author @me` (D-7).

Sort the surviving array `CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`, ties by
ascending PR number (D-2). Ordering, the label, and the quiet-period rationale:
`references/ordering.md`.

**`gh pr list` failure ends the run** with an empty report — never merge without state.

## Step 3: Read the approval policy per base branch

Apply the decision table in `references/approval-gate.md` — read
`required_approving_review_count` per distinct `baseRefName`, cached, fail-closed.

## Step 3.5: Apply the review verdict gate

Apply the decision table in `references/review-verdict-gate.md` over the PRs
Step 2 let through — no new API call, the `labels` field is already in hand.
`review-blocked` and "neither label" are `[SKIPPED]`; `review-passed` alone stays.

## Step 4: Run the train — one PR at a time

For each PR in queue order, run the loop in `references/train-loop.md`:
**re-query state immediately before processing** (F-3 — the previous merge
invalidated everything behind it), route through the D-1 table
(`references/routing-table.md`), then merge with `Skill(gh-pr:merge, "<N>")`.
Gate off with an empty `reviewDecision` first runs one
`Skill(gh-pr:approve, "<N> <remote> --self-record")` and reads the board back as
its verdict — no approval, no merge.
After a **successful** merge, close that PR's implementation tab per
`references/train-loop.md` → "Closing the merged PR's implementation tab" —
a merged PR whose tab stays open starves issue-watcher's pipeline budget.
Attempts are capped at 3 per PR (F-5); a failure skips that PR and the train
continues (F-6). Never process two PRs concurrently.

## Step 5: Report

Emit the structured `[MERGED]` / `[SKIPPED]` / `[FAILED]` report — one line per
PR with a reason — per `references/report-format.md` (F-9). Always as plain
assistant text, never via a `Bash` heredoc or `Write`.

## Constraints

Read `references/constraints.md` before the train runs — it carries all ten,
including the NF-2 ban on `gh-pr:merge-emergency` and the F-6 never-abort rule.

## Related Skills

Atoms this train calls: `gh-resolve:outdated` · `gh-resolve:conflict`
· `gh-resolve:ci-fail` · `gh-pr:approve` (`--self-record`, gate-off path
only) · `gh-pr:merge`. Deliberately **not** called:
`gh-pr:merge-emergency` (NF-2). Upstream producer of the PRs this train drains:
`gh-flow:issue`; of the Step 3.5 verdict labels it gates on: `gh-verify:review-all`
(sole writer) and `gh-setup:label-bootstrap` (provisioning). Unattended trigger:
`shell-common/tools/custom/pr_merge_train_cron.sh` (`references/cron-dispatcher.md`).
