---
description: Run the Codex advisor first, apply what holds, then call Claude's built-in advisor
argument-hint: "[what the advisors should focus on]"
disable-model-invocation: false
allowed-tools: Bash(sh:*), Bash(node:*), Bash(codex:*), Read, Glob, Grep, Edit, Write, advisor
---

Chain both advisors in order. Do not skip a step and do not reorder them.

Raw slash-command arguments:
`$ARGUMENTS`

Step 1 - Codex advisor:
```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/advisor.sh" "$ARGUMENTS"
```
- The script defaults to `gpt-5.6-sol` at `high` reasoning effort. Do not lower it here.
- Show the output to the user verbatim before doing anything else.

Step 2 - Apply what holds:
- Work through Codex's points one by one.
- Apply the ones supported by evidence in this session. Run the check that proves each applied change worked.
- For a point you reject, say so in one line with the reason. Do not silently drop it.
- If a point is out of scope for the current task, note it and leave it.

Step 3 - Built-in advisor:
- Only after step 2 is finished, call the `advisor` tool.
- Claude's advisor sees the transcript, so it sees Codex's advice and what was applied. Do not re-paste them.

Step 4 - Report:
- Lead with what changed as a result of the two reviews.
- If the two advisors disagree on something material, state the disagreement and which one the evidence supports. Do not average them.
