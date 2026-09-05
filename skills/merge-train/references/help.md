# gh-pr:merge-train — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `[owner/repo]` or `-h`/`--help`/`help` | the `[remote]`'s repo | Target repository, e.g. `acme/dotfiles`. The cron dispatcher always passes one. |
| 2 | `[remote]` | `origin` | Git remote whose URL pins the **host** (never the slug — a slug carries no host). |

## Usage

```
/gh-pr:merge-train                      # this checkout's origin repo
/gh-pr:merge-train acme/dotfiles        # explicit repo, host from origin
/gh-pr:merge-train acme/dotfiles upstream   # explicit repo, host from upstream
/gh-pr:merge-train -h                   # this help
```

## When to use this skill

- `gh-flow:issue` ran in parallel and left **several open PRs** behind. Merging
  the first one pushes every other one `BEHIND`, and a conflict or a red CI on
  top of that means picking a different remediation skill per PR, repeatedly.
- You want the queue drained unattended — the cron dispatcher
  (`shell-common/tools/custom/pr_merge_train_cron.sh`) exists for exactly that.

## When NOT to use

- **One PR.** Use `gh-pr:merge` (and `gh-resolve:outdated` / `-conflict` /
  `-ci-fail` if it needs cleanup first). A train over one PR is pure overhead.
- **A colleague's PR.** The train is `--author @me` only (D-7) and will not see
  it.
- **You need an admin bypass.** The train never calls
  `gh-pr:merge-emergency` (NF-2). Run that skill yourself, deliberately.
- **The PRs still need a human's judgement.** The train forms no opinion of
  its own: `gh-flow:issue` Step 2.4 already ran `gh-verify:review-all`, and where
  the approval gate is off the train delegates one `gh-pr:approve
  --self-record` pass rather than deciding anything itself (dEitY719/dotfiles#1519 D-3).

## What the skill does

1. Binds `TARGET_REPO` / `TARGET_HOST` from one remote URL (`references/github-target.md`).
2. Lists your own open PRs and runs them through the shared filter
   `_gh_pr_merge_train_filter_targets` (`shell-common/functions/gh_pr_merge_train.sh`,
   dEitY719/dotfiles#1524) — drafts, PRs carrying the `reply-pending` label, and anything
   updated in the last **11 minutes** (D-6) are dropped — then sorts
   `CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`, ties by ascending number (D-2).
3. Reads `required_approving_review_count` once per *distinct base branch* in
   the queue, from **both** rulesets and classic branch protection (policies
   are branch-scoped; a single-base queue is two calls). Either source asking
   for `>= 1` turns the gate on; both reporting no policy turns it off (D-5).
   The verdict is classified by **HTTP status and body**: a `404` (not
   configured), or a `403` carrying GitHub's plan-limit message, means no
   policy can apply here. Everything else — a `403` from a permission,
   rate-limit or SSO denial, a 5xx, a 401, no response, or a `2xx` whose body
   will not parse — is undetermined and stays **fail-closed** (dEitY719/dotfiles#1519 F-2).
   The report header names which of the three happened.
4. Applies the **review verdict gate** to the surviving queue, from the
   `labels` it already holds — no extra API call. `review-blocked` is
   `[SKIPPED]`, and so is a PR carrying **neither** verdict label: absence is
   "not verified", never "passed" (dEitY719/dotfiles#1564). Only `review-passed` proceeds. The
   labels are written solely by `gh-verify:review-all`; the train never parses a
   review comment. Table and rationale: `references/review-verdict-gate.md`.
5. Processes **one PR at a time**. Immediately before each one it re-queries
   state (F-3), because the previous merge changed it.
   When the gate is off and `reviewDecision` is empty, it first runs one
   `gh-pr:approve --self-record` and merges only if that review promoted the
   board card — a withheld approval skips the PR, and an already-reviewed head
   is never re-reviewed (dEitY719/dotfiles#1519 F-6 … F-9).
6. Routes on `mergeStateStatus` / `mergeable` through the D-1 table — the one
   copy lives in `references/routing-table.md`. Which atom each row reaches is
   summarised under "Atom skills it calls" below.
   The two rebase rows run in a **detached scratch worktree** the train creates
   and deletes per attempt (`references/train-loop.md` → "Detached scratch
   worktree").
7. Caps remediation at **3 attempts per PR** (F-5). Over that, the PR is
   `[FAILED]` and the train moves on (F-6).
8. Prints a per-PR `[MERGED]` / `[SKIPPED]` / `[FAILED]` report with reasons (F-9).

## What the skill will NOT do

- Merge without knowing state — a failed `gh pr list` ends the run.
- Merge an unapproved PR where either policy source requires approval, or
  where a source's state is genuinely undetermined (5xx / 401 / no response).
  A `403`/`404` is **not** that case — it is a definitive "no policy here".
- Merge a gate-off PR whose delegated `gh-pr:approve --self-record` review
  withheld approval.
- Merge a PR carrying `review-blocked`, or one carrying no verdict label at
  all — and it will not read a review comment body to second-guess either.
- Call `gh-pr:merge-emergency`, or file an incident issue.
- Pass a merge strategy — `gh-pr:merge`'s default rebase is what
  `required_linear_history` allows (D-4).
- Abort the whole train because one PR failed.
- Process two PRs at once.

## Atom skills it calls

| Skill | Called when |
|---|---|
| `gh-resolve:outdated` | `BEHIND` + `MERGEABLE` — clean rebase onto the moved base, in a scratch worktree |
| `gh-resolve:conflict` | `DIRTY` + `CONFLICTING` — the LLM-judgement row, in a scratch worktree |
| `gh-resolve:ci-fail` | `UNSTABLE` with a failing check — the other LLM-judgement row |
| `gh-pr:approve` | `--self-record`, once per head, only when the approval gate is off and `reviewDecision` is empty (dEitY719/dotfiles#1519 D-3) |
| `gh-pr:merge` | every row that reaches a mergeable state |
| none | `BLOCKED` / `DRAFT` skip; `UNSTABLE` still running and `UNKNOWN` poll first |

## Related skills

- `gh-flow:issue` — produces the parallel PRs this train drains; its Step 2.4
  `--defer-reply 4` is the reason for the 11-minute quiet period.
- `gh-verify:review-all` — the only writer of the `review-blocked` /
  `review-passed` labels this train's Step 3.5 gates on (dEitY719/dotfiles#1564).
- `gh-setup:label-bootstrap` — provisions those two labels; without them the
  producer cannot issue either and every PR skips.
- `gh-pr:merge` — the single-PR case, and the atom this train ends every PR with.
- `gh-pr:merge-emergency` — deliberately never called (NF-2).
