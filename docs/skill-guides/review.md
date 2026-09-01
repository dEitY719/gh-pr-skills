# review

> 한 줄 요약 — PR diff 를 외부 AI CLI 하나에 넘겨 2차 의견을 받고, 그 원문을 담은
> **집계 코멘트 1개**를 PR 에 남긴다.

## 언제 쓰고 언제 안 쓰는가

- **쓸 때** — 열려 있는 PR 하나에 대해 사람이 아닌 다른 시선의 리뷰가 한 번 더
  필요할 때. 자기가 올린 PR 이어도 된다. 판정을 제출하지 않으므로 self-approve
  제약이 적용되지 않는다.
- **판정(approve / request-changes)을 내려야 한다면 `/gh-pr:approve`.** 이
  스킬은 `gh pr review --approve` 도 `--request-changes` 도 절대 호출하지 않는다.
- **이미 달린 리뷰 코멘트에 하나씩 답하고 고쳐야 한다면 `/gh-pr:reply`.** 이
  스킬은 코멘트별 답글을 달지 않는다. 출력은 집계 코멘트 1개가 전부다.
- **여러 리뷰어를 한 번에 돌리고 싶다면 `gh-verify:review-all`.** 한 번의 호출은
  `--ai` 값 하나뿐이다. N-way 비교가 필요하면 명령을 N번 다시 실행한다.

## 호출 형식

근거: `skills/review/references/help.md`.

```
/gh-pr:review --ai <codex|agy|claude|opencode|hermes> [--review <preset>]
              [--user <name>] [--no-post-comment] [--paths <path>]
              [<PR#>] [<remote>]
```

| 위치 인자 | 기본값 | 설명 |
|---|---|---|
| 1 | 현재 브랜치의 PR | PR 번호. `-h` / `--help` / `help` 면 도움말만 출력하고 종료 |
| 2 | `origin` | 대상 repo 를 해석할 git remote |

| 플래그 | 필수 | 설명 |
|---|---|---|
| `--ai <codex\|agy\|claude\|opencode\|hermes>` | 예 | 위임할 외부 AI CLI. 단일 값이며 CSV 불가 |
| `--review <preset>` | 아니오 | 리뷰 렌즈. 기본 `default` |
| `--user <name>` | 아니오 | `--ai claude` 전용 다계정 라우팅. 다른 `--ai` 와 쓰면 exit 2 |
| `--no-post-comment` | 아니오 | PR 코멘트를 건너뛰고 stdout 으로만 출력 |
| `--paths <path>` | 아니오 | 반복 가능. 해당 파일만 리뷰. 매칭 파일이 없으면 exit 1 |

`--review` 는 닫힌 enum 이고 자유 문자열은 거부된다(근거:
`references/review-presets.md`).

| enum | KR 별칭 | 렌즈 |
|---|---|---|
| `default` | `보통` | correctness · conventions · security · performance · tests · docs · backward-compat 7차원 균형 |
| `quick` | `간단` | BLOCKER 만 보는 빠른 스캔(correctness + security) |
| `thorough` | `꼼꼼` / `꼼꼼하게` | 7차원 + 아키텍처 트레이드오프 + 테스트 공백 + 인접 시스템 영향 |
| `security` | `보안` | injection, secrets, authz, supply chain |
| `performance` | `성능` | N+1, hot-loop I/O, allocation, caching |

`--ai opencode` 와 `--ai hermes` 는 internal PC 전용이다
(`~/.dotfiles-setup-mode` 가 `internal` 이 아니면 exit 1).

## 동작 단계

근거: `skills/review/SKILL.md`.

1. **Step 1 — 플래그 파싱 + 타깃 해석.** `gh_pr_review_parse` 에 위임한다.
   `START_TS` 기록, `PR_NUMBER` 해석, 그리고 **같은 remote URL 하나**에서
   `TARGET_REPO` 와 `TARGET_HOST` 를 함께 바인딩한다. 이후 모든 `gh` 호출은
   `GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"` 형태로 나간다.
2. **Step 2 — pre-flight 게이트.** PR 이 `OPEN` 이고 draft 가 아닐 것,
   선택한 AI CLI 가 PATH 에 있을 것, internal 전용 lane 이면 internal 모드일 것,
   `gh auth status` 가 0 일 것. CI 상태는 게이트가 아니고, self-authored PR 도
   막지 않는다.
3. **Step 3 — 프리셋 로드.** 공통 prefix + 해석된 enum 의 preset body 로 프롬프트를
   조립한다. 공통 prefix 에는 "판정을 제출하지 말라"는 지시, BLOCKER /
   FOLLOW-UP / PRAISE 분류 규칙, 필수 assumption check 한 줄, 필수 verdict 한 줄이
   들어 있다.
4. **Step 4 — 리뷰 재료 수집.** `--paths` 가 있으면 크기와 무관하게 인라인
   `gh pr diff` 경로를 쓴다. 없으면 `additions + deletions` 가 800줄 이상일 때
   large-diff 위임 경로로, 미만이면 인라인으로 간다. 프롬프트와 diff 를
   `PROMPT_FILE` 에 쓰고 쓰기와 Step 5 dispatch 를 같은 Bash 호출에서 처리한 뒤
   파일을 지운다.
5. **Step 5 — 외부 CLI 디스패치.** `_gh_pr_review_run_ai` 가 CLI 별 호출 형태를
   담당한다: `codex exec --color=never`, `agy --print`, `claude -p`,
   `opencode run --model codemate/CodeLLMPro --dir ... --file`, `hermes -z`.
   stdout 은 재가공 없이 그대로 흘려보낸다. `opencode` / `hermes` 는 8~10분이
   걸릴 수 있어 Bash 호출 timeout 을 600000ms 이상으로 올려야 한다.
6. **Step 6 — PR 코멘트 게시(기본 ON).** 외부 AI 의 stdout 을 접힌 `<details>`
   블록에 원문 그대로 넣고, `ai-review` 마커(AI 이름과 head SHA 포함)와
   ai-metrics 푸터를 붙여 `gh pr comment --body-file` 로 게시한다.
7. **Step 7 — 보고.** 성공 시 정확히 한 줄:
   `[OK] PR #<N> reviewed by <ai> (--review=<preset>) — comment: <URL or skipped>`.

## 주의사항과 제약

근거: `skills/review/references/constraints.md`.

- **판정을 제출하지 않는다.** `--approve` / `--request-changes` 는 범위 밖이며
  `/gh-pr:approve` 의 일이다.
- **개별 리뷰 코멘트에 답글을 달지 않는다.** 호출당 집계 코멘트 1개만 쓴다.
  코멘트별 대응은 `/gh-pr:reply` 의 일이다.
- **한 호출에 AI CLI 는 하나.** 병렬 실행 없음.
- **`--review` 자유 문자열 금지.** 닫힌 enum + KR 별칭만. 오타는 exit 2 로 빠르게
  실패한다.
- **외부 AI 의 stdout 을 재가공하지 않는다.** 사용자가 직접 판단할 원문을 남긴다.
- **PR body 를 편집하지 않는다.** classic Projects 가 붙은 repo 에서
  `gh pr edit --body` 가 조용히 exit 1 하기 때문에 항상 코멘트 append 만 한다.
- **외부 CLI 의 stderr 를 PR 코멘트에 남기지 않는다.** 비정상 종료 시 첫 줄만
  오류 메시지로 쓴다.
- `GH_DISABLE_AI_METRICS=1` 이면 푸터만이 아니라 **PR 코멘트 전체**를 건너뛴다.
- 종료 코드: 0 성공(코멘트 게시 실패도 stdout 이 남으면 `[WARN]` 후 0),
  1 CLI 부재 / CLI 비정상 종료 / PR 자동 탐지 실패 / 알 수 없는 claude 계정 /
  `--paths` 무매칭 / gh 미인증, 2 인자 오류.
- **마이그레이션 부채** — 이 스킬은 dotfiles 의
  `shell-common/functions/gh_pr_review.sh` 를 source 한다. dotfiles 체크아웃이
  없는 머신에서는 해당 단계가 degrade 한다.
