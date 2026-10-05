# herdr Tab Notify — post-merge idle-tab hint (soft-fail, read-only)

Runs inside Step 4 (post-merge housekeeping), after the board
reconciliations. `HEAD_REF` is the merged PR's `headRefName`, already
fetched by Step 2's `gh pr view --json ...,headRefName,...` — carry that
value forward, do **not** re-fetch it. Step 3's `--delete-branch` removes
the *remote* branch; the local branch a worktree is checked out on is
untouched, so the `git worktree list` lookup below still resolves.

Purpose: when the merged branch was implemented in a local git worktree
that still has a `herdr` agent tab parked on it, and that tab is `idle`,
print **one** informational line so the human can tear it down. Nothing is
closed, removed, or otherwise mutated — every herdr/git call here is a
read-only `list` (NF-2). A `working`/`blocked` agent prints nothing at
all: silence, not a second info line (F-4).

Implemented as step 2 of `lib/post-merge-housekeeping.sh` (relative to `skills/merge/`). Gates, in order: `herdr` and `jq` on
PATH; a readable `${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/herdr_agent_lookup.sh`
(dEitY719/dotfiles#1569, sourced — never re-implemented); a local worktree on
`refs/heads/$HEAD_REF` from `git worktree list --porcelain`;
`herdr_agent_match_for_cwd "$(herdr_agent_physical_path "$WT_PATH")" idle`.
Only when all hold it prints the one line:

```text
[INFO] herdr tab <workspace-label|id>/<tab> is idle for the merged branch's worktree (<path>) — consider: herdr tab close <tab> / session:worktree-teardown
```

## Failure modes

Every one of these is a silent skip that leaves the Step 5 merge report
byte-identical (NF-1). None of them warn, and none of them return
non-zero to the caller.

- **`HEAD_REF` empty / no local worktree on that branch** — the usual case
  when the PR was implemented on another machine, or the worktree was
  already torn down. `WT_PATH` is empty → nothing printed.
- **`herdr` not installed** — `command -v herdr` fails → nothing printed,
  and the rest of `gh-pr:merge` runs normally. This is the expected state
  on any machine without the agent runner.
- **`jq` not installed** — same silent skip; the agent JSON cannot be
  parsed, and a hint is not worth a hand-rolled parser.
- **`herdr agent list` fails** (daemon down, no local herdr server, non-zero
  exit, or an answer that is not an agent list) — the lookup returns non-zero
  → nothing printed. The lookup does distinguish "herdr could not be asked"
  from "nothing is there", but this hint has nothing different to say about
  the two, so it stays silent for both.
- **No agent on the worktree path** — the worktree exists but no tab is
  parked on it, or under it, or standing in it → the lookup returns non-zero
  → nothing printed. Since dEitY719/dotfiles#1569 "on the path" means `cwd` OR
  `foreground_cwd`, matched on a path boundary against the physical path, so
  a session that `cd`-ed into a subdirectory and a worktree reached through a
  symlink now DO count — this hint used to miss both.
- **Agent found but `agent_status != "idle"`** (`working`, `blocked`, any
  future value, or absent) — nothing printed (F-4). Suggesting cleanup for a
  tab that is mid-run would be wrong, and a "still working" line would be
  noise.
- **`shell-common/functions/herdr_agent_lookup.sh` unreadable** — the shared
  match predicate (dEitY719/dotfiles#1569) is not there to be sourced → nothing printed. The
  hint degrades to silence, never to a hand-rolled copy of the predicate.
- **Two or more agents on the same worktree** — abnormal; the lookup takes
  the first, the rest are ignored, and no warning is emitted. The idle gate
  judges that first match rather than hunting for an idle one among several.
- **`herdr workspace list` fails, or the workspace has no label** —
  `WS_LABEL` is empty and `${WS_LABEL:-$WS_ID}` prints the raw workspace id.
  The hint still goes out; only its cosmetic prefix degrades.

## Read-only contract (NF-2)

This substep calls `git worktree list`, `herdr agent list`, and
`herdr workspace list` — enumerations only. It never closes a tab, never
deletes a worktree, and never writes to the herdr server. The suggested
cleanup commands are printed for a human to decide on and run.

`tests/bats/skills/gh_pr_merge_herdr_notify.bats` (dotfiles) enforces this
mechanically: it greps the block, its fixture mirror and the shared
`shell-common/functions/herdr_agent_lookup.sh` for the literal invocation
substrings and fails if any of them appears — the guarantee now depends on
that helper too, so the grep follows it there.

## Mirror

`tests/bats/skills/_fixtures/gh_pr_merge_herdr_notify.sh` (dotfiles) mirrors
step 2 of `lib/post-merge-housekeeping.sh` as the function
`gh_pr_merge_herdr_notify "$HEAD_REF"`. If the script's step 2 changes, mirror
the change there so the bats suite catches drift.
