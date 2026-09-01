# reply

> 한 줄 요약 — PR 의 모든 리뷰 코멘트에 **개별 답글**을 달고, 타당한 지적은 실제
> 수정 커밋으로 반영한다.

## 언제 쓰고 언제 안 쓰는가

- **쓸 때** — PR 에 리뷰 코멘트가 달린 뒤. 사람이든 봇이든(gemini-code-assist,
  sourcery-ai, copilot) 아직 답하지 않은 스레드가 있으면 이 스킬의 대상이다.
- **2차 의견을 새로 받아야 한다면 `/gh-pr:review`.** 그쪽은 집계 코멘트 1개만
  남기고 코멘트별 답글을 달지 않는다. 이 스킬은 반대로 집계 코멘트를 남기는
  스킬이 아니다 — 요약 코멘트 1개는 답글 패스가 아니다.
- **approve / request-changes 판정은 `/gh-pr:approve`.** 이 스킬은 판정을
  제출하지 않고, PR 카드를 `Approved` 컬럼으로 올리지도 않는다.
- **스레드를 닫거나 resolve 하는 것은 사용자의 몫.** 프로그램으로 resolve 하지
  않는다.
- **PR diff 밖의 파일 수정은 하지 않는다.** 필요하면 scope creep 을 먼저
  사용자에게 알린다.

## 호출 형식

근거: `skills/reply/references/help.md`.

```
/gh-pr:reply [<PR#>] [<remote>]
```

| 위치 인자 | 기본값 | 설명 |
|---|---|---|
| 1 | 현재 브랜치의 PR | 대상 PR 번호. `-h` / `--help` / `help` 면 도움말만 출력하고 종료 |
| 2 | `origin` | 대상 repo(`owner/repo`) 를 해석할 git remote |

- `/gh-pr:reply` — 현재 브랜치 PR 의 리뷰 코멘트를 처리한다.
- `/gh-pr:reply 123` — 다른 브랜치에서도 PR #123 을 강제 지정한다.
- `/gh-pr:reply 123 upstream` — fork 워크플로에서 `upstream` 쪽 repo 를 대상으로 한다.

현재 브랜치에 PR 이 없으면 멈추고 묻는다. "가장 최근 PR" 을 추측하지 않는다.

## 동작 단계

근거: `skills/reply/SKILL.md`.

1. **Step 1 — 대상 PR + repo 해석.** `START_TS` 를 즉시 기록한다. PR 번호는
   명시 인자 우선, 없으면 현재 브랜치에서 탐지한다. `TARGET_REPO` 와
   `TARGET_HOST` 는 **같은 remote URL 하나**에서 바인딩하고, 이후 모든 `gh` 호출은
   `GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"` 로 나간다
   (`gh api` 는 `--repo` 가 없으므로 경로에 repo 를 넣는다).
2. **Step 2 — 리뷰 코멘트 전량 수집.** 세 엔드포인트를 **모두** 조회한다:
   `pulls/<N>/comments`(인라인), `issues/<N>/comments`(대화),
   `pulls/<N>/reviews`(리뷰 요약). 봇은 내용을 이 셋에 흩뿌리므로 하나라도
   빠뜨리면 코멘트를 놓친다. 스레드의 **마지막** 코멘트 작성자가 본인/Claude 일
   때만 건너뛴다.
3. **Step 2.5 — 조기 종료.** dedup 후 미처리 스레드가 0건이면
   `reply-pending` 라벨 제거 블록을 돌린 뒤
   `No unaddressed review comments — nothing to do.` 만 출력하고 멈춘다. Step 3~7
   도, ai-metrics 도, push 도 없다.
4. **Step 3 — 코멘트별 평가.** 참조된 `path`/`line` 을 읽고 **ACCEPT /
   ACCEPT-PARTIAL / DECLINE / QUESTION** 으로 분류한다. 봇 코멘트도 같은 규칙을
   적용한다. 각 항목의 출처를 `<reviewer>:<severity>:<verdict>` 형태로 `ORIGINS`
   스트림에 기록한다 — Step 6 과 Step 7 이 같은 스트림을 읽는다.
5. **Step 4 — 수정 적용(ACCEPT / ACCEPT-PARTIAL 만).** 각 수정은 최소·국소로
   유지하고, 코멘트 단위가 아니라 주제 단위로 커밋을 묶는다. `--amend` 도
   `--no-verify` 도 쓰지 않는다.
6. **Step 5 — 전 코멘트 답글.** 협상 불가 항목이다. 거절한 건과 봇 코멘트를
   포함해 Step 2 에서 수집한 모든 코멘트가 답글을 받는다. 인라인 코멘트는
   replies 서브리소스로, 대화 코멘트와 리뷰 요약은 원문을 인용한 새 top-level
   코멘트로 답한다. 리뷰어가 쓴 언어로 답한다.
7. **Step 6 — push + 보드 동기화 + 판정 라벨.** 수정 커밋이 있으면 `git push`
   (force-push 금지)하고 새 SHA 를 보고한다. `PUSHED_FIXES > 0` 이면 카드를
   `In review` 로 되돌리고 낡은 `review-passed` 를 해제한다. 이어서
   `review-passed` 게이트를 돌린다: 외부 리뷰 근거(`ai-review` 마커)를 확인하고,
   미해결 **BLOCKER 심각도** 항목이 하나도 없을 때만 `review-passed` 를 붙인다.
   마지막으로 `reply-pending` 라벨 제거 블록을 무조건 한 번 더 돌린다.
8. **Step 7 — 보고.** Accepted / Declined / Answered 카운트, 리뷰어별·심각도별
   breakdown, `review-passed` 게이트 결과 한 줄, 커밋 SHA, 건너뛴 코멘트,
   그리고 `reviewDecision` 이 아직 `CHANGES_REQUESTED` 면 그 안내 한 줄을 출력한다.
   이어서 ai-metrics PR 코멘트를 게시한다(soft-fail,
   `GH_DISABLE_AI_METRICS=1` 이면 생략).

## 주의사항과 제약

근거: `skills/reply/references/constraints.md`.

- **답글을 건너뛰지 않는다.** 봇 코멘트 포함 전량이 답글 대상이며,
  "Declined: out of scope" 한 줄도 답글로 친다. 조용한 수정도 조용한 거절도 금지다.
  봇의 서비스 알림(쿼터/레이트리밋/장애 공지)은 4분류 루브릭 대신 한 줄 확인
  답글로 처리하고, Step 7 에 별도로 집계한다.
- **PR 카드를 `Approved` 로 올리지 않는다.** 그 컬럼은 `/gh-pr:approve` 소유다.
  답글과 봇 리뷰는 `COMMENTED` 이지 `reviewDecision` 을 바꾸지 않는다.
- **스레드를 프로그램으로 resolve 하지 않는다.**
- **`--amend` / `--no-verify` / force-push 금지.** history rewrite 가 필요하면
  멈추고 묻는다.
- **라벨·body 변경은 `_gh_pr_edit_safe_*` 를 경유한다.** classic Projects 가 붙은
  repo 에서 bare `gh pr edit` 이 조용히 exit 1 하기 때문이다.
  `review-passed` / `review-blocked` 를 손으로 붙이지 않는다 — 게이트 헬퍼가
  유일한 경로다.
- **NF-2("자가 인증 금지") 완화는 이 경로에 한정된다.** `review-passed` 는 외부
  AI CLI 재호출 없이 이 스킬의 판단으로 붙는다. 다만 fail-closed 방향은 그대로다
  — 미해결 BLOCKER 가 하나라도 있으면 라벨은 없고, 외부 리뷰 근거가 없는 PR 은
  라벨 없이 남으며, 라벨 쓰기 실패도 "미검증" 으로 읽힌다.
- `reply-pending` 라벨은 Step 2.5 와 Step 6 두 지점에서 제거된다. 남아 있으면
  `/gh-pr:merge-train` 이 그 PR 을 건너뛰어 머지 트레인에서 빠진다.
- **마이그레이션 부채** — 이 스킬은 dotfiles 의 `shell-common/functions/` 헬퍼
  (`gh_pr_review.sh`, `gh_host.sh`, `gh_pr_edit_safe.sh`,
  `gh_pr_reply_targeted_review.sh` 등)를 source 한다. dotfiles 체크아웃이 없는
  머신에서는 해당 단계가 degrade 한다.
