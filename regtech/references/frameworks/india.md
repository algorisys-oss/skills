# India frameworks — RBI, DPDP Act 2023, NPCI/UPI, SEBI, Account Aggregator

Obligations mapped to code signals for India-regulated banking/NBFC/fintech/ecommerce. Cite the
specific direction in findings. Engineering reference, **not legal advice** — a compliance
officer/DPO owns the determination. Pair with `checklist.md`.

## RBI — payment-data localisation (the highest-impact India check)
RBI's direction on *Storage of Payment System Data* requires that the **entire payment data** of
transactions processed in India be stored **only in India**. Limited processing abroad is allowed if
the data is brought back to India and the foreign copy purged within a defined window.

- **Code signal (C6):** database/cache/object-store hosts in foreign regions; payment data sent to
  overseas third parties, analytics, or SaaS; foreign AWS/GCP regions for payment stores; logs/
  backups of payment data stored abroad.
- **Severity:** High–Critical for payment data leaving India. Frequently an **infra** finding (DB
  region, bucket region, vendor location) — flag for an infra/compliance owner, not just code.

## RBI — IT framework, cyber security & outsourcing
Banks/NBFCs/PPI issuers must maintain security baselines, audit trails of access/changes to critical
systems, log retention, encryption of sensitive data, and incident reporting to RBI/CERT-In.

- **Code signals:** map to `owasp` (security baseline, crypto), `audit-trail` (trail coverage,
  immutability, retention), C3/C4 (encryption). Privileged-action logging → `audit-trail` AU03/AU07.
- **Incident reporting:** detection/logging sufficient to report to RBI/CERT-In within mandated
  timelines → C13 / `audit-trail`.

## DPDP Act 2023 (Digital Personal Data Protection Act)
India's personal-data law. Key obligations for a **Data Fiduciary**:

| Provision (theme) | Obligation | Code signal / check |
|---|---|---|
| **§5 Notice** | Clear notice of what/why before/at collection | C7 |
| **§6 Consent** | Free, specific, informed, unconditional, unambiguous; withdrawable as easily as given | C7 — consent record + version + withdrawal path |
| **§7 Legitimate uses** | Limited non-consent bases (e.g. user-initiated service) | C7/C8 |
| **§8 Fiduciary duties** | Accuracy, security safeguards, erase on purpose completion/withdrawal | C9, C3 |
| **§8(7) Retention** | Erase personal data once the purpose is served / consent withdrawn | C9 — retention period + erasure job |
| **§11–14 Principal rights** | Access, correction, erasure, grievance redressal | C10 |
| **§8(6) Breach** | Notify the Data Protection Board and affected principals of a breach | C13 / `audit-trail` |
| **Cross-border (§16)** | Government may restrict transfer to certain countries | C6 |
| **Significant Data Fiduciary** | Extra duties (DPO, DPIA, audit) if notified as SDF | process — flag for compliance |

- **Children's data:** verifiable parental consent and no behavioural tracking/targeted ads for
  minors — flag age-gating and any tracking of under-18 users.

## NPCI / UPI
For UPI/PSP integrations (also see `resilience/references/integrations.md` for reliability):
- Adhere to NPCI circulars on data storage (payment data localisation per RBI), transaction-limit
  and velocity rules, and mandated transaction logging/audit.
- **Code signals:** UPI transaction data stored in India (C6); audit of UPI transactions
  (`audit-trail` AU01); idempotent/reconciled handling (`money-safety` M04/M10).

## SEBI (securities / broking / wealth)
If the system handles securities trading, advisory, or wealth: SEBI cyber-security and cyber-
resilience frameworks (CSCRF), system audit, data retention of trading/KYC records, and
investor-grievance handling. Map security → `owasp`, audit/retention → `audit-trail` + C9.

## Account Aggregator (AA) framework
If consuming financial data via the AA ecosystem (RBI-regulated): honour the **consent artefact**
(purpose, duration, data types, frequency) — use data only within the granted consent scope and
expiry, and delete on expiry.
- **Code signals:** consent-artefact validation before each fetch; scope/expiry enforcement; deletion
  on consent expiry → C7/C9.

## Using this file
Lead India reports with **payment-data localisation (RBI/C6)** and **DPDP consent/erasure (C7/C9)** —
the highest-frequency, highest-severity, most India-specific gaps. Cite the specific direction,
give code evidence, and route security/audit depth to `owasp`/`audit-trail`. Recommend
compliance/DPO review for formal scope and any SDF/SEBI-audit obligations.
