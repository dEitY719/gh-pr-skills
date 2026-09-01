# approve

> 한 줄 요약 — PR 하나에 대한 **리뷰 verdict**(approve / request changes)를 제출하고, 남은 지적은 후속 이슈로 파일링한다.

`gh-pr` 플러그인의 8개 스킬 중 **verdict 를 제출하는 유일한 스킬**이다. 나머지 일곱은
커밋을 쓰거나, PR 을 열거나, 코멘트를 달거나, 머지할 뿐 승인/변경요청을 내지 않는다.

## 언제 쓰고 언제 안 쓰는가

- **verdict 를 내야 할 때** — `/gh-pr:approve`. blocker 가 없으면 `--approve`,
  하나라도 있으면 `--request-changes` 가 나간다.
- 판단이 아니라 **2차 의견 수집**이 목적일 때는 `/gh-pr:review`. 외부 AI CLI 한 개에
  위임해서 집계 코멘트 1개만 남기고 verdict 는 제출하지 않는다.
- 이미 달린 **리뷰 코멘트에 개별 답글**을 달고 수정을 반영하는 일은 `/gh-pr:reply`.
  approve 는 코멘트에 답글을 달지 않는다.
- 승인이 끝난 PR 을 **실제로 머지**하는 것은 `/gh-pr:merge`. approve 는 (자기 PR 의
  `--admin-merge` 경로를 제외하면) 머지하지 않으며, **동료의 PR 은 절대 머지하지 않는다**.
- 승인을 받을 수 없는 상황에서 머지를 강행해야 한다면 `/gh-pr:merge-emergency`.

## 호출 형식

근거: `skills/approve/references/help.md`, `references/arg-parsing.md`.

```
/gh-pr:approve [<PR#>] [<remote>] [flags]
```

| 위치 | 이름 | 기본값 | 설명 |
|---|---|---|---|
| 1 | PR 번호 또는 `-h`/`--help`/`help` | 현재 브랜치의 PR | 대상 PR |
| 2 | remote 이름 | `origin` | 대상 저장소의 git remote |

| 플래그 | 설명 |
|---|---|
| `--self-record` | 자기가 작성한 PR 에 대해 diff 를 읽고 **comment-only 리뷰 기록**만 남긴다. 리뷰 기반 branch protection 은 만족시키지 못한다. |
| `--admin-merge` | 자기가 작성한 PR 에 blocker 가 없을 때 `gh pr merge --admin` 으로 머지한다. admin 권한 필요. |
| `--squash` / `--rebase` / `--merge` | `--admin-merge` 의 머지 전략. 단독 사용은 거부된다. |

거부되는 조합: 알 수 없는 플래그, `--self-record` 와 `--admin-merge` 동시 사용,
그리고 레거시 `--self-ok`. `--self-ok` 는 애초에 불가능한 동작을 가리키므로
`--self-ok is not supported; GitHub blocks self-approval server-side.` 로 거부한다.

help 은 **arg #1 에서만** 감지된다 — `--self-ok -h` 는 help 이 아니라 미지원 플래그다.

## 동작 단계

1. **Step 1 — 인자 해석 + 사전 게이트(병렬).** `START_TS` 를 기록하고, 하나의 remote URL
   에서 `TARGET_HOST` 와 `TARGET_REPO` 를 함께 바인딩한다(#1403/#1407). PR 메타데이터,
   `ME`(인증 사용자), REST 전용 `rebaseable`, `gh pr checks` 를 병렬로 가져온다.
   **정지**: `state != OPEN`, draft, required check 실패. **경고 후 진행**:
   `mergeable: CONFLICTING` 또는 `rebaseable: false` — 경고 블록이 리뷰 본문 앞에 붙고
   최종 보고에도 포함된다.
2. **Step 2 — 리뷰 재료 수집.** `additions + deletions` 가 800줄
   (`references/large-diff-delegation.md` 의 단일 출처) 이상이면 Explore 서브에이전트에
   위임해 BLOCKER/FOLLOW-UP/PRAISE 요약만 받는다. 미만이면 인라인 경로로 diff, 커밋 JSON,
   그리고 **세 개의 코멘트 엔드포인트**(inline / issue / review)를 전부 읽는다. 하나라도
   빠뜨리면 봇 피드백을 놓친다.
3. **Step 3 — 분류.** 각 지적을 **BLOCKER / FOLLOW-UP / PRAISE** 로 나눈다. 기준은
   "지금 머지하면 무언가 깨지거나 회귀하는가". 예이면 BLOCKER, 아니지만 추적할 가치가
   있으면 FOLLOW-UP, 그것도 아니면 PRAISE 또는 무시. 이전에 내가 남긴 코멘트가 있으면
   **재리뷰 모드**로 들어가 모든 이전 지적이 수정 커밋 / 추적 이슈 / 납득 가능한 반론
   중 하나에 매핑되는지 확인하고, 어디에도 없으면 BLOCKER 로 승격한다.
4. **Step 4 — 제출.**
   - **4a** blocker 0, follow-up 0 → `gh pr review --approve`. 승인 본문에는 file:line
     또는 short SHA 로 근거를 댄 구체적인 칭찬이 최소 1개 들어간다.
   - **4b** blocker 0, follow-up 1개 이상 → follow-up 마다 이슈를 1개씩 만들고, 그것들을
     링크하는 PR 코멘트 1개를 남긴 뒤 승인한다.
   - **4c** blocker 1개 이상 → `gh pr review --request-changes`. blocker 는 PR 에 남아
     작성자의 다음 push 가 자연스럽게 재리뷰를 유발한다.
   - 제출 경로와 무관하게 ai-metrics PR 코멘트를 별도로 남긴다
     (`GH_DISABLE_AI_METRICS=1` 이면 건너뛴다).
5. **Step 4.5 — 보드 카드 승격(soft-fail).** 이 스킬은 projectV2 보드 `Approved` 칼럼의
   **유일한 스킬 소유자**다(#1350). 4a / 4b / `--self-record` 에서만 승격하고,
   4c / 분석 전용 / `--admin-merge` 에서는 절대 승격하지 않는다.
6. **Step 5 — 검증과 보고.** `reviewDecision` 과 `mergeStateStatus` 를 다시 읽어
   verdict, blocker/follow-up 개수, 이슈 링크, 머지 상태, 보드 결과, PR URL 을 보고한다.
   `--self-record` 는 `reviewDecision` 이 `APPROVED` 로 바뀌지 **않았음**을 확인한다.

## 주의사항과 제약

- **자기가 작성한 PR 은 절대 승인할 수 없다.** GitHub 이 서버 측에서 same-user
  self-approval 을 막고(`Review Can not approve your own pull request`), 스킬도 API 호출
  이전에 거부한다. 토큰, PAT, 프롬프트, 플래그 어떤 조합으로도 우회되지 않는다.
  자기 PR 을 감지하면 세 가지 경로를 제시한다
  (`references/self-pr-handling.md`):
  - **기본(분석 전용)** — diff 를 읽고 리뷰 본문을 로컬에만 출력한다. 코멘트, 리뷰,
    이슈, 머지 어떤 GitHub 변경도 하지 않고
    `No GitHub review submitted because author and reviewer are the same user.` 를 덧붙인다.
  - **`--self-record`** — `gh pr review --comment` 로 감사 기록을 남긴다(거부되면
    `gh pr comment` 로 폴백). 본문에 "이것은 승인이 아니며 branch protection 을 만족하지
    않는다"고 명시한다. 이 경로만 보드 카드를 `Approved` 로 승격한다.
  - **`--admin-merge`** — blocker 가 없을 때만 `gh pr merge --admin`. blocker 가 있으면
    출력하고 정지하며, 전략이 거부돼도 다른 전략으로 바꿔 재시도하지 않는다.
- **diff 를 읽지 않고 승인하지 않는다.**
- **후속 이슈를 지어내지 않는다.** 각 이슈는 방어 가능한 지적이어야 하고, 한 문장으로
  구체적 피해를 말할 수 없으면 파일링하지 않는다.
- **동료의 PR 을 머지하지 않는다.** `--admin-merge` 는 자기 PR 전용이다.
- `gh label list` 로 존재가 확인되지 않은 라벨/마일스톤은 붙이지 않는다.
- 모든 `gh` 호출은 `GH_HOST="$TARGET_HOST"` 와 `--repo "$TARGET_REPO"` 를 **둘 다** 싣는다.
  `--repo` 만으로는 gh CLI 자신의 기본 호스트를 따라가므로, 이중 호스트 로그인
  (github.com + GHES)에서 조용히 잘못된 서버를 향한다(#1403/#1407).
