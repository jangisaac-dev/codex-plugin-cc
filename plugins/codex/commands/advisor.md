---
description: Ask Codex to review the current Claude session's approach, like the built-in advisor
argument-hint: "[--background|--wait] [a specific question for the advisor]"
disable-model-invocation: true
allowed-tools: Bash(sh:*), Bash(node:*), Bash(codex:*)
---

Hand the current Claude Code session to Codex and return its advice.

Raw slash-command arguments:
`$ARGUMENTS`

How it works:
- `scripts/advisor.sh` transfers this session's transcript into a Codex thread (`codex-companion.mjs transfer`), then resumes that thread with the advisor prompt.
- Codex sees the whole session: the task, every tool call, every result.
- The run is read-only. Codex must not change files.

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
- After launching, tell the user: "Codex advisor started in the background."

Model selection:
- Defaults to `gpt-5.6-sol` at `medium` reasoning effort.
- Override per run with the `CODEX_ADVISOR_MODEL` and `CODEX_ADVISOR_EFFORT` environment variables.

Failure handling:
- If the transfer step reports that Codex is missing, unauthenticated, or too old for session transfer, stop and tell the user to run `/codex:setup` or update Codex.
