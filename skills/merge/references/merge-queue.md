# gh-pr:merge — the merge-queue path: `--auto` and `--finalize`

Issue dEitY719/dotfiles#1707. `references/...` paths below are relative to
`skills/merge/`, the same way SKILL.md writes them. `gh-pr:merge-train` is the
only caller of both flags: its per-PR merge passes `--auto`, and its Step 0
sweep passes `--finalize` to finish PRs the merge queue merged unattended.

## The two flags (Step 1)

- `--auto` — optional flag, any position after the positionals. Merge
  **fire-and-forget**: hand the PR to the base branch's merge queue instead of
  blocking until it merges. Step 3 and Step 3.5 below own the behavior.
- `--finalize` — optional flag, any position. Run **only** the post-merge
  completion sequence on a PR that is **already merged**, then stop: skip
  Step 2 and Step 3 entirely, jump straight to Step 4 per
  `references/finalize-merged-pr.sh.md`, and print `[FINALIZED] #<N>` instead
  of `[OK] PR #<N> merged`. If `gh pr view <N> --json state` is not `MERGED`,
  print `[FAIL] PR #<N> not finalized — state is <state>, expected MERGED` and
  stop: every step in that sequence is a GitHub write that assumes a merge
  happened.
- `--auto` and `--finalize` together is a usage error — they are the two halves
  of one deferred merge, never one invocation.

## Step 3 with `--auto`

Run this block instead of the plain Step 3 line. It **tries the queue-aware
form first and falls back to the plain merge**, so the flag can never be the
reason a merge that would otherwise have worked does not:

```bash
# Substitute PR_NUMBER / TARGET_REPO / TARGET_HOST / STRATEGY_FLAG (one of
# --rebase / --squash / --merge, per references/strategy-selection.md).
#
# `--auto` hands the PR to the queue and returns immediately, so N PRs cost
# ONE batched CI cycle instead of N serial rebase+CI round trips.
#
# On a base with NO merge queue (verified against cli/cli v2.45.0
# `pkg/cmd/pr/merge/merge.go`): gh computes
# `autoMerge = --auto AND NOT isImmediatelyMergeable(state)`, and `CLEAN` IS
# immediately mergeable — so for the only PRs the train merges (the D-1
# `CLEAN`/`MERGEABLE` row), `--auto` collapses to the ordinary
# `mergePullRequest` mutation and the PR merges immediately, exit 0, branch
# deleted. The flag is a genuine no-op there.
#
# The fallback covers the case that is NOT a no-op: a PR gh does not consider
# immediately mergeable, where `--auto` reaches `enablePullRequestAutoMerge` —
# a mutation GitHub refuses outright when the repo has
# `allow_auto_merge: false`. Without the retry, that path would fail a merge
# the plain skill would have completed, on a train a cron runs unattended. See
# ../../merge-train/references/merge-queue-investigation.md.
#
# Deliberately NO error-string matching: the wording of "auto-merge is not
# available here" has several forms and is not a stable API. Retrying the
# plain merge on ANY failure costs one extra call on a path that was already
# failing, and the second failure is the one reported — exactly the error the
# plain skill would have printed.
#
# Caveat, same source: when a merge really IS deferred, gh returns before the
# merge happens and `--delete-branch` silently does nothing in that run. The
# head branch is then GitHub's "Automatically delete head branches" setting
# to clean up, not this skill's.
if MERGE_OUT=$(GH_HOST="$TARGET_HOST" gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" \
        "$STRATEGY_FLAG" --delete-branch --auto 2>&1); then
    printf '%s\n' "$MERGE_OUT"
else
    printf '[INFO] gh-pr:merge: --auto refused (%s) — retrying the plain merge.\n' \
        "$(printf '%s' "$MERGE_OUT" | tr '\n' ' ')"
    GH_HOST="$TARGET_HOST" gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" \
        "$STRATEGY_FLAG" --delete-branch
fi
```

## Step 3.5: did it actually merge? (`--auto` only)

Without `--auto`, Step 3 returning success means the PR is merged — skip this.
With `--auto`, success means "GitHub accepted responsibility for the merge",
which is **not** the same as "the PR is merged". Run:

```bash
PR_STATE_JSON=$(GH_HOST="$TARGET_HOST" gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
    --json state,headRefName,baseRefName,url)
PR_STATE=$(printf '%s' "$PR_STATE_JSON" | jq -r '.state // empty' 2>/dev/null)
case "$PR_STATE" in
MERGED) ;; # the queue was off, or the PR merged immediately: continue to Step 4
OPEN)
    printf '[QUEUED] PR #%s added to merge queue — not yet merged\n' "$PR_NUMBER"
    printf '%s' "$PR_STATE_JSON" | jq -r '"  Branch:  \(.headRefName) → \(.baseRefName)\n  URL:     \(.url)"'
    ;;
*) printf '[FAIL] PR #%s not merged — state is %s\n' "$PR_NUMBER" "${PR_STATE:-unreadable}" ;;
esac
```

| `state` | Meaning | Do |
|---|---|---|
| `MERGED` | the queue was off, or the PR merged immediately | the block prints nothing; continue to Step 4 exactly as without `--auto` |
| `OPEN` | **queued, not yet merged** | the `[QUEUED]` report above, then **stop** — run none of Step 4, none of Step 5 |
| `CLOSED` (or unreadable) | someone closed it out from under us, or the re-read failed | `[FAIL] PR #<N> not merged — state is <state>`, stop |

`[QUEUED]` is a **third outcome**, not a dressed-up success and not a failure:
nothing went wrong, and nothing is finished. Running Step 4/5 here would sync
a board to `Done`, post an ai-metrics footer and dispatch a post-merge
verification for a merge that has not happened — and dropping `review-passed`
would destroy the one signal that says this PR still owes a completion pass.
`gh-pr:merge-train`'s Step 0 sweep finalizes it on a later tick
(`_gh_pr_merge_train_needs_finalize`, `references/finalize-merged-pr.sh.md`).
