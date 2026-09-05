# gh-pr:merge-train — Approval gate (D-5, F-7)

Read the repo's **actual** policy and obey it. This skill never bypasses an
approval requirement and never manufactures one that the platform does not
impose. Both halves of that sentence are load-bearing: inventing a requirement
the platform cannot impose is the failure dEitY719/dotfiles#1519 fixed.

## Read the requirement — once per distinct base branch, from two sources

Rulesets are frequently scoped to a branch pattern, so the answer is a property
of the **base branch**, not of the repo. Read it per distinct `baseRefName` in
the Step 2 queue and **cache it per base**: a single-base queue — the normal
case for `--author @me` — therefore costs exactly two calls, and a mixed queue
costs two per base rather than two per PR.

Two sources, because a repo can enforce review through either mechanism:

| Source | Endpoint | `jq` |
|---|---|---|
| rulesets | `repos/{repo}/rules/branches/{base}` | `[.[] \| select(.type == "pull_request") \| .parameters.required_approving_review_count] \| max // empty` |
| classic branch protection | `repos/{repo}/branches/{base}/protection` | `.required_pull_request_reviews.required_approving_review_count // empty` |

`$BASE` is the queue's `baseRefName`, which Step 2's `gh pr list --json`
already returned — never guess `main`, and never spend a `gh pr view` on it.
`max` because more than one ruleset can apply and the strictest wins.

**The percent-encoding is load-bearing**, not tidiness: an unencoded `/` in a
base like `release/2026.08` makes the path
`repos/O/R/rules/branches/release/2026.08`, which is a *different* endpoint —
the call fails, and the fail-closed default below then skips every PR in the
queue. `@uri` turns the slash into `%2F` so the ref stays one path segment.

## Classify each source by HTTP status, not by exit code

`gh api` collapses every failure into a non-zero exit, which is exactly the
information loss that produced the dEitY719/dotfiles#1519 bug. Use `-i` so the status line
survives, and read the body out of the same response — that keeps the cost at
one call per source.

```bash
# Classify one policy source. Echoes `none`, `unknown`, or the required
# approval count (>= 1). Exactly one API call.
#
# Both unknown-verdict rules below are fail-closed by construction: `none`
# is only ever reached by an explicitly recognised answer, so an unforeseen
# response shape turns the gate ON rather than off.
_gate_probe() {
    _path="$1" _jq="$2"
    _out=$(GH_HOST="$TARGET_HOST" gh api -i "$_path" 2>/dev/null)
    _status=$(printf '%s\n' "$_out" | sed -n '1s|^HTTP/[0-9.]* *\([0-9][0-9][0-9]\).*|\1|p')
    _body=$(printf '%s\n' "$_out" | sed '1,/^\r\{0,1\}$/d')
    case "$_status" in
        2??) ;;                               # fall through, parse the body
        404) echo none; return 0 ;;           # the feature is not configured here
        403)
            # NOT every 403 means "no policy". Only the plan-limit message
            # does; permission, rate-limit and SSO denials are unreadable
            # policy and must fail closed (PR dEitY719/dotfiles#1526 agy+codex review).
            case "$_body" in
                *"Upgrade to GitHub Pro"*) echo none ;;
                *) echo unknown ;;
            esac
            return 0
            ;;
        *) echo unknown; return 0 ;;          # 5xx, 401, network, no response
    esac
    # A 2xx with no body, or a body `jq` cannot parse, is NOT "no policy" —
    # it is an unparsed answer. Distinguish jq's *failure* (non-zero exit)
    # from jq's *empty result* (exit 0, no output = the rule is absent).
    [ -n "$(printf '%s' "$_body" | tr -d '[:space:]')" ] || { echo unknown; return 0; }
    _n=$(printf '%s\n' "$_body" | jq -r "$_jq" 2>/dev/null) || { echo unknown; return 0; }
    case "$_n" in
        '' | null | 0) echo none ;;
        *[!0-9]*) echo unknown ;;             # not a plain count -> unparsed
        *) echo "$_n" ;;
    esac
}

BASE_ENC=$(jq -rn --arg b "$BASE" '$b|@uri')
RULESET=$(_gate_probe "repos/$TARGET_REPO/rules/branches/$BASE_ENC" \
    '[.[] | select(.type == "pull_request") | .parameters.required_approving_review_count] | max // empty')
CLASSIC=$(_gate_probe "repos/$TARGET_REPO/branches/$BASE_ENC/protection" \
    '.required_pull_request_reviews.required_approving_review_count // empty')
```

An empty `$_status` — no HTTP response at all — falls to `*` and is `unknown`.

### `none` is a whitelist, never a fallback

Every path to `none` names the exact answer that produced it: a `404`, a `403`
whose body carries GitHub's plan-limit message, or a `2xx` whose body parsed
cleanly into "no rule" / `0`. Everything else — a `403` from a permission,
rate-limit or SAML/SSO denial, a `2xx` with an empty body, a body `jq` cannot
parse, a count that is not a plain integer — lands on `unknown` and the gate
stays on.

That asymmetry is the whole point. `unknown` costs a `[SKIPPED]` the next tick
retries; `none` on a repo that really does require approvals is an unreviewed
merge. `dEitY719/dotfiles#1519` narrowed which answers are definitive; it must never widen
which answers are *assumed* definitive.

The `403` split is what the PR dEitY719/dotfiles#1526 review added: the original patch keyed on
the status alone, and GitHub reuses `403` for "your plan lacks this feature",
"your token may not read this", "you are rate limited", and "this org needs
SSO". Only the first is a statement about the policy.

### Per-source verdicts

| Result | Meaning | Verdict |
|---|---|---|
| `2xx`, count `>= 1` | approvals are required | `<n>` |
| `2xx`, count `0` | a rule exists and asks for **zero** approvals | `none` |
| `2xx`, no matching rule | this source imposes no PR review rule | `none` |
| `403` + `Upgrade to GitHub Pro` in the body | the plan does not have this feature — no policy *can* exist | `none` |
| `403`, any other body | permission / rate-limit / SSO denial — the policy is unreadable, not absent | `unknown` |
| `404` | the feature exists but is not configured for this base | `none` |
| `2xx` with an empty or unparseable body | an answer arrived but was not understood | `unknown` |
| anything else (5xx, 401, network, no response) | genuinely undetermined | `unknown` |

### Combining the two sources (dEitY719/dotfiles#1519 F-3, F-4)

| Sources | Gate | Header (dEitY719/dotfiles#1519 NF-1) |
|---|---|---|
| either says `required n >= 1` | **on** — strictest `n` wins | `on (<source>: <n> approvals)` |
| neither requires, at least one `unknown` | **on** — fail-closed | `on (fail-closed: <base> policy unreadable)` |
| both `none` | **off** | `off (no policy on <base>)` |

`required` outranks `unknown` for the header text only; both mean the gate is
on. The three header strings are not cosmetic: distinguishing them is what
makes dEitY719/dotfiles#1519's symptom visible — `report-format.md` → "The `approval gate:`
field" carries the reason and is what the doc-guard tests pin.

## Why 403 and 404 are "no policy", not "lookup failed" (dEitY719/dotfiles#1519 D-1)

`403 Upgrade to GitHub Pro or make this repository public to enable this
feature` and `404 Branch not protected` are statements *about the policy*, not
failures to read it. (A `404` here cannot be a hidden access failure: Step 2's
`gh pr list` already succeeded against this repo, so the token can see it.) On a free-plan private repo the ruleset endpoint answers
403 for every base, forever. Treating that as "approval required" invents a
rule the platform cannot enforce, and on a `--author @me` train it is
unclearable: `gh-pr:approve` cannot approve a self-authored PR, and NF-2
forbids `gh-pr:merge-emergency`. The result is `[SKIPPED] approval required` on
every tick with no action any human or skill can take — the same disease as the
`[FAILED]` this file forbids two sections down, wearing a different name.

`gh-pr-merge/references/strategy-selection.md` → "Branch protection detection"
already states this rule — 403 means the feature is locked by plan, 404 that it
is unlocked but unconfigured, and neither would have required an approval. The
*judgement* was already in this repo; only the train disagreed. (Its
*mechanism* still sniffs `gh api`'s exit code, so it cannot tell a 5xx from a
403 either; it fails open rather than closed, so the same information loss
shows up there as an over-permissive read instead of an unclearable skip.)
`dEitY719/dotfiles#1513` fixed the same asymmetry in `gh-pr:merge`'s board gate.

**No opt-in gate is required for the off verdict.** If the repo owner put no
approval policy on this base, the safety boundary is exactly where they put it
— the same reasoning that makes skipping at `0` legitimate. Off does *not*
mean "merge unreviewed", though: the off path runs a delegated review first
(dEitY719/dotfiles#1519 D-3, next section).

## Why both sources, and not just `gh-pr:merge`'s one (dEitY719/dotfiles#1519 D-2)

Making this identical to `gh-pr:merge` — read classic protection only — would
be a regression, not a simplification. A repo that enforces review purely
through rulesets answers `404` on the classic endpoint, so a protection-only
read verdicts `none` and turns the gate **off** on a base that genuinely
requires approvals. For a human running `gh-pr:merge` on one PR that is a
recoverable mistake; in an unattended loop it is a batch of unreviewed merges.
Reading both and taking the strictest is what makes "off" trustworthy enough to
act on.

## Why the gate being off still runs a review (dEitY719/dotfiles#1519 D-3, D-4)

Gate off means "the *platform* does not require an approval". It does not mean
"nobody needs to look at this". On the off path the train runs
`Skill(gh-pr:approve, "<N> <remote> --self-record")` once before merging and
reads the board back as that review's verdict — the procedure, its re-review
suppression, and its failure handling are in `train-loop.md` → "Delegated
review on the gate-off path".

That step is not a rubber stamp: of eight agent-run `--self-record` reviews in
the issue dEitY719/dotfiles#1477 session, one withheld promotion over a real defect.

Reading the board here is **not** a revival of the board *gate* `dEitY719/dotfiles#1513`
retired — see `train-loop.md` → "Gates `gh-pr:merge` owns", which keeps that
distinction next to the board read it governs.

## Why skipping at `0` is not a bypass

`gh-pr:merge` refuses un-approved PRs and points at `gh-pr:merge-emergency`.
That is right for a human at a keyboard, but wrong as a train's normal path,
for two reasons that compound:

1. `gh-pr:approve` **cannot approve a self-authored PR** — GitHub forbids it.
   With `--author @me` (D-7), every PR in this train is self-authored. So the
   approval the gate wants can never be obtained by any skill in this repo.
2. `gh-pr:merge-emergency` would satisfy the gate, but it exists to create an
   audit trail for an *exception*: a reason comment plus a follow-up incident
   issue, every time. On the normal path it would file an incident issue per
   merge. Incidents that happen on schedule are not incidents.

When the ruleset says `required_approving_review_count = 0`, the platform is
stating that this repo does not require approval. Following that is **obeying
the policy, not routing around it** — the safety boundary is exactly where the
repo owner put it. On a repo that does require approvals, the same code path
refuses the merge and records the reason. Nothing is weakened.

## Why the gate being off is not sufficient

The gate above answers "does *the platform* require an approval". It does not
answer "will `gh-pr:merge` accept this PR", and those are not the same
question. `gh-pr:merge` Step 2 hard-stops on `reviewDecision != APPROVED` and
makes exactly one exception — base-branch protection **absent** *and*
`reviewDecision == ""` (`gh-pr-merge/references/strategy-selection.md` →
"Branch protection detection"). A **non-empty, non-`APPROVED`**
`reviewDecision` (`REVIEW_REQUIRED`, `CHANGES_REQUESTED`) stops it either way.

So a PR can pass this skill's gate and still be refused downstream. Left
alone, that PR burns all three F-5 attempts against a decision that cannot
change, lands as `[FAILED]`, and — since NF-2 forbids `gh-pr:merge-emergency`,
the only thing that would clear it — comes back `[FAILED]` on every subsequent
tick. **A train must never be able to produce an unclearable `[FAILED]`.**

Therefore: **check `reviewDecision` before calling `gh-pr:merge`, even when the
gate is off.** A non-empty value that is not `APPROVED` is
`[SKIPPED] gh-pr:merge refuses reviewDecision=<value>` — retriable the moment a
human approves or dismisses the review, and never an attempt. It is also
checked **before** the delegated review, so a PR a human explicitly blocked is
never handed to a self-record run that might promote it.

The empty (`""`) case is the delegated review's path: with protection absent
`gh-pr:merge` accepts it by design, so this is where the train supplies the
review signal the platform is not asking for.

## Why lookup failure is still fail-closed

A merge is hard to undo. A skipped PR is trivially retried on the next tick.
When the two error directions are that asymmetric, the cheap mistake is the one
to make: an *undetermined* policy is treated as "approval required", so
unapproved PRs are `[SKIPPED] policy unreadable — approval assumed required`
and nothing merges on a guess.

`dEitY719/dotfiles#1519` narrowed **what counts as undetermined**; it did not weaken the
principle. A 5xx, a 401, or a dead network still fails closed. What no longer
fails closed is a definitive answer that happens to arrive with a 4xx status.

## Applying it per PR

Look up the requirement for **that PR's own base**, from the per-base cache
above — the read happens once per distinct base, not once per PR and not once
per run. Then apply it against that PR's own `reviewDecision`:

- `reviewDecision == APPROVED` → proceed, gate on or off, no delegated review:
  a real approval already exists and re-reviewing it would be waste.
- gate on and anything else (`REVIEW_REQUIRED`, `CHANGES_REQUESTED`, `""`) →
  `[SKIPPED] approval required (reviewDecision=<value>)`, next PR.
- gate off and `reviewDecision` non-empty and not `APPROVED` →
  `[SKIPPED] gh-pr:merge refuses reviewDecision=<value>`, next PR (previous
  section — this is the case that would otherwise become an unclearable
  `[FAILED]`).
- gate off and `reviewDecision == ""` → **delegated review**
  (`train-loop.md` → "Delegated review on the gate-off path").

A `CHANGES_REQUESTED` PR is skipped **even when the gate is off**: someone
explicitly blocked it, and the absence of a platform rule does not overrule a
human's stated objection.
