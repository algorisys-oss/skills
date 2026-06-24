# Elixir — money signatures & fixes

Phoenix / Ecto over Postgres. Triage each `scan.sh` hit here.
Format: **what to look for → why → fix (with safe code)**.

## M01 Float-for-money
- **Look for:** `:float` Ecto field types for money, `String.to_float/1` on amounts, arithmetic on
  floats, `field :amount, :float`.
- **Why:** float rounding accumulates; reconciliation breaks.
- **Fix:** `Decimal` (`:decimal` Ecto type) or the `ex_money` library; or integer minor units.
  ```elixir
  # BAD
  field :amount, :float
  # GOOD
  field :amount, :decimal            # Ecto maps to NUMERIC
  # or ex_money (amount + currency)
  field :amount, Money.Ecto.Composite.Type
  Money.add!(Money.new(:INR, "10.00"), Money.new(:INR, "2.00"))
  ```

## M02 Rounding
- **Look for:** `Float.round/2`, manual `* 100`/`/ 100`, rounding splits before summing.
- **Fix:** `Decimal.round(d, places, :half_even)` with a chosen mode at one boundary;
  `Money.split/2` (ex_money) allocates remainder so parts sum to the total.

## M03 Currency
- **Look for:** amounts with no currency; mixing currencies.
- **Fix:** `ex_money`'s `Money` type carries currency and refuses cross-currency arithmetic.

## M04 Idempotency (see patterns.md)
- **Look for:** payment/transfer/refund controller actions with no idempotency key; webhook
  controllers processing every delivery without dedup on the provider event id.
- **Fix:** insert the key with a `unique_constraint`; on `{:error, changeset}` for the unique
  violation, return the stored result.

## M05 Atomic balance update (see patterns.md)
- **Look for:** `Repo.get` balance then a separate `Repo.update`; no `Ecto.Multi`/transaction;
  no row lock.
- **Fix:** single conditional update inside a transaction, or `lock: "FOR UPDATE"`:
  ```elixir
  from(a in Account, where: a.id == ^id and a.balance >= ^amt)
  |> Repo.update_all(inc: [balance: -amt])
  |> case do
       {1, _} -> :ok
       {0, _} -> {:error, :insufficient_funds}   # no overdraft
     end
  ```
  Wrap debit+credit in one `Ecto.Multi`/`Repo.transaction`.

## M06 Ledger
- **Look for:** a transfer inserting one entry; `Repo.update`/`Repo.delete` on ledger entries.
- **Fix:** insert all legs in one `Ecto.Multi`, assert they sum to zero, keep entries immutable.

## M09 Trusting client/webhook amounts
- **Look for:** settling from `params["amount"]`/`status` without server-side verification; webhook
  controllers without signature verification.
- **Fix:** verify against the gateway; verify webhook signatures (see `resilience`, `owasp`).
