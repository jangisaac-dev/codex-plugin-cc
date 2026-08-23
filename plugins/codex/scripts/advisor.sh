#!/bin/sh
# /codex:advisor - transfer the current Claude session into a Codex thread and
# ask Codex to review the approach, the way the built-in advisor does.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${CODEX_ADVISOR_MODEL:-gpt-5.6-sol}"
EFFORT="${CODEX_ADVISOR_EFFORT:-high}"

SOURCE="${CODEX_COMPANION_TRANSCRIPT_PATH:-}"
if [ -z "$SOURCE" ] || [ ! -f "$SOURCE" ]; then
  echo "Could not locate the current Claude transcript (CODEX_COMPANION_TRANSCRIPT_PATH)." >&2
  exit 1
fi

# Codex matches an imported session by content hash, and the live transcript keeps
# growing while the import runs, so transferring the same file twice finds no
# thread the second time. Import a frozen snapshot instead. It has to sit under
# ~/.claude/projects because the companion refuses sources outside that tree.
SNAPSHOT="$(dirname "$SOURCE")/codex-advisor-$$.jsonl"
cp "$SOURCE" "$SNAPSHOT"
trap 'rm -f "$SNAPSHOT"' EXIT INT TERM

THREAD="$(node "$ROOT/scripts/codex-companion.mjs" transfer --json --source "$SNAPSHOT" \
  | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).threadId')"

PROMPT="$(cat "$ROOT/prompts/advisor.md")"
QUESTION="$*"
if [ -n "$QUESTION" ]; then
  PROMPT="$PROMPT
Specific question from the caller, weigh it heavily: $QUESTION"
fi

codex exec resume "$THREAD" \
  -m "$MODEL" \
  -c model_reasoning_effort="$EFFORT" \
  -c sandbox_mode="read-only" \
  --skip-git-repo-check \
  "$PROMPT"
