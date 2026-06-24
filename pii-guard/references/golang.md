# Go — PII sinks & fixes

net/http, gin/echo/fiber; `zap`/`logrus`/`zerolog`/`slog`; `encoding/json` responses; gorm/sqlx;
Sentry. Triage each `scan.sh` hit here. Format: **what to look for → why → fix**.

## P-LOG Logs & error trackers
- **Look for:** `log.Printf("... %v", user)`, `logger.Info("body", zap.Any("req", body))`,
  `fmt.Sprintf` of a struct with PII, errors wrapping PII; Sentry with PII context.
- **Fix:** mask before logging; implement `String()`/`MarshalLog` to redact, or log allowlisted
  fields only.
  ```go
  // Redact at the type: card never prints raw
  func (c Card) String() string { return "Card{****" + last4(c.Number) + "}" }
  // zap: log explicit safe fields, not zap.Any(wholeStruct)
  logger.Info("charged", zap.String("user_id", u.ID), zap.String("card_last4", last4(u.Card)))
  ```

## P-RESP API responses
- **Look for:** `json.NewEncoder(w).Encode(user)` of a full struct; struct fields with PII and no
  `json:"-"`; returning a DB model directly.
- **Fix:** a response struct with only client fields, or `json:"-"` on Tier-0/1 fields; mask Tier-1.
  ```go
  type Card struct {
      Number string `json:"-"`          // never serialised
      Last4  string `json:"last4"`
  }
  ```

## P-URL URLs & query params
- **Look for:** PII/tokens in `r.URL.Query()` round-trips or built into outbound URLs.
- **Fix:** body/header instead; never PII in a `GET` URL.

## P-REST At rest
- **Look for:** a `CVV`/`PIN` struct/column (Tier 0); Tier-1 fields stored plaintext.
- **Fix:** remove CVV; tokenise; field-level encryption with a KMS key — crypto detail → `owasp` A02.

## P-3P Analytics & third parties
- **Look for:** PII in analytics/external API request bodies.
- **Fix:** hashed/pseudonymous id; strip PII before sending.
