# gh-pr — harness support

Per-skill portability for the eight `gh-pr` skills, and what each degraded
cell means in practice. Summarised in [`README.md`](../README.md) under
"Harness support".

These are `gh` CLI calls, `git` calls, and file writes, so they port cleanly
with two exceptions — `merge-train` chains the other skills through Claude
Code's `Skill()` tool, and `approve` / `review` hand a large diff to a subagent.
Every gap and its workaround is documented per harness in
[`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references);
read the one file for the harness you are on.

| Skill | Claude Code | Codex | Kimi | Gemini / Antigravity | Hermes | OpenCode |
|-------|:-----------:|:-----:|:----:|:--------------------:|:------:|:--------:|
| `commit` | full | full | full | full | full | full |
| `create` | full | full | full | full | full | full |
| `review` | full | inline diff | full | inline diff | inline diff | inline diff |
| `reply` | full | full | full | full | full | full |
| `approve` | full | inline diff | full | inline diff | inline diff | inline diff |
| `merge` | full | full | full | full | full | full |
| `merge-emergency` | full | full | full | full | full | full |
| `merge-train` | full | manual chain | manual chain | manual chain | manual chain | manual chain |

*inline diff* — `approve` and `review` dispatch a large diff to a subagent on
Claude Code and Kimi (`Agent`). Elsewhere they read it inline. Same verdict,
more tokens in one context.

*manual chain* — `merge-train`'s loop calls the per-PR skills through `Skill()`.
Without a skill-invocation tool, run them yourself, one PR at a time:
`gh-resolve:outdated` / `:conflict` / `:ci-fail`, then `gh-pr:merge`. The gates
are per-PR, so nothing is skipped by driving them by hand — only the walking is.
