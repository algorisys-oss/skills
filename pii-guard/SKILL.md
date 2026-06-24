---
name: pii-guard
description: Identify, explain, and (on request) fix PII/PCI data-protection gaps in Node.js, TypeScript, Python, Go, and Elixir code — sensitive data (card PAN, CVV, income-tax PAN, Aadhaar, account number, IFSC, UPI VPA, passport, DOB, name, email, phone, biometrics) leaking into logs, error trackers, analytics, API responses, URLs, caches, and non-prod, plus plaintext-at-rest and missing masking/tokenisation. Use when the user asks to "run pii-guard", "find PII leaks", "check data masking", "is PII in our logs", "tokenise card data", "PII scan", or invokes /pii-guard. Built for banking/NBFC/fintech/ecommerce systems handling KYC and payment data.
user-invocable: true
---

# pii-guard

Find where sensitive personal and payment data lives and leaks in Node.js, TypeScript, Python, Go,
and Elixir code, explain each exposure in context, and apply masking/tokenisation/redaction fixes
when asked. Built for KYC, onboarding, and payment systems where a card number in a log line or an
unmasked Aadhaar in an API response is a breach and a compliance failure.

This is the **data-protection deep skill**: it owns PII *detection breadth* and the
masking/tokenisation/redaction *patterns*. It complements — and is cross-referenced by — `regtech`
(maps exposures to PCI/DPDP/GDPR controls), `audit-trail` (AU11, PII in audit records), and `owasp`
(A02 crypto, secrets). The data taxonomy and exposure sinks live in `references/catalog.md`; value
detection signatures live in `references/detection.md`; masking/tokenisation/redaction patterns live
in `references/patterns.md`; per-language logger/serialiser sinks live in
`references/{nodejs,typescript,python,golang,elixir}.md`.

## Default behavior

- **Report, do not auto-modify.** Produce a findings report; apply fixes only when the user passes
  `--fix` or explicitly asks.
- **Default scope is the whole repository.** A path or flag narrows it.

## Invocation

```
/pii-guard                 Scan the whole repo, report PII exposures
/pii-guard <path>          Scan a directory or file
/pii-guard --diff          Scan only changed files (uncommitted + branch vs base) — pre-commit/PR use
/pii-guard --staged        Scan only git-staged files
/pii-guard --fix [scope]   Scan, then apply fixes (still confirm anything risky — see step 5)
/pii-guard <topic>         e.g. "pii-guard check the logging", "are card numbers in the API response"
```

Parse the request into a **scope** and a **mode** (report — default — or fix). A focused topic (a
field, a sink like logs/analytics) narrows what to weight.

## Workflow

### 1. Detect languages, loggers & serialisers
Identify the stack (manifests as in `owasp`). Note the **logging** framework (`winston`/`pino`/
`console`, `logging`/`structlog`, `zap`/`logrus`/`slog`, `Logger`), the **serialisation** path
(JSON responses, `toJSON`/`__str__`/`Jason`/`Inspect`, ORM serializers/DRF/Ecto), error trackers
(Sentry/Rollbar), and analytics SDKs. These are where PII leaks. Load only the relevant
`references/*.md`.

### 2. Build the PII inventory
Find where sensitive data is defined and stored — models, schemas, DTOs, migrations. Use
`references/catalog.md` (taxonomy + sensitivity tiers) and `references/detection.md` (field-name and
value signatures). For each field note its **tier** (prohibited / restricted / personal) and where
it flows. This inventory anchors every leak finding.

### 3. Run the heuristic pre-filter
Run the bundled scanner for candidate `file:line` locations. **High-recall, low-precision.**

```sh
scripts/scan.sh [PATH]        # default scope = path arg or "."
scripts/scan.sh --diff        # changed files only
scripts/scan.sh PATH --lang node|typescript|python|go|elixir
```

Output is `CATEGORY \t file:line \t matched text`. It flags PII field names, hardcoded
PII-shaped values, and PII reaching log/serialise/analytics/URL sinks. It cannot tell a masked field
from an unmasked one — confirm in step 4.

### 4. Triage each exposure in context
For each hit, open the file, read the matching `references/*.md`, and decide if sensitive data is
actually exposed **unprotected**. Trace the field to its sink. Discard false positives (a `pan` that
is a UI panel, a masked value). Then reason about the sinks grep underweights:

- **Logs & error trackers (P-LOG)** — PII in `logger.*`/`console.*`/`print`, in exception messages,
  or sent to Sentry/Rollbar without scrubbing. (Overlaps `audit-trail` AU11.)
- **API responses (P-RESP)** — endpoints returning full PII (unmasked PAN/Aadhaar/account) where
  masked/last-4 would do; over-broad serializers dumping every model field.
- **URLs / query params (P-URL)** — PII in path/query strings (logged by proxies, in browser history,
  in referrers); tokens or PII in `GET` parameters.
- **At rest unprotected (P-REST)** — prohibited data stored at all (CVV/PIN — defer the rule to
  `regtech` C2), restricted data stored plaintext instead of encrypted/tokenised. (Crypto depth →
  `owasp` A02.)
- **Analytics / third parties (P-3P)** — PII forwarded to analytics, ad, or external SaaS SDKs.
- **Non-prod & caches (P-NONPROD)** — prod PII copied to test/staging/seed data, or cached
  (Redis/CDN) unmasked.

Confirm the data is real PII and actually reaches the sink before reporting.

### 5. Report findings
Group by severity (Critical → High → Medium → Low/Info; see `references/catalog.md`). For each:

- **Severity** and **confidence**, and the **data tier** (prohibited/restricted/personal).
- **Category** — e.g. `PII in logs`, `Unmasked PAN in API response`, `Plaintext PII at rest`.
- **Location** — `file:line` as a clickable link.
- **What & why** — which field, which sink, the exposure in *this* code.
- **Fix** — concrete remediation (mask/tokenise/redact/encrypt) from `patterns.md`/the language file.

Lead with a one-line summary (exposures by tier/severity). If scope was narrowed say so — never
imply full coverage. Note which sibling skills should run for depth (`regtech`, `owasp`, `audit-trail`).

### 6. Fix (only when `--fix` or explicitly requested)
Apply the smallest correct fix, preferring a **centralised** redactor over per-call-site edits. Then:

- Make low-risk, mechanical fixes directly — mask a field before logging (`maskPan`, last-4), add a
  field to a logger/serialiser redaction denylist, remove PII from a URL/query param, drop a PII
  field from an over-broad API response, configure Sentry `beforeSend` scrubbing.
- For changes that alter behavior or data — encrypting/tokenising an existing plaintext column (a
  **data migration**), removing a stored prohibited field (CVV), or changing an API response shape
  consumers depend on — explain the change/migration and confirm first.
- Never log or expose raw PII to make something easier. Prefer a deny-by-default redaction allowlist
  so new fields are protected automatically. After fixing, re-run the scan and flag anything needing
  compliance (`regtech`) or crypto (`owasp`) review.

## Boundaries

- This skill finds **pattern-detectable** PII exposures and reasons about sinks. It is not a DLP
  product, not runtime traffic inspection, and not a guarantee that all PII is covered — say so.
- Heuristics produce false positives (`pan` the UI panel, already-masked values) and miss PII in
  free-text/opaque blobs. Always confirm classification; disclose coverage.
- Crypto-at-rest depth belongs to `owasp` A02; regulatory mapping belongs to `regtech`; audit-record
  PII belongs to `audit-trail`. pii-guard flags and remediates the exposure and defers those depths.

## Resources

- `references/catalog.md` — PII/PCI taxonomy, sensitivity tiers, exposure sinks, severity rubric.
- `references/detection.md` — field-name and value signatures (card PAN, income-tax PAN, Aadhaar,
  IFSC, UPI VPA, account number, phone, email, passport, DOB, GSTIN), with India-specific formats.
- `references/patterns.md` — masking, tokenisation/vaulting, format-preserving encryption,
  centralised log/serialiser redaction, deny-by-default allowlists.
- `references/{nodejs,typescript,python,golang,elixir}.md` — per-language logger/serialiser sinks & fixes.
- `scripts/scan.sh` — heuristic candidate finder (ripgrep/grep).
