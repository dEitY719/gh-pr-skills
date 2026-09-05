# create

> 한 줄 요약 — 현재 브랜치가 base 에서 분기한 이후의 **모든 커밋**을 하나의 Pull Request 로 묶어 연다. 필요하면 push 까지 하고, 출력은 PR URL 하나다.

## 언제 쓰고 언제 안 쓰는가

**쓸 때** — 피처 브랜치에 커밋이 쌓였고 이제 PR 로 올릴 때. 커밋이 5개면 PR 본문이
5개를 전부 다룬다. push 가 안 돼 있으면 이 스킬이 push 한다.

**안 쓸 때 — 형제 스킬로 가는 경계:**

- 아직 커밋할 게 남았다면 먼저 **`/gh-pr:commit`**. 그쪽은 커밋만 하고 절대 push
  하지 않으며 PR 도 열지 않는다. 사람이 diff 를 검토하고 커밋 스타일을 고를 수
  있도록 일부러 쪼갠 분리선이다. **push 와 PR 생성은 이 `create` 의 일이다.**
- 이미 열린 PR 에 2차 의견을 받으려면 `/gh-pr:review`, 리뷰 코멘트에 개별 답글과
  수정을 하려면 `/gh-pr:reply`, 승인 판정은 `/gh-pr:approve`, 머지는
  `/gh-pr:merge`. `create` 는 **리뷰도 머지도 하지 않는다.**
- PR 이 아니라 이슈를 만들려는 것이면 `gh-issue:create`.

## 호출 형식

```
/gh-pr:create [issue-number] [remote] [--no-stack | --base <branch>]
/gh-pr:create -h | --help | help
```

`references/help.md` 와 `references/options.md` 가 1차 근거다. 위치 인자 파싱
규칙(dEitY719/dotfiles#1405)은 `commit` 과 같다: **숫자로만 된 위치 인자는 이슈 번호**, 그 외는
remote 이름이고 순서는 무관하다.

| 인자 / 옵션 | 기본값 | 설명 |
|---|---|---|
| `[N]` | 자동 탐지 | 본문에 `Closes #N`(버그면 `Fixes #N`)으로 연결할 이슈 |
| `[remote]` | `origin` | push 대상이자 PR 을 여는 remote. `gh` 타깃(host + `--repo`)과 git plumbing(`git fetch`, `<remote>/<base>` range, `git push -u`) 양쪽을 좌우한다 |
| `--no-stack` | off | stacked 신호가 있어도 base 를 repo 기본 브랜치로 강제 |
| `--base <branch>` | repo 기본 | base 브랜치 명시. stacked 자동 탐지를 우회 |
| `GH_DISABLE_AI_METRICS=1` (env) | off | Step 4 의 ai-metrics 푸터 생략 |
| `GH_PR_LINT_BYPASS=1` (env) | off | Step 4.5 lint 게이트 생략 |
| `-h` / `--help` / `help` | — | help 를 그대로 출력하고 중단. API 호출 없음 |

`--no-stack` 과 `--base` 는 상호 배타적이다 — 같이 주면 push 전에 `rc=2` 로 중단한다.

stacked 자동 탐지는 두 조건이 **모두** 참일 때만 발동한다: (1) 저장소가 stacked PR 을
opt-in 했고(`.github/workflows/stacked-closes-rollup.yml`, `CLAUDE.md`/`AGENTS.md`/
`.claude/github-integration.md` 안의 `claude-enter-issue` / `stacked PR` /
`Depends on #` 키워드, 또는 `agent-toolbox/` 디렉터리), (2) HEAD 의 조상이면서
기본 브랜치보다 더 최근의 merge-base 를 주는 열린 PR 이 정확히 하나 있을 때.
그 외에는 base 가 repo 기본 브랜치로 떨어진다 — solo / 비-stacked 저장소는
동작 변화가 없다.

## 동작 단계

1. **Step 1 — 인자 파싱, base 결정, 상태 수집.** `START_TS` 기록.
   *1a-0*: 어떤 `gh` 호출보다 먼저 `references/github-target.md` 스니펫으로
   `GH_HOST` / `GH_REPO` / `TARGET_HOST` / `REMOTE` 를 export.
   *1a*: `references/stacked-pr.md` 의 함수와 dispatch 블록으로 `BASE_BRANCH` /
   `PARENT_PR` / `ISSUE_NUMBER` 를 바인딩. 잘못된 입력이면 push 없이 중단한다
   (`rc=2` 상호 배타 플래그, `rc=3` 잘못된 `--base`, `rc=4` 부모 PR 후보 다수,
   `rc=5` 부모 PR 이 `OPEN` 아님, `rc=6` 부모가 이미 stacked).
   *1b*: `references/branch-state.md` 로 커밋 range 와 push 상태를 조사한다.
   결과는 `not-on-base`(정상 진행) / `nothing-to-pr`(중단) /
   `auto-branch-and-rewind` / `auto-branch-warn-only` 중 하나다.
2. **Step 2-3 — 모든 커밋 분석 + 이슈 결정.** `git log <base>..HEAD` 를 읽어 주제별로
   묶는다. **PR 본문은 최신 커밋 하나가 아니라 range 전체를 반영해야 한다.**
   이슈 우선순위는 `gh-pr:commit` 과 동일: 명시 인자 → 최근 대화의 `#N` →
   range 안 커밋 푸터 → 없으면 링크 생략.
3. **Step 4 + 4.5 — 본문 초안, 그다음 lint 게이트.**
   `references/pr-body-template.md` 의 제목 규칙(70자 미만, 명령형)과 본문
   마크다운(`## Summary` / `## Changes` / `## Test plan` / `## Related`)을 따르고,
   기존 커밋이 쓰는 언어에 맞춘다. `references/ai-metrics-footer.md` 로 푸터를
   덧붙인다(soft-fail). **Step 4.5 는 push 전에** `references/lint-guard.md` 의
   `_gh_pr_lint_run "$BASE_BRANCH"` 를 실행해 lint 에러면 hard-fail 한다
   (도구 없음 / 변경 없음 / `GH_PR_LINT_BYPASS=1` 이면 자동 skip).
4. **Step 5 — push 후 생성.** upstream 상태별 push 정책: upstream 없음 또는
   mispair(`@{u}` != `<remote>/<current-branch>`) → `git push -u "$REMOTE" HEAD`,
   upstream 있고 앞서 있으면 `git push`, **diverge 했으면 중단하고 사용자에게
   묻는다**. 이어서 `mktemp` 본문 파일로
   `GH_HOST="$TARGET_HOST" gh pr create --repo "$GH_REPO" --base "$BASE_BRANCH"
   --title ... --body-file ... --assignee @me` 를 실행하고
   `[step:gh-pr-create/push-and-create] OK` 마커를 출력한다.
5. **Step 6 — 라벨 적용.** `git log <base>..HEAD` 의 conventional-commit 타입과 PR
   범위에서 후보 라벨을 뽑되, **이미 존재하는 라벨만** 적용한다
   (`gh label list` 로 대조). 새 라벨은 절대 만들지 않는다. 마커
   `[step:gh-pr-create/labels] OK`.
6. **Step 7 — 프로젝트 보드 sync.** 새 PR 카드를 `In review` 로 올리고, GitHub
   builtin 이 잘못 옮긴 연결 Issue 카드를 되돌린다(Issue 는 `In progress` 가 제자리).
   마커 `[step:gh-pr-create/board-sync] OK`.
7. **Step 8 — 보고.** `[OK] PR: <url>` 과 방어적 `[OK] Board sync:` 행,
   `Next: /gh-pr:reply (after CI green)`. 마커 `[step:gh-pr-create/report] OK`.
   요약은 덧붙이지 않는다 — 사용자는 URL 을 연다.

## 주의사항과 제약

**안전 계약 — range 가 곧 계약이다.** base 분기 이후의 커밋을 "사소하다"는 이유로
Summary 에서 빠뜨리지 않는다. 5커밋 PR 은 5개 관심사를 전부 언급한다. 진짜 사소하면
묶되 언급은 한다. 앞선 커밋을 조용히 떨어뜨리는 PR 이 이 규칙이 막는 버그다.

**절대 하지 않는 것**

- 사용자의 명시적 승인 없이 force-push 하지 않는다. upstream 이 diverge 하면
  발산 사실을 알리고 "force push" 인지 "rebase first" 인지 사용자가 말할 때까지
  기다린다 — 대신 골라주지 않는다.
- stacked 신호가 없는 저장소에서 auto-stack 탐지를 돌리지 않는다.
- 사용자가 `--base` 를 명시했는데 조용히 기본 브랜치로 강등하지 않는다.
- 부모 PR 의 본문을 수정하지 않는다 — cross-PR rollup 은 downstream 저장소의 일이다.
- 저장소가 이미 그 관례를 쓰지 않는 한 "Generated with Claude Code" 류의 AI 푸터를
  넣지 않는다(최근 머지된 PR 5건으로 확인).
- 새 라벨을 만들지 않는다.
- `--draft` 나 `--reviewer` 를 사용자가 명시하지 않는 한 설정하지 않는다.
- `[remote]` 가 없을 때 `origin` 으로 조용히 폴백하지 않는다.
- **리뷰도 머지도 하지 않는다.** 출력은 PR URL 뿐이다.

**거부 조건** — base 브랜치 위에 있으면("먼저 피처 브랜치를 만드세요"), `<base>..HEAD`
range 가 비어 있으면("nothing to PR"), `--no-stack` 과 `--base` 를 같이 주면(`rc=2`),
자동 탐지된 부모 PR 이 `OPEN` 이 아니면(`rc=5`), Step 4.5 lint 가 실패하면 —
모두 push 전에 `[FAIL] <이유>` + `Next: <복구>` 로 중단한다.

**host / repo 타게팅(dEitY719/dotfiles#1403 / dEitY719/dotfiles#1405)** — 모든 `gh` 호출은 `GH_HOST="$TARGET_HOST"` 와
`--repo "$GH_REPO"` 를 함께 싣고, 둘은 **같은** `git remote get-url "$REMOTE"` URL
하나에서 나온다. push 대상 remote 와 PR 대상 서버가 반드시 일치해야 한다. bare `gh` 는
gh CLI 자신의 `gh repo set-default` 를 따르므로, github.com 과 GHES 양쪽 로그인
상태에서 엉뚱한 서버에 **에러 없이 성공한다**. 놀라운 `gh` 결과를 재시도나 타깃 완화로
"고치지" 말고 host 부터 확인한다.

**알려진 마이그레이션 부채** — Step 4.5 는 dotfiles 의
`shell-common/functions/gh_pr_lint.sh` 를, Step 6 의 라벨 적용은
`gh_pr_edit_safe.sh` 를 source 한다. dotfiles 체크아웃이 없는 머신에서는 해당 단계가
degrade 된다. 라벨 wrapper 는 classic project board 가 붙은 저장소에서 `gh pr edit
--add-label` 이 GraphQL 경고와 함께 exit 1 로 라벨을 통째로 흘리는 문제(dEitY719/dotfiles#326)를
REST 폴백으로 우회하는 것이므로, 없으면 라벨이 조용히 안 붙을 수 있다.
