# Python — resilience signatures & fixes

`requests`/`httpx`/`aiohttp`, Django/DRF/FastAPI/Flask, SQLAlchemy/Django ORM pools, Celery. Triage
each `scan.sh` hit here. Libraries: `tenacity` (retry), `pybreaker` (breaker), `slowapi`/`limits`
(rate limiting), `aiolimiter` (async throttle).

## R01 Missing timeout
- **Look for:** `requests.get/post(...)` with no `timeout=` (the default is **no timeout** — blocks
  forever); `httpx`/`aiohttp` clients with no timeout; `urlopen` without `timeout`.
- **Fix:**
  ```python
  requests.get(url, timeout=(3.05, 10))                 # (connect, read)
  httpx.Client(timeout=httpx.Timeout(10.0, connect=3.0))
  aiohttp.ClientTimeout(total=10, connect=3)
  ```

## R02 Unbounded retry → R03 idempotency
- **Look for:** `while True` retry loops; `urllib3 Retry` on POST; `tenacity` with no wait/stop.
- **Fix:** `tenacity` with bounded stop + exponential backoff + jitter, retry only transient errors:
  ```python
  from tenacity import retry, stop_after_attempt, wait_exponential_jitter, retry_if_exception_type
  @retry(stop=stop_after_attempt(5), wait=wait_exponential_jitter(initial=0.2, max=3),
         retry=retry_if_exception_type((httpx.TimeoutException, httpx.TransportError)))
  def fetch(): ...
  ```
  Never auto-retry a non-idempotent payment without an idempotency key (`money-safety` M04).

## R05 Circuit breaker
- **Fix:** `pybreaker.CircuitBreaker(fail_max=5, reset_timeout=10)` as a decorator around the call;
  provide a fallback.

## R06/R07 Bulkhead & pools
- **Look for:** `requests.Session` reused without a pool cap; SQLAlchemy `create_engine` with no
  `pool_size`/`pool_timeout`; Django `CONN_MAX_AGE` unset; unbounded `asyncio.gather` fan-out.
- **Fix:** `httpx.Limits(max_connections=20, max_keepalive_connections=10)`;
  `create_engine(url, pool_size=10, max_overflow=5, pool_timeout=3, pool_pre_ping=True)`; cap async
  concurrency with `asyncio.Semaphore`/`aiolimiter`.

## R08 Rate limiting
- **Fix:** inbound `slowapi`/DRF throttling on expensive endpoints; outbound `aiolimiter`/`limits`
  to respect vendor quotas; honor `Retry-After` on 429.

## R10 Webhooks
- **Look for:** webhook views doing heavy work inline; no signature verify; no dedup.
- **Fix:** verify signature, dedup on event id (unique constraint), enqueue to Celery, return 200
  fast. Outbound: Celery task with bounded retries/backoff and a dead-letter.
