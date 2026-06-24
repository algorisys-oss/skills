#!/usr/bin/env bash
#
# scan.sh - heuristic audit-trail candidate finder for Node.js, TypeScript, Python, Go, Elixir.
#
# This is a HIGH-RECALL, LOW-PRECISION pre-filter. It flags (1) SENSITIVE
# OPERATIONS that should be audited, (2) MUTATION of audit stores (UPDATE/DELETE
# on audit/log tables), and (3) PII/secrets written into logs. It does NOT
# confirm an operation is unaudited - that requires cross-referencing each hit
# against the codebase's audit mechanism (read references/catalog.md +
# patterns.md and triage in context). Expect false positives; that is by design.
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
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
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

CODE_GLOBS=("*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs" "*.py" "*.go" "*.ex" "*.exs")

# ============================================================================
# Sensitive operations that MUST be audited (AU01-AU07). Each hit is a place to
# verify an audit record is written - the scanner cannot confirm that itself.
# ============================================================================
# AU01 money movement
search '\b(transfer|payout|refund|withdraw|deposit|charge|capture|settle|disburse|reverse|adjust)\w*\s*\(' "AU01-MONEY-OP" "${CODE_GLOBS[@]}"
# AU02 KYC/AML decisions
search '\b(approve|reject|verify|kyc|aml|sanction|pep|onboard|risk[_-]?score|override)\w*\s*\(' "AU02-KYC-DECISION" "${CODE_GLOBS[@]}"
# AU03 authorization / role / limit changes
search '\b(grant|revoke|assign[_-]?role|set[_-]?role|add[_-]?permission|change[_-]?limit|set[_-]?limit|impersonat|login[_-]?as)\w*' "AU03-AUTHZ-CHANGE" "${CODE_GLOBS[@]}"
# AU04 authentication events
search '\b(login|logout|sign[_-]?in|authenticate|reset[_-]?password|change[_-]?password|mfa|otp[_-]?verify|rotate[_-]?key|issue[_-]?token)\w*' "AU04-AUTH-EVENT" "${CODE_GLOBS[@]}"
# AU05 sensitive data access / export
search '\b(export|download|generate[_-]?report|bulk[_-]?|dump|extract)\w*\s*\(' "AU05-DATA-EXPORT" "${CODE_GLOBS[@]}"
# AU06/AU07 admin/config/freeze actions
search '\b(freeze|unfreeze|block|unblock|close[_-]?account|set[_-]?config|update[_-]?config|feature[_-]?flag|anonymi|hard[_-]?delete|purge)\w*' "AU06-ADMIN-CONFIG" "${CODE_GLOBS[@]}"

# ============================================================================
# Audit-store integrity (AU09): UPDATE/DELETE targeting audit/log tables.
# ============================================================================
search '(update|delete|drop|truncate)\s.*\b(audit|audit_log|audit_event|auditlog|activity_log|trail)' "AU09-MUTABLE-AUDIT-STORE" \
  "*.sql" "*.js" "*.ts" "*.py" "*.go" "*.ex" "*.exs"
search '\b(audit|auditlog|audit_log|audit_event|activity_log|trail)[a-z_]*\b.*\.(update|delete|destroy|remove|truncate)\(' "AU09-MUTABLE-AUDIT-STORE" "${CODE_GLOBS[@]}"

# ============================================================================
# PII / secrets in logs (AU11): logging calls carrying sensitive identifiers.
# ============================================================================
search '(console\.(log|info|warn|error)|logger\.\w+|log\.\w+|print\(|println|fmt\.Print|Logger\.\w+)\s*\([^)]*\b(password|passwd|pin|otp|cvv|card[_-]?number|pan\b|aadhaar|account[_-]?number|secret|token|ssn)\b' "AU11-PII-IN-LOG" "${CODE_GLOBS[@]}"

exit 0
