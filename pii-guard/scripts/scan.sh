#!/usr/bin/env bash
#
# scan.sh - heuristic PII-exposure candidate finder for Node.js, TypeScript, Python, Go, Elixir.
#
# This is a HIGH-RECALL, LOW-PRECISION pre-filter. It flags (1) PII/PCI field
# names (the inventory), (2) hardcoded PII-shaped VALUES (card/Aadhaar/PAN/IFSC),
# and (3) PII reaching LOG / RESPONSE / URL / ANALYTICS sinks. It does NOT know
# whether a field is already masked/tokenised - read references/catalog.md,
# detection.md, patterns.md and triage each hit in context. Expect false
# positives (a `pan` that is a UI panel, an already-masked value); by design.
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
JS_GLOBS=("*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs")
PY_GLOBS=("*.py")
GO_GLOBS=("*.go")
EX_GLOBS=("*.ex" "*.exs")

# PII field-name fragments (see detection.md). Tiered for severity in the report.
PII_T01='(cvv|cvc|cvv2|cvc2|card[_-]?verification|track[_-]?data|track2|\bpin\b|card[_-]?number|cardnumber|account[_-]?number|acct[_-]?no|aadhaar|aadhar|passport|voter[_-]?id|biometric|fingerprint)'
PII_T2='(\bdob\b|date[_-]?of[_-]?birth|\bemail\b|\bphone\b|\bmobile\b|msisdn|\bifsc\b|\bvpa\b|gstin|first[_-]?name|last[_-]?name)'

# ============================================================================
# Inventory: PII field names anywhere (models, schemas, DTOs, code).
# ============================================================================
search "$PII_T01" "P-INV-TIER01" "${CODE_GLOBS[@]}" "*.sql" "*.prisma"
search "$PII_T2"  "P-INV-TIER2"  "${CODE_GLOBS[@]}" "*.sql" "*.prisma"

# ============================================================================
# Hardcoded PII-shaped VALUES (validate Luhn/Verhoeff/format when triaging).
# ============================================================================
search '\b[A-Z]{5}[0-9]{4}[A-Z]\b' "P-VAL-INCOMETAX-PAN" "${CODE_GLOBS[@]}" "*.json" "*.yml" "*.yaml" "*.csv"
search '\b[A-Z]{4}0[A-Z0-9]{6}\b' "P-VAL-IFSC" "${CODE_GLOBS[@]}" "*.json" "*.yml" "*.yaml" "*.csv"
search '\b(?:\d[ -]?){13,19}\b' "P-VAL-CARD-PAN?" "${CODE_GLOBS[@]}" "*.json" "*.csv"
search '\b[2-9][0-9]{3}[ -]?[0-9]{4}[ -]?[0-9]{4}\b' "P-VAL-AADHAAR?" "${CODE_GLOBS[@]}" "*.json" "*.csv"

# ============================================================================
# Sinks: PII reaching logs / responses / URLs / analytics. Language-specific.
# ============================================================================
LOG_FN='(console\.(log|info|warn|error|debug)|logger\.(log|info|warn|error|debug)|log\.(Printf|Print|Info|Error|Debug)|fmt\.(Print|Printf|Sprintf)|print\(|logging\.(info|debug|warning|error)|Logger\.(info|debug|warn|error))'

# P-LOG: a logging call on the same line as a PII field name.
search "${LOG_FN}[^;]*${PII_T01}" "P-LOG-TIER01" "${CODE_GLOBS[@]}"
search "${LOG_FN}[^;]*${PII_T2}"  "P-LOG-TIER2"  "${CODE_GLOBS[@]}"
# P-LOG: logging whole request body / object (common bulk leak).
search "${LOG_FN}[^;]*(req\.body|request\.(data|POST|body)|conn\.params|\.__dict__|inspect\()" "P-LOG-BULK-OBJECT?" "${CODE_GLOBS[@]}"

# P-RESP: dump-everything serialisers.
if want node || want typescript; then
  search 'res\.(json|send)\([^)]*\b(user|customer|account|profile|card)\b\s*\)' "P-RESP-FULL-OBJECT?" "${JS_GLOBS[@]}"
  search '\.set\(\s*["'\'']toJSON|fields\s*:\s*\[' "P-RESP-SERIALIZER?" "${JS_GLOBS[@]}"
fi
if want python; then
  search "fields\s*=\s*['\"]__all__['\"]|model_to_dict\(" "P-RESP-FULL-OBJECT" "${PY_GLOBS[@]}"
fi
if want go; then
  search 'json\.(NewEncoder|Marshal)\([^)]*\b(user|customer|account|profile|card)\b' "P-RESP-FULL-OBJECT?" "${GO_GLOBS[@]}"
fi
if want elixir; then
  search '@derive\s*\{?\s*Jason\.Encoder' "P-RESP-SERIALIZER?" "${EX_GLOBS[@]}"
fi

# P-URL: PII names appearing in query/route strings.
search "[?&/]${PII_T01}=|[?&/]${PII_T2}=|[?&]token=" "P-URL-PII-IN-QUERY?" "${CODE_GLOBS[@]}"

# P-3P: analytics SDK calls (check for PII payloads).
search '(analytics\.(track|identify|page)|mixpanel\.|segment\.|gtag\(|fbq\()' "P-3P-ANALYTICS?" "${CODE_GLOBS[@]}"

exit 0
