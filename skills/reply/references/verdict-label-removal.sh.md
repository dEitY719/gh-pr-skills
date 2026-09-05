# 판정 라벨(`review-passed` / `review-blocked`) 무효화 — Step 6 (soft-fail)

`review-passed` 무효화는 `git push` 가 **성공했을 때만** 실행한다
(`PUSHED_FIXES > 0`). `review-blocked` 는 이 블록에서 손대지 않는다 —
뗄지 말지는 `references/review-passed-gate.md` 의 게이트가 결정하고, 실제
쓰기(반대 라벨 삭제 포함)는 `devx_pr_review_all_write_label` 이 한다.

규칙의 SSOT 는 `shell-common/functions/gh_pr_edit_safe.sh` 헤더의
"Verdict-label invalidation — SSOT for issue #1563" 절이다. 여기서는 되풀이하지
않는다. 요약만: 두 라벨은 **특정 head 커밋 하나**에 대한 주장이므로 head 를
전진시킨 스킬이 스스로 무효화해야 한다.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/target-resolution.md` 대로 이미 export 한 상태여야 한다 (#1403).
`ORIGINS` 는 Step 3 이 `references/review-passed-gate.md` 대로 기록한
`<reviewer>:<severity>:<verdict>` 스트림이다.

## 비대칭: `review-passed` 는 무조건, `review-blocked` 는 게이트가 결정

- **`review-passed`** — push 가 있었다는 사실만으로 무조건 제거한다. 리뷰된
  커밋이 더 이상 head 가 아니므로 "이 head 는 리뷰됨"이 거짓이 된다.
  이 무효화가 먼저 돌고, 같은 Step 6 뒤쪽에서
  `references/review-passed-gate.md` 의 게이트가 **새 head 기준으로** 다시
  붙일지 판단한다 — 순서가 뒤집히면 방금 붙인 라벨을 스스로 지운다.
- **`review-blocked`** — 이 스킬이 직접 떼지 않는다. 뗄지 말지는
  `references/review-passed-gate.md` 의 게이트가 결정하고, 실제 쓰기는
  `devx_pr_review_all_write_label` 이 한다(게이트가 통과하면 그 함수가
  반대 라벨인 `review-blocked` 를 먼저 지운다). 게이트가 미해결 BLOCKER를
  이유로 hold 하면 `review-blocked` 는 손대지 않고 그대로 남는다 —
  DECLINE/QUESTION 으로 남은 BLOCKER 는 "해소"로 치지 않는다(#1636 fail-closed
  방향, "역사적 참고" 아래 #1634 와의 차이 설명).

  #1616 이전에는 여기서 전역 카운터(`ACCEPTED_COUNT` / `DECLINED_COUNT`)로
  판단했다. 그 규칙은 *다른* 리뷰어의 비블로킹 제안을 정당하게 거절한 것만으로
  라벨을 붙잡아 뒀다 — PR #1609 가 그 사례다. 심각도 기반 게이트가
  그 자리를 대신한다.

### 역사적 참고 — #1634 는 #1636 으로 대체됐다

#1634 는 한때 "Step 5 완주(코멘트 전원 답변) 자체가 조건"으로 `review-blocked`
를 **무조건**(ACCEPT/DECLINE 비율과 무관하게) 해제했다 — 정당한 사유로
DECLINE 된 BLOCKER 도 라벨을 풀어 줬다는 뜻이다. #1636 은 이를 더 엄격한
규칙으로 대체한다: BLOCKER 심각도 항목이 하나라도 미해결(DECLINE/QUESTION)로
남으면 `review-passed` 는 절대 부여되지 않고, 그 결과 `review-blocked` 도
그대로 남는다 — "발견은 외부 AI, 해소 확인은 gh-pr:reply" 라는 분업에서
"해소"는 실제로 고쳐졌다는 뜻이지 답변만 달았다는 뜻이 아니다.

## 명령

공유 헬퍼 `_gh_pr_drop_label` 을 쓴다 — REST DELETE 관용구를 스킬마다 복사하지
않기 위한 단일 구현체다. 404(라벨이 애초에 없음)는 **경고가 아니라 정상**으로
흡수되므로 "있는지 먼저 확인"하는 분기가 필요 없다. rc 1 일 때만 원문 에러가
stderr 로 넘어온다.

```bash
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_edit_safe.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_edit_safe.sh" ] || {
    printf '[gh-pr:reply] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_edit_safe.sh"
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_reply_targeted_review.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_reply_targeted_review.sh" ] || {
    printf '[gh-pr:reply] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_reply_targeted_review.sh"

if [ "$PUSHED_FIXES" -gt 0 ]; then
    if _vl_err=$(_gh_pr_drop_label "$PR_NUMBER" review-passed \
            "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
        echo "[OK] \`review-passed\` 무효화됨 — head 가 전진해 이전 판정은 만료"
    else
        echo "[WARN] \`review-passed\` 제거 실패 — 리뷰되지 않은 커밋에 판정이 남아 있다: ${_vl_err}"
    fi
fi

# review-blocked 는 여기서 떼지 않는다 — review-passed-gate.md 로 넘긴다.
# 게이트는 push 여부와 무관하게 돈다: 전부 DECLINE/QUESTION 이라 커밋이
# 없었어도 "미해결 BLOCKER 가 없다"는 판단은 성립할 수 있다.
```

`2>&1` 로 잡는 것은 헬퍼가 rc 1 에서 흘려보내는 `gh` 원문 에러다 — 성공/404
경로에서는 비어 있다. 이어지는 `review-passed` 적용 판단은
`references/review-passed-gate.md` § "Step 6 — 게이트와 적용" 이 SSOT 다.

## 직접 add 금지

이 스킬은 두 라벨 중 어느 것도 **손으로 add 하지 않는다**. `review-passed` 는
`_gh_pr_reply_apply_review_passed`(→ `devx_pr_review_all_write_label`) 만이,
`review-blocked` 는 `gh-verify:review-all` 만이 쓴다. #1636 이후 이 스킬은
외부 재검토 없이 스스로 `review-passed` 를 부여할 수 **있지만**, 그 판단조차
게이트 함수를 통해서만 이루어진다 — 인라인 라벨 명령은 여전히 금지다.
완화의 범위와 근거는 `references/constraints.md` 가 SSOT 다.

## 호스트 고정

네 번째 인자 `TARGET_HOST` 가 `GH_HOST` 를 고정한다. 넘기지 않으면 dual-host
로그인에서 `gh` 가 `gh repo set-default` 로 폴백해 **에러 없이 엉뚱한 서버의
라벨을 지운다** (#1403 / #1407). `gh api` 는 `--repo` 플래그를 받지 않으므로
repo 는 경로에 들어간다 (#658) — 헬퍼가 대신 처리한다.
