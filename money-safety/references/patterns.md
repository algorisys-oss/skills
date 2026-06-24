# Money-safety patterns — idempotency, atomicity, double entry

Language-agnostic patterns for the design-level categories the scanner cannot grep
(M04–M06, M10). Triage each money flow from the SKILL.md workflow against these.

## Idempotency keys (M04)

A value-moving endpoint must execute **at most once** per logical request, even under client
retries, gateway webhook re-deliveries, and network failures.

**Pattern:**
1. The caller supplies an idempotency key (header `Idempotency-Key`, or a deterministic key derived
   from the business event — e.g. `order_id + ":capture"`).
2. Persist `(scope, idempotency_key)` with a **`UNIQUE` constraint** in the same transaction that
   performs the operation. The unique constraint is what makes it safe under concurrency — an
   application-level "have I seen this key?" check still races.
3. On a duplicate key, return the **stored** result of the first execution; do not re-execute.

```sql
CREATE TABLE idempotency_keys (
  scope        text NOT NULL,            -- e.g. 'payment.capture'
  key          text NOT NULL,
  response     jsonb,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scope, key)
);
```

```sql
-- Inside the operation's transaction:
INSERT INTO idempotency_keys (scope, key) VALUES ('payment.capture', :key);
-- If this raises a unique-violation, the operation already ran: load and return stored response.
```

**Red flags:** an idempotency check done in app code with no DB unique constraint; a key scoped too
broadly (one key reused across distinct operations) or too narrowly (timestamp in the key, so
retries never match); webhooks processed without dedup on the provider's event id.

## Atomic balance updates (M05)

Never read a balance, decide in application code, then write it back in a separate statement.

```sql
-- BAD: read-modify-write race (two requests both pass the check)
SELECT balance FROM accounts WHERE id = :id;        -- app checks balance >= amt
UPDATE accounts SET balance = balance - :amt WHERE id = :id;

-- GOOD: single conditional update, the DB enforces the invariant
UPDATE accounts
   SET balance = balance - :amt
 WHERE id = :id AND balance >= :amt;
-- rows affected = 0  =>  insufficient funds, reject. No overdraft possible.
```

Alternatives, all valid:
- `SELECT … FOR UPDATE` on the account row at the start of the transaction (pessimistic lock).
- Optimistic locking: a `version` column, `UPDATE … WHERE id = :id AND version = :v`, retry on 0 rows.
- A `CHECK (balance >= 0)` constraint as a last-line backstop.

Pick one and apply it consistently. Wrap any multi-row money move (debit one account, credit
another) in **one** transaction so it cannot half-apply.

## Double-entry ledger invariant (M06)

In a double-entry ledger, every business transaction posts ≥2 entries whose signed amounts **sum to
zero** (debits balance credits), atomically, append-only.

```
transaction T:
  entry(account=user_wallet,    amount=-1000, currency=INR)   -- debit
  entry(account=merchant_payable, amount=+1000, currency=INR)   -- credit
  assert sum(entry.amount for entry in T) == 0   -- before commit
```

Rules to check:
- All legs inserted in **one** transaction; never a partial posting.
- `sum(amounts) == 0` per transaction (per currency) asserted before commit, ideally also enforced
  by a deferred constraint or a posting service that refuses to write an unbalanced set.
- Ledger rows are **immutable** — no `UPDATE`/`DELETE`. Corrections are new reversing entries.
- A balance is *derived* (sum of entries) or a cached column reconciled against the entry sum.

**Red flags:** a single-row "transfer" with no opposing entry; `UPDATE ledger SET amount = …`;
balances stored as the source of truth with no entries backing them.

## Outbox / reconciliation (M10)

When a money flow spans systems (gateway capture → ledger post → notify), a crash between steps
leaves them inconsistent. Use a **transactional outbox**: write the side-effect intent in the same
DB transaction as the state change, then a worker delivers it with retries; and a **reconciliation
job** that periodically compares gateway settlement reports, ledger balances, and order state and
flags mismatches. Never rely on "the next line of code will run" across a process or network boundary.
