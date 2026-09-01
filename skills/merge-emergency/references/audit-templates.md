# Audit Templates — for gh-pr:merge-emergency skill

All bodies are written to `mktemp` files first (avoids shell escaping and
concurrent-run collisions). Match the language dominant in the PR body
(Korean PR → Korean audit notes).

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write the drafted body to "$BODY" ...
```

## Step 4 — PR audit comment (posted BEFORE merge)

Anchors the event on the PR timeline so it survives branch deletion.

### Body template (English)

```markdown
[EMERGENCY] **Emergency merge** by @<ME> at <NOW> UTC

**Reason:** <reason>

This PR is being merged via `gh pr merge --admin`, bypassing the normal
approval requirement. A follow-up incident issue will be filed immediately
after merge for retro within 72h.

**Pre-merge state**
- Base: `<baseRefName>` · Head: `<headRefName>`
- Required CI: [OK] passing
- Approving reviews: <count> (normal merge would need ≥1)
- Merge status at decision time: `<mergeStateStatus>`

If you believe this bypass was not justified, comment here or on the
incident issue — the decision is auditable.
```

### Body template (Korean)

```markdown
[EMERGENCY] **긴급 머지** — @<ME>, <NOW> UTC

**사유:** <reason>

이 PR은 `gh pr merge --admin`으로 approval 요구사항을 건너뛰고
머지됩니다. 머지 직후 회고용 incident 이슈가 자동 생성되며, 72시간
이내 retro 작성이 원칙입니다.

**머지 직전 상태**
- Base: `<baseRefName>` · Head: `<headRefName>`
- 필수 CI: [OK] 통과
- Approve 리뷰: <count>건 (정상 경로는 ≥1 필요)
- Merge status: `<mergeStateStatus>`

바이패스 타당성에 의문이 있으면 이 코멘트 또는 incident 이슈에 남겨
주세요 — 의사결정이 감사 가능하도록 기록됩니다.
```

### Command

```bash
GH_HOST="$TARGET_HOST" gh pr comment <N> --repo "$TARGET_REPO" --body-file "$COMMENT"
```

Capture the comment URL from the command output for Step 7's report.

## Step 5 — Admin merge command

```bash
GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --admin --squash --delete-branch
```

Flags rationale:
- `--admin` — bypasses branch protection (approval requirement, up-to-date
  branch rule). This is the whole point of the skill.
- `--squash` — single atomic commit on base; trivially revertable if the
  hotfix itself regresses something.
- `--delete-branch` — head branch is disposable once merged; keeps the repo
  tidy and prevents accidental future pushes to it.

If the command fails with "Must have admin rights" → the caller does not
have admin. Stop; do NOT retry with `--merge` / `--rebase` (those won't
bypass protection either, and trying them wastes audit clarity).

Extract the merge commit SHA from PR JSON after merge:
```bash
SHA=$(GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" \
  --json mergeCommit -q .mergeCommit.oid)
```

## Step 6 — Post-merge incident issue

Title format: `incident: emergency merge of PR #<N> — <reason first line truncated to 60 chars>`

### Body template (English)

```markdown
## Context

Emergency-merged **PR #<N>** at <NOW> UTC by @<ME>, bypassing the normal
approval path via `gh pr merge --admin`.

- PR:         <PR URL>
- Merge SHA:  `<SHA>`
- Base:       `<baseRefName>`
- Author:     @<PR author>

## Stated reason

> <reason>

## Retro checklist (complete within 72h)

- [ ] Root cause — 1 sentence, tied to the user impact.
- [ ] Why normal review path wasn't viable at decision time.
- [ ] What made this a *real* emergency vs. just inconvenient timing.
- [ ] Follow-up actions: tests added, alerting added, process change, etc.
- [ ] Any collateral risk taken on by the bypass (e.g., skipped reviewer
      perspective) and how it will be reviewed post-hoc.
- [ ] Link to postmortem / retro document, if one was written.

## Prevention

- [ ] Could an earlier alert / test / guardrail have prevented the need
      for an emergency?
- [ ] Is the on-call reviewer rotation healthy? Any gap to fix?

Close this issue with a comment summarizing the retro once items above
are complete.
```

### Body template (Korean)

```markdown
## 컨텍스트

**PR #<N>** 을 <NOW> UTC에 @<ME> 가 긴급 머지 (`gh pr merge --admin`
으로 approval 경로 우회).

- PR:         <PR URL>
- Merge SHA:  `<SHA>`
- Base:       `<baseRefName>`
- Author:     @<PR author>

## 사유

> <reason>

## 회고 체크리스트 (72시간 이내 완료)

- [ ] 근본 원인 — 유저 영향과 연결된 한 문장으로.
- [ ] 의사결정 시점에 정상 리뷰 경로가 불가능했던 이유.
- [ ] 단순히 타이밍이 안 맞는 게 아니라 *진짜* 긴급이었던 근거.
- [ ] 후속 액션: 테스트 추가, 알림 추가, 프로세스 변경 등.
- [ ] 바이패스로 감수한 부수 리스크 (예: 리뷰어 관점 누락) 및 사후
      검토 방법.
- [ ] 포스트모템/회고 문서 링크 (있으면).

## 재발 방지

- [ ] 더 이른 시점의 alert / test / 가드레일로 이 긴급을 예방할 수
      있었는가?
- [ ] 당번 리뷰어 로테이션은 건강한 상태인가? 메울 공백이 있는가?

위 항목이 채워지면 회고 요약 코멘트와 함께 이 이슈를 닫는다.
```

### Command

```bash
GH_HOST="$TARGET_HOST" gh issue create --repo "$TARGET_REPO" \
  --title "<title>" --body-file "$ISSUE"
```

Do NOT add labels/milestones unless `GH_HOST="$TARGET_HOST" gh label list --repo "$TARGET_REPO"`
confirms an `incident` label already exists; if it does, apply it.

Capture the issue URL + number from the command output for Step 7's report.
