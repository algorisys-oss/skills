# Resilience catalog

Reliability categories for external integrations in high-scale fintech/ecommerce systems. Each
entry: **ID — Name** · what it is · why it matters · severity baseline. These are *availability and
correctness-under-failure* gaps, not security bugs. Detection signatures and fixes are in the
per-language references; integration-specific expectations are in `integrations.md`.

## R01 — Missing timeout
An HTTP/gRPC/DB/cache call with no connect and no read/overall timeout (or an infinite default). A
single slow or hung dependency blocks the calling worker forever; under load every worker ends up
blocked on it and the whole service stops serving — a cascading outage from one slow dependency.
**Fix:** set finite connect + read (or overall deadline) timeouts on every outbound call; propagate
a request deadline/`context`. **Severity: High–Critical** (Critical on a synchronous request path).

## R02 — Unbounded / naive retry (retry storm)
Retries with no cap, no backoff, or no jitter — a tight loop that hammers a struggling dependency,
amplifying a partial outage into a full one and synchronising clients into thundering herds.
**Fix:** bounded attempts, **exponential backoff with jitter**, and a per-call total deadline.
**Severity: High.**

## R03 — Non-idempotent retry
Retrying (or letting a client/library auto-retry) a **non-idempotent** operation — a payment,
transfer, refund, order placement — without an idempotency key, so a timeout-then-retry executes it
twice. A double charge/credit. Cross-references `money-safety` M04.
**Fix:** make the operation idempotent (idempotency key + server-side dedup) **before** retrying;
only auto-retry idempotent verbs. **Severity: Critical.**

## R04 — Retrying non-retryable errors
Retrying on `4xx`/validation/auth errors (which will never succeed) wastes time and can lock
accounts; or *not* retrying genuinely transient errors (timeouts, `429`, `5xx`, connection reset).
**Fix:** classify errors; retry only transient ones; honor `Retry-After` on `429`/`503`.
**Severity: Medium.**

## R05 — No circuit breaker
A dependency that keeps being called while it is down, so requests pile up, latency climbs, and the
failure spreads upstream. No fail-fast path.
**Fix:** wrap unreliable dependencies (especially on sync paths) in a circuit breaker that opens on
a failure threshold and fails fast while open, with a half-open probe. **Severity: Medium–High.**

## R06 — No bulkhead / unbounded concurrency
One slow dependency consumes all threads/connections/event-loop capacity, starving unrelated work
(no isolation). Or an unbounded outbound concurrency that overwhelms a vendor.
**Fix:** isolate dependencies into bounded pools/semaphores (bulkheads); cap outbound concurrency.
**Severity: Medium–High.**

## R07 — Unbounded or mis-sized connection pool
A DB/HTTP pool with no max, no acquisition timeout, or sized larger than the dependency can serve;
connections leaked on error paths. Leads to pool exhaustion or overwhelming the database.
**Fix:** bound pool size to the dependency's capacity, set an acquisition timeout, ensure release in
`finally`/`defer`. **Severity: Medium–High.**

## R08 — Missing rate limiting / quota handling
No inbound rate limiting on expensive/abusable endpoints (overlaps `owasp` A04), or no outbound
throttling to respect a vendor's quota, leading to `429` storms or vendor bans.
**Fix:** token-bucket/sliding-window inbound limits; client-side outbound throttling; back off on
`429`. **Severity: Medium.**

## R09 — No fallback / graceful degradation
On a dependency failure the whole request fails when a degraded path was possible (cached value,
queued-for-later, default, skip-and-continue). Or partial failures in fan-out are not handled.
**Fix:** define explicit fallbacks per dependency; degrade rather than fail where business rules
allow; handle partial fan-out results. **Severity: Medium.**

## R10 — Fragile webhook handling
**Inbound:** webhooks processed synchronously in the handler (slow ack → provider retries →
duplicate processing), not de-duplicated, or not signature-verified. **Outbound:** webhooks sent
with no retry/backoff/dead-letter, so a transient receiver failure loses the event.
**Fix:** verify + dedup (idempotent) + ack fast + process async (inbound); retry with backoff to a
dead-letter (outbound). Cross-refs `money-safety` M04/M09 and `owasp`. **Severity: High.**

## R11 — No deadline propagation / cancellation
Long call chains where an upstream timeout does not cancel downstream work, so abandoned requests
keep consuming resources (no `context`/`AbortSignal`/cancellation token threaded through).
**Fix:** propagate a deadline/cancellation across the chain; stop work when the caller has given up.
**Severity: Medium.**

## Severity guidance for reporting

- **Critical** — missing timeout on a synchronous external/DB call; non-idempotent retry of a
  money-moving operation.
- **High** — retry storms, fragile money webhooks, missing breaker on a critical sync dependency.
- **Medium** — pool/bulkhead/rate-limit/fallback/deadline-propagation gaps.
- **Low / Info** — hardening, tuning, defense-in-depth.

Confidence ≠ severity. A missing-timeout hit where a timeout may be set on a shared client is
"High / needs confirmation" until you have read the client construction.
