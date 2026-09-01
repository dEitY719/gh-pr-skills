# commit

> 한 줄 요약 — 작업 트리의 변경을 저장소 고유의 커밋 스타일로 정리한 **git 커밋 1개**를 만들고, 알려진 이슈 번호가 있으면 `Closes #N` 푸터로 연결한다. push 도 PR 생성도 하지 않는다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때** — 파일을 고쳤고 그 변경을 커밋으로 남길 때. 대화 중 이슈 번호가 언급됐다면
자동으로 `Closes #N` 푸터가 붙는다. 대화 맥락이 전혀 없는 수동 편집에도 쓸 수 있다.
Step 1 이 작업 트리 상태를 무조건 조회하므로 "뭘 바꿨나요?" 를 되묻지 않는다.

**안 쓸 때 — 형제 스킬로 가는 경계:**

- 커밋이 아니라 **push 하고 PR 을 열어야 할 때는 `/gh-pr:create`**. 이 스킬은 절대
  push 하지 않는다. `create` 는 HEAD 하나가 아니라 base 에서 분기한 이후의 모든
  커밋을 묶어 PR 로 만든다.
- 커밋할 대상 자체를 아직 만들지 않았고 **이슈부터 등록해야 할 때는 `gh-issue:create`**.
  이 스킬이 링크하는 그 이슈를 만드는 쪽이다.
- 이미 열린 PR 의 리뷰 코멘트에 답하고 고치는 것은 `/gh-pr:reply`, 승인 판정은
  `/gh-pr:approve`, 머지는 `/gh-pr:merge` 다.

이 `commit` / `create` 분리는 의도된 것이다. 사람이 diff 를 직접 검토하고, 커밋을
쪼갤지 합칠지, 어떤 커밋 스타일로 갈지 정한 뒤에야 무엇이든 이 머신 밖으로
나가도록 하기 위한 분리선이다.

## 호출 형식

```
/gh-pr:commit [issue-number] [remote]
/gh-pr:commit -h | --help | help
```

`references/help.md` 가 1차 근거다. 위치 인자 파싱 규칙(#1405): **숫자로만 이루어진
위치 인자는 이슈 번호**, 그 외의 위치 인자는 remote 이름이다. 순서는 상관없다.

| 인자 | 기본값 | 설명 |
|------|--------|------|
| `issue-number` | 대화에서 자동 탐지 | `Closes #N` 푸터로 연결할 GitHub 이슈 |
| `remote` | `origin` | 이슈가 속한 repo 를 소유한 git remote. ai-metrics 코멘트와 보드 sync 의 대상이 된다 |
| `-h` / `--help` / `help` | — | `references/help.md` 를 그대로 출력하고 중단. API 호출 없음 |

예시:

- `/gh-pr:commit` — 작업 트리를 조회해 커밋 메시지를 작성하고, 최근 대화의 `#N` 을 자동 연결
- `/gh-pr:commit 123` — 대화 내용과 무관하게 `Closes #123` 강제
- `/gh-pr:commit upstream` — 메트릭/보드 대상을 `upstream` 의 repo·host 로
- `/gh-pr:commit 123 upstream` — 둘 다

환경 변수 `GH_DISABLE_AI_METRICS=1` 이면 ai-metrics 코멘트를 건너뛴다(보드 sync 는
계속 실행 — issue #399).

## 동작 단계

1. **Step 1 — 상태 조회 (항상 먼저, 병렬).** `START_TS` 를 기록하고 한 메시지 안에서
   `git status`(`-uall` 금지), `git diff`, staged 가 있으면 `git diff --staged`,
   `git log --oneline -20`(저장소 커밋 스타일 모방용)을 실행한다. 같은 메시지에서
   위치 인자를 파싱하고 `references/github-target.md` 스니펫을 그대로 붙여
   `GH_HOST` / `TARGET_REPO` / `TARGET_HOST` / `REMOTE` 를 export 한다(#1403).
   지정한 remote 가 없으면 `git remote -v` 목록과 함께 중단한다 — `origin` 으로
   조용히 폴백하지 않는다.
2. **Step 2 — 이슈 번호 결정.** 먼저 맞는 것이 이긴다: (1) 숫자 인자 명시,
   (2) 최근 약 10개 메시지에서 `#N` 또는 `Issue #N created` 스캔, (3) 없으면 푸터
   생략. **이슈 번호를 지어내지 않는다.**
3. **Step 3 — 커밋 메시지 초안.** `references/commit-message-format.md` 의 템플릿과
   HEREDOC 패턴을 따르고 `git log` 의 스타일에 맞춘다. 본문은 무엇이 아니라 왜를
   적는다. 대화 맥락이 없으면 diff 의 경로와 이름에서 의도를 유도한다. diff 가
   모호하거나 서로 무관한 영역에 걸쳐 있을 때만 사용자에게 묻는다.
4. **Step 4 — 스테이징과 커밋.** 관련 파일만 이름으로 지정해 스테이징한다
   (`git add -A` / `git add .` 회피). 커밋 성공 후
   `[step:gh-pr-commit/stage-commit] OK` 마커를 출력한다.
5. **Step 5 — AI 메트릭 + 프로젝트 보드 sync.** 이슈 번호가 있을 때만 해당 이슈에
   ai-metrics 코멘트를 POST 한다(`references/ai-metrics-comment.md`, soft-fail).
   이어서 커밋 메시지에 `Closes|Fixes #N` 이 실제로 쓰였을 때만 보드 카드를
   `In progress` 로 옮긴다(`references/board-sync.md`). 두 블록 뒤에
   `[step:gh-pr-commit/metrics-board-sync] OK` 마커를 출력한다.
6. **Step 6 — 검증.** `git status` 를 다시 실행하고
   `Committed <short-hash>: <subject line>` 를 보고한다(연결된 이슈가 있으면 둘째
   줄에 이슈 번호). 마지막으로 `[step:gh-pr-commit/report] OK` 마커를 출력한다.

## 주의사항과 제약

**절대 하지 않는 것 (안전 계약)**

- **push 하지 않는다.** push 는 `/gh-pr:create` 의 일이다. PR 도 열지 않는다.
- `--amend` 를 명시적 요청 없이 쓰지 않는다. 항상 새 커밋을 만든다.
- `--no-verify` / `--no-gpg-sign` 을 쓰지 않는다. 훅이 실패하면 원인을 고치고
  다시 스테이징해 새 커밋을 만든다.
- `.env`, `credentials.json`, 키 파일 같은 **비밀로 보이는 파일을 스테이징하지
  않는다** — diff 가 그런 파일을 건드리면 중단하고 경고한다.
- 빈 커밋을 만들지 않고 git config 를 수정하지 않는다.
- 이슈 번호를 지어내지 않는다.

**푸터 키워드 제약** — 허용되는 것은 `Closes #N`(기본)과 `Fixes #N`(버그 수정)
둘뿐이다. `Refs` / `Resolves` / `See` / `References` 는 금지다. 앞의 셋은 GitHub
auto-close 를 트리거하지 않아 프로젝트 보드 자동화를 깨고, `Resolves` 는
AgentToolbox 의 stacked-closes-rollup 정책을 위반한다(issue #392). 부분 진행이라
auto-close 를 원치 않으면 푸터를 생략하고 본문에 `(part of #N)` 을 인라인으로 적는다.

**거부 조건** — 커밋할 변경이 없으면 "nothing to commit" 으로 중단한다. diff 가
명백히 서로 무관한 두 변경이면 스테이징 전에 쪼갤지 묻는다(기본은 호출당 커밋 1개).
`[remote]` 가 존재하지 않으면 remote 목록과 함께 중단한다.

**host / repo 타게팅** — Step 5 의 모든 `gh` 호출은
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"` 형태다. bare `gh` 는 git 의
remote 가 아니라 gh CLI 자신의 `gh repo set-default` 를 따르기 때문에, github.com 과
GHES 양쪽에 로그인된 상태에서는 **에러 없이 조용히 엉뚱한 서버에** 메트릭을
남긴다(#1403). 놀라운 `gh` 결과를 `--repo` 를 빼서 우회하지 말고 host 부터 확인한다.

**알려진 마이그레이션 부채** — Step 5 의 보드 sync 는 dotfiles 의
`shell-common/functions/gh_project_status.sh` 를 source 한다. dotfiles 체크아웃이
없는 머신에서는 이 단계가 조용히 skip 된다. `[ -r ]` 는 통과했는데 함수가 정의되지
않는 경우까지 방어하는 게이트가 들어 있고(#724), 이는 커밋을 막지 않는 soft-fail 이다.
`GH_PROJECT_STATUS_SYNC=0` 으로 명시적 opt-out 할 수 있다.
