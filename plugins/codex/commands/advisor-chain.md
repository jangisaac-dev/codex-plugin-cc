---
description: Run the external advisor first, apply what holds, then call Claude's built-in advisor
argument-hint: "[what the advisors should focus on]"
disable-model-invocation: false
allowed-tools: Bash(sh:*), Bash(node:*), Bash(codex:*), Bash(agy:*), Read, Glob, Grep, Edit, Write, advisor
---

Chain the reviewers in order. Do not skip a step and do not reorder them.

Raw slash-command arguments:
`$ARGUMENTS`

Roles are fixed. One model advises, a different one judges:
- **advisor** - reviews the session's approach. Codex first, agy if Codex is missing.
- **review** - judges a disagreement between the advisor and the built-in advisor. agy first, Codex only if agy is missing. The judge must not be a party to the disagreement.

Step 1 - external advisor:
```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/advisor.sh" "$ARGUMENTS"
```
- Show the output to the user verbatim before doing anything else.
- The script prints `[advisor] role=advisor backend=<name>` on stderr. Remember that name - step 4 needs it.
- Exit 3 means every backend was missing or failed. Say so, skip to step 3, and note in the final report that only one reviewer ran.

Step 2 - apply what holds:
- Work through the advisor's points one by one.
- Apply the ones supported by evidence in this session. Run the check that proves each applied change worked.
- For a point you reject, say so in one line with the reason. Do not silently drop it.
- If a point is out of scope for the current task, note it and leave it.

Step 3 - built-in advisor:
- Only after step 2 is finished, call the `advisor` tool.
- It sees the transcript, so it already sees the external advice and what was applied. Do not re-paste them.

Step 4 - conflict branch (usually skipped):
- The two reviewers do not evaluate the same state: step 2 changed things between them. So a different conclusion is normally a timing difference, not a conflict.
- Branch only when the built-in advisor asks to revert something applied in step 2, or recommends the opposite action from the same evidence.
- When it does branch:
  1. Write both positions yourself as `주장 / 근거 / 검증 결과 / 위험`. Do not ask a model to summarize them - that only adds a distortion step.
  2. Strip every attribution. No model names, no "the first reviewer said".
  3. Send the anonymized pair to the judge, barring whichever backend gave the advice in step 1, so the judge is never a party to the disagreement:
     ```bash
     printf '%s' "<anonymized positions>" | sh "${CLAUDE_PLUGIN_ROOT}/scripts/advisor.sh" --role review --exclude <step 1 backend>
     ```
  4. Exit 3 here usually means only one backend exists on this machine, so no independent judge is available. Do not drop the exclusion to get a verdict. Report the difference to the user and let them choose.
  5. Same when the judge says the evidence cannot decide: hand the difference to the user.

Step 5 - report:
- Lead with what changed as a result of the reviews.
- Name which backends actually ran. If any step fell back or was skipped, say so.
- If a conflict went to the judge, give the verdict and the reasoning, not just the winner.
