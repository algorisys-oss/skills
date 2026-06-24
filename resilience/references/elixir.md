# Elixir — resilience signatures & fixes

Phoenix, `HTTPoison`/`Finch`/`Req`/`Tesla`, Ecto/`DBConnection` pools, Oban/Broadway. Triage each
`scan.sh` hit here. The BEAM gives you supervision and process isolation for free, but external
calls still need explicit timeouts and breakers. Libraries: `:fuse` (breaker), `ExRated` (rate
limit), `Tesla.Middleware.{Timeout,Retry}`.

## R01 Missing timeout
- **Look for:** `HTTPoison.get(url)` with no `recv_timeout`/`timeout`; `Tesla` clients without
  `Tesla.Middleware.Timeout`; `GenServer.call` with the default 5s where the work is longer or with
  `:infinity`; Ecto queries without `:timeout`.
- **Fix:**
  ```elixir
  HTTPoison.get(url, [], timeout: 3_000, recv_timeout: 5_000)
  # Tesla
  plug Tesla.Middleware.Timeout, timeout: 5_000
  # Finch
  Finch.build(:get, url) |> Finch.request(MyFinch, receive_timeout: 5_000)
  ```

## R02 Unbounded retry → R03 idempotency
- **Look for:** hand-rolled recursive retry with no cap/backoff; `Tesla.Middleware.Retry` on
  non-idempotent requests.
- **Fix:** `Tesla.Middleware.Retry` (bounded `max_retries`, exponential `delay`, jitter) for
  idempotent calls; for jobs use Oban's backoff. Never retry a money-moving call without an
  idempotency key (`money-safety` M04).

## R05 Circuit breaker
- **Fix:** `:fuse` — `:fuse.install(:bureau, {{:standard, 5, 10_000}, {:reset, 30_000}})`, check
  `:fuse.ask/2` before calling, `:fuse.melt/1` on failure; fall back when blown.

## R06/R07 Bulkhead & pools
- **Look for:** `Finch`/`DBConnection`/`Ecto` pool sizes unset or oversized; unbounded
  `Task.async_stream` with no `max_concurrency`.
- **Fix:** size the Finch pool (`pools: %{default: %{size: ...}}`) and Ecto `pool_size`/
  `queue_target`/`queue_interval`; bound fan-out with `Task.async_stream(..., max_concurrency: n,
  timeout: ...)`.

## R08 Rate limiting
- **Fix:** `ExRated`/`PlugAttack` inbound; `ExRated` token bucket for outbound vendor quotas;
  honor `Retry-After`.

## R10 Webhooks
- **Look for:** webhook controllers doing heavy work inline; no signature verify; no dedup.
- **Fix:** verify signature, dedup on event id (`unique_constraint`), enqueue to Oban, return 200
  fast. Outbound: Oban job with bounded retries/backoff and a dead-letter (discarded → alert).

## R11 Cancellation / deadlines
- **Look for:** long `Task` chains with no overall deadline.
- **Fix:** wrap with `Task.await(task, timeout)`/`Task.yield` + `Task.shutdown`; propagate a deadline
  budget through the call chain.
