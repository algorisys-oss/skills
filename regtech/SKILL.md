---
name: regtech
description: Map code and data flows against financial-services regulatory frameworks — PCI-DSS, GDPR, SOC2 (global) and RBI, DPDP Act 2023, NPCI/UPI, SEBI, Account Aggregator (India) — and report gaps in data residency, consent, retention/erasure, encryption, PII minimisation, and access accountability. Use when the user asks to "run regtech", "compliance review", "regtech scan", "PCI/DPDP/GDPR check", "data residency review", "regulatory audit", "are we DPDP compliant", or invokes /regtech. Built for banking, NBFC, fintech, and ecommerce systems handling cardholder data, KYC/PII, and cross-border data.
user-invocable: true
---

# regtech

Map a codebase's data flows against the regulations that govern banking/NBFC/fintech/ecommerce, and
report where the code does not meet them. Covers **both** global frameworks (PCI-DSS, GDPR, SOC2)
and India-specific ones (RBI, DPDP Act 2023, NPCI/UPI, SEBI, Account Aggregator). The point is the
*mapping*: turn "are we compliant?" into concrete, located code findings tied to a specific control.

This skill **orchestrates and cross-references**, it does not duplicate: it reuses `owasp`
(vulnerabilities → many PCI/RBI security controls), `audit-trail` (logging → PCI Req. 10 / DPDP
accountability), and `money-safety` (transaction integrity) for those control areas, and adds the
checks unique to compliance — **data residency, consent, retention/erasure, PII inventory,
encryption posture, cross-border transfer**. The checklist lives in `references/checklist.md`;
framework obligations and code signals live in `references/frameworks/{global,india}.md`.

## Default behavior

- **Report, do not auto-modify.** Produce a gap report mapped to controls; apply fixes only when the
  user passes `--fix` or explicitly asks. Compliance changes are reviewed before they ship.
- **Default scope is the whole repository.** A path or flag narrows it.
- **Not legal advice.** This is an engineering checklist that surfaces likely gaps; a compliance
  officer/DPO owns the formal determination. Always say so.

## Invocation

```
/regtech                      Scan the whole repo, report gaps mapped to controls
/regtech <path>               Scan a directory or file
/regtech --diff               Scan only changed files — pre-commit/PR use
/regtech --staged             Scan only git-staged files
/regtech --framework pci|dpdp|gdpr|rbi|soc2|npci   Weight one framework
/regtech --india | --global   Restrict to one regulatory set (default: both)
/regtech --fix [scope]        Scan, then apply fixes (still confirm anything risky — see step 6)
/regtech <topic>              e.g. "regtech check data residency", "are card numbers stored?"
```

Parse the request into a **scope**, a **mode** (report — default — or fix), and a **framework
weighting** (default: both India + global; `--framework`/`--india`/`--global` narrows it).

## Workflow

### 1. Establish what regulated data the system handles
Determine the applicable frameworks from the data and domain:
- **Cardholder data** (PAN, CVV, track data) → PCI-DSS in scope.
- **Personal data of India residents** → DPDP Act; **EU residents** → GDPR.
- **Payment-system data** (UPI, cards, settlement) → RBI localisation + NPCI.
- **Banking/NBFC/securities operations** → RBI / SEBI.
Load `references/checklist.md` plus the relevant framework file(s). If `--global`/`--india` was
passed, load only that set.

### 2. Build a PII / sensitive-data inventory
Find where regulated data lives and moves — the foundation for every other check. Grep models,
schemas, DTOs, and logs for sensitive fields (PAN, Aadhaar, card number, CVV, account number, name,
DOB, address, phone, email, biometrics). The scanner seeds this; you confirm classification. Note
for each: where stored, whether encrypted, where it flows (logs, third parties, other regions).

### 3. Run the heuristic pre-filter
Run the bundled scanner for candidate `file:line` locations. **High-recall, low-precision.**

```sh
scripts/scan.sh [PATH]        # default scope = path arg or "."
scripts/scan.sh --diff        # changed files only
```

Output is `CATEGORY \t file:line \t matched text`. It flags PII/PCI fields, cross-border/external
hosts, missing-consent and missing-retention signals, and plaintext-sensitive-storage smells. It
cannot determine residency or consent *correctness* — that is the mapping work in step 4–5.

### 4. Run the cross-referenced security/audit checks
The security and logging controls of PCI/RBI/SOC2 are already covered by sibling skills — invoke or
mirror them rather than re-implementing:
- **`owasp`** — encryption-in-transit/at-rest weaknesses, weak crypto, secrets, access control
  (PCI Req. 2/3/4/6/8, RBI security baseline).
- **`audit-trail`** — audit-log coverage, immutability, PII-in-logs (PCI Req. 10, DPDP/RBI trail).
- **`money-safety`** — transaction integrity where relevant to payment-system rules.
Pull their findings into the regtech report under the mapped control; note which were run.

### 5. Map each checklist item to the code (the core of this skill)
Walk `references/checklist.md`. For each control, state **met / gap / needs-review** with the
`file:line` evidence and the framework citation:
- **Data residency / localisation** — is regulated data (esp. payment data under RBI; personal data
  under DPDP transfer rules) stored/processed only in permitted regions? Look for foreign DB hosts,
  S3 regions, third-party SaaS endpoints, CDNs receiving PII.
- **Consent** — is personal-data collection gated by a recorded, purpose-specific consent (DPDP/GDPR
  lawful basis)? Look for collection with no consent check/record; pre-ticked/implied consent.
- **Purpose limitation & minimisation** — is collected data limited to the stated purpose; any
  over-collection or repurposing?
- **Retention & erasure** — is there a defined retention period and an erasure path (DPDP/GDPR
  RTBF)? Look for unbounded storage, no TTL/retention job, no delete/anonymise capability.
- **Encryption posture** — PAN/PII encrypted at rest and in transit; CVV never stored (PCI); keys
  managed (not hardcoded — defer detail to `owasp`).
- **Access accountability** — least privilege + audited access to regulated data (defer to
  `audit-trail`/`owasp`).
- **Breach readiness** — is there detection/logging to support DPDP/RBI breach-notification
  timelines (defer detection coverage to `audit-trail`)?

### 6. Report findings
Group **by framework and control**, then by severity. For each gap:

- **Framework + control** (e.g. `PCI-DSS Req. 3.2 — do not store CVV`, `DPDP §6 — consent`,
  `RBI — payment-data localisation`).
- **Status** — gap / needs-review, and **severity / confidence**.
- **Location** — `file:line` as a clickable link (or "no evidence found" for an absent control).
- **What & why** — the gap in *this* code and the obligation it misses.
- **Fix** — concrete remediation, or the policy/process step if it is not purely a code change.

Lead with a one-line summary (gaps per framework). State the **not-legal-advice** caveat and which
sibling skills were run. If scope was narrowed say so — never imply full coverage.

### 7. Fix (only when `--fix` or explicitly requested)
- Make low-risk, mechanical fixes directly — stop logging a PII field (mask/omit), add a retention
  TTL/cleanup job, add a consent check using an existing consent service, move a hardcoded region to
  config, add `.gitignore` for an env file.
- For changes that alter behavior or data handling — encrypting an existing plaintext column (a data
  migration), changing where data is stored/processed (residency — often infra, not just code),
  adding a consent gate that blocks an existing flow, deleting/anonymising stored data — explain the
  change and confirm first; many of these are policy decisions, not pure code.
- Defer security fixes to `owasp` and audit fixes to `audit-trail` to avoid divergent remediations.
  Re-run after fixing and flag anything needing DPO/compliance sign-off.

## Boundaries

- **Not legal advice and not a certification.** It surfaces likely engineering gaps mapped to
  controls; the formal compliance determination, DPIAs, and audits belong to a compliance officer/DPO.
- Residency, data-processing agreements, and many privacy controls are **organisational/infra**, not
  purely code — this skill flags the code-visible signals and says when a finding needs a process owner.
- Heuristics produce false positives (a field named `pan` that is not a card number) and miss
  context-only obligations. Always confirm classification; disclose what was and was not covered.

## Resources

- `references/checklist.md` — cross-framework control checklist, each item → the code signal to find.
- `references/frameworks/global.md` — PCI-DSS, GDPR, SOC2 obligations mapped to code.
- `references/frameworks/india.md` — RBI, DPDP Act 2023, NPCI/UPI, SEBI, Account Aggregator.
- `scripts/scan.sh` — heuristic candidate finder (PII inventory, cross-border, retention, consent).
- Sibling skills: `owasp` (security controls), `audit-trail` (logging controls),
  `money-safety` (transaction integrity).
