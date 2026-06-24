# Regtech cross-framework checklist

The control areas that recur across PCI-DSS, GDPR, SOC2, RBI, DPDP, and NPCI, each mapped to the
**code signal** to look for and the **frameworks** it serves. Walk this list in step 5 of the
SKILL.md workflow and mark each **met / gap / needs-review** with `file:line` evidence. Security and
audit controls are owned by sibling skills (`owasp`, `audit-trail`) — this checklist points at them
rather than re-detecting.

Status legend per item: what to grep for → why it matters → which frameworks → which skill owns the
deep check (if any).

## C1 — PII / cardholder-data inventory
- **Find:** model/schema/DTO fields named `pan`, `card`, `card_number`, `cvv`, `cvc`, `aadhaar`,
  `account_number`, `ifsc`, `dob`, `passport`, `name`, `email`, `phone`, `address`, `biometric`,
  `ssn`; columns of those names; these fields in API responses and logs.
- **Why:** you cannot protect or account for data you have not inventoried; every other control
  depends on knowing where regulated data lives.
- **Frameworks:** PCI (CHD), DPDP/GDPR (personal data), RBI.

## C2 — Do not store prohibited data (CVV / track / PIN)
- **Find:** persisted `cvv`/`cvc`/`track`/`pin` fields, columns, or these values written to logs/DB.
- **Why:** PCI-DSS Req. 3.2 forbids storing sensitive authentication data (CVV, full track, PIN)
  after authorisation — at all, encrypted or not.
- **Frameworks:** PCI-DSS Req. 3.2. **Severity: Critical if found.**

## C3 — Encryption at rest for regulated data
- **Find:** PAN/PII columns with no encryption (no `pgcrypto`/app-layer encryption/KMS envelope),
  plaintext sensitive fields, disk/DB encryption not configured.
- **Why:** PCI Req. 3.4 (render PAN unreadable), DPDP/RBI reasonable security safeguards.
- **Frameworks:** PCI, DPDP, RBI, GDPR Art. 32. **Deep crypto check:** `owasp` A02.

## C4 — Encryption in transit
- **Find:** `http://` endpoints for regulated data, TLS verification disabled, weak TLS config.
- **Why:** PCI Req. 4, Art. 32, RBI.
- **Frameworks:** PCI/GDPR/RBI. **Deep check:** `owasp` (TLS-verify-off, weak crypto).

## C5 — Secrets & key management
- **Find:** hardcoded keys/passwords/tokens, secrets in client bundles or committed env files.
- **Why:** PCI Req. 3.5/3.6 key management; general security.
- **Deep check:** `owasp` Cat 18 (secrets). Reference its findings here.

## C6 — Data residency / localisation
- **Find:** database/cache/object-store hosts and **regions** (`*.amazonaws.com` region strings, GCP
  regions, foreign DB hostnames), third-party SaaS endpoints and CDNs that receive regulated data,
  cross-border API calls carrying PII.
- **Why:** **RBI payment-data localisation** requires payment-system data to be stored only in India
  (limited processing-abroad-then-return allowance). DPDP restricts cross-border transfer to
  non-restricted countries; GDPR restricts transfers outside the EEA (SCCs/adequacy).
- **Frameworks:** RBI (strict for payment data), DPDP, GDPR. **Severity: High–Critical for payment
  data leaving India.** Often an **infra** finding — flag for an infra/compliance owner.

## C7 — Consent & lawful basis
- **Find:** personal-data collection (signup, profile, KYC) with no consent check or recorded
  consent; pre-ticked/implied consent; marketing/processing with no opt-in record; missing
  consent-version/timestamp storage.
- **Why:** DPDP §6 requires free, specific, informed, unambiguous consent with a clear notice; GDPR
  Art. 6/7 lawful basis + demonstrable consent.
- **Frameworks:** DPDP, GDPR. **Severity: High.**

## C8 — Purpose limitation & data minimisation
- **Find:** collecting fields not needed for the stated purpose; one consent reused across unrelated
  purposes; PII copied into analytics/marketing stores without basis.
- **Why:** DPDP/GDPR purpose limitation + minimisation.
- **Frameworks:** DPDP, GDPR.

## C9 — Retention & erasure (RTBF)
- **Find:** sensitive data stored with no retention period / TTL / cleanup job; no delete or
  anonymise capability for a user; soft-deletes that never hard-delete PII; backups with no
  retention policy.
- **Why:** DPDP requires erasure on withdrawal of consent / purpose completion; GDPR Art. 17
  right-to-erasure; PCI data-retention minimisation.
- **Frameworks:** DPDP, GDPR, PCI. **Severity: Medium–High.**

## C10 — Data-subject / data-principal rights
- **Find:** is there an access/export/correction/erasure path for a user's data (DSAR/RTBF
  endpoints or process)?
- **Why:** DPDP rights (access, correction, erasure, grievance); GDPR Arts. 15–22.
- **Frameworks:** DPDP, GDPR.

## C11 — Audit trail & access accountability
- **Find:** access to and changes of regulated data logged, attributable, immutable.
- **Why:** PCI Req. 10, DPDP/RBI accountability, SOC2 CC.
- **Deep check:** owned by **`audit-trail`** — pull its findings in under PCI Req. 10 / DPDP.

## C12 — PII in logs / non-prod
- **Find:** PII/CHD written to application logs, error trackers, analytics, or copied to
  non-production environments unmasked.
- **Why:** PCI (mask PAN), DPDP/GDPR minimisation, RBI.
- **Deep check:** `audit-trail` AU11 + `owasp`. Reference here.

## C13 — Breach detection & notification readiness
- **Find:** logging/alerting sufficient to detect and reconstruct a breach within
  notification timelines.
- **Why:** DPDP breach notification to the Board and affected principals; RBI incident reporting;
  GDPR 72-hour notification.
- **Deep check:** detection coverage via `audit-trail`; this item confirms the obligation applies.

## How to weight
- Payment data leaving India (C6) and stored CVV/PIN (C2) are the highest-severity, most
  India-specific findings — surface them first.
- Many items (C6 residency, C9 retention policy, C13 process) are **partly organisational** — say so
  and route to a compliance owner rather than implying a code-only fix.
