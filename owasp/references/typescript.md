# TypeScript — signatures & fixes

TypeScript backends (Express/Fastify/Koa/**NestJS**) and frontends (React/SolidJS) get the **full
sink coverage of `nodejs.md`, `react.md`, and `solidjs.md`** — the scanner runs those patterns on
`.ts`/`.tsx` files already. This file covers the one class of risk that is **specific to TypeScript**:
the type system creates a false sense of security because **types are erased at runtime**.

## The core trap — types are NOT runtime validation
TypeScript types vanish at compile time. A cast tells the *compiler* to trust you; it checks nothing
at runtime. So untrusted input typed as a clean shape is still arbitrary data.

- **Look for:** `const dto = req.body as CreateUserDto`, `req.query.id as string`,
  `JSON.parse(raw) as Config`, `req.params as any`.
- **Why:** the value can be *anything* the client sent — wrong types, extra fields (mass assignment,
  A04), injection payloads (A03), prototype-pollution keys (A08). The `as` made none of that safe.
- **Fix:** validate at the boundary with a **runtime schema**, then let inference give you the type:
  ```ts
  import { z } from 'zod'
  const CreateUser = z.object({ name: z.string(), email: z.string().email() }).strict()
  const dto = CreateUser.parse(req.body)   // throws on bad/extra input; dto is fully typed
  ```
  Use `.strict()` (Zod) / `forbidNonWhitelisted` (NestJS) so unexpected fields are rejected, not
  silently kept — this is what stops mass assignment of `role`, `isAdmin`, `kycVerified`, etc.

## `as any` / `as unknown as` / non-null `!` on untrusted data
- **Look for:** `req.body as any`, `(input as unknown as Foo)`, `value!` used to silence the
  compiler around request handling or DB/query construction.
- **Why:** these disable exactly the checks that would have caught an injection or mass-assignment
  bug. They are also the usual way a validated type gets bypassed.
- **Fix:** remove the escape hatch; parse/validate to get a real typed value (above). Reserve casts
  for values you have *already* validated.

## Suppressed type checks — `@ts-ignore` / `@ts-nocheck` / `@ts-expect-error`
- **Look for:** these comments near auth, query building, deserialization, or input handling.
- **Why:** a suppressed error often hides an unsound assumption about untrusted data.
- **Fix:** address the underlying type error rather than muting it; if truly necessary, scope it as
  narrowly as possible and add a comment justifying why it is safe.

## NestJS — validation & authorization
- **Global validation:** ensure `app.useGlobalPipes(new ValidationPipe({ whitelist: true,
  forbidNonWhitelisted: true, transform: true }))` (or per-route). **`whitelist`/`forbidNonWhitelisted`
  are off by default** — without them, `@Body()` DTOs keep unexpected fields (mass assignment).
- **DTOs need decorators:** a class used as a DTO does nothing at runtime unless its fields carry
  `class-validator` decorators (`@IsString()`, `@IsEmail()`, …). A bare `class Dto {}` validates nothing.
- **Authorization:** `@Body()`/`@Param()`/`@Query()` give input but not access control. Confirm
  `@UseGuards(...)` enforces authN **and** authZ (ownership/tenant/role) on every sensitive route —
  see A01 in `domain-kyc-aiml.md`. A guard that only checks "is logged in" is not authorization.

## ORM raw escape hatches (TS ecosystems)
Covered in `nodejs.md`, repeated here because they are the common TS-backend injection sink:
- **Prisma:** `$queryRaw\`...${x}\`` is safe (parameterized); `$queryRawUnsafe(...)` / `$executeRawUnsafe(...)` are not.
- **TypeORM:** `.query(\`...${x}\`)`, `createQueryBuilder().where(\`col = ${x}\`)` → use `:param` bindings.
- **Drizzle:** `sql.raw(...)` with interpolated input → use the `sql\`...\`` tagged template.
