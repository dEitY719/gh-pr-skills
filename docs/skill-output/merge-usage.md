# merge 사용 결과

> **한 줄 요약** — 승인된 PR 을 받아 머지된 PR 과 삭제된 브랜치를 생성합니다.

> NOTE: **미실행 예시** — gh-pr 스킬 8개는 모두 live repo 에 쓰므로 문서화 목적으로 실행하지 않았습니다. 명령·게이트·결과는 `skills/merge/SKILL.md` 인용이며 실행 로그가 아닙니다.

```
승인된 PR  ──▶  /gh-pr:merge  ──▶  머지된 PR + 삭제된 브랜치
```

## 1. 실행할 명령

```
/gh-pr:merge <pr-number> [rebase|squash|merge] [remote]
/gh-pr:merge 12            # 기본 전략 rebase, 확인을 묻지 않는다
/gh-pr:merge 12 squash     # squash 로 접어서 머지
# 내부 호출: GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

## 2. 입력

입력은 **승인이 끝난 열린 PR 하나**와 전략 선택이다. Step 2 게이트를 하나라도 어기면 머지하지 않고 정지한다 — 강행하지 않는다:

- `state != OPEN` / `isDraft` / `mergeable == CONFLICTING` / `mergeStateStatus` 가 `BEHIND`·`BLOCKED`·`DIRTY` / required check 가 `FAILURE`·`IN_PROGRESS`·`QUEUED`.
- `reviewDecision != APPROVED` → `/gh-pr:merge-emergency` 로 안내. 유일한 예외는 base 브랜치에 protection 이 없고 `reviewDecision` 이 빈 문자열인 경우다.
- 선택한 전략이 저장소에서 비활성화돼 있으면 안내 후 정지 — 다른 전략으로 바꾸지 않는다.

## 3. 결과 (실행 시)

- **PR 이 머지되고 head 브랜치가 삭제된다**(항상 `--delete-branch`). 이어서 projectV2 보드의 PR 카드와 연결된 이슈 카드가 `Done` 으로 이동하고, `review-passed` 라벨이 제거되며, ai-metrics PR 코멘트가 남는다(전부 soft-fail).
- 다음 형태의 compact 보고가 출력된다(`mergeCommit.oid` 가 아직 없으면 `(pending)`). 정지한 경우에는 `[FAIL] PR #<N> not merged — <reason>` 과 리다이렉트 안내가 나온다.

```
[OK] PR #<N> merged (<strategy>)
  Merge SHA:  <sha>
  Branch:     <headRefName> → <baseRefName> (deleted)
  URL:        <pr-url>
```

- 보고 출력 후, watched-repos 레지스트리에 등록된 저장소에 한해 post-merge 검증 dispatch 가 인라인 실행된다. dispatch 블록 파일이 없으면 `[WARN]` 한 줄을 찍고 건너뛴다.
