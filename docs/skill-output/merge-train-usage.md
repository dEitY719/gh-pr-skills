# merge-train 사용 결과

> **한 줄 요약** — 내가 연 열린 PR 목록을 받아, 한 번에 하나씩 정리·머지하고 PR 당 한 줄짜리 `[MERGED]` / `[SKIPPED]` / `[FAILED]` 보고서를 생성합니다.

> NOTE: **미실행 예시** — gh-pr 스킬 8개는 모두 live repo 에 쓰므로 문서화 목적으로 실행하지 않았습니다. 명령·게이트·결과는 `skills/merge-train/SKILL.md` 인용이며 실행 로그가 아닙니다.

```
내가 연 열린 PR 목록  ──▶  /gh-pr:merge-train  ──▶  순차로 머지된 PR 들
```

## 1. 실행할 명령

```
/gh-pr:merge-train [owner/repo] [remote]        # 범용 형식
/gh-pr:merge-train dEitY719/gh-pr-skills        # 이 repo 대상, host 는 origin 에서 (PR 이 하나뿐이면 /gh-pr:merge)
```

## 2. 입력

명령줄 인자가 아니라 **열려 있는 본인 PR 들** 자체가 입력입니다 (`gh pr list --author @me --state open`, D-7 — 동료 PR 은 보이지 않음). 큐 진입 조건:

| 게이트 | 통과 조건 |
|---|---|
| 공용 필터 (Step 2) | draft 아님, `reply-pending` 라벨 없음, **11분 quiet period** 밖 |
| 승인 정책 (Step 3) | 게이트 ON 이면 `reviewDecision == APPROVED`. `403`/`404` 는 "정책 없음", 판정 불가는 fail-closed |
| verdict 게이트 (Step 3.5) | `review-passed` 단독. `review-blocked` 또는 **두 라벨 모두 부재**는 `[SKIPPED]` |
| 처리 직전 재조회 (F-3) | 앞 PR 의 머지가 무효화한 상태를 다시 읽고 D-1 표로 재라우팅 |

**`/gh-pr:merge` 단독이라면 거부했을 PR 은 머지되지 않습니다** — train 은 `/gh-pr:merge-emergency` 를 절대 호출하지 않습니다(NF-2).

## 3. 결과 (실행 시)

- **머지된 PR 들** — 큐 순서(`CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`, 동순위 번호 오름차순)대로 **한 번에 하나씩**. 머지는 `gh-pr:merge` 가 전략 인자 없이(기본 rebase) 하고, `BEHIND` / `DIRTY` 는 그 전에 `gh-resolve:outdated` / `:conflict` 가 detached scratch worktree 에서 리베이스합니다 (`gh pr list` 로 큐가 줄었는지 확인).
- **보고서** — 일반 assistant 텍스트로만 출력(파일로 쓰지 않음). `queue: <n> PR(s)` 와 `approval gate: <판정>` 헤더, PR 당 한 줄과 사유, 마지막 `merged N · skipped N · failed N`.
- **부수 효과** — 머지 성공한 PR 의 구현 탭이 `idle` 이면 닫힙니다(#1565). train 자체는 GitHub 에 아무것도 쓰지 않고, ai-metrics 코멘트는 호출된 원자 스킬들이 각자 남깁니다.
