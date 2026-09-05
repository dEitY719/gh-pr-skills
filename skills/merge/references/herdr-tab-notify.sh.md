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

```bash
# NF-1: every gate here is a silent skip. Either tool missing (the expected
# state on any machine without the agent runner), or no worktree (the merge
# ran on a different machine) → the merge report is unaffected. The two
# builtin `command -v` gates come first so that common case never pays for
# the worktree scan below.
if command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # "Which herdr agent is sitting on this worktree?" comes from one SSOT
    # (dEitY719/dotfiles#1569), sourced — never re-implemented here. This hint used to carry the
    # weakest of the four hand-copied answers: a plain `.cwd == $wt` string
    # equality, which missed both a session that had `cd`-ed inside its worktree
    # and a worktree reached through a symlink. Adopting the shared predicate
    # WIDENS what this hint notices, on purpose; widening is safe precisely
    # because the hint is read-only (NF-2) and costs one INFO line.
    # An unreadable helper is a silent skip like every other gate.
    NOTIFY_LOOKUP_LIB="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/herdr_agent_lookup.sh"
    # shellcheck source=/dev/null
    if [ -r "$NOTIFY_LOOKUP_LIB" ] && . "$NOTIFY_LOOKUP_LIB"; then
        # F-1: locate the local worktree checked out on the merged branch.
        # substr() rather than $2 so a worktree path containing spaces still
        # resolves; --porcelain guarantees the "worktree <path>" / "branch <ref>"
        # line pairing this relies on.
        BRANCH="${HEAD_REF}"
        WT_PATH=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${BRANCH}" \
            '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) print p}' | head -1)

        # F-2: read-only agent enumeration. The lookup matches BOTH `cwd` (where
        # the pane was opened) and `foreground_cwd` (where its shell stands now),
        # on a path BOUNDARY, against the PHYSICAL path — and it takes the first
        # match, because two agents on one worktree is abnormal: ignore the rest,
        # warn about nothing (Error Cases).
        #
        # F-4: the `idle` argument puts the status gate inside the lookup, so a
        # `working`/`blocked` agent yields nothing at all — silence, not a second
        # info line — and does not even pay for the workspace lookup below. A
        # non-zero return is either "herdr could not be asked" or "nothing idle
        # is there"; this hint treats both the same, silently.
        if [ -n "$WT_PATH" ] &&
            MATCH=$(herdr_agent_match_for_cwd "$(herdr_agent_physical_path "$WT_PATH")" idle); then
            # tab_id <TAB> agent_status <TAB> workspace_id. The middle field is
            # discarded: the filter above already pinned it to `idle`.
            IFS=$'\t' read -r TAB_ID _ WS_ID <<<"$MATCH"

            # Label is cosmetic — fall back to the raw workspace id when
            # this read-only lookup fails or the workspace is unlabeled.
            WS_LABEL=$(herdr workspace list 2>/dev/null | jq -r --arg id "$WS_ID" \
                '.result.workspaces[]? | select(.workspace_id == $id) | .label // empty' 2>/dev/null | head -1)

            # F-3: exactly one line, only for an idle agent. The path printed is
            # the one `git worktree list` reported, not its resolved twin — that
            # is the spelling the human will recognise.
            printf "[INFO] herdr tab %s/%s is idle for the merged branch's worktree (%s) — consider: herdr tab close %s / session:worktree-teardown\n" \
                "${WS_LABEL:-$WS_ID}" "$TAB_ID" "$WT_PATH" "$TAB_ID"
        fi
    fi
fi
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

`tests/bats/skills/gh_pr_merge_herdr_notify.bats` enforces this
mechanically: it greps this file, its fixture mirror and the shared
`shell-common/functions/herdr_agent_lookup.sh` for the literal invocation
substrings and fails if any of them appears — the guarantee now depends on
that helper too, so the grep follows it there.

## Mirror

`tests/bats/skills/_fixtures/gh_pr_merge_herdr_notify.sh` mirrors the bash
block above as the function `gh_pr_merge_herdr_notify "$HEAD_REF"`. If the
block here changes, mirror the change there so the bats suite catches drift.
