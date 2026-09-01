# review 사용 결과

> **한 줄 요약** — PR diff 를 받아 외부 AI CLI 의 2차 의견을 담은 집계 코멘트 1개를 생성합니다.

> NOTE: **미실행 예시** — gh-pr 스킬 8개는 모두 live repo 에 쓰므로 문서화 목적으로 실행하지 않았습니다. 명령·게이트·결과는 `skills/review/SKILL.md` 인용이며 실행 로그가 아닙니다.

```
PR diff  ──▶  /gh-pr:review  ──▶  집계 코멘트 1개
```

## 1. 실행할 명령

```
/gh-pr:review --ai <codex|agy|claude|opencode|hermes> [--review <preset>] [<PR#>] [<remote>]
/gh-pr:review --ai codex --review thorough 12   # 이 repo(dEitY719/gh-pr-skills) 대상
```

`--ai` 없이 호출하면 exit 2. `--review` 는 `default` / `quick` / `thorough` / `security` /
`performance` 와 KR 별칭(`보통` `간단` `꼼꼼` `보안` `성능`)만 받는다.

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
