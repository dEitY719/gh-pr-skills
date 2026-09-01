# merge-emergency

> 한 줄 요약 — 승인 요건을 admin 권한으로 우회해 PR 을 머지하고, 그 대가로 **PR 사유 코멘트 1건 + 후속 incident 이슈 1건**이라는 감사 기록(audit trail)을 남긴다.

## 언제 쓰고 언제 안 쓰는가

`/gh-pr:merge` 가 "승인이 없다"는 이유로 거부했고, 그 승인을 제때 받을 수 없을 때만
쓴다. 이 스킬은 `merge` 의 거부에 대한 **유일한 우회로**이며, 리뷰의 대체재가 아니다.

**쓴다:**

- 주말/야간 핫픽스인데 리뷰어에게 연락이 닿지 않는다.
- 프로덕션 인시던트 완화(revert / feature-flag kill / config 변경).
- 비동기 리뷰를 기다릴 수 없는 보안 패치.

**쓰지 않는다:**

- "리뷰어가 느리다" — 핑을 보내거나 리뷰어를 재지정하고 `/gh-pr:approve` 로 정상 승인을 받는다.
- 사소한 nit 하나를 건너뛰고 싶다 — 가벼운 재리뷰를 요청한다.
- 자가 승인용 PR — 정상 리뷰 경로(`/gh-pr:approve` → `/gh-pr:merge`)를 쓴다.
- **CI 가 빨간데 flaky 라고 생각한다** — 재실행한다. 이 스킬은 필수 CI 가 실패/대기 중이면 머지를 거부한다.
- 승인이 있는 정상 PR 이면 이 스킬이 아니라 `/gh-pr:merge`.
- 여러 PR 을 순차 정리하는 것은 `/gh-pr:merge-train` 이고, 그 train 은 이 스킬을 절대 호출하지 않는다.

## 호출 형식

근거: `skills/merge-emergency/references/help.md`

```
/gh-pr:merge-emergency <PR> <reason> [remote]
```

| # | 이름 | 기본값 | 설명 |
|---|------|--------|------|
| 1 | PR 번호 또는 `-h` / `--help` / `help` | 필수 (생략 시 현재 브랜치의 PR 자동 탐지) | 대상 PR |
| 2 | reason | **필수** | 서면 사유. **10자 이상**, 인시던트/티켓 ID 또는 구체적 사용자 영향을 포함해야 한다 |
| 3 | remote 이름 | `origin` | 대상 저장소를 가리키는 git remote |

```
/gh-pr:merge-emergency 42 "INC-1031 prod 500 error on login since 14:00 KST"
/gh-pr:merge-emergency 42 "revenue impact — checkout broken for 12% of users" upstream
/gh-pr:merge-emergency -h
```

사유 판정 예시(help.md):

- 통과 — `"INC-1031 prod 500 on /login since 14:00 KST — reviewer on vacation"`,
  `"security: CVE-2024-XXXX RCE in dependency, upstream patched 2h ago"`
- 거부 — `"urgent"`, `"fix"`, `"hotfix"`, `"reviewer slow"`, `"merge now"`

## 동작 단계

SKILL.md 의 Step 1~7 요약.

1. **Step 1 — 인자 파싱 + 타깃 결정.** `references/github-target.md` 의 바인딩 블록으로
   `TARGET_REPO` / `TARGET_HOST` / `GH_HOST` 를 **같은 remote URL 하나**에서 해석하고,
   그 다음에야 `gh` 를 호출한다(#1403 / #1407). PR 번호 생략 시 현재 브랜치에서 자동 탐지
   (이때만 `--repo` 없이 호스트 프리픽스만 붙는다 — `gh pr view` 는 PR 인자 없이 `--repo` 를 거부).
   사유가 10자 미만이거나 모호하면 여기서 거부하고 끝난다.
2. **Step 2 — 사전 안전 게이트(병렬).** PR JSON 과
   `gh pr checks <N> --repo "$TARGET_REPO" --required` 를 병렬로 읽고 머지에 손대기 전에 판정한다.
   **하드 스톱** — `state != OPEN`, draft, conflict, 그리고 **필수 체크의 실패/대기**.
   **소프트 경고** — base 가 `BEHIND`, 승인 리뷰 없음.
3. **Step 3 — 사용자 확인.** repo / PR / author / base·head / CI 요약 / 사유를 출력하고
   `Proceed? (yes/ok/진행/머지)` 를 묻는다. **자동 진행은 없다.**
4. **Step 4 — 감사 코멘트 후 admin 머지.** 순서가 의미를 갖는다: 브랜치가 삭제돼도 기록이
   남도록 **코멘트를 먼저** 올린다. 그 다음
   `gh pr merge <N> --repo "$TARGET_REPO" --admin --squash --delete-branch`.
   "Must have admin rights" 로 실패하면 **중단**하고, `--merge` / `--rebase` 로 갈아타지 않는다.
   마지막으로 `mergeCommit.oid` 를 읽어 머지 SHA 를 확보한다.
5. **Step 5 — 후속 incident 이슈 생성.** 협상 불가한 감사 꼬리표.
   제목은 `incident: emergency merge of PR #<N> — <사유 첫 줄>`,
   본문은 `references/audit-templates.md` 의 템플릿 + 회고 체크리스트.
   `incident` 라벨은 `gh label list` 로 **존재가 확인될 때만** 붙인다.
   ai-metrics 푸터는 이슈 본문에 필수로 붙인다(soft-fail 없음, `GH_DISABLE_AI_METRICS=1` 은 존중).
6. **Step 6 — 프로젝트 보드 동기화.** `references/project-board-sync.md` 의 헬퍼로 카드를
   `Done` 으로 옮긴다. 보드가 없거나 동기화가 실패해도 감사 보고를 막지 않는다.
7. **Step 7 — 보고.** 머지 SHA, 감사 코멘트 URL, incident 이슈 번호/URL, 사유,
   그리고 `[WARN] Add retro notes to incident issue within 72h.`

### 감사 산출물의 실제 형태

`references/audit-templates.md` 가 두 산출물의 본문 템플릿을 영문/한국어 두 벌로 고정해 둔다
(PR 본문의 지배적 언어에 맞춰 고른다). 본문은 셸 이스케이프와 동시 실행 충돌을 피하려고
항상 `mktemp` 파일에 먼저 쓴다.

- **PR 사유 코멘트** — `[EMERGENCY] 긴급 머지` 헤더, `**사유:**`, 그리고 "머지 직전 상태"
  블록(base·head, 필수 CI 통과 여부, approve 리뷰 건수, `mergeStateStatus`).
  마지막 문단은 "바이패스가 부당하다고 보면 여기 또는 incident 이슈에 남겨 달라"는 이의 제기 경로다.
- **incident 이슈** — 컨텍스트(PR URL / 머지 SHA / base / author), 인용된 사유,
  **72시간 이내 완료해야 하는 회고 체크리스트**(근본 원인, 정상 리뷰 경로가 불가능했던 이유,
  진짜 긴급이었다는 근거, 후속 액션, 바이패스로 감수한 리스크, 포스트모템 링크),
  그리고 재발 방지 항목.

## 주의사항과 제약

- **우회 대상은 승인 요건뿐이다. CI 는 여전히 게이트한다.** 필수 체크가 실패했거나 아직
  대기 중이면 이 스킬은 머지하지 않고 멈춘다 — `--admin` 은 branch protection 의 approval
  요구를 넘기지, 테스트를 넘기지 않는다. draft 와 conflict 도 마찬가지로 하드 스톱이다.
- **사유·코멘트·이슈 세 가지가 강제된다.** 10자 이상의 서면 사유, 머지 **전에** 올리는 PR 사유
  코멘트, 머지 **후** 생성하는 incident 이슈. incident 이슈를 건너뛰는 경로는 없다 —
  감사 꼬리표가 이 스킬의 존재 이유다.
- **확인 없이는 실행하지 않는다.** Step 3 의 긍정 응답이 없으면 진행하지 않는다.
- **admin 머지 실패를 다른 전략으로 우회하지 않는다.** `--merge` / `--rebase` 로의 폴백 금지.
- **코드를 고치지 않는다.** PR 에 이미 들어있는 것을 머지할 뿐, push 하거나 원인을 수정하지 않는다.
- **모든 `gh` 호출은 같은 remote URL 에서 해석한 `GH_HOST` 와 `--repo` 를 함께 싣는다.**
  admin 머지가 잘못된 서버로 라우팅되면 되돌릴 수 없고, 감사 기록마저 엉뚱한 서버에 남는다.
- **머지 후 72시간 안에 회고를 채운다.** 근본 원인, 정상 경로가 불가능했던 이유, 후속 액션을
  incident 이슈에 적고 닫는다.
- **알려진 마이그레이션 부채** — 이 스킬은 dotfiles 의 `shell-common/functions/*.sh`
  (`gh_host.sh`, `gh_project_status.sh`)를 source 한다. dotfiles 체크아웃이 없는 머신에서는
  해당 단계가 soft-fail 로 저하된다(보드 동기화는 조용히 건너뛴다).

## 관련 스킬

`/gh-pr:merge` 가 정상 경로이고, 그 승인을 만들어 내는 것이 `/gh-pr:approve` 다.
`/gh-pr:merge-train` 은 이 스킬을 **의도적으로 절대 호출하지 않는다**(NF-2) — 머지 불가 PR 은
사유와 함께 `[SKIPPED]` 로 남기고, 바이패스는 사람이 의도적으로 한 번씩 하는 행위로 남긴다.
