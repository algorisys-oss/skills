# Threat → control → owning skill

Every credible threat in the model gets a concrete mitigation and an **owner**: the sibling skill
that detects and fixes that class (so the model is actionable, not just a list), or "design/process"
when the fix is a human decision rather than code. Use this table to fill the *mitigation* and
*owner* columns of the threat table.

## By STRIDE category

### Spoofing
| Threat | Mitigation | Owner |
|---|---|---|
| Forged/replayed webhook | Verify provider signature; dedup on event id | `resilience` R10, `money-safety` M09 |
| Weak/forgeable session/JWT | Strong auth, pinned alg, short-lived tokens, MFA on privileged actions | `owasp` A07 |
| Credential stuffing / OTP brute force | Rate limit + lockout on auth/OTP | `owasp` A04, `resilience` R08 |
| Service-to-service impersonation | mTLS / signed service identity | design/process |

### Tampering
| Threat | Mitigation | Owner |
|---|---|---|
| Client-supplied amount/price trusted | Server-side authoritative amount; verify vs gateway | `money-safety` M09 |
| Parameter/ID tampering | Ownership/tenant checks (also EoP) | `owasp` A01 |
| Ledger/balance mutated directly | Append-only entries, reversing corrections, balanced postings | `money-safety` M05/M06 |
| Mass assignment (`is_admin`, `balance`) | Explicit field allowlist | `owasp` Cat 13 |
| Injection altering data | Parameterise / safe APIs | `owasp` A03 |

### Repudiation
| Threat | Mitigation | Owner |
|---|---|---|
| Action with no provable record | Audit record (actor/action/target/before-after/time) | `audit-trail` AU01–AU08 |
| Audit log editable | Append-only + tamper-evidence (hash chain/WORM) | `audit-trail` AU09/AU10 |

### Information disclosure
| Threat | Mitigation | Owner |
|---|---|---|
| PII/CHD in logs/responses/analytics | Mask/tokenise/redact at the sink | `pii-guard` (P-LOG/P-RESP/P-3P) |
| IDOR leaking another user's data | Access control on every record fetch | `owasp` A01 |
| Secrets exposed / in client bundle | Secret manager; nothing sensitive client-side | `owasp` Cat 18 |
| Weak crypto / TLS off | Strong crypto at rest & in transit | `owasp` A02 |
| SSRF to internal/metadata | Allowlist hosts, block link-local | `owasp` A10 |
| Regulated data out of region / no consent | Residency, consent, retention controls | `regtech` C6/C7/C9 |

### Denial of service
| Threat | Mitigation | Owner |
|---|---|---|
| No rate limit (OTP/login/payment) | Rate limiting / quotas | `resilience` R08, `owasp` A04 |
| Slow dependency blocks workers | Timeout + circuit breaker + bulkhead | `resilience` R01/R05/R06 |
| Retry storm | Bounded retries, backoff+jitter | `resilience` R02 |
| Unbounded pool/fan-out | Pool limits, capped concurrency | `resilience` R07 |

### Elevation of privilege
| Threat | Mitigation | Owner |
|---|---|---|
| Missing function-level authz | Enforce role/permission per action | `owasp` A01 |
| Tenant crossing | Tenant scoping on every query | `owasp` A01 |
| Privileged change without dual control | Maker-checker / segregation of duties | design/process + `audit-trail` |

## Fintech design threats
| Threat | Mitigation | Owner |
|---|---|---|
| Double-spend / duplicate payment | Idempotency key + atomic balance update | `money-safety` M04/M05 |
| Inconsistent multi-step money flow | Transactional outbox + reconciliation | `money-safety` M10 |
| Business-logic abuse (refund>paid, neg qty, coupon stack) | Enforce invariants server-side; limits/velocity | design/process (+ tests) |
| Compliance exposure from the flow | Map to controls | `regtech` |

## Using this table
- Prefer a **code** owner where one exists — it makes the threat fixable now; offer to run that skill.
- Mark **design/process** threats clearly: they need an architecture or policy decision (auth model,
  key custody, segregation of duties), not a code patch.
- A threat can have layered mitigations (e.g. webhook spoofing → signature *and* dedup *and* audit);
  list the primary owner and note the others.
