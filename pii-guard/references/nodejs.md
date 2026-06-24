# Node.js — PII sinks & fixes

Express/Nest/Fastify, `winston`/`pino`/`console`, JSON responses, Sequelize/TypeORM/Prisma/Mongoose,
Sentry. Triage each `scan.sh` hit here. Format: **what to look for → why → fix**.

## P-LOG Logs & error trackers
- **Look for:** `console.log/info/error(... user ...)`, `logger.info(req.body)`, logging an entire
  entity/object, `JSON.stringify(user)` in a log, errors carrying PII; Sentry `captureException`
  with PII in context.
- **Fix:** mask before logging; configure a central redactor.
  ```js
  // pino: deny-by-default-ish redaction
  const logger = pino({ redact: { paths: ['*.cardNumber','*.cvv','*.aadhaar','*.accountNumber',
    'req.body.password','*.email','*.phone'], censor: '[REDACTED]' } })
  // Sentry: scrub before send
  Sentry.init({ beforeSend(e) { return scrubPii(e) } })
  ```
  Never log `req.body`/full objects on a route that carries PII.

## P-RESP API responses
- **Look for:** `res.json(user)` / returning a full Mongoose/Sequelize model; `toJSON()` with no
  field selection; serializers exposing every column.
- **Fix:** explicit response shape; mask Tier-1 fields.
  ```js
  res.json({ id: u.id, name: u.name, cardLast4: maskPan(u.cardNumber).slice(-4) })
  // Mongoose: toJSON transform to delete sensitive fields by default
  schema.set('toJSON', { transform: (_, ret) => { delete ret.cvv; delete ret.aadhaar; return ret } })
  ```

## P-URL URLs & query params
- **Look for:** PII/tokens in route params or `?query=` (`/users?aadhaar=...`, `?token=...`).
- **Fix:** move to the request body or an auth header; never PII in a `GET` URL.

## P-REST At rest
- **Look for:** Tier-0 fields persisted (`cvv` column/schema field); Tier-1 stored plaintext (no
  encryption/tokenisation).
- **Fix:** drop CVV entirely; tokenise card data via the gateway; field-level encrypt Tier-1 with a
  KMS key (crypto detail → `owasp` A02).

## P-3P Analytics & third parties
- **Look for:** `analytics.identify/track(... email/phone ...)`, PII in Segment/GA/Mixpanel/FB calls,
  PII forwarded to external APIs.
- **Fix:** send a hashed/pseudonymous id; strip PII before the SDK call.
