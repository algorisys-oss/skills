#!/usr/bin/env bash
#
# scan.sh - attack-surface enumerator for threat modelling (Node/TS, Python, Go, Elixir).
#
# Unlike the other skills' scanners, this does NOT look for bugs - it SEEDS the
# data-flow diagram by listing the concrete elements of the attack surface:
# ENTRY POINTS (routes/handlers), EXTERNAL CALLS (third-party deps), DATA STORES
# (db/cache/queue/object/secret access), AUTH CHECKS (where the role boundary
# is - or is missing), FILE UPLOADS, and QUEUES. Prune the output to the flow
# you are modelling (read references/dfd.md), then apply STRIDE (stride.md).
# High-recall, low-precision; expect noise.
#
# Usage:
#   scan.sh [PATH]            Scan a directory or file (default: current dir)
#   scan.sh --diff            Only the surface introduced by changed files
#   scan.sh --staged          Only git-staged files
#
# Output: TSV-ish lines  ->  ELEMENT \t file:line \t matched text
# Exit code is always 0; empty output = nothing recognised.

set -uo pipefail

TARGET="."
MODE="path"

while [ $# -gt 0 ]; do
  case "$1" in
    --diff)   MODE="diff" ;;
    --staged) MODE="staged" ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
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

CODE_GLOBS=("*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs" "*.py" "*.go" "*.ex" "*.exs")

# ============================================================================
# ENTRY POINTS - routes/handlers (the internet trust boundary).
# ============================================================================
search '(router|app|api)\.(get|post|put|patch|delete)\(|@(Get|Post|Put|Patch|Delete)\(|@app\.(route|get|post)|@router\.(get|post|put|patch|delete)|func\s+\w+\(w\s+http\.ResponseWriter|def\s+\w+\(self,\s*request' "ENTRY-POINT" "${CODE_GLOBS[@]}"
search '(get|post|put|patch|delete|resources|live)\s+["'\''"/]' "ENTRY-POINT" "*.ex" "*.exs"

# ============================================================================
# EXTERNAL CALLS - third-party / outbound (service<->third-party boundary).
# ============================================================================
search '\b(axios|fetch\(|got\(|undici|requests\.|httpx|aiohttp|urllib|http\.(Get|Post|NewRequest)|HTTPoison|Finch\.|Tesla\.|Req\.(get|post|put|patch|delete|request))\b' "EXTERNAL-CALL" "${CODE_GLOBS[@]}"
search '\b(razorpay|stripe|payu|cashfree|paytm|cibil|experian|equifax|crif|npci|upi|sentry|twilio|sendgrid)\b' "EXTERNAL-CALL-VENDOR" "${CODE_GLOBS[@]}"

# ============================================================================
# DATA STORES - db / cache / queue / object / secret (app<->store boundary).
# ============================================================================
search '\b(query|execute|find|findOne|insert|update|delete|save|Repo\.(all|get|insert|update))\b' "DATA-STORE-DB?" "${CODE_GLOBS[@]}"
search '\b(redis|memcache|cache\.(get|set))\b' "DATA-STORE-CACHE" "${CODE_GLOBS[@]}"
search '\b(sqs|kafka|rabbit|sns|pubsub|bullmq|sidekiq|oban|broadway|publish|enqueue)\b' "DATA-STORE-QUEUE" "${CODE_GLOBS[@]}"
search '\b(s3|gcs|blob|putObject|getObject|upload_fileobj|minio)\b' "DATA-STORE-OBJECT" "${CODE_GLOBS[@]}"
search '\b(process\.env|os\.environ|os\.Getenv|System\.get_env|secret|vault)\b' "DATA-STORE-SECRET?" "${CODE_GLOBS[@]}"

# ============================================================================
# AUTH / AUTHZ CHECKS - where the role/tenant boundary is (or is absent).
# ============================================================================
search '\b(authenticate|authorize|authorise|requireAuth|isAuthenticated|current_user|currentUser|@PreAuthorize|@roles_required|ensure_authenticated|verify_token|jwt|can\?|policy|permit|tenant)\b' "AUTH-CHECK" "${CODE_GLOBS[@]}"

# ============================================================================
# FILE UPLOADS - high-value processes (KYC docs, video).
# ============================================================================
search '\b(multer|multipart|upload|FileField|UploadFile|formidable|busboy|Plug\.Upload|c\.FormFile)\b' "FILE-UPLOAD" "${CODE_GLOBS[@]}"

exit 0
