# TypeScript — PII sinks & fixes

Layered on `nodejs.md` (same runtime). The TS-specific leverage is using types and NestJS to make
redaction structural rather than per-call discipline.

## Type the response boundary
- **Look for:** controllers returning entities directly (`: Promise<User>`), `any`-typed responses,
  `class-transformer` without `@Exclude`, returning `await repo.findOne()` straight to the client.
- **Fix:** a dedicated response DTO containing only client-facing fields; `class-transformer`
  `@Exclude()` on Tier-0/1 fields and `excludeExtraneousValues: true` so new fields default to hidden.
  ```ts
  export class UserResponseDto {
    @Expose() id!: string
    @Expose() name!: string
    @Expose() @Transform(({ obj }) => maskPan(obj.cardNumber)) cardMasked!: string
    // cvv, aadhaar, accountNumber are NOT @Expose()d -> never serialised
  }
  // NestJS: app.useGlobalInterceptors(new ClassSerializerInterceptor(reflector))
  ```

## Brand sensitive fields so leaks are visible
- **Look for:** `cardNumber: string` flowing freely into logs/responses.
- **Fix:** a branded type (`type Pan = string & { __pii: 'pan' }`) plus a lint rule / redactor so PII
  is not passed to `console`/`logger`/response without going through a mask function. Types do not
  enforce at runtime — pair with the central redactor from `patterns.md`.

## NestJS logging
- **Look for:** `Logger.log(object)` with entities; interceptors logging `request.body`.
- **Fix:** a logging interceptor that redacts by field name before emitting; never log full DTOs on
  PII routes.

For loggers, Sentry, URLs, at-rest, and analytics see `nodejs.md` — identical runtime.
