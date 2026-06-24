# TypeScript — resilience signatures & fixes

Layered on `nodejs.md` (same runtime/clients). The TS-specific angle is using the type system and
NestJS/`cockatiel` to make resilience *structural* rather than per-call discipline.

## Centralise the policy, type the boundary
- **Look for:** timeouts/retries set ad-hoc per call site; a shared axios/`got` instance created
  with no defaults; `any`-typed responses that hide error classification.
- **Fix:** construct one configured client with defaults and reuse it; classify errors with a typed
  result (`Result<T, E>` / discriminated union) so retryable vs non-retryable is explicit.
  ```ts
  export const http = axios.create({ timeout: 3000 })   // default timeout for every call
  // cockatiel: compose retry + breaker + timeout into one typed policy
  import { retry, circuitBreaker, timeout, wrap, handleAll, ExponentialBackoff, TimeoutStrategy } from 'cockatiel'
  export const gatewayPolicy = wrap(
    timeout(3000, TimeoutStrategy.Aggressive),
    retry(handleAll, { maxAttempts: 4, backoff: new ExponentialBackoff() }),
    circuitBreaker(handleAll, { halfOpenAfter: 10_000, breaker: /* … */ }),
  )
  await gatewayPolicy.execute(({ signal }) => callGateway(payload, { idempotencyKey, signal }))
  ```

## NestJS
- **Look for:** `HttpModule`/`HttpService` with no `timeout`; no global timeout interceptor.
- **Fix:** `HttpModule.register({ timeout: 3000, maxRedirects: 2 })`; add a `TimeoutInterceptor`
  (RxJS `timeout()` operator) for inbound request deadlines; wrap external calls in a policy as above.

## Idempotency typing
- **Look for:** retryable client wrappers that accept any operation, including non-idempotent ones.
- **Fix:** require an `idempotencyKey` in the type signature of any retried money-moving call so the
  compiler forces it (`callGateway(payload: Charge, opts: { idempotencyKey: string })`). See
  `money-safety` M04.

For timeouts, pools, breakers, and webhooks see `nodejs.md` — identical runtime.
