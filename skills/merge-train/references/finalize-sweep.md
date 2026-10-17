# gh-pr:merge-train — Step 0: finalize PRs the merge queue merged since the last tick

Issue dEitY719/dotfiles#1707 (sweep query: PR dEitY719/dotfiles#1725). Runs
**before** Step 2 builds this tick's queue, because these PRs are already
merged — they are not candidates, they are unfinished business.

```bash
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"                                   # tier 1
if [ ! -f "$_SC/functions/gh_pr_merge_train.sh" ]; then
    [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || {                                            # tier 5
        printf '[gh-pr:merge-train] no shell-common under %s, and CLAUDE_PLUGIN_ROOT is unset. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
            "$_SC" >&2
        return 1 2>/dev/null || exit 1
    }
    _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common"                                # tier 2
fi
unset -f _gh_pr_merge_train_filter_targets 2>/dev/null || :
unalias _gh_pr_merge_train_filter_targets 2>/dev/null || :
export SHELL_COMMON="$_SC"                                                           # before the load
[ -f "$_SC/functions/gh_pr_merge_train.sh" ] && . "$_SC/functions/gh_pr_merge_train.sh"
[ "$(command -v _gh_pr_merge_train_filter_targets 2>/dev/null)" = _gh_pr_merge_train_filter_targets ] || { # tier 5
    unset SHELL_COMMON
    printf '[gh-pr:merge-train] %s did not load a usable shell-common. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
GH_HOST="$TARGET_HOST" gh search prs --repo "$TARGET_REPO" --author @me \
  --merged --label review-passed \
  --limit 100 --json number,title,state,labels \
  | _gh_pr_merge_train_finalize_targets \
  | jq -r '.[].number'
```

Each number that comes out gets **one**
`Skill(gh-pr:merge, "<N> rebase <remote> --finalize")`, then a
`[FINALIZED] #<N> <title>` line in the Step 5 report.

`_gh_pr_merge_train_finalize_targets` is the **shared** array-level filter in
`shell-common/functions/gh_pr_merge_train.sh` (vendored at
`lib/vendor/shell-common/functions/`), same shape as Step 2's
`_gh_pr_merge_train_filter_targets` — run it, do not paraphrase it. It answers
"MERGED **and** still carrying `review-passed`" for the whole list in one pass
(the same rule `_gh_pr_merge_train_needs_finalize` answers for a single PR),
and that combination is the signal precisely because `gh-pr:merge` drops that
label as the last step of a completed merge (dEitY719/dotfiles#1636): a merged
PR that still has it is a PR whose completion steps never ran, which is what an
enqueued (`--auto`) merge leaves behind.

The query asks the **search index by label**, not `gh pr list` by recency (PR
dEitY719/dotfiles#1725, codex BLOCKER). `gh pr list --state merged --limit 30`
returned "the 30 most recently merged PRs" and filtered those — so a PR that
genuinely still owed a finalize pass fell out of the sweep forever once 30
further merges had happened, silently, with no error and no report line.
`is:merged label:review-passed` returns that set directly, with no recency cap;
`--limit 100` is a sanity bound on a set that is normally empty and never
legitimately large — if it is ever hit, the leftovers are a real incident, not
a window to widen.

The tradeoff taken knowingly: the search index is eventually consistent, so a
PR merged (or labelled) seconds ago may not appear for a tick or two. That
delays a finalize by minutes, against a bug that lost it permanently.

`_gh_pr_merge_train_finalize_targets` still runs over the result even though
the query already filters to the same rule. It is not redundant: `gh search`
reports `state` lowercase (`"merged"`), `gh pr list` uppercase (`"MERGED"`),
and the shared filter is the one place that normalises — routing the search
output through it keeps the *rule* in one place, so a future change of query or
of `gh`'s output shape cannot quietly turn the sweep into "finalize everything
the API returned".

The finalize work itself is **not done here**. The train writes nothing to
GitHub of its own (`references/constraints.md`); `gh-pr:merge --finalize` owns
every one of those mutations already, and the sequence it runs is defined in
`../../merge/references/finalize-merged-pr.sh.md`.
