# Audit-trail — regulatory mapping

Why audit trails are mandatory, not optional, for this stack. This is a *pointer* into the
frameworks; the full obligations and code signals live in `regtech/references/`. Use this to set
severity (a missing trail on a regulated operation is higher severity) and to phrase findings.

## PCI-DSS Requirement 10 — Logging & monitoring
Applies wherever cardholder data is processed. Req. 10 mandates audit trails that:
- link all access to system components to an **individual user** (10.2),
- record user id, event type, date/time, success/failure, origin, and affected
  resource/identity (10.3),
- are **protected from alteration** (10.5 — restrict viewing, protect from modification, file-
  integrity/change-detection),
- are **retained** (historically ≥1 year, ≥3 months immediately available).
Maps to `catalog.md` AU01/AU04 (coverage), AU08 (fields), AU09/AU10 (integrity).

## RBI (India) — IT framework & cyber-security
RBI directions for banks/NBFCs/payment operators require maintaining audit trails of access to and
changes in critical/financial systems, log retention, and protection of logs from tampering, plus
the ability to reconstruct events for investigation and supervisory review. Privileged/admin
actions and exception handling must be logged and reviewed. Maps to AU03/AU06/AU07, AU09.

## DPDP Act 2023 (India) / GDPR
Personal-data processing must be accountable and demonstrable: a data fiduciary should be able to
show *who accessed or changed* personal data and *on what basis*, support data-principal rights
(access/correction/erasure), and evidence breach handling. Maps to AU05 (access/export of PII) and
AU11 (the trail must not itself leak PII). See `regtech/references/frameworks/india.md` and
`global.md`.

## SOC 2 (Common Criteria)
CC-series controls (notably logical-access and change-management criteria) expect that access to
data and changes to the system are logged, attributable to individuals, and reviewed. Auditors
sample audit logs to test these controls. Maps to AU03/AU04/AU06, AU08.

## How to use this in a report
- If an unaudited operation handles cardholder data → cite PCI-DSS Req. 10, severity High–Critical.
- If it is a privileged/admin or financial action under RBI scope → cite RBI audit-trail
  expectations, severity High.
- If it accesses/exports personal data → cite DPDP/GDPR accountability, severity High.
- Keep the citation short and point the user to `regtech` for the full obligation and control text.
