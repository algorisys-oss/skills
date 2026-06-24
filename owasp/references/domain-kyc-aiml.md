# Domain risks — KYC / onboarding / backoffice / AI-ML

Stack-agnostic checks specific to onboarding journeys, video KYC, workflow & rules engines, and
internal/external AI/ML integrations. These rarely show up in a grep — find them by reasoning
about data flow, trust boundaries, and state. Apply alongside the language references.

## Category 20 — AI/ML integration security (OWASP LLM Top 10)

### LLM01 Prompt injection
- **Risk:** untrusted content (user message, uploaded doc, KYC field, web page, tool output)
  steers the model to ignore instructions, exfiltrate data, or misuse tools.
- **Check:** is any untrusted text concatenated into a system/developer prompt? Are tool-calling
  agents exposed to attacker-controlled content?
- **Fix:** keep instructions and untrusted data in separate roles/delimiters; treat model output
  as untrusted; least-privilege tools; human approval for consequential actions; do not let a
  document's contents grant itself privileges in a KYC decision.

### LLM02 Insecure output handling
- **Risk:** model output used directly in SQL, shell, HTML, `eval`, file paths, or as an authz
  decision.
- **Fix:** validate/parse model output against a strict schema before use; apply the same
  injection defenses (parameterize, encode, allowlist) as for any untrusted input. Never `eval`
  or `dangerouslySetInnerHTML` model output without sanitization.

### LLM / agent SSRF & tool abuse
- **Risk:** an agent with an HTTP/fetch tool can be steered to hit internal services or cloud
  metadata.
- **Fix:** apply A10 SSRF controls to every agent tool; allowlist domains; sandbox code-exec tools.

### Sensitive data & PII leakage
- **Risk:** sending full KYC/PII (PAN, Aadhaar, passport, biometrics) to an external LLM provider;
  PII captured in prompt/response logs and training pipelines.
- **Fix:** minimize and redact PII before external calls; prefer providers with no-retention /
  zero-data-retention terms; do not log full prompts containing PII; document the data-flow and
  legal basis.

### Over-reliance on model decisions
- **Risk:** auto-approving KYC / fraud / eligibility from a model with no human review or audit.
- **Fix:** human-in-the-loop for adverse or high-value decisions; log model version, inputs
  (redacted), and rationale for every automated decision (ties to A09).

### Cost / abuse limits
- **Risk:** no rate or token/cost limits on LLM endpoints → financial DoS.
- **Fix:** per-user rate and spend limits; timeouts; circuit breakers.

## Video KYC & document upload (ties to category 15, A02, A01)

- **Liveness / spoofing:** confirm liveness detection exists and is server-verified; do not trust
  a client "liveness passed" flag. Bind the captured media to the session/identity.
- **Upload validation:** validate by content (magic bytes), not client MIME/extension; enforce
  size and duration limits; generate server-side filenames; store in object storage outside the
  web root; scan for malware; serve with `Content-Disposition: attachment` and correct type.
- **Access control on media:** KYC documents/recordings must be access-controlled per subject and
  reviewer role — never a guessable/public URL (IDOR is the classic KYC leak). Use signed,
  short-TTL URLs.
- **Encryption:** encrypt KYC media and PII at rest (KMS-managed keys) and in transit; segregate
  from general app storage; define retention/deletion per regulation.

## Workflow & rules engines (ties to category 19, A01, A04)

- **Authorization per transition:** every state transition (approve, reject, escalate, override)
  must check the actor's role AND that the action is legal from the current state. Do not rely on
  the UI hiding a button.
- **Race conditions / idempotency:** concurrent approvals or duplicate submissions must not
  double-apply. Use DB transactions, `SELECT ... FOR UPDATE`/optimistic locking, unique
  constraints, and idempotency keys on onboarding/payment actions.
- **Rule injection:** if rules/expressions are user- or admin-authored and evaluated, never `eval`
  them — use a sandboxed, allowlisted expression evaluator. Treat a rules engine that executes
  arbitrary code as RCE.
- **Tamper-evident audit trail:** record who/what/when for every decision and override; protect
  logs from modification (A09 + compliance).

## Multi-tenancy / backoffice access control (A01)

- **Tenant isolation:** every query is scoped by tenant/org id, enforced server-side (row-level
  security or an enforced base scope), not just a filter the client can change.
- **IDOR sweep:** for each endpoint taking a record id, confirm an ownership/tenant check exists.
  This is the single highest-yield review for backoffice systems.
- **Privilege escalation:** mass-assignment and role fields (see language refs) — clients must
  never set their own role/permissions/tenant.
- **Admin/internal endpoints:** authenticated AND authorized to an admin role; not merely
  "hidden"; rate-limited and audit-logged.

## Secrets, logging & compliance (category 18, A09, A02)

- No PII/secrets/tokens in logs, error messages, or analytics events.
- Secrets in a manager (not env files in the repo, not client bundles); rotate on exposure.
- Audit logs for auth, KYC decisions, data access/export, and admin actions — retained and
  tamper-evident.
