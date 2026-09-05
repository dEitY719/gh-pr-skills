# `review-passed` 게이트 — Step 6 (이슈 #1636, #1616 승계)

`gh-pr:reply` 는 BLOCKER 를 실제로 고친다. 그러니 "고쳐졌다"를 아는 스킬도
이 스킬이다. #1636 부터 `review-passed` 라벨은 **이 스킬이 직접** 붙인다 —
외부 AI CLI 재호출 없이, 자기 판단만으로.

이 문서가 그 절차의 SSOT 다. 구현체는
`shell-common/functions/gh_pr_reply_targeted_review.sh`.

## 여기까지 온 경로

- **#1616 이전** — 해제 규칙은 `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0`
  이라는 **전역 카운터 한 쌍**이었다. 같은 pass 안에서 *다른* 리뷰어의
  비블로킹 제안을 정당하게 DECLINE 하기만 해도 `review-blocked` 가 그대로
  눌러앉았다. 실제 사례 PR #1609 — codex 가 BLOCKER 2건(둘 다 수정), agy 가
  별도로 비블로킹 FOLLOW-UP 3건(전부 타당하게 거절). 라벨 하나 떼려고 5-lane
  `gh-verify:review-all` 전체 재실행이 필요했다.
- **#1616** — 질문을 리뷰어별·심각도별로 좁히고, 통과 판정은 여전히 외부
  `gh-pr:review --paths` 재호출에 맡겼다(NF-2, 자가 인증 금지).
- **#1636** — 그 재호출을 제거했다. 재호출 자체가 비용·지연·실패 지점이었고,
  `review-passed` 를 재획득하는 **유일한** 경로였기 때문에 실패할 때마다
  `gh-pr:merge-train` 이 반복적으로 막혔다.

## 원칙 두 개

- **심각도로 묻는다.** "이 pass 에 DECLINE 이 있었나"가 아니라 "**BLOCKER
  심각도 항목**이 하나라도 미해결로 남았나"를 묻는다. 비블로킹 FOLLOW-UP 의
  거절은 이 질문과 무관하다.
- **NF-2 는 이 경로에 한해 완화됐다(#1636).** 위 질문에 no 면 이 스킬이
  `review-passed` 를 **스스로** 붙인다. 남는 검증 연결고리는 분업이다 —
  **발견은 외부 AI**(`gh-verify:review-all` 이 여전히 매 PR 마다 fan-out 하고
  `review-blocked` 를 소유), **해소 확인은 `gh-pr:reply`**. fail-closed 방향은
  그대로다: 미해결 BLOCKER 가 하나라도 있으면 `review-passed` 는 없다.
  사용자의 명시적 트레이드오프 결정이며, `references/constraints.md` 가
  그 근거를 함께 적어 둔다.

## Step 3 — origin 토큰 기록 (F-1, #1616 그대로)

Step 3 에서 코멘트 하나를 분류할 때마다 출처를 함께 남긴다:

```bash
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_reply_targeted_review.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_reply_targeted_review.sh" ] || {
    printf '[gh-pr:reply] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_reply_targeted_review.sh"

ORIGINS=$(
    _gh_pr_reply_origin_line codex '[BLOCKER]'   ACCEPT
    _gh_pr_reply_origin_line codex '[BLOCKER]'   ACCEPT
    _gh_pr_reply_origin_line agy   '[FOLLOW-UP]' DECLINE
)
```

- `<reviewer>` — 코멘트 작성자. 두 집합 중 하나여야 하고, 그 외는 exit 2.
  - **AI CLI** — `gh-pr:review` 의 `--ai` 값 그대로:
    `agy` / `codex` / `claude` / `opencode` / `hermes`.
  - **봇 로그인** (PR #1637 리뷰, codex BLOCKER) — `gemini-code-assist` /
    `sourcery-ai` / `copilot`. Step 3 의 분류 규칙은 봇 코멘트를 AI CLI
    코멘트와 **똑같이** 다루는데 리뷰어 필드가 `--ai` enum 하나로 닫혀 있어서,
    봇이 올린 BLOCKER 는 exit 2 로 튕겨 나가 `ORIGINS` 에 아예 못 들어갔다 —
    게이트에게 보이지 않는 BLOCKER 였다.
  - **왜 두 집합을 따로 두나.** 봇은 오직 코멘트 *작성자*다. `--ai` 로 다시
    호출되는 일이 없다(GitHub App 이라 CLI 디스패처 자체가 없다). 한 집합으로
    합치면 `--ai` enum 이 실행 불가능한 이름까지 받아들이게 되고, 오타 난
    `--ai` 값이 이 목록으로 검증하는 모든 호출자에게 유효해 보인다.
    판별은 `_gh_pr_reply_reviewer_is_bot <name>` (rc 0 = 봇).
  - 봇 로그인에는 `-` 는 있어도 `:` 는 없다. `reviewer:severity:verdict`
    구분자와 `_gh_pr_reply_origin_tally` 의 awk `-F:` 그룹핑은 그대로 동작한다.
- `<severity>` — 리뷰어가 본문에 단 태그(`[BLOCKER]` / `[FOLLOW-UP]` /
  `[Suggestion]` …). 대괄호는 렌더링이라 헬퍼가 벗겨낸다.
- `<verdict>` — `ACCEPT` / `ACCEPT-PARTIAL` / `DECLINE` / `QUESTION`.

Step 7 의 리뷰어별 표는 이 스트림을 `_gh_pr_reply_origin_tally` 로 집계한다.
스트림은 **하나**다 — Step 6 과 Step 7 이 같은 `ORIGINS` 를 읽는다.

## Step 6 — 게이트와 적용 (F-2 / F-3 / F-4)

**Step 5 가 모든 코멘트에 답변을 마친 뒤에** 실행한다. 게이트는 "이 PR 에
BLOCKER 가 미해결로 남았나"를 묻는 것이므로, 아직 답하지 않은 코멘트가 있으면
물을 수 없다.

### 실행 순서 (PR #1637 리뷰 이후)

순서가 전부 load-bearing 이다. 그대로 지킨다:

1. **drop** — `PUSHED_FIXES > 0` 이면 `review-passed` 를 먼저 뗀다
   (`references/verdict-label-removal.sh.md`). 게이트보다 **앞**이어야 한다 —
   뒤로 가면 방금 붙인 라벨을 지운다.
2. **history + evidence** — Step 2 에서 이미 받아 둔 PR 코멘트를 재사용해
   (API 추가 호출 없음) 과거 pass 들의 origin 이력과 외부 리뷰 근거를 구한다.
   #1639 이후 두 리더는 **본문 텍스트가 아니라 원본 코멘트 JSON 배열**
   (`gh api repos/<repo>/issues/<pr>/comments` 응답 그대로, `.user.login` 보존)
   을 stdin 으로 받고, `<expected-login>` 인자를 **필수**로 요구한다.
   `--jq '.[].body'` 로 미리 본문만 뽑아 두면 작성자가 사라져 위조 마커가
   그대로 통과한다.
3. **merge** — 이 pass 의 `ORIGINS` 를 그 이력 위에 리뷰어 단위로 덮어쓴다.
4. **ledger** — 병합 결과를 원장 코멘트로 **먼저** 기록한다. 게이트 결과와
   **무관하게** 기록한다 — hold 인 경우가 바로 다음 pass 가 알아야 하는 경우다.
5. **gate + apply** — 병합 결과와 근거 플래그를 게이트에 넘긴다.

```bash
# 이 파이프라인이 인증하는 단 하나의 신원. Step 2 의 중복 제거가 이미 "현재
# 사용자" 를 알아야 하므로 보통 그때 한 번 구해 둔 값을 재사용한다.
# GH_PR_REPLY_TRUSTED_LOGIN 은 리뷰/답변 파이프라인이 서로 다른 계정으로
# 도는 배포를 위한 탈출구다 (아래 "마커 작성자" 절).
ME="${GH_PR_REPLY_TRUSTED_LOGIN:-${ME:-$(GH_HOST="$TARGET_HOST" gh api user -q .login)}}"

# $COMMENT_JSON 은 Step 2 가 받아 둔 /issues/<N>/comments 응답 **원본 배열**
# 이다 (본문만 뽑아 둔 텍스트가 아니다 — #1639).
HISTORY=$(_gh_pr_reply_history_origins "$ME" <"$COMMENT_JSON")
if _gh_pr_reply_history_has_review "$ME" <"$COMMENT_JSON"; then
    EVIDENCE=yes
else
    EVIDENCE=no
fi

MERGED=$(printf '%s\n' "$ORIGINS" | _gh_pr_reply_origins_merge "$HISTORY")

printf '%s\n' "$MERGED" |
    _gh_pr_reply_post_origins_ledger "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" "$HEAD_SHA"

DECISION=$(printf '%s\n' "$MERGED" | _gh_pr_reply_review_passed_gate "$EVIDENCE")
```

### origin 원장 — pass 사이의 기억 (PR #1637 리뷰, codex BLOCKER)

게이트는 원래 **이번 pass 의 `ORIGINS` 만** 봤다. 그런데 Step 2 의 "이미
답변함" 중복 제거가 앞선 pass 의 스레드를 이후 모든 pass 에서 걸러낸다. 그래서
1차 pass 가 BLOCKER 를 DECLINE 하면 2차 pass 의 `ORIGINS` 에는 그 흔적이 전혀
남지 않고, 게이트는 `pass=no-blocker` 를 읽어 **고쳐지지 않은 BLOCKER 를 품은
PR 에 `review-passed` 를 붙였다**.

이 저장소는 "게시된 코멘트가 곧 지속되는 기계 판독 상태"라는 관례를 이미
쓴다(`<!-- ai-review:<ai>:<sha> -->`, `devx_pr_review_all_write_label` 이 남기는
`<!-- review-verdict:review-passed:<sha> -->` 마커 코멘트). 원장도 같은 모양이다:

```
<!-- pr-reply-origins:<head-sha> -->
codex:BLOCKER:DECLINE
agy:FOLLOW-UP:ACCEPT
<!-- /pr-reply-origins:<head-sha> -->
```

- `_gh_pr_reply_origins_block <head-sha>` — origin 스트림을 위 블록으로 감싼다.
  빈 스트림이면 아무것도 출력하지 않는다(기억할 게 없다). `<head-sha>` 가
  비면 접미사 없는 `<!-- pr-reply-origins -->` 형태로 떨어진다.
- `_gh_pr_reply_history_origins <expected-login>` — 원본 코멘트 JSON 배열에서
  **`<expected-login>` 이 작성한** 코멘트만 골라, 그 안의 **마지막 완전한**
  블록의
  origin 줄들을 뽑는다(`devx_pr_review_all_lane_block` 과 같은 계약: 나중 pass 가
  앞선 pass 를 대체하고, 닫히지 않은 블록은 절대 수확하지 않는다). sha 접미사
  유무 둘 다 매치한다 — 옛 head 에서 거절된 BLOCKER 는 오늘도 거절된 상태이므로
  여기서 신선도를 따지면 이 구멍이 도로 열린다. 블록 안의 산문 줄은 조용히
  버린다(사람이 코멘트 안에 답글을 달 수 있다).
- `_gh_pr_reply_origins_merge "<history>"` — 이 pass 의 스트림을 stdin 으로 받아,
  **이 pass 에 등장하지 않은 리뷰어**의 이력 줄들 + 이 pass 의 줄들(원래 순서)을
  출력한다.
- `_gh_pr_reply_post_origins_ledger <pr> <repo> [host] [head-sha]` — 병합 결과를
  PR 코멘트로 게시한다. soft-fail(항상 rc 0), host 는 서브셸 안에서 핀 고정
  (#1403 / #1407).

**리뷰어 단위 supersede 와 탈출구.** 덮어쓰기는 줄 단위가 아니라 **리뷰어**
단위다. supersede 가 없으면 한 번 DECLINE 된 BLOCKER 가 `review-passed` 를
영원히 막고 풀 방법이 없다. 리뷰어 단위로 두면 탈출구가 정확히 옳은 하나만
남는다 — 리뷰어가 다음 라운드에서 그 항목을 다시 제기하고, `gh-pr:reply` 가
재분류하면 새 판정이 낡은 판정을 대체한다. 이번 pass 에 아무 말도 하지 않은
리뷰어는 이력을 그대로 유지하므로, **침묵이 BLOCKER 를 지우지는 못한다.**

### 외부 리뷰 근거 (PR #1637 리뷰, agy BLOCKER)

`ORIGINS` 가 비어 있으면(외부 리뷰가 아예 돈 적 없음 — CLI 미설치,
`gh-verify:review-all` 미실행) 게이트는 `pass=no-blocker` 를 읽고 스스로
`review-passed` 를 붙였다. #1636 이 NF-2 를 완화한 근거는 분업 — **발견은
외부 AI, 해소 확인은 `gh-pr:reply`** — 인데, 발견자가 없으면 확인할 대상도
없다.

`_gh_pr_reply_history_has_review <expected-login>` 가 **`<expected-login>` 이
작성한** PR 코멘트에 `<!-- ai-review:` 마커가
하나라도 있는지 본다(rc 0 = 있음). 게이트의 5번째 인자는 **fail-closed 기본값**
이다: 생략/빈 값/그 외 어떤 값이든 "근거 없음"으로 읽고 `hold` 한다. 근거를
조회하지 않은 호출자가 인증을 얻어 가서는 안 되기 때문이다.

알려진 한계(의도적 수용): `gh-pr:review` 의 large-diff 위임 경로는 마커를 찍지
않고(별건 버그, #1636 범위 밖), 봇 전용 리뷰도 `ai-review` 마커를 남기지 않는다.
두 경우 모두 "근거 없음"으로 읽혀 PR 은 **무라벨**로 남는다 — 무라벨은 하류에서
"미검증"이므로 fail-closed 방향이다.

### 마커 작성자 (#1639)

원장 블록도 `ai-review` 마커도 **평범한 PR 코멘트 안의 그냥 텍스트**다. 대부분의
저장소에서 PR 을 볼 수 있는 사람은 코멘트를 달 수 있고, 이는 `review-passed`
라벨을 직접 붙이는 데 필요한 label-write 권한보다 훨씬 낮은 문턱이다. #1639
이전에는 두 리더 모두 작성자가 이미 버려진 본문 텍스트만 받았으므로, **아무나**
다음 둘 중 하나로 게이트를 열 수 있었다:

- `<!-- pr-reply-origins -->` 원장을 위조해 모든 BLOCKER 가 ACCEPT 된 것으로
  기록한다 → `pass=no-blocker`. (반대로 DECLINE 을 위조해 라벨을 영구히 막을
  수도 있다.)
- `<!-- ai-review:` 문자열이 든 코멘트 하나로 "외부 리뷰가 실제로 돌았다" 는
  근거를 날조한다 → `EVIDENCE=yes`.

그래서 두 리더 모두 `<expected-login>` 을 **필수 인자**로 받고, 정확히 그 로그인이
작성한 코멘트만 센다. 위조 비용이 라벨을 직접 위조하는 비용(= label-write 권한,
이 게이트가 처음부터 의존해 온 이미 수용된 신뢰 경계)과 같아진다. 로그인이
없거나 유효하지 않으면 **아무것도 찾지 못한 것**으로 처리한다 — "모두를 신뢰"
로의 폴백은 없다.

PR #1608 이 `_gh_pr_merge_train_review_passed_marker_sha` 에 적용한 것과 같은
수정·검증기·논거다. 전체 논증은
`../../merge-train/references/review-verdict-gate.md` →
"Marker authorship" 에 있고, 두 후속 논점은 그대로 적용된다:

- **봇 로그인.** GitHub 은 App 신원에 `<name>[bot]` 형태의 로그인을 준다
  (`github-actions[bot]`, `dependabot[bot]`). 검증기는 뒤에 붙은 리터럴
  `[bot]` 하나를 떼어 낸 뒤 남은 부분에 `[A-Za-z0-9-]+` 를 적용한다. 봇 계정으로
  인증하는 파이프라인이 자기 마커를 신뢰할 수 있으면서, `[bot]` 으로 정확히
  끝나지 않는 주입 시도는 여전히 막힌다.
- **단일 신원 가정과 탈출구.** 이 방식은 마커를 **쓰는** 쪽과 **읽는** 쪽이 같은
  계정이라고 가정한다 — 이 저장소의 단일 계정 파이프라인에서는 참이지만 모든
  배포에서 그렇지는 않다. `GH_PR_REPLY_TRUSTED_LOGIN` 이 그 탈출구로,
  `gh api user -q .login` 이 이 컨텍스트에서 답하는 값과 실제 생산자 신원이
  다를 때 설정한다. `DEVX_PR_REVIEW_ALL_TRUSTED_LOGIN` /
  `GH_PR_MERGE_TRAIN_TRUSTED_LOGIN` 과 **일부러 분리**했다 — 실무에서는 한
  계정이 셋 다 돌리지만, 리뷰·답변·머지 역할을 계정별로 쪼갠 배포는 각각을
  독립적으로 지정할 수 있어야 한다.

두 리더는 작성자 필터를 **로컬 `jq` 패스**로 수행한다 — 자체 `gh api` 호출이
아니다. Step 2 가 코멘트를 **한 번** 받아 두 리더에 같은 덤프를 먹이는 구조이므로,
작성자 확인을 네트워크 호출로 만들면 그 한 번의 fetch 가 프로브 수만큼 늘어난다.

### 토큰 표

`DECISION` 은 정확히 한 토큰이다:

| 토큰 | 의미 | 후속 |
|---|---|---|
| `pass=no-blocker` | BLOCKER 심각도 항목이 애초에 없었음 | `review-passed` 적용 |
| `pass=blockers-resolved:<n>` | BLOCKER `<n>` 건이 전부 ACCEPT / ACCEPT-PARTIAL | `review-passed` 적용 |
| `hold=unresolved-blocker:<r>` | `<r>` 의 BLOCKER 가 DECLINE/QUESTION 으로 남음 | 미적용, `review-blocked` 유지, **쓰기 0회** |
| `hold=no-external-review` | 이 PR 을 본 외부 리뷰어가 없음 (`ai-review` 마커 부재) | 미적용, 무라벨(=미검증), **쓰기 0회** |

평가 순서: **BLOCKER 루프가 먼저**다. 미해결 BLOCKER 와 근거 부재가 동시에
성립하면 BLOCKER 토큰이 이긴다 — 둘 다 hold 라 라벨 결과는 같지만, BLOCKER
토큰은 리뷰어 이름과 조치할 항목을 알려 준다.

BLOCKER 판정은 `_gh_pr_reply_severity_is_blocking` 을 쓰므로 `BLOCKER` /
`BLOCKING` / `블로커` 가 모두 블로킹으로 센다. `ACCEPT-PARTIAL` 은 해소로
친다(#1616 과 동일) — 부분 수용도 "고쳤다"는 답변이고, 남은 부분은 별도
FOLLOW-UP 으로 다시 제기되는 것이 이 저장소의 흐름이다.

`hold` 은 **첫 번째** 미해결 BLOCKER 에서 즉시 결정되고 그 리뷰어를 이름으로
남긴다. 하나로 충분하다 — NF-2 의 fail-closed 절반은 완화 대상이 아니다.

### 적용 (F-3 / F-4)

```bash
printf '%s\n' "$MERGED" |
    _gh_pr_reply_apply_review_passed "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" \
        "$HEAD_SHA" "$EVIDENCE"
```

입력은 **병합된** 스트림이다 — 이 pass 의 `ORIGINS` 만 먹이면 cross-pass 구멍이
도로 열린다. 5번째 인자는 그대로 게이트로 넘어가고, 생략하면 fail-closed 기본값
(`hold=no-external-review`)이라 아무것도 쓰지 않는다. `hold=*` 는 **전부** 같은
경로다: 보고하고, 쓰지 않고, rc 0.

이 함수가 게이트를 직접 돌리고, `pass=` 일 때만 쓴다. 쓰기는 공유 프리미티브
`devx_pr_review_all_write_label` 로 간다 — `gh-verify:review-all` 이 쓰는 것과
**같은 경로**다:

- 반대 라벨 `review-blocked` 를 **먼저 무조건 삭제**한다. #1616 의 "해제"가
  여기서 함께 일어난다.
- add 는 `_gh_pr_edit_safe_label` 로만 한다 — bare `gh pr edit --add-label` 은
  classic Projects 가 붙은 저장소에서 조용히 exit 1 한다(#326).
- `HEAD_SHA` 4번째 인자는 `review-passed` 에 신선도 마커를 남긴다(#1601).
  **push 이후의 head** 여야 한다(NF-1) — 그래야 `gh-pr:merge-train` 의
  `_gh_pr_merge_train_review_passed_stale` 이 현재 head 와 대조해 통과시킨다.
- soft-fail: 라벨 실패는 WARN 한 줄이고 PR 은 무라벨로 남는다. 무라벨은
  머지 게이트에서 "미검증"으로 읽히므로 안전한 방향이다(기존 계약 그대로).

**`devx_pr_review_all_apply_label` 을 쓰지 않는다.** 그 함수는 리뷰어 판정
토큰 스트림을 받는다. 가짜 `lgtm` 줄을 만들어 먹이면 이 스킬의 자체 판단이
리뷰어 CLI 의 의견인 것처럼 코드에 기록된다 — #1636 이 명시적으로 배제한
단 하나의 선택지다. 완화는 코드에서 **보여야** 하고, 위장되면 안 된다.

### Step 7 문구

`_gh_pr_reply_apply_review_passed` 가 결과 한 줄을 그대로 출력한다
(내부적으로 `_gh_pr_reply_review_passed_report` 를 쓴다).

| 상황 | 문구 |
|---|---|
| BLOCKER 없음 | `[OK] 미해결 BLOCKER 없음(BLOCKER 항목 자체가 없음) — review-passed 적용 (외부 재검토 없음, #1636)` |
| BLOCKER 전부 해소 | `[OK] BLOCKER <n>건 전부 해소 — review-blocked 해제, review-passed 적용 (외부 재검토 없음, #1636)` |
| BLOCKER 미해결 | `[BLOCKED] <r> 의 블로커가 미해결 — review-passed 미부여, review-blocked 유지` |
| 외부 리뷰 근거 없음 | `[BLOCKED] 외부 리뷰 근거(ai-review 마커) 없음 — review-passed 미부여 (#1636 의 분업 전제 미충족)` |
| 원장 기록됨 | `[OK] origin 원장 기록됨 — 다음 pass 가 이 pass 의 판정을 본다` |
| 원장 기록 실패 | `[WARN] origin 원장 기록 실패 — 다음 pass 가 이번 판정을 못 본다(BLOCKER 재분류 필요)` |
| 라벨 미프로비저닝 | `[WARN] label \`review-passed\` missing in <repo> — provision it first (gh-setup:label-bootstrap)` |
| 그 외 쓰기 실패 | `[WARN] PR #<n> review-passed 적용 실패 — 미검증으로 취급` |

## #1637 리뷰가 막은 구멍

#1636 의 완화는 두 군데가 새고 있었고, 둘 다 "분업이 실제로 성립한 PR" 이
아닌데도 인증이 나가는 경로였다.

- **codex BLOCKER — pass 사이의 기억이 없었다.** Step 2 의 중복 제거가 앞선
  pass 의 스레드를 가려서, BLOCKER 를 DECLINE 한 이력이 이후 pass 에는 보이지
  않았다. 그 pass 는 `pass=no-blocker` 를 읽고 미해결 BLOCKER 를 품은 PR 을
  통과시켰다. → `pr-reply-origins` 원장.
- **agy BLOCKER — 발견자가 없어도 인증이 나갔다.** `ORIGINS` 가 비면(외부 리뷰
  자체가 없던 PR) 역시 `pass=no-blocker` 였다. 확인할 발견이 없는데 "해소
  확인"이 나가는 셈이다. → `ai-review` 마커 근거 요구, fail-closed 기본값.

`gh-verify:review-all` 쪽 반대 라벨 삭제도 같은 리뷰에서 조용한 실패를 고쳤다
(codex FOLLOW-UP): `_devx_pr_review_all_delete_label` 이 이제
`drop=ok|absent|failed` 를 내고, 진짜 실패일 때만 WARN 한다 — 404("애초에 없음")
는 정상 다수 경로라 조용히 지나간다.

## 제거된 것 (#1636)

- `Skill(gh-pr:review, "--ai <r> --paths <files> <PR> <remote>")` 재호출과
  그 `BASE_SHA..HEAD` 파일 스코프 계산 — 통과 판정에 더 이상 필요 없다.
  `gh-pr:review` 의 `--paths` 플래그 자체는 남아 있고, 사람이 스코프된
  2차 의견을 원할 때 그대로 쓸 수 있다.
- `_gh_pr_reply_targeted_lane_decide` / `_gh_pr_reply_lane_available` /
  `_gh_pr_reply_targeted_lane_report` — 재호출 전용 게이트였다.
  `_gh_pr_reply_review_passed_gate` / `_gh_pr_reply_review_passed_report` 가
  대신한다. `BLOCKING_REVIEWERS`(PR 의 `ai-review` 블록에서 구하던 집합)도
  더 이상 필요 없다: 질문이 "누가 막았나"가 아니라 "미해결 BLOCKER 가
  남았나"로 바뀌었기 때문이다.

## 회귀 테스트

- `tests/bats/functions/gh_pr_reply_targeted_review.bats` — 게이트 단위
- `tests/bats/skills/gh_pr_reply_review_passed_gate.bats` — 이 문서의 미러
  (`_fixtures/gh_pr_reply_review_passed_gate.sh`)
- `tests/bats/functions/devx_pr_review_all_verdict.bats` — 공유 쓰기
  프리미티브(`devx_pr_review_all_write_label`)와 producer 측 억제
