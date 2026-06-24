# Audit-trail patterns

Implementation patterns for the categories the scanner cannot confirm (coverage, immutability,
reliability, masking). Apply the one that fits the codebase's existing audit mechanism.

## A reliable audit record (AU08, AU12)

Write the audit record **in the same transaction** as the change, so it can never be lost or
orphaned. Capture the delta, not just "something changed".

```sql
CREATE TABLE audit_events (
  id             bigserial PRIMARY KEY,
  occurred_at    timestamptz NOT NULL DEFAULT now(),   -- server-trusted, UTC
  actor_id       text NOT NULL,                         -- who (user/service)
  on_behalf_of   text,                                  -- impersonation, if any
  action         text NOT NULL,                         -- 'role.grant', 'payment.refund'
  target_type    text NOT NULL,
  target_id      text NOT NULL,
  outcome        text NOT NULL,                          -- 'success' | 'denied' | 'error'
  changes        jsonb,                                  -- { field: { before, after } }, masked
  correlation_id text,
  source_ip      inet,
  user_agent     text
);
```

```js
// Inside the operation's DB transaction (Prisma example):
await prisma.$transaction(async (tx) => {
  const before = await tx.user.findUnique({ where: { id }, select: { role: true } });
  const after  = await tx.user.update({ where: { id }, data: { role: newRole } });
  await tx.auditEvent.create({ data: {
    actorId: ctx.userId, action: 'role.grant', targetType: 'user', targetId: id,
    outcome: 'success', changes: { role: { before: before.role, after: after.role } },
    correlationId: ctx.requestId, sourceIp: ctx.ip, userAgent: ctx.ua,
  }});
});
```

Where a same-transaction write is impossible (audit lives in another store), use a **transactional
outbox**: write an `audit_outbox` row in the change's transaction, a worker ships it with retries.
Never `setImmediate(() => log(...))` fire-and-forget for an audit-of-record.

## Centralised capture (AU01–AU07 coverage)

To avoid per-handler omissions, capture audits in one place:
- **Middleware/interceptor** that records mutating requests (method, route, actor, outcome) — good
  for breadth, but it does not know the domain *delta*; pair it with explicit calls for high-value
  ops.
- **ORM hooks** — Django model signals (`post_save`/`post_delete`), Ecto changeset callbacks /
  `paper_trail`-style versioning, TypeORM subscribers, Sequelize hooks — capture before/after at the
  data layer so a forgotten controller call cannot skip the trail.
- **DB triggers** — an `AFTER INSERT/UPDATE/DELETE` trigger writing to `audit_events` is the
  hardest to bypass (fires even for direct SQL), at the cost of less app context.

Prefer a layer the application cannot accidentally skip for AU01–AU03.

## Immutability & tamper-evidence (AU09, AU10)

- Make the audit table **append-only**: the application DB role gets `INSERT`/`SELECT` only —
  `REVOKE UPDATE, DELETE ON audit_events FROM app_role`. Corrections are new records.
- Block deletes structurally: a `BEFORE UPDATE OR DELETE` trigger that `RAISE`s, or a rule.
- **Hash-chain** for tamper-evidence: each record stores `hash = H(prev_hash || canonical(record))`;
  a verifier walks the chain. Any altered record breaks every subsequent hash.
- For regulated audit-of-record, ship to a **separate WORM/immutable sink** (object-lock storage, an
  append-only log service) so DB-level access cannot rewrite history.

## PII / secret masking (AU11)

Before a value enters an audit record or any log:
- **Never log** passwords/PINs, OTPs, CVV, full card PAN, private keys, session tokens — omit them.
- **Mask** identifiers that must appear: card `XXXX-XXXX-XXXX-1234`, Aadhaar `XXXX-XXXX-9012`,
  account `…3456`, email `j***@d***.com`.
- Centralise masking in the audit/log serializer (a redaction allowlist/denylist), not per call
  site, so a new field defaults to redacted. Keep `changes` deltas masked too.
