---
name: resilience
description: Identify, explain, and (on request) fix reliability gaps in external integrations in Node.js, TypeScript, Python, Go, and Elixir code — HTTP/gRPC/DB calls with no timeout, retries without backoff/jitter, non-idempotent retries, missing circuit breakers/bulkheads, no rate limiting, unbounded connection pools, and fragile webhook handling. Use when the user asks to "run resilience", "resilience review", "check timeouts and retries", "circuit breaker audit", "integration reliability", or invokes /resilience. Built for fintech/banking/ecommerce integrations with payment gateways, UPI/NPCI, credit bureaus, and KYC/AML vendors.
user-invocable: true
---

# resilience

Find reliability gaps in external integrations in Node.js, TypeScript, Python, Go, and Elixir code,
explain each in context, and apply fixes when asked. Built for the calls that fail in production at
scale — payment gateways, UPI/NPCI, credit bureaus (CIBIL/Experian), KYC/AML vendors, SMS/email —
where a missing timeout cascades into an outage and a careless retry double-charges a customer.

This complements `money-safety` (idempotency of the *operation*) and `owasp` (security); resilience
covers the *transport* reliability around those calls and cross-references them. The category list
and severity rubric live in `references/catalog.md`. Integration-specific expectations live in
`references/integrations.md`. Per-language library signatures and fixes live in
`references/{nodejs,typescript,python,golang,elixir}.md`.

## Default behavior

- **Report, do not auto-modify.** Produce a findings report; apply fixes only when the user passes
  `--fix` or explicitly asks.
- **Default scope is the whole repository.** A path or flag narrows it.

## Invocation

```
/resilience                 Scan the whole repo, report findings
/resilience <path>          Scan a directory or file
/resilience --diff          Scan only changed files (uncommitted + branch vs base) — pre-commit/PR use
/resilience --staged        Scan only git-staged files
/resilience --fix [scope]   Scan, then apply fixes (still confirm anything risky — see step 5)
/resilience <topic>         e.g. "resilience check the bureau client", "do we retry the refund safely"
```

Parse the request into a **scope** and a **mode** (report — default — or fix). A focused topic (a
specific client/integration) narrows which files to weight.

## Workflow

### 1. Detect languages, HTTP/RPC clients & resilience libs
Identify the stack (manifests as in `owasp`). Note the **HTTP/RPC clients** in use (axios/fetch/got,
`httpx`/`requests`/`aiohttp`, `net/http`/resty, `HTTPoison`/`Finch`/`Req`/`Tesla`) and any
resilience libraries already present (`p-retry`/`opossum`/`cockatiel`, `tenacity`/`pybreaker`,
`sony/gobreaker`/`failsafe`, `:fuse`/`ExRated`). Load only the relevant `references/*.md`.

### 2. Run the heuristic pre-filter
Run the bundled scanner for candidate `file:line` locations. **High-recall, low-precision.**

```sh
scripts/scan.sh [PATH]        # default scope = path arg or "."
scripts/scan.sh --diff        # changed files only
scripts/scan.sh PATH --lang node|typescript|python|go|elixir
```

Output is `CATEGORY \t file:line \t matched text`. It flags external calls and retry loops; it
**cannot** see whether a timeout is configured globally, whether a breaker wraps a call, or whether
a retried operation is idempotent — reason about those in step 4.

### 3. Map the external dependencies
List every **outbound** dependency: third-party HTTP/gRPC APIs, the database, cache, queue/broker,
and object storage. For each, note whether it sits on a **synchronous request path** (a user is
waiting) — those are where a missing timeout or breaker does the most damage. The scanner gives
candidates; you build the dependency list.

### 4. Triage each integration in context
For each external call, check (read the matching `references/*.md` for the concrete fix):

- **Timeout** — does every call have a finite connect *and* read/overall timeout? A client with no
  timeout blocks a worker indefinitely and exhausts the pool. (Highest-yield check.)
- **Retries** — are retries bounded, with **exponential backoff + jitter**, and only on retryable
  errors (timeouts, 5xx, 429 — not 4xx)? A tight `for`-loop retry amplifies an outage (retry storm).
- **Idempotent retries** — is the retried call **safe to repeat**? Retrying a non-idempotent
  payment/transfer without an idempotency key can double-charge. (Cross-ref `money-safety` M04.)
- **Circuit breaker** — is a failing dependency wrapped so calls fail fast instead of piling up?
  Especially on synchronous request paths.
- **Bulkhead / pool limits** — are concurrency and connection pools bounded so one slow dependency
  cannot starve the whole service? Is the DB pool sized and acquisition time-bounded?
- **Rate limiting / quotas** — outbound limits to respect a vendor's quota; inbound limits on
  expensive endpoints (overlaps `owasp` A04).
- **Fallback / graceful degradation** — on failure, is there a sensible degraded path, or does the
  whole request fail? Are partial failures handled?
- **Webhooks** — are inbound webhooks verified, de-duplicated (idempotent), and acknowledged fast
  with processing deferred? Are outbound webhooks retried with backoff to a dead-letter?

### 5. Report findings
Group by severity (Critical → High → Medium → Low/Info; see `references/catalog.md`). For each:

- **Severity** and **confidence**.
- **Category** (e.g. `Missing timeout`, `Unbounded retry`, `Non-idempotent retry`, `No breaker`).
- **Location** — `file:line` as a clickable link.
- **What & why** — the failure mode in *this* code (e.g. "bureau call has no timeout → on a bureau
  slowdown every onboarding worker blocks → onboarding outage").
- **Fix** — concrete remediation (snippet from the language reference, adapted).

Lead with a one-line summary. If scope was narrowed (e.g. `--diff`) say so — never imply full
coverage that was not performed.

### 6. Fix (only when `--fix` or explicitly requested)
Apply the smallest correct fix using libraries already in the project. Then:

- Make low-risk, mechanical fixes directly — add a timeout to a client call, add backoff+jitter to
  an existing retry, cap a retry count, bound a connection pool, set an acquisition timeout.
- For changes that alter behavior — adding retries to a **non-idempotent** call (must add an
  idempotency key first — confirm with `money-safety`), introducing a circuit breaker (changes
  failure semantics and needs tuned thresholds), changing fallback behavior — explain and confirm
  first.
- Never retry a money-moving call without confirming it is idempotent. After fixing, re-run the scan
  and note anything needing load/chaos testing to validate.

## Boundaries

- This skill finds **pattern-detectable** transport-reliability gaps and reasons about design-level
  ones (breakers, bulkheads, idempotent retries). It is not load testing, chaos engineering, or an
  SRE capacity review — say so; these findings should be validated under load.
- Heuristics produce false positives (a call with a timeout set on a shared client instance the grep
  cannot see) and miss config-driven settings. Always confirm in context; disclose coverage.
- Idempotency of the *business operation* is owned by `money-safety`; this skill flags the
  *retry-safety* link and defers the ledger/payment correctness to it.

## Resources

- `references/catalog.md` — the reliability categories, descriptions, severity rubric.
- `references/integrations.md` — gateway / UPI-NPCI / bureau / KYC-vendor / SMS-email expectations.
- `references/nodejs.md` · `references/typescript.md` · `references/python.md` ·
  `references/golang.md` · `references/elixir.md` — per-language client/timeout/retry/breaker fixes.
- `scripts/scan.sh` — heuristic candidate finder (ripgrep/grep).
