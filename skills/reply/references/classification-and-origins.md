# gh-pr:reply Step 3 — Classification rubric and origin tokens

Read from `SKILL.md` Step 3, before evaluating the first comment. The
classification vocabulary and the `ORIGINS` token shape below are wire
format: Steps 6 and 7 parse them, so reproduce them exactly.

`references/...` and `../...` paths below are relative to `skills/reply/`, the same way SKILL.md writes them.

For each unaddressed comment, read the referenced file (`path` at `line`)
and classify as **ACCEPT** / **ACCEPT-PARTIAL** / **DECLINE** / **QUESTION**.
Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules; see `references/reply-templates.md` for the full rubric.

Record each item's origin as `<reviewer>:<severity>:<verdict>[:<owner>/<repo>#<N>]`
into `ORIGINS` via `_gh_pr_reply_origin_line` (`references/review-passed-gate.md`
§ Step 3) — Steps 6 and 7 both read that stream, because a flat
accepted/declined count cannot tell an unresolved BLOCKER from a declined
suggestion (dEitY719/dotfiles#1616). The optional 4th field names the issue a
declined BLOCKER was escalated to (dEitY719/dotfiles#1762); it changes the
report line, never the gate's decision — escalation is not resolution.
