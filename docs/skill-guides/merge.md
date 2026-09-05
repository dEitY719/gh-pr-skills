# merge

> 한 줄 요약 — 승인된 PR 하나를 **머지하고 head 브랜치를 삭제**한다. 기본 전략은 rebase.

확인을 묻지 않는다 — 스킬을 실행한 것이 곧 확인이다. 대신 **강행하지 않고 거부한다**:
미승인 / CI 실패 / draft / conflict 네 가지가 정지 조건이고, 그 거부의 우회로는
`/gh-pr:merge-emergency` **하나뿐**이다.

## 언제 쓰고 언제 안 쓰는가

- **승인이 끝난 PR 하나**를 머지할 때 — `/gh-pr:merge`.
- 승인을 받을 수 없어 branch protection 을 admin 권한으로 우회해야 할 때는
  `/gh-pr:merge-emergency`. 10자 이상의 사유, PR 사유 코멘트, 후속 인시던트 이슈가
  강제되고 **CI 는 여전히 게이트한다** — 우회 대상은 승인 요건뿐이다.
- 자기 소유의 열린 PR **여러 개**를 정리하며 순차 머지할 때는 `/gh-pr:merge-train`.
  직렬로 한 번에 하나씩 돌고, 각 PR 을 `gh-resolve:outdated` / `:conflict` / `:ci-fail`
  로 먼저 라우팅한 뒤 이 스킬과 같은 게이트를 통과시킨다. `merge` 가 거부했을 PR 을
  머지하지 않는다.
- 아직 승인이 없다면 먼저 `/gh-pr:approve`. 이 스킬은 verdict 를 만들지 않고, 이미
  존재하는 `reviewDecision` 을 읽고 게이트할 뿐이다.
- conflict / base out-of-date / red CI 자체를 푸는 것은 `gh-resolve` 쪽 스킬들의 일이다.

## 호출 형식

근거: `skills/merge/references/help.md`.

```
/gh-pr:merge <pr-number> [rebase|squash|merge] [remote]
```

| 위치 | 이름 | 기본값 | 설명 |
|---|---|---|---|
| 1 | `<pr-number>` 또는 `-h`/`--help`/`help` | 필수 | 양의 정수. 없거나 잘못되면 usage 를 가리키고 정지 |
| 2 | 전략 | `rebase` | `rebase` / `squash` / `merge` 중 하나. 그 외는 허용값을 출력하고 정지 |
| 3 | remote 이름 | `origin` | PR 이 속한 저장소의 git remote |

전략 선택 기준:

- **`rebase`**(기본) — 선형 히스토리. 커밋이 깔끔한 피처 브랜치에 적합.
- **`squash`** — PR 의 모든 커밋을 하나로 접는다. WIP 커밋이 지저분할 때.
- **`merge`** — 모든 커밋 보존 + 머지 커밋 추가. 히스토리 자체가 의미를 가질 때.

전략의 사용 가능 여부는 저장소 설정(Settings > General > Pull Requests)에 달려 있다.
비활성화된 전략을 고르면 안내 메시지를 출력하고 **정지**한다 — 다른 전략으로 폴백하지 않는다.

## 동작 단계

1. **Step 1 — 인자 해석 + repo 해석.** `START_TS` 를 기록하고, `remote` 하나의 URL 에서
   `TARGET_REPO` 와 `TARGET_HOST` 를 함께 바인딩한 뒤 `GH_HOST` 를 export 한다
   (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407). remote 가 없으면 `git remote -v` 를 나열하고 정지 — 조용한 `origin`
   폴백은 없다. 호스트를 잘못 바인딩했을 때 그 잘못된 서버 호출이 도달하는 지점이
   `gh pr merge --delete-branch`, 즉 저장소에서 가장 파괴적인 쓰기이기 때문이다.
2. **Step 2 — 사전 점검(병렬).** `gh pr view --json state,isDraft,mergeable,`
   `mergeStateStatus,reviewDecision,baseRefName,headRefName,url` 과
   `gh pr checks --required` 를 한 번에 돌리고, base 브랜치의 protection 유무를
   `gh api repos/<repo>/branches/<base>/protection` 으로 감지한다(exit 0 = 있음,
   403/404 = 없음).
   **정지 조건**: `state != OPEN`; `isDraft`; `mergeable == CONFLICTING`;
   `mergeStateStatus` 가 `BEHIND`/`BLOCKED`/`DIRTY`; required check 가
   `FAILURE`/`IN_PROGRESS`/`QUEUED`; `reviewDecision != APPROVED`
   (→ `/gh-pr:merge-emergency` 안내).
   **조건부 예외 하나**: protection 이 **없고** `reviewDecision` 이 **빈 문자열**일 때만
   수용하고 `INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.`
   를 출력한다. 비어 있지 않은 비-APPROVED 값(`CHANGES_REQUESTED`, `REVIEW_REQUIRED`)은
   protection 유무와 무관하게 정지한다 — 누군가 명시적으로 막은 신호다.
   projectV2 보드 Status 는 머지 게이트가 **아니다**(dEitY719/dotfiles#1513) — 여기서 읽지 않는다.
3. **Step 3 — 머지(확인 없음).**
   `GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch`.
   `merge method is not allowed` 가 나오면 저장소 설정 안내를 출력하고 정지한다.
   **전략을 조용히 바꾸지 않는다.**
4. **Step 4 — 보드 동기화와 뒷정리.** PR 카드와 연결된 이슈 카드를 `Done` 으로 옮기고,
   머지된 브랜치의 로컬 worktree 에 유휴 herdr 탭이 있으면 `[INFO]` 힌트 한 줄을 찍고,
   이제 읽을 사람이 없는 `review-passed` 라벨을 뗀 뒤, ai-metrics PR 코멘트를 남긴다.
   **전부 soft-fail** — 실패는 stderr 한 줄이고 보고나 종료 코드를 바꾸지 않는다.
5. **Step 5 — 머지 SHA 조회 + 보고.** `mergeCommit.oid` 를 읽어 compact 보고를 출력한다.
   `null` 이면 1초 후 한 번 재시도하고, 그래도 없으면 `(pending)` 으로 찍고 PR URL 을 함께
   낸다. 보고가 출력된 **뒤에** post-merge 검증 dispatch 블록이 실행된다(아래 참조).

## 주의사항과 제약

- **확인을 묻지 않는다.** 스킬 실행 자체가 확인이다.
- **미승인 PR 을 머지하지 않고, CI 를 우회하지 않는다.** 유일한 우회로는
  `/gh-pr:merge-emergency` 이며, 그마저도 CI 는 여전히 게이트한다.
- **실패한 전략을 다른 전략으로 바꿔 재시도하지 않는다. 언제나 `--delete-branch`.**
- 모든 `gh` 호출은 같은 remote URL 에서 해석한 `GH_HOST` 와 `--repo` 를 **둘 다** 싣는다.
  `gh api` 에는 `--repo` 가 없으므로 repo 는 경로(`repos/$TARGET_REPO/...`)에 들어가고
  `GH_HOST=` 접두는 그대로 남는다.
- **마이그레이션 부채 1 — Step 5 의 dispatch 경로 (해소됨, #13).** Step 5 는 예전에
  post-merge 검증 블록을 dotfiles 경로
  `${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md`
  에서 읽었다. 그러나 `~/dotfiles/claude/skills/` 는 이미 삭제됐고 스킬 이름도
  `post-merge-verify` 로 바뀌어, `[ -r ]` 가드가 394줄짜리 검증 게이트를 매 머지마다
  조용히 건너뛰고 있었다. 지금은 2단 폴백으로 읽는다 — 1순위 `GH_VERIFY_ROOT` 가
  가리키는 라이브 `gh-verify`, 2순위 이 저장소가 벤더링한 사본
  `lib/vendor/gh-verify/post-merge-verify/dispatch.sh.md` (SSOT: `gh-verify-skills`
  의 `skills/post-merge-verify/references/dispatch.sh.md`). watched-repos
  레지스트리에 **등록된** 저장소인데 dispatch 를 스테이징하지 못하면 `[WARN]` 이
  아니라 `[FAIL]` 로 크게 실패한다 — opt-out 이 아니라 깨진 설치이기 때문이다.
  미등록 저장소는 예전 그대로 출력도 dispatch 도 `[WARN]` 도 없다.
- **알려진 마이그레이션 부채 2 — SKILL.md 길이.** `skills/merge/SKILL.md` 는 197줄로
  이 플러그인에서 가장 길고, 100줄 progressive-disclosure 한도를 넘긴다. CI 는
  `max-skill-lines: 197` 로 고정해 이를 허용하고 있다. 해결책은 한도를 올리는 것이
  아니라 세부를 `references/` 로 빼는 것이다.
