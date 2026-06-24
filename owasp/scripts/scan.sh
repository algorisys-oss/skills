#!/usr/bin/env bash
#
# scan.sh - heuristic OWASP candidate finder for Node.js, TypeScript, React, SolidJS, Elixir, Python, Go.
#
# This is a HIGH-RECALL, LOW-PRECISION pre-filter. It greps for dangerous APIs
# and patterns and prints candidate `file:line` locations grouped by OWASP
# category. It does NOT decide whether a hit is a real vulnerability - that is
# the reviewer's job (read references/<language>.md and triage each hit in
# context). Expect false positives; that is by design.
#
# Usage:
#   scan.sh [PATH]            Scan a directory or file (default: current dir)
#   scan.sh --diff            Scan only files changed vs git HEAD / branch
#   scan.sh --staged          Scan only git-staged files
#   scan.sh PATH --lang node  Restrict to one language (node|typescript|react|solidjs|elixir|python|go)
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
    # include changes vs the default branch's merge-base when on a feature branch
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
# NOTE: explicitly-named files are searched by rg/grep even when they do not
# match --glob, so for single-file and --diff/--staged modes the glob is applied
# in the shell (matches_glob) instead of trusting the engine's --glob filter.
# Without this, a .go file would also be matched by the Node/Python/Elixir
# patterns (e.g. os.ReadFile -> readFile), cross-labelling findings.
search() {
  local pattern="$1"; local category="$2"; shift 2
  local globs=("$@")

  if [ "$MODE" = "path" ] && [ -d "$TARGET" ]; then
    # Directory scan: the engine recurses and --glob/--include filters correctly.
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
    # Explicit file list (single file, or --diff/--staged): filter by extension here.
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
EX_GLOBS=("*.ex" "*.exs" "*.eex" "*.heex" "*.leex")
GO_GLOBS=("*.go")

# ============================================================================
# Cross-language: secrets, injection sinks. (A03 Injection, secrets mgmt)
# ============================================================================
search '(api[_-]?key|secret|password|passwd|token|client[_-]?secret|aws_access|private[_-]?key)\s*[:=]\s*["'\''"][A-Za-z0-9/+_=-]{12,}' "SECRETS" \
  "*.js" "*.jsx" "*.ts" "*.tsx" "*.py" "*.ex" "*.exs" "*.go" "*.json" "*.yml" "*.yaml" "*.env*"
search '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' "SECRETS" "*"

# Shared frontend router open redirect (React Router & Solid Router both use
# useNavigate()->navigate(...) and redirect(...)). Ungated + framework-agnostic
# so it fires once regardless of --lang and never double-counts across the
# react/solidjs blocks below.
search '\b(navigate|redirect)\(\s*[^)]*(searchParams|params|query|location|next|returnTo|url)' "OPEN-REDIRECT" "${JS_GLOBS[@]}"

# ============================================================================
# Node.js / TypeScript backend
# ============================================================================
if want node; then
  search '\b(child_process|exec|execSync|spawn)\b.*(req\.|request\.|input|params|query|body)' "A03-INJECTION-CMD" "${JS_GLOBS[@]}"
  search '\beval\(|new Function\(' "A03-INJECTION-EVAL" "${JS_GLOBS[@]}"
  search '\.(query|raw|execute)\(\s*[`"'\''].*\$\{|\.(query|raw)\(\s*["'\''].*\+' "A03-INJECTION-SQL" "${JS_GLOBS[@]}"
  search '\$where|\bmapReduce\b|\$function' "A03-INJECTION-NOSQL" "${JS_GLOBS[@]}"
  search '__proto__|constructor\s*\[|prototype\s*\[' "A08-PROTOTYPE-POLLUTION" "${JS_GLOBS[@]}"
  search 'Object\.assign\(\s*\w+\s*,\s*req\.(body|query|params)|new \w+\(req\.body\)' "A04-MASS-ASSIGNMENT" "${JS_GLOBS[@]}"
  search '(readFile|createReadStream|sendFile|unlink|readdir)\(.*(req\.|params|query|body)' "A01-PATH-TRAVERSAL" "${JS_GLOBS[@]}"
  search '\b(axios|fetch|http\.get|request|got)\b.*\(.*(req\.|params|query|body|url)' "A10-SSRF" "${JS_GLOBS[@]}"
  search 'res\.redirect\(.*(req\.|params|query|body)' "OPEN-REDIRECT" "${JS_GLOBS[@]}"
  search 'createCipheriv?\(\s*["'\''](des|rc4|aes-128-ecb|.*-ecb)|crypto\.createHash\(\s*["'\''](md5|sha1)' "A02-WEAK-CRYPTO" "${JS_GLOBS[@]}"
  search 'Math\.random\(\)' "A02-WEAK-RANDOM" "${JS_GLOBS[@]}"
  search 'jwt\.(verify|decode)\([^,]*\)|algorithms?\s*:\s*\[?\s*["'\'']none|verify:\s*false|rejectUnauthorized\s*:\s*false' "A07-AUTH-JWT-TLS" "${JS_GLOBS[@]}"
  search 'cors\(\)|origin\s*:\s*["'\'']\*["'\'']|Access-Control-Allow-Origin.*\*' "A05-CORS" "${JS_GLOBS[@]}"
  search 'cookie.*secure\s*:\s*false|httpOnly\s*:\s*false|sameSite\s*:\s*["'\'']?none' "A05-COOKIE-FLAGS" "${JS_GLOBS[@]}"
  search 'helmet\(\)|app\.disable\(\s*["'\'']x-powered-by' "A05-HEADERS-INFO" "${JS_GLOBS[@]}"
  search 'JSON\.parse\(.*(req\.|body)|node-serialize|funcster|serialize-javascript' "A08-DESERIALIZATION" "${JS_GLOBS[@]}"
fi

# ============================================================================
# React / frontend
# ============================================================================
if want react; then
  search 'dangerouslySetInnerHTML' "A03-XSS-DANGEROUS-HTML" "${JS_GLOBS[@]}"
  search '\.innerHTML\s*=|insertAdjacentHTML|document\.write' "A03-XSS-DOM" "${JS_GLOBS[@]}"
  search 'href=\{[^}]*\}|window\.location\s*=|location\.href\s*=' "OPEN-REDIRECT-XSS" "${JS_GLOBS[@]}"
  search '<Navigate\b[^>]*\bto\s*=\s*\{' "OPEN-REDIRECT" "${JS_GLOBS[@]}"   # React Router <Navigate to={...}/>
  search 'localStorage\.setItem\(.*(token|jwt|secret|password)|sessionStorage\.setItem\(.*(token|jwt)' "A07-TOKEN-IN-STORAGE" "${JS_GLOBS[@]}"
  search 'REACT_APP_[A-Z_]*(SECRET|KEY|TOKEN|PASSWORD)' "SECRETS-CLIENT-BUNDLE" "${JS_GLOBS[@]}"
  search 'target=["'\'']_blank["'\'']' "REL-NOOPENER" "*.jsx" "*.tsx"
fi

# ============================================================================
# SolidJS / SolidStart  (shares the generic frontend sinks in the React block;
# these are the Solid-distinct signatures — see references/solidjs.md)
# ============================================================================
if want solidjs; then
  search 'innerHTML\s*=\s*\{' "A03-XSS-INNERHTML-PROP" "${JS_GLOBS[@]}"
  search '<Dynamic\b[^>]*component\s*=\s*\{' "A03-XSS-DYNAMIC-COMPONENT" "${JS_GLOBS[@]}"
  search 'import\.meta\.env\.VITE_[A-Z_]*(SECRET|KEY|TOKEN|PASSWORD)' "SECRETS-CLIENT-BUNDLE" "${JS_GLOBS[@]}"
  search '["'\'']use server["'\'']' "SOLIDSTART-SERVER-FN" "${JS_GLOBS[@]}"
fi

# ============================================================================
# TypeScript-specific  (sink rules come from the node/react/solidjs blocks,
# which already scan .ts/.tsx; these flag the TS-only trap that types are NOT
# runtime validation, plus NestJS validation/authz — see references/typescript.md)
# ============================================================================
if want typescript; then
  search '(req|request|ctx|context)\.(body|query|params|headers|cookies)(\.\w+)*\s+as\b' "A04-TS-CAST-NOT-VALIDATION" "${TS_GLOBS[@]}"
  search 'JSON\.parse\([^)]*\)\s+as\b' "A04-TS-CAST-NOT-VALIDATION" "${TS_GLOBS[@]}"
  search '\bas any\b|as unknown as\b' "TS-UNSAFE-CAST" "${TS_GLOBS[@]}"
  search '@ts-(ignore|nocheck|expect-error)' "TS-SUPPRESSED-CHECK" "${TS_GLOBS[@]}"
  search 'new ValidationPipe\(' "NESTJS-VALIDATION-PIPE" "${TS_GLOBS[@]}"
fi

# ============================================================================
# Python (Django / Flask / FastAPI)
# ============================================================================
if want python; then
  search '\b(os\.system|os\.popen|subprocess\.(call|run|Popen|check_output))\b.*shell\s*=\s*True' "A03-INJECTION-CMD" "${PY_GLOBS[@]}"
  search '\beval\(|\bexec\(|\b__import__\(' "A03-INJECTION-EVAL" "${PY_GLOBS[@]}"
  search '\.(execute|executemany|raw|extra)\(\s*f["'\'']' "A03-INJECTION-SQL" "${PY_GLOBS[@]}"
  search '\.(execute|executemany|raw|extra)\([^)]*(\.format\(|["'\'']\s*\+|["'\'']\s*%\s*[(a-z_])' "A03-INJECTION-SQL" "${PY_GLOBS[@]}"
  search '\b(pickle|cPickle|dill|shelve|jsonpickle)\.(load|loads)\b|yaml\.load\(' "A08-DESERIALIZATION" "${PY_GLOBS[@]}"
  search 'render_template_string\(|Template\(.*(request|input)|\|\s*safe\b|mark_safe\(|autoescape.*[Ff]alse' "A03-XSS-SSTI" "${PY_GLOBS[@]}" "*.html" "*.jinja*"
  search '(open|os\.remove|os\.path\.join|send_file|send_from_directory)\(.*(request\.|args|form|params|filename)' "A01-PATH-TRAVERSAL" "${PY_GLOBS[@]}"
  search '\b(requests|urllib|httpx|aiohttp|urlopen)\b.*\(.*(request\.|args|form|params|url)' "A10-SSRF" "${PY_GLOBS[@]}"
  search 'verify\s*=\s*False|ssl\._create_unverified|CERT_NONE' "A07-TLS-VERIFY-OFF" "${PY_GLOBS[@]}"
  search 'hashlib\.(md5|sha1)\(|DES\.|ARC4\.|Random\.random\(|\brandom\.(random|randint|choice)\b' "A02-WEAK-CRYPTO" "${PY_GLOBS[@]}"
  search 'DEBUG\s*=\s*True|ALLOWED_HOSTS\s*=\s*\[\s*["'\'']\*' "A05-MISCONFIG-DJANGO" "${PY_GLOBS[@]}" "settings*.py"
  search '@csrf_exempt|csrf_protect.*False|WTF_CSRF_ENABLED\s*=\s*False' "CSRF-DISABLED" "${PY_GLOBS[@]}"
  search 'allow_origins\s*=\s*\[\s*["'\'']\*|CORS_ORIGIN_ALLOW_ALL\s*=\s*True' "A05-CORS" "${PY_GLOBS[@]}"
  search 'lxml.*resolve_entities\s*=\s*True|etree\.parse\(|XMLParser\(' "XXE" "${PY_GLOBS[@]}"
fi

# ============================================================================
# Elixir (Phoenix / Ecto)
# ============================================================================
if want elixir; then
  search 'System\.cmd\(.*(params|conn|input)|:os\.cmd|Code\.eval_string|Code\.eval_quoted' "A03-INJECTION-CMD-EVAL" "${EX_GLOBS[@]}"
  search 'Ecto\.Adapters\.SQL\.query|fragment\(\s*"[^"]*#\{|Repo\.query\(.*#\{' "A03-INJECTION-SQL" "${EX_GLOBS[@]}"
  search 'raw\(|{:safe' "A03-XSS-RAW" "${EX_GLOBS[@]}"
  search ':erlang\.binary_to_term|:erlang\.binary_to_atom|String\.to_atom\(' "A08-ATOM-DESERIALIZATION" "${EX_GLOBS[@]}"
  search 'cast\(.*,\s*__schema__\(:fields\)|cast_assoc.*with:.*&|\|>\s*cast\(params,' "A04-MASS-ASSIGNMENT" "${EX_GLOBS[@]}"
  search 'plug :protect_from_forgery|protect_from_forgery' "CSRF-CHECK" "${EX_GLOBS[@]}"
  search 'File\.(read|rm|stream|open)\(.*(params|conn)' "A01-PATH-TRAVERSAL" "${EX_GLOBS[@]}"
  search 'HTTPoison|Finch|Req\.|Tesla.*(params|conn|url)' "A10-SSRF" "${EX_GLOBS[@]}"
  search ':crypto\.hash\(\s*:(md5|sha)\b|:rand\.uniform|:crypto\.rand_uniform' "A02-WEAK-CRYPTO" "${EX_GLOBS[@]}"
  search 'verify:\s*:verify_none|secure:\s*false|http_only:\s*false' "A05-TLS-COOKIE" "${EX_GLOBS[@]}"
fi

# ============================================================================
# Go (net/http, gin/echo/fiber, database/sql, gorm)
# ============================================================================
if want go; then
  search '\.(Query|QueryRow|Exec|QueryContext|ExecContext|Raw|Where)\(\s*fmt\.Sprintf|\.(Query|QueryRow|Exec|Raw|Where)\(\s*"[^"]*"\s*\+' "A03-INJECTION-SQL" "${GO_GLOBS[@]}"
  search 'exec\.Command(Context)?\(\s*"(sh|bash|/bin/sh|/bin/bash|cmd|powershell)"' "A03-INJECTION-CMD" "${GO_GLOBS[@]}"
  search '"text/template"|template\.(HTML|JS|URL|CSS|HTMLAttr)\(' "A03-XSS-TEMPLATE" "${GO_GLOBS[@]}"
  search '(os\.(Open|ReadFile|Create|Remove)|ioutil\.ReadFile|http\.ServeFile)\(.*(r\.|req\.|param|query|input|c\.Param|c\.Query)|filepath\.Join\([^)]*(r\.|req\.|param|query|input|c\.Param|c\.Query)' "A01-PATH-TRAVERSAL" "${GO_GLOBS[@]}"
  search 'http\.(Get|Post|Head|PostForm)\(.*(r\.|req\.|param|query|input|url|c\.Query)|http\.NewRequest(WithContext)?\(.*(r\.|param|query|url)' "A10-SSRF" "${GO_GLOBS[@]}"
  search 'http\.Redirect\([^)]*(r\.URL|r\.Form|c\.Query|param|query|next|returnTo)' "OPEN-REDIRECT" "${GO_GLOBS[@]}"
  search 'InsecureSkipVerify\s*:\s*true' "A05-TLS-VERIFY-OFF" "${GO_GLOBS[@]}"
  search 'crypto/md5|crypto/sha1|crypto/des|crypto/rc4|md5\.New|sha1\.New|"math/rand"|math/rand\.' "A02-WEAK-CRYPTO" "${GO_GLOBS[@]}"
  search 'SigningMethodNone|UnsafeAllowNoneSignature|jwt\.Parse\(' "A07-AUTH-JWT" "${GO_GLOBS[@]}"
  search 'encoding/gob|gob\.NewDecoder|yaml\.Unmarshal\([^)]*interface' "A08-DESERIALIZATION" "${GO_GLOBS[@]}"
  search 'Access-Control-Allow-Origin.*\*|AllowAllOrigins\s*:\s*true|AllowOrigins.*"\*"' "A05-CORS" "${GO_GLOBS[@]}"
  search '(c\.(Bind|BindJSON|ShouldBind|ShouldBindJSON)|json\.NewDecoder\([^)]*\)\.Decode)\(&' "A04-MASS-ASSIGNMENT" "${GO_GLOBS[@]}"
fi

exit 0
