---
name: threat-model
description: Produce a STRIDE threat model for a feature, endpoint, or user journey — enumerate the data-flow diagram (entry points, processes, data stores, trust boundaries, external deps), derive threats per element with STRIDE, rate them, and map each to a concrete mitigation and the skill that owns the fix. Use when the user asks to "run threat-model", "threat model this feature", "STRIDE review", "what could go wrong with this flow", "security design review", "model threats for the onboarding journey", or invokes /threat-model. Built for banking/NBFC/fintech/ecommerce journeys (onboarding, KYC, payments, payouts, backoffice).
user-invocable: true
---

# threat-model

Produce a structured **STRIDE** threat model for a feature, endpoint, or user journey: map the
data-flow, enumerate what can go wrong at each element and trust boundary, rate each threat, and tie
every credible one to a concrete mitigation. This is the **design-level, preventive** skill — it
reasons about what *could* go wrong before it ships, where the sibling skills (`owasp`, `pii-guard`,
`audit-trail`, `money-safety`, `resilience`, `regtech`) *detect* and *fix* specific instances. The
threat model points at them: each mitigation names the skill that owns the deep check.

The STRIDE category guidance lives in `references/stride.md`; how to build the data-flow diagram and
find trust boundaries lives in `references/dfd.md`; the threat→control→owning-skill mapping lives in
`references/mitigations.md`; the output document format lives in `references/template.md`.

## Default behavior

- **Produce a threat-model document** (the analysis is the deliverable). It does not modify product
  code; on request it saves the model to a file and can hand specific threats to the owning skill to
  remediate.
- **Scope is one feature / endpoint / journey** — threat modelling is per-flow, not whole-repo. Ask
  for the target if not given (e.g. "the video-KYC upload", "the payout endpoint").

## Invocation

```
/threat-model <feature/journey>     Model a feature or journey by name
/threat-model <path>                Model the flow implemented under a path (routes/handlers/services)
/threat-model --save [file]         Write the model to docs/threat-models/<feature>.md (default)
/threat-model --quick               Lightweight pass (key elements + top threats only)
```

Parse the request into a **target flow** and depth (`--quick` vs full). If the target is unclear,
ask which feature/journey to model before proceeding — a threat model needs a defined boundary.

## Workflow

### 1. Scope the flow
State the feature/journey, its **actors** (end user, staff/backoffice, service, attacker), the
**assets** at stake (money, KYC/PII, credentials, ledger integrity, availability), and the
in/out-of-scope boundary. A tight scope makes the model usable; "the whole app" does not.

### 2. Build the data-flow diagram (DFD)
Use `references/dfd.md`. Enumerate the elements of *this* flow:
- **External entities** — who/what initiates (user, partner API, gateway webhook, batch job).
- **Processes** — the handlers/services/functions that act (auth, KYC decision, charge, ledger post).
- **Data stores** — DB tables, cache, queue, object storage, secrets.
- **Data flows** — each call/message between the above, with what data it carries.
- **Trust boundaries** — where control/trust changes: internet↔service, service↔third party,
  app↔DB, user-role↔admin, tenant↔tenant. **Threats cluster on boundaries.**

Run the bundled scanner (step 3) to seed this from code when a path is given.

### 3. Run the attack-surface enumerator
For a path-based target, run the scanner to list the concrete elements fast.

```sh
scripts/scan.sh [PATH]        # default scope = path arg or "."
scripts/scan.sh --diff        # the surface introduced by a change
```

Output is `ELEMENT \t file:line \t matched text` — entry points (routes), external calls, data
stores, auth checks, file uploads, and queues. It seeds the DFD; you decide which belong to the flow.

### 4. Enumerate threats with STRIDE
Walk each DFD element and apply the STRIDE categories that fit it (see `references/stride.md` for the
element→category matrix and fintech examples):
- **S**poofing — identity faked (weak auth, stolen token, unverified webhook sender).
- **T**ampering — data/parameter/ledger/amount manipulated in transit or at rest.
- **R**epudiation — actor denies an action; no/forgeable audit trail. (→ `audit-trail`.)
- **I**nformation disclosure — PII/CHD/secret leakage. (→ `pii-guard`, `owasp`.)
- **D**enial of service — resource exhaustion, retry storms, missing rate limits. (→ `resilience`.)
- **E**levation of privilege — IDOR, missing authz, role bypass, tenant crossing. (→ `owasp` A01.)
Also weigh the fintech-specific design threats: **double-spend / idempotency** (→ `money-safety`),
**business-logic abuse** (coupon/limit/refund), and **regulatory exposure** (→ `regtech`).

### 5. Rate each threat
For each credible threat give **likelihood** (how reachable/easy) × **impact** (money, data,
compliance, availability) → a priority (Critical/High/Medium/Low). Note existing controls already in
the code (from the scanner / your reading) so you do not over-rate a mitigated threat. Drop threats
that do not apply to this flow rather than padding the list.

### 6. Map to mitigations and owners
For each kept threat, give a **concrete mitigation** and name the **owning skill** that detects/fixes
it (see `references/mitigations.md`). This makes the model actionable: a Spoofing-of-webhook threat
→ "verify gateway signature + dedup event id (`resilience` R10, `money-safety` M09)". Distinguish
mitigations that are **code** (route to a skill) from **design/process** (auth model, segregation of
duties, key custody — a human decision).

### 7. Deliver the threat model
Produce the document per `references/template.md`: scope, DFD (elements + trust boundaries as a
list/mermaid), the threat table (element · STRIDE · threat · likelihood/impact · mitigation · owner ·
status), and a prioritised "address first" list. Lead with the top 3–5 threats. If `--save` was
passed, write it to `docs/threat-models/<feature>.md` (create the dir) and tell the user the path.
Offer to invoke the owning skills on the highest-priority threats.

## Boundaries

- A threat model is a **structured reasoning aid, not a guarantee** — it surfaces plausible threats
  for review; it does not prove their presence or absence. Confirm exploitability via the detective
  skills before treating a threat as a real finding. Say so.
- Quality depends on scope: model one flow well rather than everything shallowly. Decline to "threat
  model the whole system" in one pass — propose modelling its top journeys in turn.
- It defers all *detection and fixing* to the owning skills; it does not re-implement their checks.

## Resources

- `references/stride.md` — STRIDE categories, the element→category matrix, fintech threat examples.
- `references/dfd.md` — building the data-flow diagram, finding trust boundaries.
- `references/mitigations.md` — threat → control → owning skill (`owasp`/`pii-guard`/`audit-trail`/
  `money-safety`/`resilience`/`regtech`).
- `references/template.md` — the threat-model output document format.
- `scripts/scan.sh` — attack-surface enumerator (routes, external calls, stores, authz, uploads, queues).
