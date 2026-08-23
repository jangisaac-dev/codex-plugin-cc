---
description: Ask an external model to review the current Claude session's approach, like the built-in advisor
argument-hint: "[--background|--wait] [--backend auto|codex|agy] [a specific question for the advisor]"
disable-model-invocation: true
allowed-tools: Bash(sh:*), Bash(node:*), Bash(codex:*), Bash(agy:*)
---

Hand the current Claude Code session to an external model and return its advice.

Raw slash-command arguments:
`$ARGUMENTS`

How it works:
- `scripts/advisor.sh` runs with `--role advisor`.
- With Codex it transfers this session's transcript into a Codex thread (`codex-companion.mjs transfer`) and resumes that thread with the advisor prompt, so Codex reads the real session.
- With agy it sends a condensed transcript (`scripts/transcript-digest.mjs`) instead, since agy cannot import a Claude session. Tool output is truncated, so agy sees less detail than Codex does.
- Either way the run is read-only and the model must not change files.

Backend selection:
- `auto` (default) picks Codex, falls back to agy, and exits 3 if neither is installed.
- Exit 3 means there is no external advisor. Say so and use the built-in `advisor` tool alone.
- Force one with `--backend codex` or `--backend agy`.

Core constraint:
- This command is advice-only. Do not fix anything, apply patches, or announce that you are about to make changes.
- Return the command stdout verbatim. Do not paraphrase, summarize, or add commentary before or after it.
- Act on the advice only if the user asks for it in a later turn.

Execution mode rules:
- If the arguments include `--wait`, run in the foreground.
- If the arguments include `--background`, run in a Claude background task.
- Otherwise default to foreground. A transfer plus one advisor turn usually takes a few minutes.
- `--wait` and `--background` are Claude Code execution flags. Strip them before forwarding the rest as the advisor question.

Foreground flow:
```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/advisor.sh" "<question text without the execution flags>"
```

Background flow:
```typescript
Bash({
  command: `sh "${CLAUDE_PLUGIN_ROOT}/scripts/advisor.sh" "<question text without the execution flags>"`,
  description: "Codex advisor",
  run_in_background: true
})
```
- After launching, tell the user: "advisor started in the background."

Model selection:
- Codex defaults to `gpt-5.6-sol` at `high` reasoning effort. Override with `CODEX_ADVISOR_MODEL` and `CODEX_ADVISOR_EFFORT`.
- agy runs at `high` effort on its own default model.

Failure handling:
- Exit 3: no backend installed. Fall back to the built-in advisor.
- If Codex reports that it is unauthenticated or too old for session transfer, tell the user to run `/codex:setup` or update Codex, and retry with `--backend agy`.

Sending the session outside:
- Codex receives the full transcript, agy receives the condensed one. Invoking this command is consent for that turn.
