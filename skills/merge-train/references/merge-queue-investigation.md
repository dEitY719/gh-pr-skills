# GitHub merge queue on `dEitY719/dotfiles` — findings and the manual activation step

> Ported from `dEitY719/dotfiles` `claude/skills/gh-pr-merge-train/references/`
> (dEitY719/dotfiles#2219). "This repo" below means `dEitY719/dotfiles`, where
> every measurement on this page was taken.

Issue dEitY719/dotfiles#1707, AC1.

> **Looking for what dEitY719/dotfiles#1707 actually shipped?** That is
> `strict-mode-relaxation.md`, not this page. This page is the **why not the
> merge queue** — the investigation that found the queue categorically
> unavailable here, plus the manual activation procedure kept for a possible
> future org transfer. Everything on this page is inert. The fix that replaced
> it, and that is live on `main` right now, is the strict-checks relaxation
> documented next door.

**Nothing in this repository executes anything on this page.** Enabling a merge queue rewrites how every future PR reaches `main` on
a repo whose merge train runs unattended every 5 minutes
(`shell-common/tools/custom/cron-jobs.json`), so the activation is a human's
deliberate act, taken *after* the code that depends on it is merged — never a
side effect of merging it.

## Blocker first: the queue is not available on this repo today

> Pull request merge queues are available in any public repository owned by an
> **organization**, or in private repositories owned by organizations using
> GitHub Enterprise Cloud.
>
> — [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)

`dEitY719/dotfiles` is public, but its owner is a **personal user account**,
not an organization:

```console
$ gh api repos/dEitY719/dotfiles --jq '{owner_type: .owner.type, visibility}'
{"owner_type":"User","visibility":"public"}
```

So the gate is **ownership type, not plan tier**. No ruleset payload makes the
queue work here; the prerequisite is transferring the repo to an organization.
Until that happens the `merge_queue` rule below cannot be added at all.

This corrects the premise this work started from. "Public repo ⇒ merge queue is
free" is true only for org-owned public repos.

### The second blocker, if the first is ever cleared

`gh pr merge` cannot enqueue a PR on a repo whose `allow_auto_merge` is
`false`. It only ever calls the `enablePullRequestAutoMerge` GraphQL mutation
— `enqueuePullRequest` appears nowhere in the CLI — and GitHub rejects that
mutation when the repo setting is off. This is
[cli/cli#13398](https://github.com/cli/cli/issues/13398), open, and it
reproduces on v2.45.0, the version installed here. This repo is currently
`allow_auto_merge: false`, so **both** of these would have to be flipped:

```console
$ gh api repos/dEitY719/dotfiles --jq '.allow_auto_merge'
false
```

Legacy branch protection implicitly forced `allow_auto_merge` on, which is why
this was never visible before rulesets.

## The premise that was wrong in the other direction

`main` **is** protected. The 404 that suggested otherwise comes from the
*legacy* endpoint, which 404s whenever protection is ruleset-based rather than
classic — the absence of a classic record, not the absence of protection:

```console
$ gh api repos/dEitY719/dotfiles/branches/main/protection
gh: Not Found (HTTP 404)

$ gh api repos/dEitY719/dotfiles/rulesets --jq '.[] | {id, name, enforcement}'
{"id":16849266,"name":"main-protection","enforcement":"active"}
```

Ruleset `16849266` currently carries `deletion`, `non_fast_forward`,
`required_linear_history`, `pull_request`
(`required_approving_review_count: 0`, `allowed_merge_methods: [squash, rebase]`)
and `required_status_checks` (`Lint (mise)`, `Shell Lint (mise)`). There is no
`merge_queue` rule.

`strict_required_status_checks_policy` on that last rule read `true` when this
investigation was written; it is **`false` now** — that flip is what dEitY719/dotfiles#1707
actually shipped, and it is documented in `strict-mode-relaxation.md`.

This matters beyond bookkeeping: `gh-pr:merge`'s Step 2 protection probe uses
that same legacy endpoint (`references/strategy-selection.md` → "Branch
protection detection") and therefore reads this repo as **unprotected**. It is
a conservative misread — it only widens the empty-`reviewDecision` exception on
a repo whose ruleset asks for 0 approvals anyway — but it is a misread, and
worth its own issue rather than a silent fix here.

## The activation command (manual, for a human, after this PR is merged)

Only meaningful once **both blockers above are cleared** (org-owned repo, and
either `allow_auto_merge: true` or a `gh` release that calls
`enqueuePullRequest`).

`PATCH /repos/{owner}/{repo}/rulesets/{id}` replaces the whole `rules` array,
so every existing rule has to be re-sent alongside the new one. Read the
current ruleset first and diff the payload against it — do not retype it from
this page, which is a snapshot:

```sh
# The activation targets one host and one repo explicitly. Bind both the way
# every gh-* skill's Step 1 does (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407) rather than typing a bare
# slug: `--repo`/a path slug carries no host, and a dual-host login would
# otherwise resolve it against `gh repo set-default`.
TARGET_HOST=github.com
TARGET_REPO=dEitY719/dotfiles
RULESET_ID=16849266

# 1. Read and keep the current state. This is the rollback artifact.
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/rulesets/$RULESET_ID" \
    > /tmp/ruleset-before.json

# 2. Build the new rules array from that file — the four existing rules
#    unchanged, plus merge_queue.
jq '{rules: (.rules + [{
      type: "merge_queue",
      parameters: {
        check_response_timeout_minutes: 60,
        grouping_strategy: "ALLGREEN",
        max_entries_to_build: 5,
        max_entries_to_merge: 5,
        merge_method: "REBASE",
        min_entries_to_merge: 1,
        min_entries_to_merge_wait_minutes: 5
      }
    }])}' /tmp/ruleset-before.json > /tmp/ruleset-patch.json

# 3. Apply.
GH_HOST="$TARGET_HOST" gh api -X PATCH "repos/$TARGET_REPO/rulesets/$RULESET_ID" \
    --input /tmp/ruleset-patch.json

# Rollback: PATCH again with {rules: .rules} taken from /tmp/ruleset-before.json.
```

### The parameters, and why these values

Every one of the seven is **required** by the schema — the API documents no
defaults, so all seven must be sent on every PATCH. Allowed values are from the
[rules REST schema](https://docs.github.com/en/rest/repos/rules).

| Parameter | Value | Why |
|---|---|---|
| `merge_method` | `REBASE` | The only choice consistent with the ruleset's own `required_linear_history` and its `allowed_merge_methods: [squash, rebase]`. `MERGE` would create a merge commit and violate linear history. Also matches D-4. Allowed: `MERGE` / `SQUASH` / `REBASE`. |
| `grouping_strategy` | `ALLGREEN` | Only a fully green batch merges; one red PR does not drag the batch in. Allowed: `ALLGREEN` / `HEADGREEN`. |
| `max_entries_to_build` | `5` | The batch width — this is the number that turns N CI round trips into one. 5 covers the observed queue depth (7 PRs was the worst case measured). Range 0-100. |
| `max_entries_to_merge` | `5` | Matched to the build width; merging more than was built together defeats the batch. Range 0-100. |
| `min_entries_to_merge` | `1` | A single PR must still merge on its own — this train is often one PR deep. Range 0-100. |
| `min_entries_to_merge_wait_minutes` | `5` | How long a partial batch waits for company before merging anyway. Aligned with the 5-minute cron tick, so a PR waits at most one extra tick. Range 0-360. |
| `check_response_timeout_minutes` | `60` | How long the queue waits for checks before giving up on an entry. Range 1-360. |

The numbers above (other than `merge_method`) are the values GitHub's web UI
pre-fills when the rule is first enabled. They are **not** documented API
defaults — the schema lists all seven as required with no `default` key — so
treat them as this repo's chosen configuration, not as "the defaults".

### Two things to check at activation time, not now

- **`strict_required_status_checks_policy` is now `false`** (dEitY719/dotfiles#1707,
  `strict-mode-relaxation.md`) — it was `true` when this section was written.
  GitHub documents the queue as *providing the same benefit* ("does not require
  a pull request author to update their branch and wait for status checks"),
  but does **not** document the two as incompatible or the strict flag as
  ignored. Unverified either way. If the queue is ever activated, decide
  deliberately whether to restore strict: the queue would then be supplying the
  pre-merge verification the relaxation gave up, which is the one condition
  under which turning it back on costs nothing.
- **`--delete-branch` on a genuinely deferred merge.** `gh pr merge` returns
  before the merge happens and skips branch deletion entirely in that run, with
  no warning (verified in cli/cli v2.45.0 `merge.go`). Head-branch cleanup then
  depends on the repo's "Automatically delete head branches" setting. Nothing
  in this train depends on the remote branch being gone, but the setting should
  be turned on so merged branches do not accumulate.

## What this repo ships in the meantime

`gh-pr:merge --auto` and the Step 0 finalize sweep are in place and inert:
with no queue on the base, `--auto` collapses to the immediate merge for the
`CLEAN` PRs the train merges (verified in cli/cli v2.45.0: `autoMerge = --auto
AND NOT isImmediatelyMergeable(state)`, and `CLEAN` is immediately mergeable),
and a PR that merges immediately has its `review-passed` label dropped in the
same run, so `_gh_pr_merge_train_needs_finalize` never matches and the sweep
finds nothing. The behavior is unchanged until a human performs the activation
above.
