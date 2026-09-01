# gh-pr:merge-emergency — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | PR number, or `-h`/`--help`/`help` | required (or current-branch PR) | Target PR, e.g. `42` |
| 2 | reason | **required** | Written justification, ≥10 chars, must reference incident/ticket or user impact |
| 3 | remote name | `origin` | Git remote for the target repo |

## Usage

```
/gh-pr:merge-emergency 42 "INC-1031 prod 500 error on login since 14:00 KST"
/gh-pr:merge-emergency 42 "revenue impact — checkout broken for 12% of users" upstream
/gh-pr:merge-emergency -h
```

## When to use this skill

- Weekend / after-hours hotfix and no reviewer is reachable.
- Production incident mitigation (revert / feature-flag kill / config).
- Security patch that cannot wait for async review.

## When NOT to use

- "My reviewer is slow" — ping them or reassign instead.
- Missing a tiny nit you want to skip — ask for a lightweight re-review.
- Self-assigned vanity PR — normal review path applies.
- CI is failing and you think it's flaky — rerun, don't bypass. This
  skill refuses to merge with failing required CI.

## What the skill does

1. Validates PR state (open, not draft, no conflicts) and that required CI is green.
2. Shows you the exact plan (repo, PR, base/head, CI summary, reason) and waits for your confirmation.
3. Posts a visible audit comment on the PR explaining *why* this is being emergency-merged.
4. Runs `GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --admin --squash --delete-branch` to bypass approval requirements.
5. Creates a follow-up `incident:` issue with a retro checklist so the decision is tracked and reviewed later.
6. Moves the PR project-board card to `Done` when a projectV2 board is attached.
7. Reports the merge SHA, audit comment URL, and incident issue number.

## Good reason examples

- `"INC-1031 prod 500 on /login since 14:00 KST — reviewer on vacation"`
- `"revenue impact — checkout 5xx for paid tier, hotfix reverts PR #41"`
- `"security: CVE-2024-XXXX RCE in dependency, upstream patched 2h ago"`
- `"customer-reported data loss on /projects; kill-switch flag via config"`

## Bad reason examples (will be refused)

- `"urgent"` — too vague
- `"fix"` / `"hotfix"` — no user impact stated
- `"reviewer slow"` — use normal path or reassign
- `"merge now"` — not a reason

## What this skill will NOT do

- Bypass CI failures (approval bypass only).
- Merge a draft PR or one with conflicts.
- Skip the incident issue — the audit tail is mandatory.
- Auto-confirm; it always asks before executing.
- Push code or fix the underlying issue — it only merges what's already in the PR.

## After the merge

Within 72h, add to the incident issue:
- Root cause 1-liner.
- Why normal review path wasn't viable.
- Follow-up actions (tests added, process change, etc.).
- Close the incident issue with the retro link.
