# Threat-model output template

The deliverable format. Fill this in for the flow in scope; with `--save` write it to
`docs/threat-models/<feature>.md`. Keep it scannable — lead with the top threats, drop categories
that do not apply rather than padding.

```markdown
# Threat model — <feature / journey>

- **Scope:** <the one flow being modelled; what is in and out of scope>
- **Date / author:** <date> · <author>   (the harness has no clock — ask or leave a placeholder)
- **Actors:** <end user, backoffice operator, service, partner, attacker>
- **Assets at stake:** <money, KYC/PII, credentials, ledger integrity, availability, compliance>

## Data-flow diagram

<mermaid flowchart or a bullet list of: external entities, processes, data stores, data flows>
<mark trust boundaries explicitly>

Trust boundaries:
- <internet ↔ service: which endpoints>
- <service ↔ third party: which vendors>
- <app ↔ data store / role ↔ role / tenant ↔ tenant>

## Threats

| # | Element | STRIDE | Threat | Likelihood | Impact | Priority | Mitigation | Owner | Status |
|---|---------|--------|--------|-----------|--------|----------|------------|-------|--------|
| 1 | Gateway webhook | S | Forged webhook marks order paid | Med | High | **High** | Verify signature + dedup event id | `resilience` R10 / `money-safety` M09 | open |
| 2 | Charge handler | T | Client-supplied amount trusted | Med | High | **High** | Server-authoritative amount; verify vs gateway | `money-safety` M09 | open |
| 3 | Charge handler | — | Duplicate request double-charges | High | High | **Critical** | Idempotency key + atomic update | `money-safety` M04/M05 | open |
| 4 | customers store | I | PII returned unmasked in response | Med | High | **High** | Response DTO + mask Tier-1 | `pii-guard` P-RESP | open |
| 5 | Approve action | R | KYC approval not audited | Low | High | **High** | Audit record + immutable store | `audit-trail` AU02/AU09 | open |
| 6 | KYC vendor call | D | Vendor slowdown blocks workers | Med | Med | **Med** | Timeout + circuit breaker | `resilience` R01/R05 | open |

(Likelihood/Impact: Low/Med/High. Priority = combined. Status: open / mitigated / accepted.)

## Address first
1. <#3 — Critical: idempotency on the charge handler>
2. <#1 — High: webhook signature + dedup>
3. <#4 — High: mask PII in the response>

## Design / process items (not a code patch)
- <e.g. maker-checker on manual ledger adjustments; key custody for the card vault; data-residency
  decision for the KYC document store>

## Residual risk & notes
- <threats accepted for now and why; assumptions; what was out of scope>
- This model is a reasoning aid, not a guarantee — confirm credible threats with the owning skill
  (`owasp` / `pii-guard` / `audit-trail` / `money-safety` / `resilience` / `regtech`) before sign-off.
```

## Tips
- Order the threat table by priority; put Critical/High at the top.
- Every threat row should have a **mitigation** and an **owner** — an unowned threat is a TODO, say so.
- Prefer naming the **owning skill + category id** (e.g. `money-safety` M04) so the reader can act.
- For `--quick`, keep only the DFD bullets, the trust boundaries, and the top 3–5 threats.
