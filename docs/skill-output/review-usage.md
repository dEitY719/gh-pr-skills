# review 사용 결과

> **한 줄 요약** — PR diff 를 받아 외부 AI CLI 의 2차 의견을 담은 집계 코멘트 1개를 생성합니다.

> NOTE: 이 문서는 **미실행 예시**입니다. gh-pr 의 8개 스킬은 모두 live GitHub
> repo 에 쓰기를 하고, 이 저장소에는 대상 PR 이 없으며 커밋/push 가 금지된
> 작업이었으므로 문서화 목적의 실행을 하지 않았습니다. 아래 명령과 게이트는
> `skills/review/SKILL.md` 에서 인용한 것이고, 결과 절은 실행 시 생성되는
> 산출물을 기술합니다. 실제 실행 로그가 아닙니다.

```
PR diff  ──▶  /gh-pr:review  ──▶  집계 코멘트 1개
```

## 1. 실행할 명령

범용 형식:

```
/gh-pr:review --ai <codex|agy|claude|opencode|hermes> [--review <preset>] [<PR#>] [<remote>]
```

이 repo(`dEitY719/gh-pr-skills`) 를 대상으로 했을 때:

```
/gh-pr:review --ai codex --review thorough 12
```

`--ai` 없이 호출하면 exit 2. `--review` 는 `default` / `quick` / `thorough` /
`security` / `performance` 와 KR 별칭(`보통` `간단` `꼼꼼` `보안` `성능`)만 받는다.

## 2. 입력

- **입력** — 대상 PR 의 diff(`gh pr diff`)와 메타데이터. `--paths` 를 주면 그 경로로 필터된 diff.
- **게이트** — PR 이 `OPEN` + non-draft, 선택한 AI CLI 가 PATH 에 존재,
  `--ai opencode` / `--ai hermes` 는 internal PC, `gh auth status` 가 0.
  CI 상태는 게이트가 아니고 자기가 올린 PR 도 막히지 않는다(판정 미제출이므로).

## 3. 결과 (실행 시)

- **PR 코멘트 1개** — 외부 AI stdout 을 재가공 없이 담은 접힌 `<details>` 블록 +
  `ai-review:<ai>:<head-sha>` 마커 쌍 + ai-metrics 푸터(차트/사람/로봇 글리프로
  토큰·사람 시간·경과 분 표기). `--no-post-comment` 나 `GH_DISABLE_AI_METRICS=1` 이면 미게시.
- **터미널 stdout** — 외부 CLI 출력 원문 그대로.
- **확인 한 줄** — `[OK] PR #<N> reviewed by <ai> (--review=<preset>) — comment: <URL or skipped>`.
- **남지 않는 것** — 판정도 코멘트별 답글도 없다. 각각 `/gh-pr:approve` 와 `/gh-pr:reply` 의 산출물이다.
