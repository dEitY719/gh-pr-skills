# gh-pr:review — Help

Delegate a GitHub PR's review to an external AI CLI (`codex`, `agy`,
`claude`, `opencode`, or `hermes`) for a **second opinion**. Output is written to stdout and
posted as a PR comment by default. **No decision (approve /
request-changes) is submitted** — see `gh-pr-approve` for that.

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | PR number, or `-h`/`--help`/`help` | current-branch PR | Target PR, e.g. `99` |
| 2 | remote name | `origin` | Git remote for the target repo |

### Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--ai <codex\|agy\|claude\|opencode\|hermes>` | yes | External AI CLI to delegate the review to. Single value — no CSV. |
| `--review <preset>` | no | Review depth/lens enum. Default `default`. See below. |
| `--user <name>` | no | `--ai claude` only. Multi-account routing via `_claude_resolve_account` (e.g. `personal`, `work`, `work1`). |
| `--no-post-comment` | no | Skip the automatic PR comment; only print to stdout. |
| `--paths <path>` | no | Repeatable. Review only these files — the diff is filtered by path, so the run stays on the inline path however large the PR is. A scope matching no file exits 1. Added for `gh-pr:reply`'s targeted re-review lane (#1616). |

## `--review` enum

Closed enum — free-text values are rejected. Korean aliases normalize to
the English enum before dispatch. Every preset, `quick` included,
always adds a mandatory "at least one questionable assumption"
critique and an overall translatable verdict line — e.g.
`Verdict: [LGTM|CONCERNS|BLOCKING]` for an English-dominant diff, or
`판정: [LGTM|우려있음|블로킹]` for a Korean-dominant diff — matching the
diff's dominant language without mixing the two. There is no flag to
turn this off.

| enum | KR alias | Lens |
|------|----------|------|
| `default` | `보통` | 7-dim balance: correctness · conventions · security · performance · tests · docs · backward-compat |
| `quick` | `간단` | BLOCKER-only quick scan (correctness + security) |
| `thorough` | `꼼꼼` / `꼼꼼하게` | 7-dim + architecture trade-offs + test-coverage gaps + adjacent-system impact |
| `security` | `보안` | Security lens — injection, secrets, authz, supply chain |
| `performance` | `성능` | Performance lens — N+1, hot-loop I/O, allocation, caching |

## `--user` (claude only)

Multi-account routing for `--ai claude`. Reuses the SSOT helper
`_claude_resolve_account` (the same one `claude-yolo --user <name>`
calls) so `--user work` runs `CLAUDE_CONFIG_DIR=$HOME/.claude-work
claude -p ...`.

- Default: when omitted, the **current shell's `CLAUDE_CONFIG_DIR` is
  preserved** — no forced `personal`. Calling `/gh-pr:review --ai
  claude 99` from inside a `claude-yolo --user work` shell continues to
  use the `work` account.
- `--user` with `--ai codex`, `--ai agy`, `--ai opencode`, or `--ai hermes` is **rejected (exit 2)** —
  those CLIs have no multi-account routing mechanism, so silently
  ignoring would risk hiding an intent mismatch.
- Unknown account names fall through `_claude_resolve_account` and exit
  1 with `Unknown claude account: '<name>' (allowed: <list>)`. The
  allowed list comes from `CLAUDE_ENABLED_ACCOUNTS`.

## `--ai opencode`

Internal-PC only. The lane uses fixed model `codemate/CodeLLMPro`,
passes the prompt file with `--file`, and runs in an isolated temporary
directory via `--dir` so relative writes do not touch the PR checkout.

## `--ai hermes`

Internal-PC only (Samsung DS internal AI coding CLI; setup module
`hermes/`). Outside `_dotfiles_setup_mode == internal` the lane exits 1
with `--ai hermes is internal-PC only (~/.dotfiles-setup-mode !=
internal)`. The invocation passes a short instruction as argv plus the
prompt file with `--file`; no `--model` override is accepted. The exact
non-interactive subcommand is a first-pass assumption pending
verification on an internal PC — see
`references/ai-cli-invocation.md` § `--ai hermes`.

## Usage

- `/gh-pr:review --ai codex 99` — codex review of PR #99 (default preset)
- `/gh-pr:review --ai agy --review thorough 99` — agy, thorough preset
- `/gh-pr:review --ai claude --review 꼼꼼 99` — claude, KR alias → thorough
- `/gh-pr:review --ai opencode 99` — opencode review on internal PC
- `/gh-pr:review --ai hermes 99` — hermes review on internal PC
- `/gh-pr:review --ai claude --user work 99` — claude as `work` account
- `/gh-pr:review --ai claude --user work1 --review 보안 99` — work1 + security
- `/gh-pr:review --ai codex --no-post-comment 99` — stdout only, no PR comment
- `/gh-pr:review --ai codex --paths a.sh --paths b.sh 99` — review only those two files
- `/gh-pr:review --ai codex 99 upstream` — PR #99 on `upstream`'s repo
- `/gh-pr:review --ai agy` — auto-detect PR from current branch
- `/gh-pr:review -h` / `--help` / `help` — print this help

## What the skill does

1. Parse flags + resolve PR number / `TARGET_REPO` / external CLI PATH.
2. Pre-flight: refuse closed/merged/draft PRs. CI status is **not** a
   gate — opinion collection works regardless of CI.
3. Load the `--review` preset's prompt template from
   `references/review-presets.md` — the shared prefix always requires a
   questionable-assumption critique and a closing verdict tag.
4. Fetch `gh pr diff <N>` + PR metadata. Large diffs reuse
   `gh-pr-approve`'s subagent delegation pattern.
5. Dispatch to the chosen external CLI per
   `references/ai-cli-invocation.md` — stdin gets `(prompt + diff)`.
6. Stream the external CLI's stdout verbatim to your terminal. Unless
   `--no-post-comment` is set, also post it as a PR comment per
   `references/post-comment.md` (collapsed `<details>` wrapper + ai-metrics
   footer).
7. Print a one-line confirmation: `[OK] PR #<N> reviewed by <ai>
   (--review=<preset>) — comment: <URL or skipped>`.

## What the skill will NOT do

- Submit `gh pr review --approve` / `--request-changes`. Opinion
  collection only — `gh-pr-approve` is the decision skill.
- Reply to individual review comments — that's `gh-pr-reply`.
- Run multiple AI CLIs in parallel. Single `--ai` value; rerun the
  command N times for an N-way comparison.
- Accept a free-text `--review` value. Closed enum only (KR aliases
  allowed).
- Reformat or summarize the external AI's stdout — the user wants raw
  AI output to judge for themselves.
- Block self-authored PRs. No decision is submitted, so the
  self-approve restriction does not apply.

## Exit codes

| Code | Cause |
|------|-------|
| 0 | Review completed and (optionally) commented on the PR. |
| 0 | PR comment post failed but stdout still has the AI output (soft fail with `[WARN]`). |
| 1 | External CLI missing on `$PATH`, external CLI returned non-zero, PR auto-detect failed, unknown `--user` account, `--paths` matched no file in the diff, or `gh` not authenticated. |
| 2 | Argument error: missing `--ai`, unknown `--ai` value, unknown `--review` value, `--user` with non-claude `--ai`, `--paths` with no value. |

## Good vs. bad invocation

- **Good**: `/gh-pr:review --ai codex 99` — gather a 2nd opinion on PR #99.
- **Good**: `/gh-pr:review --ai agy --review security 99` — security-focused lens.
- **Good**: chained `/gh-pr:review --ai codex 99` then `/gh-pr:review --ai opencode 99` — side-by-side comparison.
- **Bad**: `/gh-pr:review --ai codex --user work 99` — exits 2 (`--user` is claude-only).
- **Bad**: `/gh-pr:review --ai claude --review "꼼꼼하게 봐줘" 99` — exits 2 (free text rejected; use `꼼꼼` alias).
- **Bad**: `/gh-pr:review --ai chatgpt 99` — exits 2 (unknown AI).
