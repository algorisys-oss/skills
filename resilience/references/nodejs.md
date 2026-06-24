# Node.js — resilience signatures & fixes

axios/fetch/got/undici clients, Express/Nest/Fastify, `pg`/Prisma pools, BullMQ/SQS. Triage each
`scan.sh` hit here. Format: **what to look for → why → fix (with safe code)**.
Libraries: `p-retry`/`cockatiel` (retry), `opossum`/`cockatiel` (breaker), `bottleneck` (rate/concurrency).

## R01 Missing timeout
- **Look for:** `axios.get/post(...)` with no `timeout`; `fetch(url)` with no `AbortSignal`; `got`
  without `timeout`; DB queries with no statement timeout.
- **Fix:**
  ```js
  axios.get(url, { timeout: 3000 })                          // ms
  await fetch(url, { signal: AbortSignal.timeout(3000) })    // Node 18+
  // pg: statement_timeout on the pool; Prisma: ?connect_timeout=...&pool_timeout=...
  ```

## R02 Unbounded retry → R03 idempotency
- **Look for:** hand-rolled `for`/`while` retry loops; axios-retry/got retries on POST; `p-retry`
  with no backoff.
- **Fix:** bounded attempts + exponential backoff + jitter; only retry idempotent calls.
  ```js
  import pRetry from 'p-retry'
  await pRetry(() => callGateway(payload, { idempotencyKey }), {
    retries: 4, factor: 2, minTimeout: 200, maxTimeout: 3000, randomize: true,  // jitter
  })
  ```
  Never auto-retry a POST that moves money without an idempotency key (`money-safety` M04).

## R05 Circuit breaker
- **Look for:** repeated direct calls to a flaky dependency with no breaker.
- **Fix:** `opossum`:
  ```js
  import CircuitBreaker from 'opossum'
  const breaker = new CircuitBreaker(callBureau, { timeout: 3000, errorThresholdPercentage: 50, resetTimeout: 10000 })
  breaker.fallback(() => cachedScore)
  ```

## R06/R07 Bulkhead & pools
- **Look for:** `new Pool()` with no `max`/`connectionTimeoutMillis`; unbounded `Promise.all` fan-out
  over a dependency; no concurrency cap on outbound calls.
- **Fix:** `pg` `new Pool({ max: 10, connectionTimeoutMillis: 2000 })`; cap concurrency with
  `bottleneck` / `p-limit`; release clients in `finally`.

## R10 Webhooks
- **Look for:** webhook routes doing heavy work inline; no signature verify; no dedup on event id.
- **Fix:** verify signature, dedup on provider event id (unique constraint), enqueue and return
  `200` fast, process async. Outbound: retry with backoff to a dead-letter.

## R11 Deadline propagation
- **Look for:** `AbortSignal` not threaded from the inbound request into outbound calls.
- **Fix:** create one signal per request (`AbortSignal.timeout` + `AbortSignal.any`) and pass it down.
