# Global frameworks — PCI-DSS, GDPR, SOC 2

Obligations mapped to code signals. Cite the specific requirement in findings. This is an
engineering reference, not the standard text — and **not legal advice**. Pair with `checklist.md`.

## PCI-DSS (cardholder data)
Applies when the system stores, processes, or transmits cardholder data (CHD: PAN, cardholder name,
expiry, service code) or sensitive authentication data (SAD: full track, CVV/CVC, PIN).

| Requirement | What it means in code | Owning skill / signal |
|---|---|---|
| **Req. 3.2** — never store SAD after auth | No persisted/logged `cvv`/`cvc`/`track`/`pin` | `checklist.md` C2 — **Critical** |
| **Req. 3.4** — render PAN unreadable at rest | PAN encrypted/tokenised/truncated, not plaintext | C3 / `owasp` A02 |
| **Req. 3.5–3.6** — key management | No hardcoded keys; KMS/rotation | C5 / `owasp` Cat 18 |
| **Req. 4** — strong crypto in transit | TLS everywhere CHD flows; no `http://`, no verify-off | C4 / `owasp` |
| **Req. 6** — secure development | Vulnerability management of the app | `owasp` (Top 10) |
| **Req. 7–8** — least privilege + unique IDs | Access control, no shared accounts | `owasp` A01 / `audit-trail` |
| **Req. 10** — log & monitor all access to CHD | Audit trail, individual attribution, protected logs | **`audit-trail`** AU01/AU08/AU09 |
| **Req. 3.3** — mask PAN on display | PAN shown as first6/last4 max | C12 / `audit-trail` AU11 |

**Scope reduction:** tokenising/outsourcing CHD to a PCI-compliant processor and never touching raw
PAN dramatically reduces scope — flag where raw PAN is handled that could be tokenised instead.

## GDPR (EU personal data)
Applies to personal data of people in the EU/EEA.

| Article | Obligation | Code signal / owning check |
|---|---|---|
| **Art. 6/7** — lawful basis & consent | Recorded, specific, withdrawable consent before processing | C7 |
| **Art. 5(1)(b/c)** — purpose limitation & minimisation | Collect only what the purpose needs | C8 |
| **Art. 5(1)(e) / Art. 17** — storage limitation & erasure | Retention period + RTBF/delete path | C9 |
| **Arts. 15–22** — data-subject rights | Access/export/correct/erase capability | C10 |
| **Art. 25** — data protection by design/default | Defaults minimise data; privacy built in | C7/C8 |
| **Art. 32** — security of processing | Encryption at rest/in transit, resilience | C3/C4 / `owasp` |
| **Arts. 33–34** — breach notification (72h) | Detection + logging to meet the timeline | C13 / `audit-trail` |
| **Arts. 44–49** — international transfers | Transfers outside EEA need adequacy/SCCs | C6 |

## SOC 2 (Trust Services Criteria — Common Criteria)
Not a law; an attestation auditors test against. Engineering-relevant criteria:
- **CC6 (logical access)** — least privilege, authentication, access reviews → `owasp` A01/A07,
  `audit-trail`.
- **CC7 (system operations / monitoring)** — detection of anomalies, incident response → `audit-trail`.
- **CC8 (change management)** — changes authorised, tested, logged → `audit-trail` AU06.
- Confidentiality/Privacy criteria → encryption (C3/C4) and the privacy items (C7–C10).
Auditors sample logs and configs; the same evidence the other checks produce supports SOC 2.

## Using this file
For each finding, cite the narrowest applicable control (e.g. "PCI-DSS Req. 3.2", "GDPR Art. 17"),
state code evidence, and route security/audit depth to `owasp`/`audit-trail`. Keep the legal framing
light and recommend DPO/QSA review for formal scope.
