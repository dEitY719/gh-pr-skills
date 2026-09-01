# reply 사용 결과

> **한 줄 요약** — PR 의 리뷰 코멘트 전부를 받아 코멘트별 답글과 반영된 수정 커밋을 생성합니다.

> NOTE: 이 문서는 **미실행 예시**입니다. gh-pr 의 8개 스킬은 모두 live GitHub
> repo 에 쓰기를 하고, 이 저장소에는 대상 PR 이 없으며 커밋/push 가 금지된
> 작업이었으므로 문서화 목적의 실행을 하지 않았습니다. 아래 명령과 게이트는
> `skills/reply/SKILL.md` 에서 인용한 것이고, 결과 절은 실행 시 생성되는
> 산출물을 기술합니다. 실제 실행 로그가 아닙니다.

```
리뷰 코멘트 전부  ──▶  /gh-pr:reply  ──▶  코멘트별 답글 + 반영된 수정
```

## 1. 실행할 명령

범용 형식:

```
/gh-pr:reply [<PR#>] [<remote>]
```

이 repo(`dEitY719/gh-pr-skills`) 를 대상으로 했을 때:

```
/gh-pr:reply 12
```

인자를 생략하면 현재 브랜치의 PR 을 쓴다. 브랜치에 PR 이 없으면 추측하지 않고 멈춘다.
fork 워크플로에서는 `/gh-pr:reply 12 upstream` 처럼 remote 를 명시한다.

## 2. 입력

- **입력** — 세 엔드포인트의 리뷰 코멘트 전량: `pulls/<N>/comments`(인라인),
  `issues/<N>/comments`(대화), `pulls/<N>/reviews`(리뷰 요약). 스레드의 마지막
  코멘트를 본인/Claude 가 쓴 스레드만 dedup 으로 제외한다.
- **게이트** — 대상 PR 이 해석될 것(명시 인자 우선, 없으면 현재 브랜치),
  `TARGET_REPO` 와 `TARGET_HOST` 가 같은 remote URL 에서 바인딩될 것. dedup 후
  미처리 스레드가 0건이면 `reply-pending` 만 정리하고
  `No unaddressed review comments — nothing to do.` 출력 후 즉시 종료.

## 3. 결과 (실행 시)

- **코멘트별 답글** — 수집한 모든 코멘트에 1개씩. 인라인은 `pulls/<N>/comments/<id>/replies`,
  대화 코멘트와 리뷰 요약은 원문을 인용한 새 top-level 코멘트. 봇 코멘트와 거절한 건도 예외가 아니다.
- **수정 커밋** — ACCEPT / ACCEPT-PARTIAL 의 실제 수정이 주제 단위 커밋으로 묶여 push 된다
  (force-push 없음). 답글에 해당 커밋 short-SHA 가 들어간다.
- **라벨 변화** — push 가 있었으면 낡은 `review-passed` 해제 + 카드 `In review` 복귀. 미해결
  BLOCKER 가 없고 외부 리뷰 근거가 있으면 `review-passed` 적용. `reply-pending` 은 항상 제거.
- **터미널 요약 표** — Accepted / Declined / Answered 카운트, 리뷰어별·심각도별 breakdown,
  `review-passed` 게이트 결과 한 줄, 커밋 SHA, `-> All comments replied to.` 마무리 줄,
  `reviewDecision` 이 여전히 `CHANGES_REQUESTED` 면 재리뷰 안내 한 줄.
- **ai-metrics PR 코멘트** — 차트/사람/로봇 글리프로 토큰·사람 시간·경과 분을 적는 푸터(soft-fail).
