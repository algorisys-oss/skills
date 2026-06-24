---
name: owasp
description: Identify, explain, and (on request) fix OWASP-class security vulnerabilities in Node.js, React, SolidJS, Elixir, Python, and Go code. Use when the user asks to "run owasp", "security scan", "check for vulnerabilities", "OWASP review", "find security issues", "audit this for security", or invokes /owasp. Covers the OWASP Top 10 (2021) plus 10 extended categories (CSRF, XSS, mass assignment, path traversal, insecure upload, open redirect, deserialization, secrets, race conditions, AI/ML risks) with onboarding/KYC/backoffice domain checks.
user-invocable: true
---

# owasp

Find OWASP-class vulnerabilities in Node.js, React, SolidJS, Elixir, Python, and Go code, explain
each in context, and apply fixes when asked. Built for onboarding journeys, video-KYC, workflow/rules
backoffice systems, and internal/external AI-ML integrations.

The category list (Top 10 + 10 extended = "Top 20") lives in `references/catalog.md`. Per-language
dangerous-API → fix tables live in `references/{nodejs,react,solidjs,python,elixir,golang}.md`. Domain-specific
checks (KYC, video upload, workflow races, LLM/prompt-injection) live in `references/domain-kyc-aiml.md`.

## Default behavior

- **Report, do not auto-modify.** Produce a findings report; apply fixes only when the user passes
  `--fix` or explicitly asks. (Decision: security-sensitive code is reviewed before it is changed.)
- **Default scope is the whole repository.** A path or flag narrows it.

## Invocation

```
/owasp                 Scan the whole repo, report findings
/owasp <path>          Scan a directory or file
/owasp --diff          Scan only changed files (uncommitted + branch vs base) — pre-commit/PR use
/owasp --staged        Scan only git-staged files
/owasp --fix [scope]   Scan, then apply fixes (still confirm anything risky — see step 5)
/owasp <Top-N or topic> e.g. "owasp check SSRF in the webhook handler", "owasp audit KYC upload"
```

Parse the request into a **scope** (path / `--diff` / `--staged` / whole repo) and a **mode**
(report — default — or fix). A focused topic (e.g. "SSRF", "the upload endpoint") narrows which
categories and files to weight.

## Workflow

### 1. Detect languages & frameworks
Identify which of Node.js/TypeScript, React/frontend, SolidJS, Python, Elixir, Go are present
(manifests: `package.json` — incl. `solid-js`/`@solidjs/*`/`@solidjs/start` deps,
`requirements.txt`/`pyproject.toml`, `mix.exs`, `go.mod`; file extensions; frameworks like
Express/Django/FastAPI/Phoenix/Flask/gin/SolidStart). Load only the relevant `references/*.md`
to save context.

### 2. Run the heuristic pre-filter
Run the bundled scanner to get candidate `file:line` locations fast. It is **high-recall,
low-precision** — a triage list, not a verdict.

```sh
scripts/scan.sh [PATH]        # default scope = path arg or "."
scripts/scan.sh --diff        # changed files only
scripts/scan.sh PATH --lang node|react|solidjs|python|elixir|go   # restrict language
```

Output is `CATEGORY \t file:line \t matched text`. It prefers `ripgrep` and falls back to `grep`.
The scanner is a starting point — also reason about categories it cannot grep (access control,
insecure design, race conditions, business logic; see step 4).

### 3. Run ecosystem auditors for A06 (dependencies)
These find vulnerable-component issues the grep cannot. Run those that apply, report
high/critical with fix versions:
- Node: `npm audit --omit=dev` (or `pnpm audit` / `yarn npm audit`)
- Python: `pip-audit` or `safety check`
- Elixir: `mix deps.audit` and `mix hex.audit`
- Go: `govulncheck ./...` (official, call-graph aware) and `gosec ./...` (SAST)
- Phoenix bonus: `mix sobelow` (Phoenix-aware SAST) — cross-check its hits against `references/elixir.md`

### 4. Triage every candidate in context
For each scanner hit, open the file and decide if it is real. Read the matching `references/*.md`
entry for the fix pattern. Discard false positives (e.g. a parameterized query that merely
contained a `+`). Then add the findings grep cannot reach by reasoning about:
- **A01 Broken access control / IDOR** — every endpoint taking a record id: is there an
  ownership/tenant check? (Highest-yield review for backoffice — see `domain-kyc-aiml.md`.)
- **A04 Insecure design** — missing rate limiting / idempotency on login/OTP/KYC/payment.
- **Category 19 Race conditions** — concurrent state transitions in workflow/onboarding.
- **Category 20 AI/ML** — prompt injection, insecure model-output handling, PII to external LLMs.
- **Category 15 Upload / video KYC** — content validation, storage, access control on media.

Confirm exploitability where feasible (does untrusted input actually reach the sink?). Do not
report a pattern as a vulnerability without tracing the data flow.

### 5. Report findings
Group by severity (Critical → High → Medium → Low/Info; see `references/catalog.md` for the rubric).
For each finding give:

- **Severity** and **confidence** (heuristic hit needing confirmation vs. confirmed).
- **OWASP category** (e.g. `A03 Injection — SQL`, `Cat 14 Path traversal`).
- **Location** — `file:line` as a clickable link.
- **What & why** — one or two sentences on the risk in *this* code.
- **Fix** — concrete remediation (code snippet from the language reference, adapted).

Lead with a one-line summary (counts by severity). If scope was narrowed (e.g. `--diff`) or any
auditor was skipped/unavailable, say so — never imply full coverage that was not performed.

### 6. Fix (only when `--fix` or explicitly requested)
Apply the smallest correct fix per the language reference, preferring framework-native safe APIs
(parameterized queries, allowlist casts, `DOMPurify`, `secrets.token_urlsafe`, etc.). Then:
- Make low-risk, mechanical fixes directly (add `Secure` cookie flag, parameterize a query,
  pin JWT algorithm, add `rel="noopener"`).
- For changes that can alter behavior (auth/authz logic, deserialization removal, CORS tightening,
  redirect allowlists), explain the change and confirm with the user before applying.
- Never weaken a control to make a test pass. After fixing, re-run the relevant scan to confirm the
  signature is gone and note any fix that needs a human security review.

## Boundaries

- This skill finds **common, pattern-detectable** issues and reasons about high-value design gaps.
  It is not a penetration test or a substitute for a security audit of auth/crypto-critical code —
  say so when the code under review is in that class.
- Heuristics produce false positives and miss novel/logic-only bugs. Always confirm in context;
  always disclose what was and was not covered.
- Operate in a defensive posture: identify and remediate. Do not produce working exploits beyond a
  minimal proof needed to confirm a finding.

## Resources

- `references/catalog.md` — the Top 20 categories, descriptions, severity rubric.
- `references/nodejs.md` · `references/react.md` · `references/solidjs.md` · `references/python.md`
  · `references/elixir.md` · `references/golang.md` — per-language signatures and fixes.
- `references/domain-kyc-aiml.md` — KYC/upload, workflow races, multi-tenant access control,
  LLM/AI-ML risks.
- `scripts/scan.sh` — heuristic candidate finder (ripgrep/grep).
