# STRIDE — categories, matrix, fintech examples

STRIDE classifies threats by what they violate. Use the **element→category matrix** to know which
categories to apply to each DFD element (not every category fits every element), then the fintech
examples to make threats concrete.

| STRIDE | Violates | One-line meaning |
|---|---|---|
| **S**poofing | Authenticity | Pretending to be someone/something you are not |
| **T**ampering | Integrity | Modifying data or code in transit or at rest |
| **R**epudiation | Non-repudiation | Denying an action with no provable record |
| **I**nformation disclosure | Confidentiality | Exposing data to someone not authorised |
| **D**enial of service | Availability | Making the system unusable/slow |
| **E**levation of privilege | Authorisation | Doing something you should not be allowed to |

## Element → applicable categories
- **External entity** (user, partner, webhook sender): **S**, **R**.
- **Process** (handler/service/function): **S T R I D E** (all apply — the richest element).
- **Data store** (DB, cache, queue, object store, secrets): **T I D** (and **R** for logs/audit).
- **Data flow** (a call/message between elements): **T I D** (and **S** at a trust boundary).

Apply categories where the element crosses a **trust boundary** first — that is where threats are
real rather than theoretical.

## Fintech threat examples by category

### Spoofing
- Forged or replayed **gateway/UPI webhook** marking an order paid (no signature verify / no dedup).
- Stolen/sessions or JWT with `alg:none`; OTP/credential stuffing on login.
- Partner/service calling an internal API without mutual auth.

### Tampering
- Client-supplied **amount/price** trusted (`amountPaid` from the body); coupon/discount tampering.
- Parameter tampering to change **another account's** id (also EoP/IDOR).
- **Ledger/balance** modified directly (not via reversing entries); request replay altering state.
- Mass-assignment setting `is_admin`/`kyc_verified`/`balance`.

### Repudiation
- A money movement, KYC approval, or role grant with **no audit record**, or a **mutable** audit log
  an insider can edit — the actor can deny it happened.

### Information disclosure
- **PII/CHD in logs**, error responses, or analytics; full PAN/Aadhaar in an API response.
- IDOR returning another customer's statement/KYC document.
- Secrets in client bundles; verbose stack traces; SSRF reaching cloud metadata.

### Denial of service
- No **rate limit** on OTP/login/KYC/payment → resource exhaustion and cost abuse.
- A slow third party (bureau, KYC vendor) with **no timeout/breaker** blocking all workers.
- **Retry storms** amplifying a partial outage; unbounded fan-out/queues.

### Elevation of privilege
- Missing **function-level authz** on a backoffice action; horizontal **tenant crossing**.
- Forced browsing to an admin route; role/limit change without maker-checker.
- Privilege via injection (SQL/command) — also Tampering/Disclosure.

## Fintech design threats that ride alongside STRIDE
- **Double-spend / idempotency** (Tampering + business logic): a retried/duplicated payment executing
  twice. Owned by `money-safety` (M04/M05).
- **Business-logic abuse**: refund-more-than-paid, negative quantities, limit/velocity bypass,
  coupon stacking. Reason about invariants, not signatures.
- **Regulatory exposure**: data residency, consent, retention gaps triggered by the flow. Owned by
  `regtech`.

## Using this file
For each DFD element, list the applicable categories, then ask the concrete "how could an attacker…"
question per category using these examples. Keep only threats credible for *this* flow; map each to
`mitigations.md`.
