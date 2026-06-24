# Go — resilience signatures & fixes

`net/http`, resty, gin/echo/fiber, `database/sql`/gorm/pgx pools. Triage each `scan.sh` hit here.
Libraries: `sony/gobreaker` / `mercari/go-circuitbreaker` (breaker), `cenkalti/backoff` /
`avast/retry-go` (retry), `golang.org/x/time/rate` (rate limit). Go's idiom is `context` deadlines.

## R01 Missing timeout / deadline
- **Look for:** `http.Get(...)` / `http.DefaultClient` (no timeout); `&http.Client{}` with no
  `Timeout`; calls with `context.Background()`/`context.TODO()` on a request path (no deadline);
  `db.Query` without a `Context`.
- **Fix:**
  ```go
  client := &http.Client{ Timeout: 5 * time.Second }
  ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second); defer cancel()
  req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
  rows, err := db.QueryContext(ctx, q, args...)   // deadline flows to the DB
  ```
  Set transport-level `DialContext`/`ResponseHeaderTimeout` for connect vs read separation.

## R02 Unbounded retry → R03 idempotency
- **Look for:** `for { ... }` retry loops with no cap/backoff.
- **Fix:** `cenkalti/backoff` (exponential + jitter, bounded) or `avast/retry-go`; only retry
  idempotent calls; respect `ctx` cancellation. Never retry a money-moving call without an
  idempotency key (`money-safety` M04).

## R05 Circuit breaker
- **Fix:** `gobreaker.NewCircuitBreaker(gobreaker.Settings{MaxRequests, Interval, Timeout,
  ReadyToTrip})`; wrap the call, return a fallback when open.

## R06/R07 Bulkhead & pools
- **Look for:** `db.SetMaxOpenConns` unset (unbounded); no `SetConnMaxLifetime`; unbounded goroutine
  fan-out over a dependency.
- **Fix:** `db.SetMaxOpenConns(n)`, `SetMaxIdleConns`, `SetConnMaxLifetime`; bound goroutines with a
  worker pool or `golang.org/x/sync/semaphore`; cap HTTP transport `MaxConnsPerHost`.

## R08 Rate limiting
- **Fix:** `rate.NewLimiter` for outbound throttling; middleware limiter inbound; honor `Retry-After`.

## R10 Webhooks
- **Look for:** webhook handlers doing heavy work before responding; no signature verify; no dedup.
- **Fix:** verify signature, dedup on event id, enqueue, `w.WriteHeader(200)` fast, process async.
  Outbound: bounded retry + backoff to a dead-letter.

## R11 Cancellation
- **Look for:** downstream calls not receiving the request `ctx`.
- **Fix:** thread `r.Context()` (or a derived deadline) through every downstream call so an
  abandoned request cancels its work.
