# Approval Templates — for gh-pr:approve skill

Every command below is host-pinned and repo-scoped with the `TARGET_HOST` /
`TARGET_REPO` bound in Step 1 (`references/arg-parsing.md`).

All three paths write the body to a `mktemp` file first (avoids shell-escaping and concurrent-run collisions), then call `gh`. Match the language dominant in the PR body/comments.

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write the drafted body to "$BODY" ...
```

## 6a — Clean LGTM

No findings. Approve with 2–4 specific compliments.

### Body template

```markdown
LGTM

### 요약
<한 문단 — 이 PR이 달성한 것, 리뷰 관점의 핵심 포인트>

### 잘 된 점
- <file:path:line 또는 short-sha 근거>로 <왜 좋은지>
- <...>
- <...>

<선택: 이 PR이 프로젝트에 주는 가치를 1줄로>
```

### Command

```bash
GH_HOST="$TARGET_HOST" gh pr review <N> --repo "$TARGET_REPO" --approve --body-file "$BODY"
```

## 6b — Approve with Follow-up Issues

No BLOCKERs, ≥1 FOLLOW-UP. Three-step sequence — **do them in order**.

### Step 1 — Create one issue per follow-up

```bash
ISSUE_BODY=$(mktemp) && trap 'rm -f "$ISSUE_BODY"' EXIT
# ... write the issue body ...
GH_HOST="$TARGET_HOST" gh issue create \
  --repo "$TARGET_REPO" \
  --title "<type>: <concise description>" \
  --body-file "$ISSUE_BODY" \
  --assignee @me
```

Issue body template:

```markdown
## 배경
PR #<PR> 리뷰 중 발견된 후속 개선 항목.

## 현상
<file:path:line 또는 함수/블록 이름>에서 <observation>.

## 제안
<actionable fix — code snippet or prose>

## 참고
- Refs #<PR> (리뷰 시점: <short-sha>)
- <optional: 관련 docs/링크>
```

Collect each created issue number for Step 2.

### Step 2 — Post one PR comment linking all follow-ups

```bash
COMMENT_BODY=$(mktemp) && trap 'rm -f "$COMMENT_BODY"' EXIT
# ... write comment body ...
GH_HOST="$TARGET_HOST" gh pr comment <N> --repo "$TARGET_REPO" --body-file "$COMMENT_BODY"
```

Comment template:

```markdown
리뷰하면서 발견한 후속 개선 항목을 이슈로 분리해 두었습니다. 이 PR 머지와 독립적으로 처리해주시면 됩니다.

- #<A> — <한 줄 요약>
- #<B> — <한 줄 요약>
- #<C> — <한 줄 요약>

Approve는 별도로 제출합니다 — 아래 리뷰 참고.
```

### Step 3 — Submit approving review

Body template (extends 6a + a follow-up section):

```markdown
LGTM

### 요약
<PR 핵심 요약 1문단>

### 잘 된 점
- <file:line 근거로 왜 좋은지>
- <...>

### 후속 개선 (별도 이슈)
- #<A>, #<B>, #<C> — 본 PR 머지와 독립적으로 추적합니다.
```

```bash
GH_HOST="$TARGET_HOST" gh pr review <N> --repo "$TARGET_REPO" --approve --body-file "$BODY"
```

## 6c — Request Changes (BLOCKERs present)

Never approve. List each blocker with a `file:line` pointer and the minimal fix expected. Blockers stay on the PR; the author's next push triggers natural re-review.

### Body template

```markdown
머지 전에 반드시 수정이 필요한 항목이 있어 **Request changes**로 남깁니다.

### Blockers

1. **<short title>** — `<file>:<line>`
   - 증상: <what's wrong>
   - 제안: <minimal fix>
   - 근거: <why this blocks merge — regression / security / spec violation>

2. **<...>** — `<file>:<line>`
   - ...

### 참고로 잘 된 점
- <1–2 specific compliments so the author knows what to keep>

수정 후 push 주시면 재리뷰하겠습니다.
```

### Command

```bash
GH_HOST="$TARGET_HOST" gh pr review <N> --repo "$TARGET_REPO" --request-changes --body-file "$BODY"
```

## Self-PR bodies

Self-authored PRs never use `--approve`; GitHub rejects same-user approval
server-side. Use `self-pr-handling.md` for mode selection and command shapes.

### `--self-record` body suffix

Append this to the review body before `gh pr review --comment` or fallback
`gh pr comment`:

```markdown
### Self-PR note

This is a self-authored PR. GitHub blocks self-approval server-side, so this
comment records review analysis only and does not satisfy review-based branch
protection. External review or admin merge is still required where protection
rules apply.
```

### `--admin-merge` body note

If follow-up issues are created before an admin merge, post one PR comment:

```markdown
Self-authored PR reviewed before admin merge. GitHub blocks self-approval
server-side, so no approving review was submitted.

Follow-up issues:
- #<A> — <one-line summary>
- #<B> — <one-line summary>
```

## Language matching

Scan the PR body + most recent 3 human comments. Reply in the dominant language. Korean PR → Korean review. Mixed → match the PR body.

## Don'ts

- **Never** attach `--label`/`--milestone` to follow-up issues unless verified via `gh label list` / `gh api` that they exist — silent failures or surprise taxonomy damage is worse than terse issues. `--assignee @me` is exempt from this rule (issue #1523): the authenticated user always exists, so there is nothing to verify and no taxonomy risk — it is added unconditionally.
- **Never** submit a `--comment` review as a substitute for `--approve`, except the explicit `--self-record` path. Comment reviews do not satisfy branch protection.
- **Never** re-submit a review if one already exists — GitHub dismisses stale ones; check `reviewDecision` first.
