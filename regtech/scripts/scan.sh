#!/usr/bin/env bash
#
# scan.sh - heuristic regtech (compliance) candidate finder.
#
# This is a HIGH-RECALL, LOW-PRECISION pre-filter. It seeds the compliance review
# by flagging: (1) PII/cardholder-data fields (the data inventory), (2) PROHIBITED
# stored data (CVV/PIN), (3) cross-border / external hosts (data residency),
# (4) missing-consent and (5) missing-retention signals, and (6) plaintext-
# sensitive-storage smells. It does NOT determine residency, consent, or
# retention CORRECTNESS - that is the mapping work in the SKILL.md workflow
# (read references/checklist.md + frameworks/*.md and triage in context).
# Security and audit depth are owned by the `owasp` and `audit-trail` skills.
# Expect false positives (a field named `pan` that is not a card); by design.
#
# Usage:
#   scan.sh [PATH]            Scan a directory or file (default: current dir)
#   scan.sh --diff            Scan only files changed vs git HEAD / branch
#   scan.sh --staged          Scan only git-staged files
#
# Output: TSV-ish lines  ->  CATEGORY \t file:line \t matched text
# Exit code is always 0 (candidates are not failures); empty output = no hits.

set -uo pipefail

TARGET="."
MODE="path"

while [ $# -gt 0 ]; do
  case "$1" in
    --diff)   MODE="diff" ;;
    --staged) MODE="staged" ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
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

CODE_GLOBS=("*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs" "*.py" "*.go" "*.ex" "*.exs" "*.rb" "*.java")
SCHEMA_GLOBS=("*.sql" "*.prisma" "*.rb" "*.py" "*.ex" "*.exs" "*.ts" "*.go")
CONFIG_GLOBS=("*.env*" "*.yml" "*.yaml" "*.json" "*.tf" "*.toml" "*.ts" "*.js" "*.py" "*.go" "*.ex" "*.exs")

# ============================================================================
# C1 - PII / cardholder-data inventory: fields that name regulated data.
# ============================================================================
search '\b(pan|card[_-]?number|cardnumber|aadhaar|aadhar|account[_-]?number|ifsc|passport|date[_-]?of[_-]?birth|dob|ssn|biometric|nationalid|national[_-]?id)\b' "C1-PII-INVENTORY" "${CODE_GLOBS[@]}" "${SCHEMA_GLOBS[@]}"

# ============================================================================
# C2 - prohibited stored data (CVV / track / PIN). High severity if persisted.
# ============================================================================
search '\b(cvv|cvc|cvv2|cvc2|card[_-]?verification|track[_-]?data|track2|\bpin\b)\b' "C2-PROHIBITED-CVV-PIN" "${CODE_GLOBS[@]}" "${SCHEMA_GLOBS[@]}"

# ============================================================================
# C6 - data residency / cross-border: external hosts, cloud regions.
# ============================================================================
search '(us-east-1|us-west-[12]|eu-west-[123]|eu-central-1|ap-southeast-[12]|ap-northeast-[123]|us-central1|europe-west[0-9]|region\s*[:=]\s*["'\''](us|eu|ap-(?!south-1))[a-z0-9-]+)' "C6-DATA-RESIDENCY-REGION" "${CONFIG_GLOBS[@]}"
search '(https?://[a-z0-9.-]+\.(com|io|net|co)/)|DATABASE_URL|MONGO_URI|REDIS_URL|S3_BUCKET|GCS_BUCKET' "C6-EXTERNAL-HOST?" "${CONFIG_GLOBS[@]}"

# ============================================================================
# C7 - consent: presence (verify it gates collection) or absence (in signup/KYC).
# ============================================================================
search '\bconsent\b' "C7-CONSENT-PRESENT?" "${CODE_GLOBS[@]}"
search '\b(signup|sign[_-]?up|register|onboard|create[_-]?user|collect)\w*' "C7-COLLECTION-CHECK-CONSENT?" "${CODE_GLOBS[@]}"

# ============================================================================
# C9 - retention & erasure: presence of retention/TTL, and delete/anonymise.
# ============================================================================
search '\b(retention|ttl|expire[_-]?at|expires_at|purge|anonymi[sz]e|right[_-]?to[_-]?be[_-]?forgotten|rtbf|data[_-]?deletion)\b' "C9-RETENTION-PRESENT?" "${CODE_GLOBS[@]}" "${SCHEMA_GLOBS[@]}"

# ============================================================================
# C12 - PII potentially in logs (deep check: audit-trail AU11).
# ============================================================================
search '(console\.(log|info|error)|logger\.\w+|log\.\w+|print\(|fmt\.Print|Logger\.\w+)\s*\([^)]*\b(pan|card[_-]?number|cvv|aadhaar|account[_-]?number|passport|dob|ssn)\b' "C12-PII-IN-LOG" "${CODE_GLOBS[@]}"

exit 0
