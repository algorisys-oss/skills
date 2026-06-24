#!/usr/bin/env bash
#
# scan.sh - heuristic money-safety candidate finder for Node.js, TypeScript, Python, Go, Elixir.
#
# This is a HIGH-RECALL, LOW-PRECISION pre-filter. It greps for financial-
# correctness smells (float-for-money, ad-hoc rounding, payment/refund handlers,
# read-modify-write balance updates) and prints candidate `file:line` locations
# grouped by category. It does NOT decide whether a hit is a real bug - that is
# the reviewer's job (read references/<language>.md + patterns.md and triage each
# hit in context). It also CANNOT see the highest-value issues - missing
# idempotency, missing transaction boundaries, ledger imbalance - which require
# reasoning about money flows. Expect false positives (percentages, non-money
# floats); that is by design.
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
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *)        TARGET="$1" ;;
  esac
  shift
done

# Prefer ripgrep; fall back to grep -rEn.
if command -v rg >/dev/null 2>&1; then
  ENGINE="rg"
else
  ENGINE="grep"
  echo "# note: ripgrep (rg) not found, falling back to grep (slower, fewer features)" >&2
fi

# Build the file list once.
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

# matches_glob FILE GLOB...  -> 0 if FILE's name matches any GLOB
matches_glob() {
  local f="$1"; shift
  local g
  for g in "$@"; do
    # shellcheck disable=SC2254
    case "$f" in $g) return 0 ;; esac
  done
  return 1
}

# search PATTERN CATEGORY [glob...]
# Explicitly-named files are searched even when they do not match --glob, so for
# single-file and --diff/--staged modes the glob is applied in the shell instead
# of trusting the engine's --glob filter (prevents cross-labelling a .go file
# with Node/Python patterns).
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
TS_GLOBS=("*.ts" "*.tsx" "*.mts" "*.cts")
PY_GLOBS=("*.py")
GO_GLOBS=("*.go")
EX_GLOBS=("*.ex" "*.exs")

# A money identifier fragment reused across patterns.
MONEY='(amount|amt|balance|price|total|fee|interest|tax|cost|charge|payable|debit|credit|refund|payout|wallet)'

# ============================================================================
# Node.js / TypeScript
# ============================================================================
if want node || want typescript; then
  search "\b(parseFloat|Number)\(\s*[^)]*${MONEY}" "M01-FLOAT-FOR-MONEY" "${JS_GLOBS[@]}"
  search "${MONEY}\s*:\s*number\b|${MONEY}\w*\s*[-+*/]\s*" "M01-FLOAT-FOR-MONEY" "${JS_GLOBS[@]}"
  search '(Float|Double|Real)\b.*@db|type:\s*["'\'']?(float|double|real)' "M01-FLOAT-COLUMN" "${JS_GLOBS[@]}"
  search "(\.toFixed\(|Math\.round\()[^)]*${MONEY}|${MONEY}[^;]*\*\s*100|${MONEY}[^;]*/\s*100" "M02-ROUNDING" "${JS_GLOBS[@]}"
  search 'router\.(post|put)\(\s*["'\''][^"'\'']*(payment|transfer|refund|charge|payout|withdraw|topup|debit|credit)' "M04-IDEMPOTENCY?" "${JS_GLOBS[@]}"
  search '(webhook|/hooks/|razorpay|stripe|payu|cashfree|paytm)' "M04-WEBHOOK-DEDUP?" "${JS_GLOBS[@]}"
  search "${MONEY}\s*=\s*${MONEY}\s*[-+]|\.balance\s*[-+]?=|set\s*\(\s*\{\s*balance" "M05-BALANCE-RMW?" "${JS_GLOBS[@]}"
fi

# TypeScript-specific: money typed/cast as number.
if want typescript; then
  search "(req|request|ctx|body)\.[^ ]*${MONEY}[^ ]*\s+as\s+(number|Money)" "M01-TS-CAST-MONEY" "${TS_GLOBS[@]}"
  search "type\s+Money\s*=\s*number|${MONEY}\s*:\s*number" "M01-TS-MONEY-IS-NUMBER" "${TS_GLOBS[@]}"
fi

# ============================================================================
# Python
# ============================================================================
if want python; then
  search "\bfloat\(\s*[^)]*${MONEY}|${MONEY}\s*=\s*float\(" "M01-FLOAT-FOR-MONEY" "${PY_GLOBS[@]}"
  search 'FloatField\(' "M01-FLOAT-COLUMN" "${PY_GLOBS[@]}"
  search 'Decimal\(\s*[0-9]+\.[0-9]' "M01-DECIMAL-FROM-FLOAT" "${PY_GLOBS[@]}"
  search "\bround\(\s*[^)]*${MONEY}|\.quantize\(" "M02-ROUNDING" "${PY_GLOBS[@]}"
  search "\.balance\s*[-+]?=|${MONEY}\s*[-+]?=\s*${MONEY}" "M05-BALANCE-RMW?" "${PY_GLOBS[@]}"
  search '\.save\(\)' "M05-SAVE-CHECK-TXN?" "${PY_GLOBS[@]}"
  search '(def\s+\w*(payment|transfer|refund|charge|payout|withdraw|debit|credit)|webhook)' "M04-IDEMPOTENCY?" "${PY_GLOBS[@]}"
fi

# ============================================================================
# Go
# ============================================================================
if want go; then
  search "${MONEY}\s+float(32|64)|float(32|64)\s*\`.*${MONEY}" "M01-FLOAT-FOR-MONEY" "${GO_GLOBS[@]}"
  search "strconv\.ParseFloat\([^)]*${MONEY}" "M01-FLOAT-FOR-MONEY" "${GO_GLOBS[@]}"
  search "math\.Round\(|${MONEY}[^;]*\*\s*100|${MONEY}[^;]*/\s*100" "M02-ROUNDING" "${GO_GLOBS[@]}"
  search "\.Balance\s*[-+]?=|${MONEY}\s*[-+]?=\s*${MONEY}" "M05-BALANCE-RMW?" "${GO_GLOBS[@]}"
  search '(func\s+\w*(Payment|Transfer|Refund|Charge|Payout|Withdraw|Debit|Credit)|Webhook|webhook)' "M04-IDEMPOTENCY?" "${GO_GLOBS[@]}"
  search "${MONEY}\s+int32\b" "M07-OVERFLOW-INT32?" "${GO_GLOBS[@]}"
fi

# ============================================================================
# Elixir
# ============================================================================
if want elixir; then
  search "field\s+:[a-z_]*${MONEY}[a-z_]*,\s*:float|field\s+:${MONEY},\s*:float" "M01-FLOAT-FOR-MONEY" "${EX_GLOBS[@]}"
  search 'String\.to_float\(' "M01-FLOAT-FOR-MONEY" "${EX_GLOBS[@]}"
  search "Float\.round\(|${MONEY}[^;]*\*\s*100|${MONEY}[^;]*/\s*100" "M02-ROUNDING" "${EX_GLOBS[@]}"
  search "\.balance\s|Repo\.update\(" "M05-BALANCE-RMW?" "${EX_GLOBS[@]}"
  search '(def\s+\w*(payment|transfer|refund|charge|payout|withdraw|debit|credit)|webhook)' "M04-IDEMPOTENCY?" "${EX_GLOBS[@]}"
fi

# ============================================================================
# Cross-language: money columns in schema/migration files.
# ============================================================================
search "(add|column|t\.)\s.*${MONEY}.*\b(float|double|real)\b" "M01-FLOAT-COLUMN" \
  "*.sql" "*.rb" "*.ex" "*.exs" "*.js" "*.ts" "*.py" "*.go"

exit 0
