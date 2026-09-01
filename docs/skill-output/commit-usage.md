# commit 사용 결과

> **한 줄 요약** — 작업 트리의 변경과 (알고 있다면) 이슈 번호를 받아 저장소 스타일의 git 커밋 1개를 생성합니다.

> NOTE: 이 문서는 **미실행 예시**입니다. gh-pr 의 8개 스킬은 모두 live GitHub
> repo 에 쓰기를 하고, 이 저장소에는 대상 PR 이 없으며 커밋/push 가 금지된
> 작업이었으므로 문서화 목적의 실행을 하지 않았습니다. 아래 명령과 게이트는
> `skills/commit/SKILL.md` 에서 인용한 것이고, 결과 절은 실행 시 생성되는
> 산출물을 기술합니다. 실제 실행 로그가 아닙니다.

```
작업 트리의 변경 + 이슈 번호  ──▶  /gh-pr:commit  ──▶  커밋 1개
```

## 1. 실행할 명령

범용 형식:

```
/gh-pr:commit [issue-number] [remote]
```

이 저장소(`dEitY719/gh-pr-skills`, remote `origin`)를 대상으로 했을 때:

```
/gh-pr:commit                 # 대화에서 이슈 번호 자동 탐지
/gh-pr:commit 42              # Closes #42 강제
/gh-pr:commit -h              # references/help.md 출력 후 중단
```

## 2. 입력

- **작업 트리의 변경** — `git status` / `git diff` 로 읽는 staged + unstaged 변경.
  Step 1 이 상태를 무조건 조회하므로 사용자에게 "뭘 바꿨나요" 를 되묻지 않는다.
- **이슈 번호(선택)** — 숫자 위치 인자 → 최근 대화의 `#N` → 없으면 푸터 생략.
- **선행 조건(게이트):** 커밋할 변경이 있어야 한다(없으면 "nothing to commit" 으로
  중단). `[remote]` 가 지정됐다면 실제로 존재해야 한다(없으면 `git remote -v` 목록과
  함께 중단, `origin` 폴백 없음). 비밀로 보이는 파일(`.env`, `credentials.json`,
  키)이 diff 에 있으면 중단하고 경고한다.

## 3. 결과 (실행 시)

- **커밋 1개** — `git log -1` 로 확인 가능. `<type>(<scope>): <summary>` 형식의
  제목, 왜를 설명하는 본문, 그리고 이슈가 해결됐다면 `Closes #N` 또는 `Fixes #N`
  푸터와 `Co-Authored-By` 푸터. `--amend` 가 아닌 새 커밋이다.
- **stdout 보고** — `Committed <short-hash>: <subject line>` (연결된 이슈가 있으면
  둘째 줄에 이슈 번호). 단계 마커 `[step:gh-pr-commit/stage-commit] OK`,
  `[step:gh-pr-commit/metrics-board-sync] OK`, `[step:gh-pr-commit/report] OK`.
- **연결된 이슈 위 ai-metrics 코멘트** — 이슈 번호가 있고 `GH_DISABLE_AI_METRICS=1`
  이 아닐 때만. 실패해도 커밋을 막지 않는 soft-fail 이다.
- **프로젝트 보드** — 커밋 메시지에 `Closes|Fixes #N` 이 실제로 쓰였을 때만, 그리고
  카드의 현재 Status 가 `Backlog` 일 때만 `In progress` 로 이동한다.
- **남지 않는 것** — 원격 브랜치도 PR 도 생기지 않는다. push 는
  `/gh-pr:create` 의 일이다.
