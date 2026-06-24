---
name: audit-trail
description: Identify, explain, and (on request) fix audit-logging gaps in Node.js, TypeScript, Python, Go, and Elixir code — sensitive operations (money movement, KYC/AML decisions, role/limit changes, auth, data export, config changes) that write no audit record, audit records missing required fields, mutable/tamper-evident-less audit stores, and PII written into logs unmasked. Use when the user asks to "run audit-trail", "audit trail review", "check audit logging", "are sensitive ops logged", "audit-log coverage", or invokes /audit-trail. Built for banking, NBFC, fintech, and ecommerce backoffice/KYC systems where audit trails are a compliance requirement.
user-invocable: true
---

# audit-trail

Find audit-logging gaps in Node.js, TypeScript, Python, Go, and Elixir code, explain each in
context, and apply fixes when asked. Built for KYC/onboarding, backoffice, and ledger systems where
*who did what, to what, when* must be recorded immutably — both to investigate incidents and to
satisfy RBI / PCI-DSS Req. 10 / SOC2 / DPDP obligations.

This complements `owasp` A09 (logging/monitoring failures) and `regtech` (regulatory mapping), which
it cross-references rather than duplicates. The category list and required-field rubric live in
`references/catalog.md`. Regulatory mapping lives in `references/regulatory.md`. Implementation
patterns (middleware, DB triggers, hash-chaining, PII masking) live in `references/patterns.md`.

## Default behavior

- **Report, do not auto-modify.** Produce a findings report; apply fixes only when the user passes
  `--fix` or explicitly asks.
- **Default scope is the whole repository.** A path or flag narrows it.

## Invocation

```
/audit-trail                 Scan the whole repo, report findings
/audit-trail <path>          Scan a directory or file
/audit-trail --diff          Scan only changed files (uncommitted + branch vs base) — pre-commit/PR use
/audit-trail --staged        Scan only git-staged files
/audit-trail --fix [scope]   Scan, then apply fixes (still confirm anything risky — see step 5)
/audit-trail <topic>         e.g. "audit-trail check the KYC approval flow", "is the role change logged"
```

Parse the request into a **scope** and a **mode** (report — default — or fix). A focused topic
narrows which operations and files to weight.

## Workflow

### 1. Detect languages, framework & the audit mechanism
Identify the stack (manifests as in `owasp`). Then find the **existing audit mechanism**, if any: an
`audit_log`/`audit_events` table or model, an `auditLog(...)`/`log_audit(...)` helper, an ORM hook
(Django signals, Ecto/`paper_trail`-style versioning), or DB triggers. Establishing the convention
tells you what a *missing* call looks like. Load only the relevant `references/*.md`.

### 2. Run the heuristic pre-filter
Run the bundled scanner for candidate `file:line` locations. **High-recall, low-precision** — a
triage list, not a verdict.

```sh
scripts/scan.sh [PATH]        # default scope = path arg or "."
scripts/scan.sh --diff        # changed files only
scripts/scan.sh PATH --lang node|typescript|python|go|elixir
```

Output is `CATEGORY \t file:line \t matched text`. It flags **sensitive operations** (so you can
check each is audited), **audit-store mutability** (UPDATE/DELETE on audit tables), and **PII in
logs**. It cannot confirm an operation is *unaudited* — that needs the cross-reference in step 4.

### 3. Enumerate the sensitive operations
List the operations that MUST be audited (see `references/catalog.md`): money movement, KYC/AML
decisions, role/permission/limit changes, login/MFA/auth events, data exports, config/feature-flag
changes, customer-data edits by staff. Derive this from routes and service methods — the scanner
hands you candidates, but you decide which are in-scope.

### 4. Triage: is each operation audited, completely, immutably?
For each sensitive operation, confirm:

- **Coverage** — does it write an audit record on the success path (and, where relevant, on denied
  attempts)? Cross-reference the operation against the audit mechanism from step 1.
- **Required fields** — actor (user/service id), action, target (entity + id), outcome,
  before/after (for changes), timestamp (UTC), request/correlation id, source IP/user-agent. Missing
  *who* or *what changed* makes the record useless. (See `references/catalog.md`.)
- **Immutability / tamper-evidence** — is the audit store append-only? Any `UPDATE`/`DELETE` path on
  audit rows, or app DB credentials with delete rights on the audit table, is a finding. For
  high-assurance trails, is there hash-chaining / WORM / a separate sink? (See `patterns.md`.)
- **No secrets/PII leakage** — the audit record must not store raw passwords, full card numbers/CVV,
  OTPs, or unmasked PII (mask: `XXXX-XXXX-XXXX-1234`). Logging PII is itself a finding.
- **Reliability** — is the audit write in the same transaction as the change (so it cannot be lost),
  or at least guaranteed via an outbox? A fire-and-forget log that can drop records is a gap.

### 5. Report findings
Group by severity (Critical → High → Medium → Low/Info; see `references/catalog.md`). For each:

- **Severity** and **confidence**.
- **Category** (e.g. `Unaudited sensitive operation`, `Mutable audit store`, `PII in audit record`).
- **Location** — `file:line` as a clickable link.
- **What & why** — the operation and what is missing (e.g. "role escalation endpoint writes no
  audit record → no trail of privilege grants").
- **Fix** — concrete remediation (snippet from `patterns.md`, adapted).

Lead with a one-line summary. If scope was narrowed (e.g. `--diff`) say so — never imply full
coverage that was not performed.

### 6. Fix (only when `--fix` or explicitly requested)
Apply the smallest correct fix using the codebase's existing audit mechanism. Then:

- Make low-risk, mechanical fixes directly — add an `auditLog(...)` call to an unaudited handler
  using the established helper, add a missing field (actor/correlation id) to an audit payload, mask
  a PII field before logging, add a `rel`/index, revoke nothing.
- For changes that alter behavior or schema — making an audit table append-only (revoking
  UPDATE/DELETE, adding triggers), moving the audit write inside the operation's transaction,
  introducing hash-chaining, or changing retention — explain the change and confirm first.
- Never delete or weaken existing audit records to make something pass. After fixing, re-run the scan
  and note anything still needing human/compliance review.

## Boundaries

- This skill finds **pattern-detectable** gaps (unaudited operations, mutable stores, PII in logs)
  and reasons about field completeness and immutability. It is not a SIEM, not log-pipeline
  monitoring, and not a compliance certification — say so for audit-of-record systems.
- Heuristics produce false positives (a "delete" that is not on an audit table) and miss
  operations it cannot recognize. Always confirm in context; disclose what was and was not covered.
- It does not assess alerting/detection response (that is operational) or the full regulatory
  mapping (that is `regtech`).

## Resources

- `references/catalog.md` — what must be audited, required fields, immutability, severity rubric.
- `references/regulatory.md` — PCI-DSS Req. 10, SOC2 CC, RBI, DPDP trail expectations (→ `regtech`).
- `references/patterns.md` — middleware/interceptor logging, transactional outbox, DB triggers,
  hash-chain tamper-evidence, PII masking.
- `scripts/scan.sh` — heuristic candidate finder (ripgrep/grep).
