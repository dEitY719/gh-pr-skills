# create 사용 결과

> **한 줄 요약** — base 에서 분기한 이후의 모든 커밋을 받아 Pull Request 1건을 생성합니다.

> NOTE: 이 문서는 **미실행 예시**입니다. gh-pr 의 8개 스킬은 모두 live GitHub
> repo 에 쓰기를 하고, 이 저장소에는 대상 PR 이 없으며 커밋/push 가 금지된
> 작업이었으므로 문서화 목적의 실행을 하지 않았습니다. 아래 명령과 게이트는
> `skills/create/SKILL.md` 에서 인용한 것이고, 결과 절은 실행 시 생성되는
> 산출물을 기술합니다. 실제 실행 로그가 아닙니다.

```
base 분기 이후의 모든 커밋  ──▶  /gh-pr:create  ──▶  Pull Request
```

## 1. 실행할 명령

범용 형식:

```
/gh-pr:create [issue-number] [remote] [--no-stack | --base <branch>]
```

이 저장소(`dEitY719/gh-pr-skills`, remote `origin`, base `main`)를 대상으로 했을 때:

```
/gh-pr:create                        # base 자동 결정(신호 없음 → main)
/gh-pr:create 42                     # 본문에 Closes #42 강제
/gh-pr:create --base release/v2.0    # base 명시, stacked 탐지 우회
/gh-pr:create -h                     # references/help.md 출력 후 중단
```

## 2. 입력

- **`<base>..HEAD` range 의 모든 커밋** — HEAD 하나가 아니다. `git log <base>..HEAD`
  가 곧 PR 본문의 계약이다.
- **이슈 번호(선택)** — 명시 인자 → 최근 대화의 `#N` → range 안 커밋 푸터 → 없으면 생략.
- **선행 조건(게이트):**
  - base 브랜치 위가 아니어야 한다(위면 "create a feature branch first" 로 중단).
  - `<base>..HEAD` 가 비어 있지 않아야 한다(`nothing-to-pr` 이면 중단).
  - `--no-stack` 과 `--base` 를 같이 주면 push 전에 `rc=2` 로 중단.
  - 자동 탐지된 부모 PR 은 `OPEN` 이어야 한다(`rc=5`).
  - Step 4.5 lint 게이트가 **push 전에** 통과해야 한다(`GH_PR_LINT_BYPASS=1` 로 skip).
  - upstream 이 diverge 했으면 중단하고 사용자에게 묻는다 — 스스로 force-push 하지 않는다.

## 3. 결과 (실행 시)

- **Pull Request 1건** — `gh pr view <N>` 로 확인 가능. 70자 미만 명령형 제목,
  `## Summary` / `## Changes` / `## Test plan` / `## Related` 구조의 본문,
  range 의 **모든** 커밋을 다루는 Changes, 이슈가 있으면 `Closes #N`(버그면 `Fixes #N`),
  stacked 면 `Depends on #<PARENT_PR>`. `--assignee @me` 로 항상 자기 할당.
- **push 된 원격 브랜치** — upstream 이 없거나 mispair 면 `git push -u <remote> HEAD`,
  앞서 있기만 하면 `git push`. push 대상 remote 와 PR 이 열리는 서버는 동일하다.
- **라벨** — conventional-commit 타입과 PR 범위에서 유도하되 **저장소에 이미 존재하는
  라벨만** 적용된다. 없는 라벨은 조용히 skip 되고 새로 만들지 않는다.
- **프로젝트 보드** — PR 카드가 `In review` 로, GitHub builtin 이 잘못 옮긴 Issue 카드는
  `In progress` 로 교정된다.
- **stdout 보고** — `[OK] PR: <url>` + `[OK] Board sync: ...` +
  `Next: /gh-pr:reply (after CI green)`. 단계 마커
  `[step:gh-pr-create/push-and-create] OK`, `[step:gh-pr-create/labels] OK`,
  `[step:gh-pr-create/board-sync] OK`, `[step:gh-pr-create/report] OK`.
  실패 시에는 `[FAIL] <한 줄 이유>` + `Next: <복구>`.
- **남지 않는 것** — 리뷰 코멘트도 승인 판정도 머지도 없다. 그것들은
  `/gh-pr:review`, `/gh-pr:approve`, `/gh-pr:merge` 의 일이다.
