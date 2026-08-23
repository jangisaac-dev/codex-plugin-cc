#!/bin/sh
# /codex:advisor - external review of the current Claude session.
#
#   --role advisor  (default)  review the session's approach; needs the transcript
#   --role review              judge an anonymized disagreement; must NOT see the transcript
#   --backend auto|codex|agy   auto picks codex for advisor, agy for review, then falls back
#
# Exit 3 means no backend is available and the caller should fall back to the
# built-in advisor alone.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROLE="advisor"
BACKEND="auto"
MODEL="${CODEX_ADVISOR_MODEL:-gpt-5.6-sol}"
EFFORT="${CODEX_ADVISOR_EFFORT:-high}"

while [ $# -gt 0 ]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --backend) BACKEND="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

case "$ROLE" in
  advisor|review) ;;
  *) echo "Unknown role: $ROLE (use advisor or review)." >&2; exit 1 ;;
esac

has() { command -v "$1" >/dev/null 2>&1; }

if [ "$BACKEND" = auto ]; then
  if [ "$ROLE" = advisor ]; then
    # Codex first: it imports the real session instead of a digest of it.
    if has codex; then BACKEND=codex; elif has agy; then BACKEND=agy; else BACKEND=none; fi
  else
    # agy first: for a tie-break the judge must not be one of the two parties.
    if has agy; then BACKEND=agy; elif has codex; then BACKEND=codex; else BACKEND=none; fi
  fi
fi

if [ "$BACKEND" = none ] || ! has "$BACKEND"; then
  echo "No external $ROLE backend available (codex, agy). Fall back to the built-in advisor." >&2
  exit 3
fi

QUESTION="$*"
if [ "$ROLE" = review ] && [ -z "$QUESTION" ]; then
  QUESTION="$(cat)"
fi

PROMPT="$(cat "$ROOT/prompts/$ROLE.md")"
if [ -n "$QUESTION" ]; then
  if [ "$ROLE" = review ]; then
    PROMPT="$PROMPT

The two positions:
$QUESTION"
  else
    PROMPT="$PROMPT
Specific question from the caller, weigh it heavily: $QUESTION"
  fi
fi

echo "[advisor] role=$ROLE backend=$BACKEND" >&2

if [ "$ROLE" = review ]; then
  if [ "$BACKEND" = agy ]; then
    # No repo context needed, so run from an empty throwaway directory: agy has no
    # read-only mode and this keeps it away from any working tree.
    WORKDIR="$(mktemp -d)"
    trap 'rm -rf "$WORKDIR"' EXIT INT TERM
    cd "$WORKDIR"
    agy --effort high --sandbox -p "$PROMPT"
  else
    echo "[advisor] warning: judging with codex, which authored one of the positions. Treat it as a rebuttal, not a verdict." >&2
    # Fresh thread on purpose - no transfer, so it cannot recognize its own answer.
    codex exec -m "$MODEL" -c model_reasoning_effort="$EFFORT" -s read-only \
      --skip-git-repo-check "$PROMPT"
  fi
  exit $?
fi

SOURCE="${CODEX_COMPANION_TRANSCRIPT_PATH:-}"
if [ -z "$SOURCE" ] || [ ! -f "$SOURCE" ]; then
  echo "Could not locate the current Claude transcript (CODEX_COMPANION_TRANSCRIPT_PATH)." >&2
  exit 1
fi

if [ "$BACKEND" = agy ]; then
  DIGEST="$(node "$ROOT/scripts/transcript-digest.mjs" "$SOURCE")"
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT INT TERM
  cd "$WORKDIR"
  agy --effort high --sandbox -p "$PROMPT

The session transcript follows, condensed. Tool output is truncated.
---
$DIGEST"
  exit $?
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

codex exec resume "$THREAD" \
  -m "$MODEL" \
  -c model_reasoning_effort="$EFFORT" \
  -c sandbox_mode="read-only" \
  --skip-git-repo-check \
  "$PROMPT"
