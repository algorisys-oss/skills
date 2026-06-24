# Go — money signatures & fixes

net/http, gin/echo/fiber, database/sql, gorm over Postgres/MySQL. Triage each `scan.sh` hit here.
Format: **what to look for → why → fix (with safe code)**.

## M01 Float-for-money
- **Look for:** `float64`/`float32` fields named `Amount`/`Balance`/`Price`/`Total`,
  `strconv.ParseFloat` on money, gorm columns as `float`, JSON `float64` for amounts.
- **Why:** binary float rounding accumulates; reconciliation breaks.
- **Fix:** integer **minor units** as `int64`, or `github.com/shopspring/decimal`.
  ```go
  // BAD
  type Account struct { Balance float64 }
  // GOOD — minor units
  type Account struct { BalanceMinor int64 } // paise
  // or decimal
  import "github.com/shopspring/decimal"
  total := price.Mul(decimal.NewFromInt(qty)).Add(tax)
  ```
  Store as `BIGINT` (minor units) or `NUMERIC`; scan `NUMERIC` into `decimal.Decimal`, never `float64`.

## M02 Rounding
- **Look for:** `math.Round`, manual `*100`/`/100`, ad-hoc rounding per call site.
- **Fix:** `decimal.Decimal.Round(places)` / `RoundBank(places)` with a chosen mode at one boundary;
  allocate splits so rounded parts sum to the total.

## M03 Currency
- **Look for:** amounts with no currency; mixing currencies in arithmetic.
- **Fix:** an (amount, currency) struct or `github.com/Rhymond/go-money` (`money.New(amt, "INR")`),
  which errors on cross-currency ops.

## M04 Idempotency (see patterns.md)
- **Look for:** payment/transfer/refund handlers with no idempotency-key read; webhook handlers
  processing every call without dedup on the provider event id.
- **Fix:** persist the key with a `UNIQUE` constraint; return the stored result on replay.

## M05 Atomic balance update (see patterns.md)
- **Look for:** `SELECT balance` then a later `UPDATE` outside a `*sql.Tx`; gorm read then `Save`.
- **Fix:** single conditional update in a transaction:
  ```go
  res, err := tx.ExecContext(ctx,
      `UPDATE accounts SET balance_minor = balance_minor - $1 WHERE id = $2 AND balance_minor >= $1`,
      amt, id)
  n, _ := res.RowsAffected()
  if n == 0 { return ErrInsufficientFunds }   // no overdraft possible
  ```
  Or `SELECT … FOR UPDATE` within the tx; wrap debit+credit in one `tx`.

## M06 Ledger
- **Look for:** a transfer inserting one row; `UPDATE`/`DELETE` on a ledger table.
- **Fix:** insert all legs in one `tx`, assert they sum to zero, keep entries immutable.

## M07 Overflow
- **Look for:** `int32` for minor units on large totals.
- **Fix:** `int64` (or `decimal`); centralize the currency exponent instead of hardcoding `100`.

## M09 Trusting client/webhook amounts
- **Look for:** binding `Amount`/`Status` from the request and settling on it; webhook handlers with
  no signature verification.
- **Fix:** verify against the gateway; verify webhook signatures (see `resilience`, `owasp`).
