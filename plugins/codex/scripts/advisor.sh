#!/bin/sh
# /codex:advisor - transfer the current Claude session into a Codex thread and
# ask Codex to review the approach, the way Claude Code's built-in advisor does.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${CODEX_ADVISOR_MODEL:-gpt-5.6-sol}"
EFFORT="${CODEX_ADVISOR_EFFORT:-medium}"

THREAD="$(node "$ROOT/scripts/codex-companion.mjs" transfer --json \
  | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).threadId')"

PROMPT="$(cat <<'EOF'
You are the advisor for the Claude Code session you just received.
The full transcript above is the session: the task, every tool call, every result, and Claude's reasoning.

Review the work in progress and answer:
1. Is the current approach right? If it is heading somewhere wrong or wasteful, say so first and directly.
2. Which assumptions are unstated or unverified, and what evidence in the transcript contradicts them?
3. What has been missed: a file, a constraint, a failure mode, a simpler path already available.
4. What are the concrete next steps, in order, with the check that proves each one worked.

Rules:
- Read-only. Do not edit, create, or run anything that changes state.
- Be specific and cite file paths, commands, or transcript facts. No generic advice.
- If the approach is sound, say so plainly and keep the answer short.
- Answer in Korean.
EOF
)"

QUESTION="$*"
if [ -n "$QUESTION" ]; then
  PROMPT="$PROMPT

Caller's specific question, weigh it heavily: $QUESTION"
fi

exec codex exec resume "$THREAD" \
  -m "$MODEL" \
  -c model_reasoning_effort="$EFFORT" \
  -c sandbox_mode="read-only" \
  --skip-git-repo-check \
  "$PROMPT"
