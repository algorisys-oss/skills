# TypeScript — money signatures & fixes

Layered on `nodejs.md`. TypeScript's types are erased at runtime, so a `number` typed as `Money`
is still a float — the *type* does not make the arithmetic safe. Triage `.ts`/`.tsx` hits here.

## Types are not money safety
- **Look for:** `type Money = number`, `amount: number` on DTOs/entities, `JSON.parse(body) as
  Payment` where `Payment.amount: number`, `Number(req.body.amount)`.
- **Why:** a branded-number type compiles away; the runtime value is still IEEE-754, and external
  JSON gives you a `number` regardless of the annotation.
- **Fix:** represent money as `bigint` minor units or a decimal class instance, validated at the
  boundary with Zod/class-validator (not a cast).
  ```ts
  // BAD — type says Money, runtime is a float
  type Money = number
  const total: Money = price * qty

  // GOOD — bigint minor units, parsed from a string at the edge
  const AmountSchema = z.string().regex(/^\d+$/).transform(BigInt)  // paise as string → bigint
  const amount: bigint = AmountSchema.parse(req.body.amountMinor)
  ```

## Decimal columns typed as number
- **Look for:** ORM entities declaring a `NUMERIC`/`DECIMAL` column as `number` (TypeORM
  `@Column('decimal') amount: number`, Prisma field read into `number`).
- **Why:** the driver may hand back a JS `number` and silently lose precision on large values.
- **Fix:** map decimal columns to a string/`Decimal`/`bigint` transformer; configure the driver to
  return strings for `NUMERIC` and wrap in `decimal.js`/`bignumber.js`.

## `as` casts on money input
- **Look for:** `req.body.amount as number`, `as Money`, `as any` around amounts.
- **Fix:** validate and convert at the boundary; never cast untrusted money input — parse it.

See `patterns.md` for idempotency, atomic updates, and the double-entry invariant (same as Node).
