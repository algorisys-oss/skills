# Money-safety catalog

Financial-correctness categories that recur in banking/NBFC/fintech/ecommerce code. Each entry:
**ID — Name** · what it is · why it matters · severity baseline. These are *correctness* bugs:
the code is not necessarily insecure, but it can move the wrong amount, move it twice, or fail to
balance. Detection signatures and fixes are in the per-language references and `patterns.md`.

## M01 — Float / double used for money
Storing or computing monetary amounts in binary floating point (`float`, `double`, JS `number`,
Python `float`). `0.1 + 0.2 != 0.3`; errors accumulate over many postings and break reconciliation.
**Fix:** integer **minor units** (paise/cents as `int64`/`BigInt`) or a decimal type
(`Decimal`/`dinero`/`shopspring`). Never `JSON.parse` a money string into a JS `number`.
**Severity: High–Critical** (Critical for ledger/balance storage).

## M02 — Rounding errors / inconsistent rounding
No explicit rounding mode, rounding applied in multiple places, or rounding before summing so the
parts no longer equal the whole. Classic: split a ₹100 bill three ways, round each to ₹33.33, sum =
₹99.99, ₹0.01 lost. Banker's rounding (half-even) vs half-up chosen inconsistently across services.
**Fix:** one explicit rounding mode at one boundary; use a "largest remainder"/allocation helper for
splits so rounded parts sum to the rounded total. **Severity: High.**

## M03 — Currency mismatch / missing currency
Amounts without an attached currency, or arithmetic across currencies (`usd + inr`) with no
conversion. Comparing or summing mixed-currency values silently produces nonsense.
**Fix:** money is an (amount, currency) pair; reject operations on differing currencies; convert
explicitly through a rate with a recorded timestamp. **Severity: High.**

## M04 — Missing idempotency on value-moving endpoints
A payment / transfer / refund / charge endpoint that a client (or a gateway webhook, or a retry)
can call twice, executing the operation twice — a double charge or double credit. No idempotency
key, or a key that is checked but not enforced by a unique constraint (so a race still duplicates).
**Fix:** require an idempotency key, persist it with a `UNIQUE` constraint, return the stored result
on replay. See `patterns.md`. **Severity: Critical.**

## M05 — Non-atomic balance update / read-modify-write race
`balance = read(); if (balance >= amt) write(balance - amt)` without a transaction + lock. Two
concurrent requests both read the old balance and both succeed → overdraft / double-spend. Same
shape as `owasp` Cat 19 (TOCTOU) but specific to balances and limits.
**Fix:** do it in one transaction with `SELECT … FOR UPDATE`, an atomic `UPDATE … SET balance =
balance - :amt WHERE balance >= :amt`, optimistic version column, or a DB CHECK constraint. See
`patterns.md`. **Severity: Critical.**

## M06 — Double-entry / ledger imbalance
A ledger where postings do not sum to zero per transaction (total debits ≠ total credits), entries
are inserted outside a single transaction (partial posting on crash), or rows are mutable
(`UPDATE`/`DELETE` on a ledger instead of reversing entries).
**Fix:** post all legs of a transaction atomically; assert `sum(debits) == sum(credits)` before
commit; make ledger tables append-only and correct via reversing entries. See `patterns.md`.
**Severity: High–Critical.**

## M07 — Integer overflow / unit confusion on minor units
Minor-unit math in a type too small (e.g. 32-bit cents overflow on large totals), or mixing major
and minor units (adding rupees to paise), or a wrong scale factor (`* 100` vs `* 1000` for 3-dp
currencies like BHD/KWD).
**Fix:** use 64-bit integers (or arbitrary precision) for minor units; centralize unit conversion;
encode the currency's exponent rather than hardcoding `100`. **Severity: Medium–High.**

## M08 — Business-date / timezone errors in settlement
Interest, settlement, statement, or cutoff logic using `now()`/server local time instead of a
defined business date and timezone, so a transaction lands in the wrong day/cycle near midnight or
across DST.
**Fix:** compute against an explicit business date in a defined timezone (often IST/UTC per policy);
store timestamps in UTC; make cutoffs explicit. **Severity: Medium–High.**

## M09 — Unverified / unsafe external money signals
Trusting a client-supplied amount or status, or a gateway webhook, without verifying it against the
server's record or the gateway's signature/API. E.g. honoring `req.body.amountPaid`, or marking an
order paid from an unverified webhook.
**Fix:** treat client amounts as untrusted; reconcile against the gateway via server-side
capture/verify; verify webhook signatures (overlaps `owasp` and the `resilience`/webhook checks).
**Severity: High–Critical.**

## M10 — Missing reconciliation / silent partial failure
Multi-step money flows (charge → ledger → notify) where a later step can fail leaving the system
inconsistent, with no reconciliation or outbox to detect/repair it. Money captured at the gateway
but never posted to the ledger, or vice versa.
**Fix:** transactional outbox / saga with compensation; a reconciliation job comparing gateway,
ledger, and order state. **Severity: High.**

## Severity guidance for reporting

- **Critical** — can double-move money (missing idempotency, balance race), corrupt a stored
  balance/ledger (float storage, imbalance), or honor an unverified amount.
- **High** — rounding/currency errors that drift balances, ledger entries that can post partially,
  trusting client/webhook amounts without verification.
- **Medium** — overflow risk not yet reachable, business-date edge cases, defense-in-depth gaps.
- **Low / Info** — style/precision hardening with no current money impact.

Confidence ≠ severity. A Critical category found via a low-confidence grep hit is "Critical /
needs confirmation", not a definitive finding — trace the flow first.
