# gh-pr:merge-train — The cron dispatcher (D-8, NF-1)

```
cron -> shell-common/tools/custom/pr_merge_train_cron.sh   (thin dispatcher, 1 tick)
          |- 1. flock                    — one tick at a time
          |- 2. herdr agent get mt-<repo>  — is a train from a previous tick still live
          |- 3. gh pr list --author @me  — is there anything worth waking a session for
          `- 4. herdr workspace -> tab -> claude -> /gh-pr:merge-train <owner/repo>
```

Register it with something like:

```
*/15 * * * * /path/to/pr_merge_train_cron.sh --cwd ~/dotfiles >> ~/.local/state/pr-merge-train/cron.log 2>&1
```

Illustrative only — the actual schedule of this repo's `merge-train` job is
whatever `shell-common/tools/custom/cron-jobs.json` says (`*/5 * * * *` as of
dEitY719/dotfiles#1482), installed via `aicron add merge-train`, not a hand-edited crontab
line. Treat that manifest, not the example above, as the schedule SSOT.

`--dry-run` reports what a tick would launch without taking the lock or opening
a pane.

## Why the train runs inside a claude session, not in the shell

This is the one structural difference from `issue_watcher_cron.sh`, and it is
deliberate.

The issue watcher's dispatches are **independent and parallel**: it opens a
pane per issue, hands each one a prompt, and never needs to know how any of
them ended. Fire-and-forget is sound there, so the whole cycle can live in
shell.

A merge train is **serial, and every step depends on the previous one having
completed**. If the shell fired the steps off, the ordering that D-2 and D-3
exist to create would be destroyed. To keep it, one process must hold the
entire run — and that process needs an LLM at two points (conflict resolution,
CI repair), so it has to be a claude session.

Hence the split: the shell answers "should a train start right now?", and the
session *is* the train.

## NF-1 needs two layers, and neither one is redundant

The dispatcher's flock covers **ticks** — two cron periods overlapping, or a
manual run racing a scheduled one. It cannot cover the train: the tick is
short-lived (seconds), while the session it spawns runs for many minutes. The
tick that started a train has exited and dropped the lock long before that
train reaches its second PR.

So the second layer asks herdr directly whether the deterministically named
train agent is still `working` or `blocked`. Together: the lock stops a second
dispatcher, the agent probe stops a second train.

That name is `mt-<repo>` — **no PR or issue number in it**. The name *is* the
lock, so a per-tick discriminator would make every tick compute a different
string, find no running train, and start a second one merging onto the same
base. It is built by `herdr_agent_name`
(`shell-common/functions/herdr_agent_name.sh`), the SSOT shared with
`issue_watcher_cron.sh` and `gh-verify:post-merge-verify`.

The workspace label is the *same string* as the agent name (dEitY719/dotfiles#1549) — no longer
`mt-<host>-<owner>-<repo>`. Pre-#1549 the label kept its own host-qualified
fold while the agent name had already moved to `herdr_agent_name` (dEitY719/dotfiles#1530), so
the same train answered to two different names: `herdr workspace list` showed
one, `herdr agent get` the other, with no way to cross-reference them. Dropping
host/owner from the label rides on the same one-repo-in-watched-repos.json
guard the agent name already accepted (dEitY719/dotfiles#1530): herdr validates agent names
against `^[a-z][a-z0-9_-]{0,31}$`, which has no room for a host, so a second
host or a second owner sharing a repo name collides on both names now, not
just the agent name. The trade-off and its expiry condition (a short digest
appended to both names together) are recorded at the helper
(`shell-common/functions/herdr_agent_name.sh`).

An agent that still **resolves** — `idle`, but also `done` or a status herdr
does not name — means the previous train's pane is still open and still holds
the name. The dispatcher prompts that same pane rather than opening a second
one, because `herdr agent start` under a name a live agent holds fails with
`agent_name_taken`, and a stale pane does not close by itself: mapping those
statuses to a fresh launch would wedge every later tick on the same collision.
Only a name that no longer resolves at all (`agent_not_found` — the pane is
gone, the name is released) earns a new workspace/tab/agent.

## What the dispatcher deliberately does not do

- It does **not** implement the routing table, the ordering, the attempt cap or
  the report. Those are this skill's text. A shell reimplementation would be a
  second SSOT that drifts.
- It does **not** write to GitHub. Its only `gh` call is a `pr list` read.
- It does **not** decide which PRs the train works on. Its target count is a
  "worth waking a session?" heuristic; this skill re-derives the real queue and
  re-runs the filter authoritatively (`ordering.md`). Both call the *same*
  function — `_gh_pr_merge_train_filter_targets` in
  `shell-common/functions/gh_pr_merge_train.sh` (dEitY719/dotfiles#1524) — so this is one
  implementation run at two clocks, not two implementations that could drift.
  Duplicating the filter here as shell *or* as prose is exactly the bug dEitY719/dotfiles#1524
  removed.

## Failure behaviour

| Failure | Dispatcher's response |
|---|---|
| `gh pr list` fails | end the tick, launch nothing — never merge without knowing state |
| herdr launch fails | end the tick, closing the tab this tick opened if no agent was ever placed on it (dEitY719/dotfiles#1512); the next tick retries |
| `agent start` says `agent_name_taken` | close this tick's tab, then prompt the name's existing holder — a second pane under that name is impossible, and failing here would repeat every period. The holder is on another pane, so the tab this tick opened holds nothing and is closed like any other failed start (dEitY719/dotfiles#1512) |
| `agent start` says `agent_pane_busy` | make up to 3 start attempts with a short backoff — a pane's shell is not interactive the instant `tab create` answers (dEitY719/dotfiles#1512) |
| a train is already live | end the tick quietly (NF-1) |
| zero target PRs | end the tick quietly |

Every one of these is "do nothing and try again next period". A dispatcher that
retried a *prompt* harder would be the thing most likely to produce two trains —
a prompt that looked stalled may well have landed. The `agent_pane_busy` retry
is not that: it repeats a start that registered no agent at all, on a pane that
holds none, so no attempt can produce a second train. A start that never places
an agent also leaves its tab behind, which is why every such path closes the tab
it opened (dEitY719/dotfiles#1512) — cron ticks every few minutes, and the workspace had
collected dozens of dead tabs. Tabs that predate the fix need a manual sweep.

A failed `agent start` now also carries herdr's own first stderr line as an
indented `원인:` under the error — dEitY719/dotfiles#1458's idiom. Without it a busy pane, a dead
server and a rejected account all read as the same sentence in the cron log,
which is why dEitY719/dotfiles#1512 went unnoticed for weeks of failed ticks.
