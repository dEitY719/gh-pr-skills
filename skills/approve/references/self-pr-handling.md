# Self-PR Handling

GitHub blocks self-approval server-side. When `author.login == ME`, do not
call `gh pr review --approve`; GitHub returns:

```text
Review Can not approve your own pull request
```

No prompt, token, PAT, or freeform flag can turn same-user self-approval
into a valid approving review. In particular, `--self-ok` is unsupported
and must be rejected before any API mutation.

## Initial Message

When the PR author is the authenticated user, print:

```text
self-PR detected (author == ME). GitHub blocks self-approval server-side.
Choose:
  --admin-merge   review then gh pr merge --admin (admin rights required)
  --self-record   comment-only review record + external reviewer guidance
  (default)       analyze only and exit without GitHub mutation
```

Then continue according to the selected mode.

## Default: Analysis Only

Read the diff and comments, classify findings, and print the review body
locally. Do not create comments, reviews, issues, or merges.

Append this line to the report:

```text
No GitHub review submitted because author and reviewer are the same user.
```

## `--self-record`: Comment-Only Record

Use this when the user wants an audit trail but cannot satisfy branch
protection by self-approval.

If BLOCKER exists:

```bash
GH_HOST="$TARGET_HOST" gh pr review <N> --repo "$TARGET_REPO" --comment --body-file "$BODY"
```

If no BLOCKER exists, use the same command with an LGTM-style body that
explicitly says it is not an approval:

```markdown
LGTM analysis only

This is a self-authored PR. GitHub blocks self-approval server-side, so this
comment does not satisfy review-based branch protection.
```

If `gh pr review --comment` is rejected for a self-authored PR, fall back to:

```bash
GH_HOST="$TARGET_HOST" gh pr comment <N> --repo "$TARGET_REPO" --body-file "$BODY"
```

After posting, re-fetch `reviewDecision` and report that external review or
admin merge is still required when branch protection applies.

### Board promotion (-> `Approved`)

`--self-record` is the explicit human action that promotes the card for
self-authored PRs (issue #1350). Run `references/board-approved-sync.sh.md`
with `BOARD_BYPASS=1`; that file holds the per-path table (the other two
self-PR modes never promote) and the rationale for the `#393` bypass and
its POSIX prefix form.

## `--admin-merge`: Admin Bypass Merge

Use this only for self-authored PRs and only after reading the diff.

Rules:

- If any BLOCKER exists, do not merge. Print blockers and stop.
- If FOLLOW-UP exists, create follow-up issues first unless the user asked
  for analysis only.
- Skip `gh pr review --approve`; it cannot work for the same GitHub user.
- Let `gh` print permission or branch-protection errors verbatim.

Command:

```bash
GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --admin
```

When the user supplied a strategy, append exactly one of:

```bash
--squash
--rebase
--merge
```

Do not silently switch strategies if GitHub rejects the selected method.

## Legal Alternatives Summary

- `gh pr merge --admin` - bypass branch protection using admin rights.
- `gh pr review --comment` - keep review analysis as a comment-only review.
- `gh pr comment` - fallback audit trail when comment reviews are rejected.
- External reviewer request - the normal path that satisfies review rules.
