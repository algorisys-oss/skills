# pii-guard catalog — taxonomy, tiers, sinks

PII/PCI data classes, how sensitive each is, and where it leaks. Use the **tiers** to set severity
and the **sinks** to drive the triage. Value/field signatures are in `detection.md`; protections are
in `patterns.md`.

## Sensitivity tiers

### Tier 0 — Prohibited (never store; minimise even in memory)
Sensitive authentication data and equivalents: **CVV/CVC**, full magnetic **track data**, card
**PIN/PIN block**, full private keys. PCI-DSS Req. 3.2 forbids storing these after authorisation, at
all. Any persistence or logging is **Critical**. (The storage rule is owned by `regtech` C2; the
exposure is owned here.)

### Tier 1 — Restricted (encrypt/tokenise at rest; mask on display; never in logs)
Data that directly enables fraud or identity theft: **card PAN** (Primary Account Number),
**bank account number**, **Aadhaar number**, **passport number**, **biometric** templates,
government IDs (voter ID, driving licence), full **income-tax PAN** (ABCDE1234F). Exposure is
**High–Critical**.

### Tier 2 — Personal (minimise; mask in logs; access-control)
Identifying personal data: **name**, **DOB**, **email**, **phone**, **address**, **IFSC** (with an
account number), **UPI VPA**, **GSTIN**, IP/device id, customer id tied to identity. Exposure is
**Medium–High** (higher in combination, which enables re-identification).

> Combination raises tier: name + DOB + address, or any Tier-2 set that uniquely identifies a person,
> should be treated as Tier 1 for at-rest and log protection.

## Exposure sinks (where PII leaks)

### P-LOG — Logs & error trackers
PII passed to `logger.*`/`console.*`/`print`/`fmt.Print`, embedded in exception messages and stack
traces, or shipped to Sentry/Rollbar/Datadog without scrubbing. The most common real leak. **Fix:**
mask before logging; centralise redaction; scrub error-tracker payloads. **Severity by tier.**

### P-RESP — API responses
Endpoints returning full PII where masked/last-4 suffices; "dump the whole model" serializers
(DRF `fields = '__all__'`, `model.toJSON()`, Ecto deriving `Jason.Encoder` for all fields) that leak
fields the client never needs. **Fix:** explicit response DTO/allowlist; mask Tier-1 fields.
**Severity: High for Tier-1 fields.**

### P-URL — URLs, query params, referrers
PII or tokens in path/query strings — logged by web servers/proxies, kept in browser history,
leaked via `Referer`. **Fix:** move to the request body/headers; never put PII/tokens in `GET` URLs.
**Severity: Medium–High.**

### P-REST — At rest, unprotected
Tier-0 data stored at all; Tier-1 data stored plaintext rather than encrypted/tokenised; PII in
plaintext config/seed files. **Fix:** remove (Tier 0), tokenise/encrypt (Tier 1). Crypto depth →
`owasp` A02. **Severity: Critical (Tier 0) / High (Tier 1 plaintext).**

### P-3P — Analytics & third parties
PII forwarded to analytics/ad/marketing/SaaS SDKs (Segment, GA, Mixpanel, FB pixel) or external
APIs beyond what is necessary. **Fix:** strip/hash identifiers before sending; minimise.
**Severity: Medium–High** (also a `regtech` consent/transfer issue).

### P-NONPROD — Non-prod & caches
Production PII copied into test/staging/seed fixtures, or cached in Redis/CDN/edge unmasked.
**Fix:** synthetic/masked test data; mask cached values; short TTLs. **Severity: Medium–High.**

## Severity guidance for reporting

- **Critical** — Tier-0 data stored or logged; Tier-1 (card PAN/Aadhaar/account) in plaintext at
  rest or shipped to a third party / error tracker.
- **High** — Tier-1 in logs or unmasked in an API response; combined Tier-2 set exposed.
- **Medium** — single Tier-2 field in logs/URLs/analytics; PII in non-prod copies.
- **Low / Info** — masked-but-could-be-tokenised, defense-in-depth, hardening.

Confidence ≠ severity. A Critical hit from a low-confidence grep (a `pan` that may be a UI panel) is
"Critical / needs confirmation" until you confirm it is real card data reaching a real sink.
