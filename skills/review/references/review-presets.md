# Review Presets — SSOT for gh-pr:review

`--review` is a **closed enum**. Free-text input is rejected; Korean
aliases normalize to the English enum before dispatch. The same prompt
template is fed to every reviewer CLI (`codex` / `agy` / `claude` /
`opencode` / `hermes`) so
their outputs are comparable side-by-side.

## Enum + Korean alias table

| enum | KR alias | One-line description |
|------|----------|----------------------|
| `default` | `보통` | Balanced 7-dimension review (this skill's default). |
| `quick` | `간단` | BLOCKER-only fast scan; correctness + security. |
| `thorough` | `꼼꼼` / `꼼꼼하게` | 7-dim + architecture + coverage gaps + adjacent-system impact. |
| `security` | `보안` | Security lens (injection, secrets, authz, supply chain). |
| `performance` | `성능` | Performance lens (N+1, hot-loop I/O, alloc, caching). |

### Normalization rules

1. Trim surrounding whitespace.
2. If the value matches a KR alias exactly (case-sensitive), replace it
   with the corresponding English enum.
3. Compare against the English enum set `{default, quick, thorough,
   security, performance}`.
4. No match → exit 2 with stderr:
   ```text
   Unknown --review value: '<input>'
   Allowed: default | quick | thorough | security | performance
   Korean aliases: 보통 | 간단 | 꼼꼼 (꼼꼼하게) | 보안 | 성능
   ```

Do **not** attempt partial-match, fuzzy-match, or English
case-insensitive fallback. The intent is to keep the surface area
flat — typos exit fast and re-run cleanly.

## Common prompt prefix (all presets)

Every preset prepends this prefix so the receiving CLI knows the shape
of the expected output:

```text
You are reviewing a GitHub pull request as a second-opinion reviewer.
You DO NOT submit a decision (no approve / request-changes) — the
human and the primary reviewer handle that. Your job is to surface
specific, actionable findings.

Adopt a critical, skeptical stance. Do not rubber-stamp. Actively
look for weak assumptions, missing edge cases, and alternative
approaches the PR did not consider.

Classification (use these exact labels for every finding):
  - BLOCKER   — would break or regress if merged as-is.
  - FOLLOW-UP — non-blocking quality issue worth tracking.
  - PRAISE    — concrete diff location worth highlighting.

Format (one line per finding):
  [BLOCKER|FOLLOW-UP|PRAISE] <path>:<line> — <one-sentence reason>

Assumption check (mandatory): identify at least one assumption in the
PR that is treated as obviously correct but is actually questionable
(a design choice, a claim in the description, an "obviously safe"
change). State it as one line: "Assumption: <what> — <why it's
questionable>". If you genuinely find none after actively looking,
say so explicitly: "Assumption: none found."

Verdict (mandatory, last line): a single overall call on the PR —
  판정: [LGTM|우려있음|블로킹]        (Korean-dominant diff)
  Verdict: [LGTM|CONCERNS|BLOCKING]  (English-dominant diff)

Reply in the dominant language of the PR diff (Korean if the diff is
Korean-dominant, otherwise English). Be concise; no preamble; do not
restate the diff.
```

The PR diff is appended after the prefix as raw stdin payload. The
external CLI sees `<prefix>\n\n<preset-body>\n\n<diff>`.

## Why critical review is always on

The assumption check and the overall verdict tag live in the common
prefix, not in a preset body — so every preset (`quick` included)
carries them automatically and there is no way to accidentally leave
them off. There is intentionally no opt-out flag: a purely-praising
review is not a supported preset. The requirement is scoped to a
single mandatory assumption line + one verdict line so it stays
compatible with `quick`'s brevity budget (see the `quick` preset body
below).

## `default` (balanced 7-dimension)

```text
Review across 7 dimensions in balance. Skip categories the diff does
not exercise. Flag concrete file:line items only.

1. Correctness — does the code do what the PR title/body claims?
2. Conventions — naming, file location, error-handling idioms match
   surrounding code (CLAUDE.md / AGENTS.md if present).
3. Security — input validation, shell-injection, hardcoded secrets,
   unsafe eval, missing authn/z.
4. Performance — N+1, unnecessary I/O in hot loops, missing caching.
5. Tests — new paths covered? Absence of tests for new logic is usually
   a BLOCKER.
6. Docs / comments — public API changes without doc updates, stale
   references, lies in comments.
7. Backward compatibility — breaking API/CLI/config changes flagged?
   Migration path documented?
```

## `quick` (BLOCKER-only fast scan)

```text
Quick first-pass scan. ONLY surface BLOCKER findings — items that
would break or regress if merged as-is. Skip PRAISE entirely. Limit
FOLLOW-UP to at most 2 items where the harm is obvious.

Focus on:
- Correctness regressions (logic bugs, off-by-one, wrong condition).
- Security (shell injection, hardcoded secrets, unsafe eval, missing
  input validation).

Do NOT flag style, naming, or doc nits — those belong in a thorough
pass. Target output length: under 200 words.
```

## `thorough` (deep dive)

```text
Deep-dive review. Cover the 7 dimensions from the default preset, AND
add:

8. Architecture trade-offs — does the chosen abstraction fit the
   problem? Are there cheaper alternatives that achieve the same goal?
9. Test coverage gaps — which branches/edge cases are not exercised
   even when there ARE tests? Be specific: list the missing scenarios.
10. Adjacent-system impact — what other modules / scripts / docs
    depend on changed surface area? Are those callers updated?
11. Migration / rollout — if behavior changes silently, how would a
    user notice? Is there a feature flag or version gate?

Be exhaustive. PRAISE concrete diff locations worth highlighting.
```

## `security` (security lens)

```text
Security-focused review. Other dimensions are out of scope for THIS
invocation — the caller will run a separate review for correctness,
performance, etc.

Look for:
- Injection (shell, SQL, command, prompt) at any user-controlled input.
- Hardcoded secrets, tokens, credentials in code, tests, or examples.
- Authn/authz — missing checks, broken access control, privilege
  escalation paths.
- Supply chain — new dependencies, pinned versions, install-script
  integrity (signed-by, checksums).
- Data handling — PII logging, unredacted error messages, insecure
  defaults.
- Crypto — homerolled primitives, weak algorithms, missing nonce/IV.
- Race conditions on filesystem (TOCTOU), env var injection, signal
  handling.

Classify each finding as BLOCKER (exploitable) or FOLLOW-UP (defense
in depth). PRAISE specific security-positive patterns when present.
```

## `performance` (performance lens)

```text
Performance-focused review. Other dimensions are out of scope for
THIS invocation — the caller will run a separate review for
correctness, security, etc.

Look for:
- N+1 patterns (DB, API, filesystem).
- Unnecessary I/O inside hot loops (fork, exec, network, disk).
- Allocation hotspots — repeated string concatenation, large buffers
  in loops, missing pre-sizing.
- Missing caching on expensive idempotent calls.
- Synchronous calls that should be batched / pipelined.
- Algorithmic complexity worse than necessary (O(n²) where O(n log n)
  fits, etc.).

Quantify when possible: "executes ~N times per request" or "scales
linearly with X". Flag only concrete wins — avoid premature
optimization theatre. Classify each finding as BLOCKER (production
hot path) or FOLLOW-UP (visible only at scale).
```

## Why a closed enum

- Output comparability across 3 CLIs requires identical prompts.
- Free-text values widen the prompt-injection surface — PR body and
  diff already flow into the AI, but the depth/lens dimension is a
  *control* path and stays closed.
- The five enums cover the practical review depths users actually want;
  adding a sixth is cheap (one section here) — but should require
  evidence that the existing five are insufficient.
