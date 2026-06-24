# OWASP Top 20 Catalog

The standard is the **OWASP Top 10 (2021)**. This skill extends it with 10 high-frequency
categories that recur in onboarding/KYC/backoffice/workflow systems, for a margin of safety
("Top 20"). Categories 11-20 are not official OWASP rankings; several overlap with the Top 10
but are called out separately because they have distinct detection signatures and fixes.

Each entry: **ID — Name** · what it is · why it matters here · severity baseline.

## OWASP Top 10 (2021)

### A01 — Broken Access Control
Users acting outside intended permissions: IDOR (object IDs in URLs with no ownership check),
missing function-level authz, path traversal, forced browsing, JWT/role tampering. Most common
real-world breach class. In backoffice/workflow systems, check every state transition and record
fetch enforces tenant + role + ownership, not just authentication. **Severity: High–Critical.**

### A02 — Cryptographic Failures
Sensitive data exposed through weak or missing crypto: plaintext PII/KYC data, MD5/SHA1 for
passwords, ECB mode, hardcoded keys/IVs, `Math.random`/`random` for tokens, TLS verification
disabled, secrets in logs. KYC document and biometric data raise this to top priority. **Severity: High.**

### A03 — Injection
Untrusted input reaches an interpreter: SQL/NoSQL injection, OS command injection, LDAP,
XPath, SSTI (server-side template injection), and XSS (DOM/reflected/stored). The fix is
almost always the same shape: parameterize / use safe APIs / context-aware output encoding;
never string-concatenate untrusted data into a query, command, or markup. **Severity: High–Critical.**

### A04 — Insecure Design
Missing or flawed security controls by design, not by bug: no rate limiting on KYC/OTP
endpoints, no idempotency on financial/onboarding actions, business-logic bypass, missing
mass-assignment allowlist, trust boundaries crossed without validation. Found by reasoning
about threat models, not grep. **Severity: Varies, often High.**

### A05 — Security Misconfiguration
Insecure defaults left in place: `DEBUG=True` in prod, wildcard CORS, permissive cookies
(missing `Secure`/`HttpOnly`/`SameSite`), verbose error pages/stack traces, default
credentials, missing security headers (CSP, HSTS, X-Frame-Options), open cloud buckets,
directory listing. **Severity: Medium–High.**

### A06 — Vulnerable and Outdated Components
Known-vulnerable dependencies. Detected by manifest/lockfile audit, not source grep:
`npm audit`, `pip-audit`/`safety`, `mix deps.audit`/`mix hex.audit`. Also unmaintained packages
and pinned-but-old transitive deps. **Severity: Varies by CVE.**

### A07 — Identification & Authentication Failures
Weak auth: credential stuffing allowed (no rate limit/lockout), weak password policy, session
fixation, JWT with `alg:none` or unverified signature, long-lived/non-rotating tokens, tokens
in localStorage, missing MFA on privileged actions, predictable password reset. **Severity: High.**

### A08 — Software & Data Integrity Failures
Trusting data/code without verifying integrity: insecure deserialization (pickle, Java/PHP
serialize, `node-serialize`, `binary_to_term`, unsafe `yaml.load`), unsigned auto-updates,
CI/CD pipeline tampering, unvetted CDN scripts without SRI, prototype pollution. **Severity: High–Critical.**

### A09 — Security Logging & Monitoring Failures
Inability to detect/respond to breaches: no audit log on auth and privileged actions, logging
secrets/PII in plaintext, no alerting, logs not tamper-evident. For KYC/backoffice, missing
audit trails are also a compliance failure. **Severity: Medium.**

### A10 — Server-Side Request Forgery (SSRF)
Server fetches a user-controlled URL, letting an attacker reach internal services/cloud
metadata (`169.254.169.254`). Common in webhook callbacks, document/image fetch-by-URL, KYC
provider integrations, link previews. Fix: allowlist hosts, block private/link-local ranges,
disable redirects, no raw user URL to an HTTP client. **Severity: High.**

## Extended (11–20) — high-frequency for this stack

### 11 — Cross-Site Request Forgery (CSRF)
State-changing request forged from another origin. Risk wherever cookie-based sessions are used.
Fix: framework CSRF tokens (Django/Phoenix on by default — do not disable), `SameSite` cookies,
re-auth for sensitive actions. Pure token-in-header APIs are lower risk. **Severity: Medium–High.**

### 12 — Cross-Site Scripting (XSS), frontend-focused
Subset of A03, but the React/template signatures are distinct enough to track separately:
`dangerouslySetInnerHTML`, `innerHTML`, `document.write`, `v-html`, `raw()`/`{:safe}` in EEx,
`|safe`/`mark_safe` in Jinja/Django, unsanitized `href`/`src` from user input. **Severity: High.**

### 13 — Mass Assignment / Over-Posting
Binding request body directly to a model/record so a client can set fields it should not
(`is_admin`, `role`, `balance`, `kyc_verified`). Fix: explicit allowlist of permitted fields
(Ecto `cast/3` field list, DRF serializer fields, Pydantic models, never `Object.assign(model, req.body)`).
**Severity: High.**

### 14 — Path Traversal / Arbitrary File Access
User input flows into a filesystem path (`../../etc/passwd`) for read/write/delete/serve. Very
common in document/KYC upload-download flows. Fix: resolve to a canonical base dir and verify
the result stays inside it; never join raw user input into a path. **Severity: High.**

### 15 — Insecure File Upload
Accepting uploads without validating type/size/content; trusting client MIME or extension;
storing under web root; no AV scan. Critical for **video KYC and document uploads**. Fix:
validate by content (magic bytes), generate server-side names, store outside web root / in
object storage, set size limits, scan, serve with correct `Content-Disposition`. **Severity: High.**

### 16 — Open Redirect
Redirect target taken from user input (`?next=`, `returnTo`, OAuth `redirect_uri`) without
validation — aids phishing and OAuth token theft. Fix: allowlist redirect targets or only allow
relative same-origin paths. **Severity: Medium.**

### 17 — Insecure Deserialization
Called out from A08 for its distinct, deterministic signatures: `pickle.loads`, `yaml.load`
without `SafeLoader`, `node-serialize`/`funcster`, `:erlang.binary_to_term`, `String.to_atom`
on user input (atom-table DoS). Fix: never deserialize untrusted data; use JSON + schema
validation; safe loaders only. **Severity: Critical.**

### 18 — Secrets & Credential Management
Hardcoded API keys, passwords, private keys, tokens in source/config/client bundles; secrets in
`REACT_APP_*` (shipped to the browser); secrets committed to git history. Fix: env vars / secret
manager, rotate any exposed secret, `.gitignore` env files, never put secrets in client builds.
**Severity: High–Critical.**

### 19 — Race Conditions / TOCTOU
Concurrent requests violate an invariant the code assumed was sequential: double-spend, duplicate
onboarding, approval applied twice, balance check then update without a lock. Common in
**workflow/rules engines and financial onboarding**. Fix: DB transactions with appropriate
isolation, `SELECT ... FOR UPDATE`/optimistic locking, idempotency keys, unique constraints.
**Severity: High.**

### 20 — AI/ML Integration Risks (LLM/model security)
For internal/external AI/ML integrations: **prompt injection** (untrusted content steering an
LLM), **insecure output handling** (model output used in SQL/shell/HTML/`eval` without
validation), **SSRF/tool abuse via agents**, training-data/PII leakage, no rate/cost limits,
over-trusting model output for KYC decisions without human review. Maps to the OWASP Top 10 for
LLM Applications. See `domain-kyc-aiml.md`. **Severity: Varies, often High.**

## Severity guidance for reporting

- **Critical** — unauthenticated RCE, injection with confirmed sink, secrets enabling account
  takeover, insecure deserialization of untrusted input.
- **High** — auth/access-control bypass, exploitable injection requiring some context, PII/KYC
  exposure, SSRF to internal services.
- **Medium** — misconfig, CSRF on cookie sessions, open redirect, missing security headers.
- **Low / Info** — defense-in-depth gaps, missing hardening, weak-but-not-yet-exploitable patterns.

Confidence ≠ severity. Report both: a high-severity category with a low-confidence heuristic hit
is "High severity / needs confirmation", not a definitive finding.
