#!/usr/bin/env bash
#
# scan.sh - heuristic resilience candidate finder for Node.js, TypeScript, Python, Go, Elixir.
#
# This is a HIGH-RECALL, LOW-PRECISION pre-filter. It flags external calls (HTTP
# clients, DB pools) and retry loops so the reviewer can check each for timeouts,
# backoff, breakers, and idempotent retries. It CANNOT see whether a timeout is
# set on a shared client, whether a breaker wraps a call, or whether a retried
# operation is idempotent - read references/<language>.md + catalog.md and triage
# each hit in context. Expect false positives; that is by design.
#
# Usage:
#   scan.sh [PATH]            Scan a directory or file (default: current dir)
#   scan.sh --diff            Scan only files changed vs git HEAD / branch
#   scan.sh --staged          Scan only git-staged files
#   scan.sh PATH --lang node  Restrict to one language (node|typescript|python|go|elixir)
#
# Output: TSV-ish lines  ->  CATEGORY \t file:line \t matched text
# Exit code is always 0 (candidates are not failures); empty output = no hits.

set -uo pipefail

TARGET="."
MODE="path"
ONLY_LANG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --diff)   MODE="diff" ;;
    --staged) MODE="staged" ;;
    --lang)   shift; ONLY_LANG="${1:-}" ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *)        TARGET="$1" ;;
  esac
  shift
done

if command -v rg >/dev/null 2>&1; then
  ENGINE="rg"
else
  ENGINE="grep"
  echo "# note: ripgrep (rg) not found, falling back to grep (slower, fewer features)" >&2
fi

FILES_TMP="$(mktemp)"
trap 'rm -f "$FILES_TMP"' EXIT

case "$MODE" in
  diff)
    git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null > "$FILES_TMP" || true
    base="$(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
    [ -n "$base" ] && git diff --name-only --diff-filter=ACMR "$base"...HEAD 2>/dev/null >> "$FILES_TMP"
    sort -u "$FILES_TMP" -o "$FILES_TMP"
    ;;
  staged)
    git diff --name-only --cached --diff-filter=ACMR 2>/dev/null > "$FILES_TMP" || true
    ;;
  path)
    echo "$TARGET" > "$FILES_TMP"
    ;;
esac

matches_glob() {
  local f="$1"; shift
  local g
  for g in "$@"; do
    # shellcheck disable=SC2254
    case "$f" in $g) return 0 ;; esac
  done
  return 1
}

search() {
  local pattern="$1"; local category="$2"; shift 2
  local globs=("$@")

  if [ "$MODE" = "path" ] && [ -d "$TARGET" ]; then
    if [ "$ENGINE" = "rg" ]; then
      local args=(--no-heading --line-number --color never -i -e "$pattern")
      for g in "${globs[@]}"; do args+=(--glob "$g"); done
      rg "${args[@]}" "$TARGET" 2>/dev/null
    else
      local include=()
      for g in "${globs[@]}"; do include+=(--include="${g#*/}"); done
      grep -rEni "${include[@]}" -e "$pattern" "$TARGET" 2>/dev/null
    fi
  else
    local files=() matched=() f
    if [ "$MODE" = "path" ]; then files=("$TARGET"); else mapfile -t files < "$FILES_TMP"; fi
    for f in "${files[@]}"; do
      [ -f "$f" ] && matches_glob "$f" "${globs[@]}" && matched+=("$f")
    done
    [ ${#matched[@]} -eq 0 ] && return 0
    if [ "$ENGINE" = "rg" ]; then
      rg --no-heading --line-number --color never -i -e "$pattern" "${matched[@]}" 2>/dev/null
    else
      grep -EnHi -e "$pattern" "${matched[@]}" 2>/dev/null
    fi
  fi | sed "s/^/${category}\t/" | awk '!seen[$0]++'
}

want() { [ -z "$ONLY_LANG" ] || [ "$ONLY_LANG" = "$1" ]; }

JS_GLOBS=("*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs")
PY_GLOBS=("*.py")
GO_GLOBS=("*.go")
EX_GLOBS=("*.ex" "*.exs")

# ============================================================================
# Cross-language: hand-rolled retry loops (check for cap + backoff + idempotency).
# ============================================================================
search '(retry|retries|attempt|maxRetries|max_retries|backoff)' "R02-RETRY-CHECK-BACKOFF" \
  "*.js" "*.jsx" "*.ts" "*.tsx" "*.py" "*.go" "*.ex" "*.exs"

# ============================================================================
# Node.js / TypeScript
# ============================================================================
if want node || want typescript; then
  # external HTTP calls - verify a timeout/AbortSignal is set
  search '\b(axios|fetch|got|undici|request|superagent)\b\s*(\.\w+)?\s*\(' "R01-HTTP-CALL-TIMEOUT?" "${JS_GLOBS[@]}"
  search 'http\.(get|request)\(|https\.(get|request)\(' "R01-HTTP-CALL-TIMEOUT?" "${JS_GLOBS[@]}"
  # DB / connection pools - verify max + acquisition timeout
  search 'new Pool\(|createPool\(|new Sequelize\(|PrismaClient\(' "R07-POOL-LIMITS?" "${JS_GLOBS[@]}"
  # unbounded fan-out
  search 'Promise\.all\(' "R06-FANOUT-CONCURRENCY?" "${JS_GLOBS[@]}"
  # webhook handlers
  search '(webhook|/hooks/)' "R10-WEBHOOK?" "${JS_GLOBS[@]}"
fi

# ============================================================================
# Python
# ============================================================================
if want python; then
  search '\b(requests|httpx|aiohttp|urllib|urlopen)\b[^=]*\.(get|post|put|patch|delete|request|head)\(' "R01-HTTP-CALL-TIMEOUT?" "${PY_GLOBS[@]}"
  search 'create_engine\(|ConnectionPool\(|psycopg2\.connect\(|httpx\.(Client|AsyncClient)\(' "R07-POOL-LIMITS?" "${PY_GLOBS[@]}"
  search 'asyncio\.gather\(' "R06-FANOUT-CONCURRENCY?" "${PY_GLOBS[@]}"
  search '(webhook|/hooks/)' "R10-WEBHOOK?" "${PY_GLOBS[@]}"
  # context.Background-style: blocking call with no timeout kwarg is common; flag bare requests.get
  search 'requests\.(get|post|put|patch|delete)\([^)]*\)' "R01-REQUESTS-NO-TIMEOUT?" "${PY_GLOBS[@]}"
fi

# ============================================================================
# Go
# ============================================================================
if want go; then
  search 'http\.(Get|Post|Head|PostForm)\(|http\.DefaultClient|&http\.Client\{' "R01-HTTP-CALL-TIMEOUT?" "${GO_GLOBS[@]}"
  search 'context\.(Background|TODO)\(\)' "R01-NO-DEADLINE?" "${GO_GLOBS[@]}"
  search '\.(Query|Exec|QueryRow)\(' "R01-DB-NO-CONTEXT?" "${GO_GLOBS[@]}"
  search 'SetMaxOpenConns|sql\.Open\(|pgxpool\.New\(' "R07-POOL-LIMITS?" "${GO_GLOBS[@]}"
  search '\bgo\s+func\b' "R06-GOROUTINE-FANOUT?" "${GO_GLOBS[@]}"
  search '(Webhook|webhook|/hooks/)' "R10-WEBHOOK?" "${GO_GLOBS[@]}"
fi

# ============================================================================
# Elixir
# ============================================================================
if want elixir; then
  search 'HTTPoison\.(get|post|put|patch|delete|request)\(|Tesla\.(get|post)\(|Finch\.request\(|Req\.(get|post)\(' "R01-HTTP-CALL-TIMEOUT?" "${EX_GLOBS[@]}"
  search 'GenServer\.call\([^,]*,[^,]*,\s*:infinity|GenServer\.call\([^,)]*,[^,)]*\)' "R01-GENSERVER-CALL-TIMEOUT?" "${EX_GLOBS[@]}"
  search 'Task\.async_stream\(' "R06-FANOUT-CONCURRENCY?" "${EX_GLOBS[@]}"
  search 'pool_size|queue_target|Finch\.start_link' "R07-POOL-LIMITS?" "${EX_GLOBS[@]}"
  search '(webhook|/hooks/)' "R10-WEBHOOK?" "${EX_GLOBS[@]}"
fi

exit 0
