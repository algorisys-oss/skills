# Resilience — integration-specific expectations

Per-dependency reliability expectations for the integrations common in fintech/banking/ecommerce.
Use these to weight findings: the same "missing timeout" is Critical on a payment-capture path and
Medium on an analytics ping. Each integration cross-references `money-safety` where money correctness
is also at stake.

## Payment gateways (Razorpay, Stripe, PayU, Cashfree, Paytm, Adyen)
- Capture/charge/refund calls **must** carry an idempotency key (gateway-native, e.g. Stripe
  `Idempotency-Key`) so a retry never double-charges — `money-safety` M04. Set a timeout; retry only
  with the idempotency key.
- **Verify webhook signatures**; dedup on the gateway event id; ack fast, process async (R10).
- Never settle an order from a client-reported status — reconcile via the gateway's
  fetch/verify API (`money-safety` M09).
- Reconcile captured-vs-posted daily (`money-safety` M10).

## UPI / NPCI (PSP, switch, collect/pay)
- Strict timeouts and a defined **deemed-failure / pending** state — UPI responses can be delayed or
  ambiguous; never assume success on timeout. Drive resolution via status/callback APIs.
- Idempotent request ids; reconcile pending transactions; honor NPCI rate limits (R08).
- Handle the asynchronous callback and the polling fallback both (R09/R11).

## Credit bureaus (CIBIL, Experian, Equifax, CRIF)
- These are slow and quota-limited. **Timeout + circuit breaker** are essential so a bureau slowdown
  does not block onboarding workers (R01/R05). Cache pulls within the policy window; respect quotas
  (R08).
- Retries must be bounded and backed off; a pull is billable, so avoid accidental duplicate pulls
  (treat as effectively non-idempotent for cost — R03).

## KYC / AML vendors (video-KYC, doc OCR, liveness, sanctions/PEP screening)
- Long-running/async — use timeouts plus async callbacks, not a blocking wait (R01/R11). Bulkhead so
  a vendor outage does not starve the rest of the service (R06).
- De-dup callbacks; never auto-approve on vendor timeout — fail to manual review (R09). Overlaps
  `owasp` KYC checks and `audit-trail` AU02 (log the decision).

## SMS / email / notifications
- Lowest criticality but highest volume. Outbound throttling to the provider's rate (R08); retry
  with backoff to a dead-letter (R10); never block the main flow on a notification — enqueue it
  (R09). Idempotent send keys to avoid duplicate OTP/SMS storms.

## Datastores, cache, queue
- DB: bounded pool sized to the DB's capacity, acquisition timeout, statement timeout; release in
  `finally`/`defer` (R07). Cache: treat as optional — on cache failure fall back to source, do not
  fail the request (R09). Queue/broker: bounded consumers, visibility-timeout-aware idempotent
  consumers, dead-letter queues.

## Weighting cheat-sheet
- Synchronous + money-moving (gateway capture, UPI pay) → Critical for R01/R03/R10.
- Synchronous + slow third party (bureau, video-KYC) → High for R01/R05/R06.
- Asynchronous / best-effort (SMS, analytics) → Medium for R08/R09/R10.
