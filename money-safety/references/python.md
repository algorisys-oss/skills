# Python — money signatures & fixes

Django/DRF, Flask, FastAPI over Postgres/MySQL. Triage each `scan.sh` hit here.
Format: **what to look for → why → fix (with safe code)**.

## M01 Float-for-money
- **Look for:** `float(amount)`, money in plain `float`, `models.FloatField()` for money,
  `Decimal(0.1)` (constructing a Decimal *from a float* re-imports the error), JSON parsed to `float`.
- **Why:** `0.1 + 0.2 != 0.3`; errors accumulate.
- **Fix:** `decimal.Decimal` constructed **from strings**, or integer minor units; in Django use
  `DecimalField(max_digits=…, decimal_places=…)` or store minor units in a `BigIntegerField`.
  ```python
  from decimal import Decimal, ROUND_HALF_EVEN
  amount = Decimal(request.data["amount"])        # from str — exact; never Decimal(0.1)
  total  = (amount * qty).quantize(Decimal("0.01"), rounding=ROUND_HALF_EVEN)
  ```
  Consider `py-moneyed`/`django-money` for an (amount, currency) `Money` type.

## M02 Rounding
- **Look for:** `round()` (banker's rounding, and on floats), `quantize` with no explicit `rounding`,
  rounding each split before summing.
- **Fix:** `Decimal.quantize(exp, rounding=…)` with a chosen mode at one boundary; allocate splits so
  rounded parts sum to the total.

## M03 Currency
- **Look for:** amount fields with no currency; arithmetic across currencies.
- **Fix:** `py-moneyed` `Money(amount, "INR")` raises on cross-currency ops; store currency per amount.

## M04 Idempotency (see patterns.md)
- **Look for:** payment/transfer/refund views (DRF `APIView`/viewset, FastAPI routes) with no
  idempotency key; webhook endpoints processing every call without deduping the provider event id.
- **Fix:** persist the key with a `unique=True` / `UniqueConstraint`; return the stored response on
  replay. Use `select_for_update`-guarded get-or-create.

## M05 Atomic balance update (see patterns.md)
- **Look for:** `account.balance -= amt; account.save()` after a separate read (read-modify-write);
  no `transaction.atomic()` / `select_for_update()`.
- **Fix:**
  ```python
  from django.db import transaction
  from django.db.models import F
  with transaction.atomic():
      updated = Account.objects.filter(id=aid, balance__gte=amt).update(balance=F("balance") - amt)
      if not updated:            # 0 rows → insufficient funds
          raise InsufficientFunds()
  ```
  (`F()` makes it a single atomic UPDATE; the `balance__gte` filter blocks overdraft.)

## M06 Ledger
- **Look for:** a transfer writing one row; `.update()`/`.delete()` on ledger entries.
- **Fix:** post both legs inside `transaction.atomic()`, assert they sum to zero, keep entries immutable.

## M09 Trusting client/webhook amounts
- **Look for:** `request.data["amount"]`/`status` used to settle without server-side verification;
  webhook handlers without signature verification.
- **Fix:** verify against the gateway API; verify webhook signatures.
