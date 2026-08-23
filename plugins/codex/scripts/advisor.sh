#!/bin/sh
# /codex:advisor - external review of the current Claude session.
#
#   --role advisor  (default)  review the session's approach; needs the transcript
#   --role review              judge an anonymized disagreement; must NOT see the transcript
#   --backend auto|codex|agy   auto tries codex then agy for advisor, agy then codex for review
#   --exclude codex|agy        never use this backend (pass the advisor's backend to the judge)
#
# A backend that is installed but fails (unauthenticated, offline, unsupported
# model) falls through to the next one. Exit 3 means every candidate was missing
# or failed, and the caller should fall back to the built-in advisor alone.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROLE="advisor"
BACKEND="auto"
EXCLUDE=""
MODEL="${CODEX_ADVISOR_MODEL:-gpt-5.6-sol}"
EFFORT="${CODEX_ADVISOR_EFFORT:-high}"

require_value() {
  [ -n "${2:-}" ] || { echo "Missing value for $1." >&2; exit 1; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --role) require_value "$1" "${2:-}"; ROLE="$2"; shift 2 ;;
    --backend) require_value "$1" "${2:-}"; BACKEND="$2"; shift 2 ;;
    --exclude) require_value "$1" "${2:-}"; EXCLUDE="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

case "$ROLE" in advisor|review) ;; *) echo "Unknown role: $ROLE (advisor, review)." >&2; exit 1 ;; esac
case "$BACKEND" in auto|codex|agy) ;; *) echo "Unknown backend: $BACKEND (auto, codex, agy)." >&2; exit 1 ;; esac
case "$EXCLUDE" in ""|codex|agy) ;; *) echo "Unknown backend to exclude: $EXCLUDE." >&2; exit 1 ;; esac

has() { command -v "$1" >/dev/null 2>&1; }

# The backends run for minutes, so an interrupt is the likely exit. Clean up from
# a trap as well as inline, or a snapshot is left behind in ~/.claude/projects.
cleanup() {
  [ -n "${snapshot:-}" ] && rm -f "$snapshot"
  [ -n "${workdir:-}" ] && rm -rf "$workdir"
  return 0
}
trap cleanup EXIT INT TERM

if [ "$BACKEND" = auto ]; then
  # advisor: codex first, it imports the real session instead of a digest of it.
  # review:  agy first, a judge must not be one of the two parties.
  if [ "$ROLE" = advisor ]; then CANDIDATES="codex agy"; else CANDIDATES="agy codex"; fi
else
  CANDIDATES="$BACKEND"
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

run_agy() {
  # agy has no enforced read-only mode, and none of these runs need repo context,
  # so run from an empty throwaway directory.
  workdir="$(mktemp -d)"
  if [ "$ROLE" = advisor ]; then
    digest="$(node "$ROOT/scripts/transcript-digest.mjs" "$SOURCE")"
    text="$PROMPT

The session transcript follows, condensed. Tool output is truncated.
---
$digest"
  else
    text="$PROMPT"
  fi
  ( cd "$workdir" && agy --effort high --sandbox -p "$text" )
  status=$?
  rm -rf "$workdir"
  return $status
}

run_codex() {
  if [ "$ROLE" = review ]; then
    echo "[advisor] note: codex is judging. If it also wrote one of the positions, treat this as a rebuttal, not a verdict." >&2
    # Fresh thread, empty directory, no user config or rules: the judge should see
    # the two positions and nothing else.
    workdir="$(mktemp -d)"
    ( cd "$workdir" && codex exec -m "$MODEL" -c model_reasoning_effort="$EFFORT" \
        -s read-only --skip-git-repo-check --ignore-user-config --ignore-rules "$PROMPT" )
    status=$?
    rm -rf "$workdir"
    return $status
  fi

  # Codex matches an imported session by content hash, and the live transcript keeps
  # growing while the import runs, so transferring the same file twice finds no
  # thread the second time. Import a frozen snapshot instead. It has to sit under
  # ~/.claude/projects because the companion refuses sources outside that tree.
  snapshot="$(dirname "$SOURCE")/codex-advisor-$$.jsonl"
  cp "$SOURCE" "$snapshot"
  status=0
  thread="$(node "$ROOT/scripts/codex-companion.mjs" transfer --json --source "$snapshot" \
    | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).threadId')" || status=$?
  if [ $status -eq 0 ] && [ -n "$thread" ]; then
    codex exec resume "$thread" -m "$MODEL" -c model_reasoning_effort="$EFFORT" \
      -c sandbox_mode="read-only" --skip-git-repo-check "$PROMPT" || status=$?
  else
    status=1
  fi
  rm -f "$snapshot"
  return $status
}

if [ "$ROLE" = advisor ]; then
  SOURCE="${CODEX_COMPANION_TRANSCRIPT_PATH:-}"
  if [ -z "$SOURCE" ] || [ ! -f "$SOURCE" ]; then
    echo "Could not locate the current Claude transcript (CODEX_COMPANION_TRANSCRIPT_PATH)." >&2
    exit 1
  fi
fi

for candidate in $CANDIDATES; do
  [ "$candidate" = "$EXCLUDE" ] && continue
  has "$candidate" || continue
  echo "[advisor] role=$ROLE backend=$candidate" >&2
  if [ "$candidate" = agy ]; then
    run_agy && exit 0
  else
    run_codex && exit 0
  fi
  echo "[advisor] $candidate failed for role=$ROLE, trying the next backend." >&2
done

echo "No external $ROLE backend succeeded (candidates: $CANDIDATES, excluded: ${EXCLUDE:-none}). Fall back to the built-in advisor." >&2
exit 3
