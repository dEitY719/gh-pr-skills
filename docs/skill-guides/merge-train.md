# merge-train

> 한 줄 요약 — 한 저장소에 열려 있는 **본인 PR** 들을 정해진 순서로 **한 번에 하나씩** 정리·머지하고, PR 당 한 줄짜리 `[MERGED]` / `[SKIPPED]` / `[FAILED]` 보고서를 남긴다.

## 언제 쓰고 언제 안 쓰는가

**쓴다** — `gh-flow:issue` 가 병렬로 돌아 **여러 개의 열린 PR** 을 남겼을 때. 첫 PR 을 머지하면
나머지가 전부 `BEHIND` 가 되고, conflict 나 빨간 CI 가 겹치면 PR 마다 다른 정리 스킬을 골라
반복해야 한다 — 그 반복이 이 스킬의 존재 이유다. 큐를 무인으로 비울 때도(cron) 쓴다.

**쓰지 않는다:**
- **PR 이 하나뿐이면 이 스킬이 아니라 `/gh-pr:merge`** 를 쓴다(정리가 필요하면
  `/gh-resolve:outdated` / `:conflict` / `:ci-fail` 을 직접). PR 하나에 train 은 순수 오버헤드다.
- **동료의 PR** — train 은 `--author @me` 전용(D-7)이라 애초에 보이지 않는다.
- **admin 바이패스가 필요하거나 사람의 판단이 남아 있을 때** — train 은
  `/gh-pr:merge-emergency` 를 절대 호출하지 않고(NF-2), 자체 리뷰 의견도 만들지 않는다.

## 호출 형식

근거: `skills/merge-train/references/help.md`

```
/gh-pr:merge-train [owner/repo] [remote]
```

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | `[owner/repo]` 또는 `-h`/`--help`/`help` | `[remote]` 의 repo | 대상 저장소. cron 디스패처는 항상 명시적으로 넘긴다 |
| 2 | `[remote]` | `origin` | **호스트**를 고정하는 git remote (slug 에는 호스트 정보가 없다) |

```
/gh-pr:merge-train                          # 이 체크아웃의 origin repo
/gh-pr:merge-train acme/dotfiles upstream   # repo 명시, host 는 upstream 에서
/gh-pr:merge-train -h
```

## 동작 단계

1. **Step 1 — 타깃 바인딩.** `TARGET_REPO` / `TARGET_HOST` / `GH_HOST` 를 **같은 remote URL
   하나**에서 해석한 뒤에야 `gh` 를 호출한다(dEitY719/dotfiles#1403/dEitY719/dotfiles#1407). `owner/repo` 를 명시해도 호스트는 여전히 remote URL 에서 온다.
2. **Step 2 — 큐 수집과 정렬.** `gh pr list --author @me --state open`(작성자 한정은 선택이
   아니다, D-7) 결과를 공용 필터 `_gh_pr_merge_train_filter_targets` 에 통과시킨다 — draft,
   `reply-pending` 라벨, **11분 quiet period**(D-6) 안의 갱신을 떨어뜨리며, cron 디스패처와
   **문자 그대로 같은 함수**다. 남은 PR 은 `CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`,
   동순위는 번호 오름차순(D-2). `gh pr list` 실패는 **빈 보고서와 함께 런 종료** 다.
3. **Step 3 — base 별 승인 정책 읽기.** rulesets 와 classic branch protection **양쪽**에서
   `required_approving_review_count` 를, **PR 마다가 아니라 서로 다른 `baseRefName` 마다 한 번씩**
   읽어 캐시한다(base 당 2콜). 한쪽이라도 `>= 1` 이면 게이트 ON, 양쪽 다 "정책 없음"이면 OFF
   (D-5). 판정 기준은 exit code 가 아니라 **HTTP status** — `403`/`404` 는 "정책 없음"이고,
   진짜 판정 불가(5xx / 401 / 무응답)만 fail-closed 로 게이트를 켠다(dEitY719/dotfiles#1519).
4. **Step 3.5 — 리뷰 verdict 게이트.** Step 2 가 이미 들고 있는 `labels` 만으로 판정한다
   (추가 API 콜 없음). `review-blocked` 가 있으면 — 낡은 `review-passed` 가 함께 있어도 —
   `[SKIPPED] review-blocked`. 두 라벨이 **모두 없으면**
   `[SKIPPED] review not verified — no review-passed label` 이다. **부재는 "통과"가 아니라
   "미검증"이라는 것이 이 게이트의 전부다.** `review-passed` 단독만 큐에 남고, 라벨의 유일한
   작성자는 `gh-verify:review-all` 이다(리뷰 코멘트 본문 파싱은 금지).
5. **Step 4 — train 실행, PR 한 번에 하나씩.** 큐 순서대로 (1) 처리 직전 상태 **재조회**
   (F-3 — 앞의 머지가 뒤의 모든 상태를 무효화했다), (2) D-1 라우팅 테이블로 분기,
   (3) 필요하면 원자 스킬에 위임, (4) 재조회 후 재라우팅, (5) `Skill(gh-pr:merge, "<N>")`
   (전략 인자 없음), (6) 머지 성공 시 그 PR 의 구현 탭이 `idle` 이면 닫는다(dEitY719/dotfiles#1565).
   `BEHIND` / `DIRTY` 의 리베이스는 시도마다 만들고 반드시 제거하는 **detached scratch
   worktree** 안에서 돈다(dEitY719/dotfiles#1493). 시도는 PR 당 **최대 3회**(F-5), 실패하면 그 PR 만 건너뛰고
   train 은 계속한다(F-6). **두 PR 을 동시에 처리하지 않는다.**
6. **Step 5 — 보고.** PR 당 한 줄, 반드시 사유를 붙인 `[MERGED]` / `[SKIPPED]` / `[FAILED]`
   보고서(F-9). 헤더에 큐 크기와 `approval gate:` 판정 문자열(`off (no policy on <base>)` /
   `on (<source>: <n> approvals)` / `on (fail-closed: <base> policy unreadable)`)이 들어가며,
   항상 일반 assistant 텍스트로 출력한다(`Bash` heredoc / `Write` 금지).

### 라우팅 테이블 (D-1)

`references/routing-table.md` 의 결정론적 표 — 판단이 필요한 두 행만 원자 스킬에 위임한다.

| `mergeStateStatus` | `mergeable` | 동작 |
|---|---|---|
| `CLEAN` | `MERGEABLE` | 바로 `Skill(gh-pr:merge, "<N>")` |
| `BEHIND` | `MERGEABLE` | scratch worktree 에서 `gh-resolve:outdated` → 재조회 → 머지 |
| `DIRTY` | `CONFLICTING` | scratch worktree 에서 `gh-resolve:conflict` → 재조회 → 머지 |
| `UNSTABLE` | `MERGEABLE` | `statusCheckRollup` 을 보고 분기 (아래) |
| `BLOCKED` | — | 사유를 기록하고 `[SKIPPED]` |
| `UNKNOWN` | `UNKNOWN` | 폴링 후 재평가, 3회 폴링 후 `[SKIPPED]` |
| `DRAFT` | — | `[SKIPPED]` |

`mergeStateStatus` 를 읽기 **전에** 확인하는 단락(short-circuit): `isDraft`, `reply-pending`
라벨, `review-blocked` 라벨, 두 verdict 라벨의 부재, `review-passed` 의 sha 신선도
(dEitY719/dotfiles#1601 — 마커 불일치 / 부재 / 조회 실패가 각각 다른 `[SKIPPED]` 사유). `UNSTABLE` 은 rollup 으로 갈라진다: `FAILURE` / `TIMED_OUT` / `CANCELLED` / `ACTION_REQUIRED`
가 있으면 `Skill(gh-resolve:ci-fail, "<N>")`, `IN_PROGRESS` / `QUEUED` / `PENDING` 뿐이면
**기다린다**(아직 안 끝난 테스트를 "고치러" 가지 않는다), 전부 성공이면 재조회한다.
폴링은 최대 3회(약 30초 간격)이고 **F-5 시도 횟수를 소모하지 않는다.**

## 주의사항과 제약

- **직렬이 설계다(D-8).** 각 머지가 큐의 나머지를 무효화하므로 병렬 train 은 자기 머지끼리
  경쟁한다(서브에이전트 분기 금지). `DIRTY` 가 마지막인 이유도 같다 — 가장 비싼 작업을
  **최종 base** 를 상대로 정확히 한 번만 하려는 것이다.
- **`merge` 단독이라면 거부했을 것을 머지하지 않는다.** `gh-pr:merge` 의 게이트(비어 있지 않고
  `APPROVED` 도 아닌 `reviewDecision`)는 위임하기 **전에** 감지해 사유와 함께 `[SKIPPED]` 로
  기록한다 — 결정론적 거부에 시도 3회를 써서 만든 `[FAILED]` 는 NF-2 때문에 해제할 길이 없다.
- **`/gh-pr:merge-emergency` 를 절대 호출하지 않는다(NF-2).** `BLOCKED` 에도, 승인 누락에도,
  "이번 한 번만"도 없다 — 머지 불가 PR 은 사유와 함께 `[SKIPPED]` 다.
- **PR 하나의 실패로 train 전체를 중단하지 않는다(F-6).** 런을 끝내는 유일한 사건은 큐 자체를
  잃는 것(`gh pr list` 실패)이다. 머지 전략 인자도 넘기지 않는다(D-4) — `required_linear_history` 가 허용하는 것은 `gh-pr:merge` 의 기본값 rebase 다.
- **자체 리뷰 판단을 만들지 않는다.** 게이트가 OFF 이고 `reviewDecision` 이 비었을 때만
  `Skill(gh-pr:approve, "<N> <remote> --self-record")` 를 head 당 **한 번** 위임하고 보드를
  읽어 판정으로 삼는다 — 승인이 없으면 머지도 없다. train 자체는 ai-metrics 코멘트도 쓰지
  않는다(호출되는 원자 스킬들이 각자 남긴다).
- **Claude Code 전용 — 이식성 제약.** 이 스킬은 다른 스킬을 `Skill()` 로 체이닝하는데 `Skill()`
  은 Claude Code 밖에 등가물이 없다. 다른 하네스에서는 train 대신 **PR 하나씩** per-PR 스킬을
  직접 실행한다: 상태에 맞는 `/gh-resolve:outdated` / `:conflict` / `:ci-fail` 후 `/gh-pr:merge`.
- **알려진 마이그레이션 부채** — `merge-train/SKILL.md` 는 148줄로 100줄 progressive-disclosure
  한도를 넘긴다(마이그레이션 중 동작 변경 금지라 그대로 넘어왔다). 해결책은 한도를 올리는 것이
  아니라 `references/` 로 상세를 옮기는 Phase 4 작업이다. 또한 dotfiles 의
  `shell-common/functions/gh_pr_merge_train.sh` 등을 source 하므로, dotfiles 체크아웃이 없는
  머신에서는 해당 단계가 저하된다.

## 관련 스킬

호출하는 원자 스킬: `gh-resolve:outdated` · `gh-resolve:conflict` · `gh-resolve:ci-fail` ·
`gh-pr:approve`(게이트 OFF 경로 `--self-record` 전용) · `gh-pr:merge`. **의도적으로 호출하지
않는 것**: `gh-pr:merge-emergency`(NF-2). PR 들의 생산자는 `gh-flow:issue`, verdict 라벨의 유일한
작성자는 `gh-verify:review-all`, 프로비저닝은 `gh-setup:label-bootstrap`.
