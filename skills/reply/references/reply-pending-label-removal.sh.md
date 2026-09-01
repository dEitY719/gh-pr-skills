# `reply-pending` 라벨 제거 (무조건, soft-fail)

Runs on **every** completion of this skill — 인라인 호출이든 지연 예약 호출이든,
수정 커밋이 있었든 없었든. 조건 분기 없음.

호출 지점은 **두 곳**이고, 둘 다 이 파일의 같은 블록을 실행한다 (인라인 복제 금지):

| 호출 지점 | 상황 |
|---|---|
| Step 2.5 조기 종료 | 답할 코멘트가 하나도 없어 Step 3–7 을 건너뛸 때 |
| Step 6 | 정상 경로 — Step 5 답변까지 끝난 뒤 |

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/target-resolution.md` 대로 이미 export 한 상태여야 한다 (#1403).
Step 2.5 는 Step 1 뒤이므로 두 경로 모두 계약을 만족한다.

## 왜 무조건인가 (#1524)

`gh-verify:review-all` 의 `defer` 브랜치가 이 라벨을 붙인다. 붙어 있는 동안
`gh-pr:merge-train` 은 경과 시간과 무관하게 그 PR 을 건너뛴다 (스테일 판정
윈도우가 지나기 전까지 — `gh-pr-merge-train/references/ordering.md` D-6).
답변 패스가 끝났다는 사실을 아는 지점은 여기 하나뿐이므로, 제거도 여기 하나뿐이다.

Step 2.5 가 이 블록을 부르는 이유가 그것이다: 리뷰어가 아무 코멘트도 남기지
않았어도 `defer` 브랜치는 이미 라벨을 붙여 뒀다. 조기 종료가 라벨을 그대로 두면
"답할 게 없었다"는 이유로 PR 이 트레인에서 밀려난다 (PR #1545 리뷰, agy BLOCKER).

`inline` 브랜치에서 온 호출은 애초에 라벨이 붙은 적이 없다. 그 경우 DELETE 는
404 를 돌려주고, 아래 블록은 그것을 **경고가 아니라 정상**으로 보고한다 — 멱등이므로
분기해서 "있는지 먼저 확인"할 이유가 없다.

## 명령

`gh pr edit --remove-label` 이 아니라 REST DELETE 다: 전자는 classic Projects
보드가 붙은 repo 에서 GraphQL deprecation 때문에 **조용히 실패**한다 (#326 Bug B,
`_gh_pr_edit_safe_label` 의 fallback 과 같은 이유).

```bash
if _rp_err=$(GH_HOST="$TARGET_HOST" gh api -X DELETE \
        "repos/$TARGET_REPO/issues/$PR_NUMBER/labels/reply-pending" 2>&1 >/dev/null); then
    echo "[OK] \`reply-pending\` 라벨 제거됨 — merge-train 이 이 PR 을 다시 본다"
else
    case "$_rp_err" in
        *"HTTP 404"* | *"Not Found"*)
            echo "[OK] \`reply-pending\` 라벨 없음 (라벨이 애초에 없었음 — 정상)" ;;
        *)
            echo "[WARN] \`reply-pending\` 라벨 제거 실패 — merge-train 이 이 PR 을 계속 건너뛴다: ${_rp_err}" ;;
    esac
fi
```

`2>&1 >/dev/null` 은 순서가 중요하다: stderr 를 (아직 원래 stdout 인) 캡처 대상으로
먼저 보낸 뒤 stdout 을 버린다. 반대로 쓰면 stderr 가 `/dev/null` 로 간다.

### 왜 404 를 WARN 에서 떼어냈나 (#1545 리뷰, agy FOLLOW-UP)

인라인 리뷰 완료는 **정상적인 다수 경로**인데 라벨이 애초에 없으므로 DELETE 는 늘
404 다. 이전 판은 `||` 한 가지로 404 와 실제 실패(인증 만료, 네트워크, 5xx)를 같이
받아 매번 `[WARN]` 을 찍었고, 그 결과 진짜 실패도 평소의 소음처럼 보였다. 이제
`[WARN]` 은 **사람이 손봐야 하는 상황에서만** 나온다 — 라벨이 남아 트레인이 계속
이 PR 을 건너뛴다는 뜻이므로, 원문 에러를 그대로 붙여 원인을 바로 읽게 한다.

`gh` 는 실패를 전부 non-zero exit 하나로 뭉개므로 상태 구분은 stderr 본문에서
얻는다(같은 정보 손실이 #1519 를 만들었다). `gh` 의 404 문구는
`gh: Not Found (HTTP 404)` 라 두 패턴 중 어느 쪽으로도 잡힌다.

## 호스트 고정

`gh api` 는 `--repo` 플래그를 받지 않으므로 repo 는 경로에 넣는다 (#658).
리터럴 `{owner}/{repo}` 를 남기면 `gh` 가 git remote 대신 `gh repo set-default`
로 폴백해서 **에러 없이 엉뚱한 서버의 라벨을 지운다** (#1403 / #1407).
`GH_HOST="$TARGET_HOST"` 가 그 서버를 고정한다.
