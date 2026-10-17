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
한 PR 이 막혀도 그 PR 만 건너뛰고 train 은 계속한다. 머지는 `--auto` fire-and-forget 이고
(dEitY719/dotfiles#1707) 큐 조사·수동 활성화는 `references/merge-queue-investigation.md`, 실제
N회 CI 왕복을 없앤 strict 완화와 그 안전망은 `references/strict-mode-relaxation.md` 에 있다.

## Help

If arg #1 is `-h`, `--help`, or `help`, output `references/help.md` verbatim and stop. **No API calls.**

## Step 1: Bind the GitHub target

Run the binding block from `references/github-target.md` **before any `gh` call** — `TARGET_REPO` /
`TARGET_HOST` / `GH_HOST` from one remote URL (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407); an `owner/repo` positional pins only the repo.

## Step 0: Finalize PRs the merge queue merged since the last tick

Run the block in `references/finalize-sweep.md` (after Step 1's binding): each PR it prints gets one
`Skill(gh-pr:merge, "<N> rebase <remote> --finalize")` and a `[FINALIZED]` report line.

## Step 2: Collect and order the queue

Paste the queue-collection snippet from `references/ordering.md` → "Step 2 — queue collection"
verbatim: it sources shell-common and pipes `gh pr list --author @me` through the shared
`_gh_pr_merge_train_filter_targets` filter — never re-implement or paraphrase that filter, and
never drop `--author @me` (D-7). Sort the survivors `CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`,
ties by ascending PR number (D-2; rationale in `references/ordering.md`).
**`gh pr list` failure ends the run** with an empty report — never merge without state.

## Step 3: Read the approval policy per base branch

Apply the decision table in `references/approval-gate.md` — read
`required_approving_review_count` per distinct `baseRefName`, cached, fail-closed.

## Step 3.5: Apply the review verdict gate

Apply `references/review-verdict-gate.md` over Step 2's PRs — no new API call (`labels` is in hand).
`review-blocked` and "neither label" are `[SKIPPED]`; `review-passed` alone stays.

## Step 3.6: Read the base's check policy and health — once per base

Run `references/strict-mode-relaxation.md` → "New: the train refuses to pile onto a red base" once
per distinct `baseRefName` (bind `BASE`), cached like Step 3. It sets `$BEHIND_DIRECT` for the D-1
`BEHIND` row; its `[SKIPPED]` line skips every PR on that base this tick — never `[FAILED]`.

## Step 4: Run the train — one PR at a time

For each PR in queue order, run the loop in `references/train-loop.md`: **re-query state
immediately before processing** (F-3 — the previous merge invalidated everything behind it),
route through the D-1 table (`references/routing-table.md`), then merge with
`Skill(gh-pr:merge, "<N> rebase <remote> --auto")` — a `[QUEUED]` answer ends that PR's turn.
Gate off with an empty `reviewDecision` first runs one `Skill(gh-pr:approve, "<N> <remote>
--self-record")` and reads the board back as its verdict — no approval, no merge. After a
**successful** merge, close that PR's implementation tab per `references/train-loop.md` — an open
tab starves issue-watcher's pipeline budget. Attempts are capped at 3 per PR (F-5); a failure
skips that PR and the train continues (F-6). Never process two PRs concurrently.

## Step 5: Report

Emit the `[FINALIZED]` / `[MERGED]` / `[QUEUED]` / `[SKIPPED]` / `[FAILED]` report, one line per PR with a reason,
per `references/report-format.md` (F-9) — as plain assistant text, never via a `Bash` heredoc or `Write`.

## Constraints

Read `references/constraints.md` before the train runs — it carries all ten,
including the NF-2 ban on `gh-pr:merge-emergency` and the F-6 never-abort rule.

## Related Skills

Atoms this train calls: `gh-resolve:outdated` · `gh-resolve:conflict` · `gh-resolve:ci-fail` ·
`gh-pr:approve` (`--self-record`, gate-off path only) · `gh-pr:merge`. Deliberately **not** called:
`gh-pr:merge-emergency` (NF-2). Upstream producer of the PRs this train drains:
`gh-flow:issue`; of the Step 3.5 verdict labels it gates on: `gh-verify:review-all`
(sole writer) and `gh-setup:label-bootstrap` (provisioning). Unattended trigger:
`shell-common/tools/custom/pr_merge_train_cron.sh` (`references/cron-dispatcher.md`).
