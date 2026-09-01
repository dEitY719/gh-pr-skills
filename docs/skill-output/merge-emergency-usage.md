# merge-emergency 사용 결과

> **한 줄 요약** — 미승인 PR 과 10자 이상의 서면 사유를 받아, admin 우회 머지와
> 사유 코멘트 1건 + 후속 incident 이슈 1건을 생성합니다.

> NOTE: 이 문서는 **미실행 예시**입니다. gh-pr 의 8개 스킬은 모두 live GitHub
> repo 에 쓰기를 하고, 이 저장소에는 대상 PR 이 없으며 커밋/push 가 금지된
> 작업이었으므로 문서화 목적의 실행을 하지 않았습니다. 아래 명령과 게이트는
> `skills/merge-emergency/SKILL.md` 에서 인용한 것이고, 결과 절은 실행 시 생성되는
> 산출물을 기술합니다. 실제 실행 로그가 아닙니다.

```
미승인 PR + 서면 사유  ──▶  /gh-pr:merge-emergency  ──▶  머지된 PR + 사유 코멘트 + 인시던트 이슈
```

## 1. 실행할 명령

```
/gh-pr:merge-emergency <PR> <reason> [remote]                       # 범용 형식
/gh-pr:merge-emergency 42 "INC-1031 prod 500 on /login since 14:00 KST"   # 이 repo(dEitY719/gh-pr-skills, origin) 대상
```

## 2. 입력

- **PR 번호** — 생략 시 현재 브랜치의 PR 을 자동 탐지하고, 그것도 없으면 중단.
- **사유** — 필수, **10자 이상**, 인시던트/티켓 ID 또는 구체적 사용자 영향 포함.
  `"urgent"` / `"fix"` / `"merge now"` 는 거부.
- **remote** — 기본 `origin`. 이 URL 하나에서 `TARGET_REPO` 와 `TARGET_HOST` 를 함께 해석.

실행 전 게이트(Step 2 — 하나라도 어긋나면 하드 스톱): PR `state == OPEN`,
draft 아님, conflict 없음, **필수 CI 통과**, 그리고 `Proceed? (yes/ok/진행/머지)` 에 대한
긍정 응답. **우회 대상은 승인 요건뿐이고 CI 는 여전히 게이트합니다.**

## 3. 결과 (실행 시)

| 산출물 | 남는 위치 | 검증 방법 |
|---|---|---|
| 사유 코멘트 | 대상 PR 타임라인 (머지 **전**) | `gh pr view <N> --comments` 에 `[EMERGENCY]` 헤더 + 사유 + 머지 직전 상태 |
| 머지된 PR | base 에 squash 커밋 1개, head 브랜치 삭제 | `gh pr view <N> --json mergeCommit -q .mergeCommit.oid` 가 SHA 반환 |
| incident 이슈 | Issues (`incident: emergency merge of PR #<N> — ...`) | 머지 SHA + 인용 사유 + 72시간 회고 체크리스트 + ai-metrics 푸터 |
| 보드 카드 | 프로젝트 보드 `Done` | 보드 미부착/실패 시 조용히 건너뜀 |

보고에는 머지 SHA, 감사 코멘트 URL, incident 이슈 번호와 URL, 사유,
`[WARN] Add retro notes to incident issue within 72h.` 가 출력됩니다.
