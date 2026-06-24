# Node.js — money signatures & fixes

Express/Nest/Fastify backends with Prisma/Knex/TypeORM/Sequelize over Postgres/MySQL/Mongo.
Triage each `scan.sh` hit here. Format: **what to look for → why → fix (with safe code)**.
(For `.ts` specifics — casts, JSON.parse typing — also read `typescript.md`.)

## M01 Float-for-money
- **Look for:** `Number(amount)`, `parseFloat(price)`, arithmetic on `amount`/`balance`/`total`
  declared as plain `number`, money columns typed `float`/`double`/`real` in the schema, money sent
  as JS numbers over JSON (`JSON.parse` → `number`).
- **Why:** IEEE-754 cannot represent `0.10` exactly; sums drift and break reconciliation.
- **Fix:** integer **minor units** (`BigInt` for large totals) or a money library.
  ```js
  // BAD
  const total = price * qty + tax            // floats
  // GOOD — integer minor units (paise)
  const totalPaise = pricePaise * qty + taxPaise   // exact
  // or a library
  import Dinero from 'dinero.js'
  Dinero({ amount: 1099, currency: 'INR' }).add(Dinero({ amount: 200, currency: 'INR' }))
  ```
  Store as `BIGINT` (minor units) or `NUMERIC(precision, scale)`; never `float8`. In Prisma use
  `Decimal` (`@db.Decimal`)/`BigInt`, not `Float`.

## M02 Rounding
- **Look for:** `Math.round`/`toFixed` scattered across services, `* 100`/`/ 100` conversions with
  no single helper, rounding each split before summing.
- **Fix:** one money module with an explicit mode; allocate splits so they sum to the total.
  ```js
  // dinero.js distributes remainder so parts sum to the whole
  const [a, b, c] = Dinero({ amount: 10000, currency: 'INR' }).allocate([1, 1, 1])
  ```

## M03 Currency
- **Look for:** amounts with no currency field; adding/comparing two money values without checking
  currency; a single `amount` column and no `currency` column.
- **Fix:** carry `(amount, currency)`; a money library throws on cross-currency ops. Persist
  currency alongside every amount.

## M04 Idempotency (see patterns.md)
- **Look for:** `router.post('/payments'…)`, `/transfer`, `/refund`, `/charge` handlers with no
  idempotency-key read; webhook handlers (`/webhooks/razorpay`, `/stripe`) that process every
  delivery without deduping on the provider event id.
- **Fix:** require `Idempotency-Key`, persist with a `UNIQUE` constraint, return stored result on
  replay; dedup webhooks on `event.id`.

## M05 Atomic balance update (see patterns.md)
- **Look for:** a `SELECT balance` / `findUnique` followed by a separate `UPDATE`/`update` outside a
  transaction; `prisma.$transaction` absent around a debit+credit pair.
- **Fix:** conditional update or `SELECT … FOR UPDATE` inside `prisma.$transaction` / Knex
  `trx`. `UPDATE accounts SET balance = balance - $1 WHERE id = $2 AND balance >= $1`.

## M06 Ledger
- **Look for:** a "transfer" writing one row; `UPDATE`/`delete` on a ledger/entries table.
- **Fix:** post both legs in one `$transaction`, assert the legs sum to zero, keep entries immutable.

## M09 Trusting client/webhook amounts
- **Look for:** `req.body.amount`/`amountPaid`/`status` used to settle without re-verifying against
  the gateway; webhook handlers with no signature verification.
- **Fix:** verify via server-side capture/verify API; verify webhook signatures (see `resilience`
  and `owasp`). Never trust a client-sent amount.
