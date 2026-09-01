# approve 사용 결과

> **한 줄 요약** — PR diff 와 리뷰 기준을 받아 리뷰 verdict 와 후속 이슈를 생성합니다.

> NOTE: 이 문서는 **미실행 예시**입니다. gh-pr 의 8개 스킬은 모두 live GitHub
> repo 에 쓰기를 하고, 이 저장소에는 대상 PR 이 없으며 커밋/push 가 금지된
> 작업이었으므로 문서화 목적의 실행을 하지 않았습니다. 아래 명령과 게이트는
> `skills/approve/SKILL.md` 에서 인용한 것이고, 결과 절은 실행 시 생성되는
> 산출물을 기술합니다. 실제 실행 로그가 아닙니다.

```
PR diff + 리뷰 기준  ──▶  /gh-pr:approve  ──▶  리뷰 verdict + 후속 이슈
```

## 1. 실행할 명령

범용 형식 / 이 repo(`dEitY719/gh-pr-skills`, remote `origin`) 대상 형식:

```
/gh-pr:approve [<PR#>] [<remote>] [--self-record | --admin-merge [--squash|--rebase|--merge]]
/gh-pr:approve 12
/gh-pr:approve 12 --self-record   # 자기가 작성한 PR 은 승인 대신 이 경로
```

## 2. 입력

대상 PR 의 diff, 커밋, 그리고 세 개의 코멘트 엔드포인트(inline / issue / review) 전부와,
`skills/approve/references/review-criteria.md` 의 체크리스트. 실행 전 게이트(Step 1):

- PR 이 `OPEN` 이고 draft 가 아니며 required check 가 실패가 아닐 것 — 하나라도 걸리면 정지.
- `mergeable: CONFLICTING` / `rebaseable: false` 는 정지가 아니라 경고이며, 경고 블록이
  리뷰 본문과 최종 보고에 붙는다.
- `author.login == ME` 이면 승인 경로가 열리지 않는다. GitHub 이 self-approval 을 서버
  측에서 거부하므로 스킬이 API 호출 전에 막는다.

## 3. 결과 (실행 시)

- PR 에 **리뷰 verdict 1개** — blocker 0이면 `--approve`, 1개 이상이면 `--request-changes`.
  승인 본문에는 file:line 또는 short SHA 근거를 댄 구체적 칭찬이 최소 1개 들어간다.
- **FOLLOW-UP 마다 GitHub 이슈 1개** + 그것들을 링크하는 PR 코멘트 1개(4b 경로).
- **ai-metrics PR 코멘트 1개**(`GH_DISABLE_AI_METRICS=1` 이면 생략).
- **projectV2 보드 카드 `Approved` 승격** — 4a / 4b / `--self-record` 에서만.
- 최종 보고에 `reviewDecision`, `mergeStateStatus`, blocker/follow-up 개수, 이슈 링크,
  PR URL. 검증은 PR 페이지의 review 상태와 새로 생긴 이슈 번호로 한다.
