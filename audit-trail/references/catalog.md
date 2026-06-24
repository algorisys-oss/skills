# Audit-trail catalog

What must be audited, what a complete record contains, and how the store must behave. Each entry:
**ID — Name** · what it is · why it matters · severity baseline.

## What must be audited (operations)

A01 through A07 below are the operation classes that require an audit record in
banking/NBFC/fintech/ecommerce systems. A *missing* record on any of these is the core finding.

### AU01 — Money movement
Any credit/debit, transfer, payout, refund, charge, limit utilisation, or ledger posting. Must
record actor, amount, currency, source/target accounts, reference, outcome. **Severity: Critical.**

### AU02 — KYC / AML / onboarding decisions
Identity verification approve/reject, document acceptance, sanctions/PEP screening results,
risk-score assignment, manual overrides of an automated decision. The decision and the decider must
be traceable. **Severity: Critical.**

### AU03 — Authorization & access changes
Role/permission grants and revokes, group membership, limit/threshold changes, maker-checker
approvals, impersonation/"login as customer". Privilege changes with no trail are an audit failure
and a breach-investigation blind spot. **Severity: High–Critical.**

### AU04 — Authentication events
Login success/failure, MFA enrol/challenge/reset, password/PIN change, session
creation/revocation, API-key issue/rotate. Needed to detect credential abuse. **Severity: High.**

### AU05 — Sensitive data access & export
Staff viewing/exporting customer PII or statements, bulk downloads, report generation, admin reads
of another user's data. Required for DPDP/GDPR access accountability. **Severity: High.**

### AU06 — Customer-data and config changes by staff/admin
Backoffice edits to customer records, KYC fields, contact details, beneficiary/payee changes,
feature flags, pricing/interest config, and other system configuration. **Severity: High.**

### AU07 — Security-relevant administrative actions
Account freeze/unfreeze/close, fraud-hold apply/release, refund overrides, manual ledger
adjustments, data deletion/anonymisation. **Severity: High.**

## What a complete audit record contains (fields)

### AU08 — Missing required fields
A record exists but cannot answer who/what/when. Required fields:
- **actor** — authenticated user or service id (not just "system"); plus on-behalf-of if impersonating.
- **action** — a stable verb/type (`role.grant`, `payment.refund`), not a free-text blob.
- **target** — entity type + id the action affected.
- **outcome** — success / denied / error.
- **before / after** — for changes, the changed fields' prior and new values (the *delta*).
- **timestamp** — UTC, server-trusted (not client-supplied).
- **correlation / request id** — to tie the record to a request and across services.
- **source** — IP and user-agent / channel.
Missing *actor* or *before/after on a change* are the highest-impact gaps. **Severity: Medium–High.**

## How the store must behave (integrity)

### AU09 — Mutable / deletable audit store
Audit rows that can be `UPDATE`d or `DELETE`d (by the app's own DB role, an admin endpoint, or an
ORM cascade), or logs written only to a file that staff can edit. An attacker or insider can erase
their tracks. **Fix:** append-only table, revoke UPDATE/DELETE from the app role, ship to a separate
WORM/immutable sink, and/or hash-chain records. **Severity: High–Critical.**

### AU10 — No tamper-evidence
Even append-only rows can be altered by someone with DB access. High-assurance trails chain each
record's hash to the previous one (or use a signed/WORM store) so tampering is detectable.
**Severity: Medium** (High for regulated audit-of-record).

### AU11 — PII / secrets inside audit or application logs
Audit records or logs containing raw passwords/PINs, OTPs, full PAN/card numbers, CVV, Aadhaar,
full account numbers, or session tokens. The trail itself becomes a data-exposure liability.
**Fix:** mask (`XXXX…1234`), tokenise, or omit; never log credentials/CVV/OTP at all.
**Severity: High** (overlaps `owasp` A02/A09 and `regtech`).

### AU12 — Unreliable / lossy audit write
The audit write is fire-and-forget (async with no delivery guarantee), happens outside the
operation's transaction (so a later failure rolls back the change but not the log, or vice versa),
or is best-effort and silently dropped. A trail that loses records is unreliable.
**Fix:** write the audit record in the same transaction as the change, or via a transactional
outbox. **Severity: Medium–High.**

## Severity guidance for reporting

- **Critical** — money movement or KYC/AML decisions with no audit record; an audit store the app
  can freely delete from.
- **High** — privilege/auth/config changes or data exports unaudited; raw credentials/PAN in the
  trail; tamper-evident-less audit-of-record.
- **Medium** — incomplete fields (missing correlation id, before/after), lossy/async-only writes.
- **Low / Info** — hardening (no hash-chain where not strictly required, retention tuning).

Confidence ≠ severity. Flag a Critical category from a low-confidence grep hit as "Critical / needs
confirmation" until you have cross-referenced the operation against the audit mechanism.
