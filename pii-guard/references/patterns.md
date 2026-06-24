# pii-guard patterns — masking, tokenisation, redaction

How to protect PII once detected. Prefer **centralised, deny-by-default** protection (one redactor
the whole app routes through) over per-call-site discipline, which always drifts.

## Masking (display & logs)

Show the minimum needed to be useful; hide the rest. Mask at the boundary, never store the masked
form as if it were the real value.

```
card PAN        4111 11XX XXXX 1111   (first 6 / last 4 max — PCI Req. 3.3)
account number  XXXXXX3456            (last 4)
Aadhaar         XXXX-XXXX-1234        (last 4)
income-tax PAN  ABCDEXXXXF            (or fully masked)
email           j***@d***.com
phone           +91-XXXXX-X4321
```

```js
const maskPan = (s) => s.replace(/\d(?=\d{4})/g, 'X');     // keep last 4
const maskAround = (s, keep = 4) => s.slice(0, 0) + 'X'.repeat(Math.max(0, s.length - keep)) + s.slice(-keep);
```

## Tokenisation & vaulting (at rest, Tier 0/1)

Replace the sensitive value with a non-sensitive **token**; keep the real value only in a dedicated
vault (or use a PCI-compliant processor so raw PAN never touches your DB — the strongest scope
reduction). The application stores and passes the token.

- **Card data:** prefer the gateway/processor's tokenisation (Stripe/Razorpay tokens). Never store
  CVV (Tier 0). If you must store PAN, use a vault with strict access + audit (`audit-trail`).
- **Format-preserving encryption (FPE)** keeps the value's shape (useful for legacy schemas) while
  rendering it unreadable; still treat the ciphertext as sensitive.

## At-rest encryption (Tier 1)

For PII you must store and read back, use **field-level encryption** with a KMS-managed key
(envelope encryption), not a hardcoded key. Crypto specifics and key management are owned by
`owasp` A02 — defer the algorithm/rotation detail there; pii-guard's rule is *Tier-1 plaintext at
rest is a finding*.

## Centralised log/serialiser redaction (deny-by-default)

Make the safe path the default so a newly added PII field is protected automatically.

- **Loggers:** configure a redaction list once (pino `redact`, winston format, structlog processor,
  zap/zerolog hooks, Logger.Filter) keyed on field names from `detection.md`. Default-deny: log a
  curated allowlist of fields, not arbitrary objects.
- **Serialisers/DTOs:** return an explicit response DTO with only the fields the client needs; mask
  Tier-1 fields in the serializer. Never `fields = '__all__'` / `model.toJSON()` for an entity with
  PII.
- **Error trackers:** Sentry `beforeSend` / Rollbar scrubber stripping PII fields and PII-shaped
  values from events, breadcrumbs, and request bodies.
- **URLs:** keep PII and tokens out of query strings entirely; put them in the body or headers.

## Non-prod & analytics

- **Test/staging:** seed with synthetic data or an irreversibly masked copy; never restore raw prod
  PII into a lower environment.
- **Analytics/3P:** send a hashed/pseudonymous id, not raw PII; strip identifiers in the client
  before the SDK call. This is also a `regtech` consent/transfer concern.

## Verifying a fix
After applying redaction, re-run `scripts/scan.sh` on the path and confirm the field no longer
reaches the sink. For value-regex scrubbing (free text), remember it is best-effort — prefer
field-name redaction at the serialiser/logger layer where the field is structured.
