---
name: money-safety
description: Identify, explain, and (on request) fix financial-correctness bugs in Node.js, TypeScript, Python, Go, and Elixir code — float-for-money, rounding/currency errors, missing idempotency on payment endpoints, non-atomic balance updates, double-spend races, and double-entry ledger imbalance. Use when the user asks to "run money-safety", "check money handling", "audit financial correctness", "idempotency check", "ledger review", "is this payment code safe", or invokes /money-safety. Built for banking, NBFC, fintech, and ecommerce ledger/payment/settlement code.
user-invocable: true
---

# money-safety

Find financial-correctness bugs in Node.js, TypeScript, Python, Go, and Elixir code, explain each
in context, and apply fixes when asked. Built for ledgers, wallets, payment/transfer/refund
endpoints, fee/interest/tax math, and settlement jobs — the code where a rounding error or a
duplicated request moves real money.

This is **correctness**, not security — it complements `owasp` (vulnerabilities) and `audit-trail`
(logging), which it cross-references rather than duplicates. The category list and severity rubric
live in `references/catalog.md`. Per-language dangerous-API → fix tables live in
`references/{nodejs,typescript,python,golang,elixir}.md`. Idempotency, double-entry, and
atomic-update patterns live in `references/patterns.md`.

## Default behavior

- **Report, do not auto-modify.** Produce a findings report; apply fixes only when the user passes
  `--fix` or explicitly asks. (Money code is reviewed before it is changed.)
- **Default scope is the whole repository.** A path or flag narrows it.

## Invocation

```
/money-safety                 Scan the whole repo, report findings
/money-safety <path>          Scan a directory or file
/money-safety --diff          Scan only changed files (uncommitted + branch vs base) — pre-commit/PR use
/money-safety --staged        Scan only git-staged files
/money-safety --fix [scope]   Scan, then apply fixes (still confirm anything risky — see step 5)
/money-safety <topic>         e.g. "money-safety check the refund endpoint", "audit the ledger postings"
```

Parse the request into a **scope** (path / `--diff` / `--staged` / whole repo) and a **mode**
(report — default — or fix). A focused topic (e.g. "the wallet debit", "settlement rounding")
narrows which categories and files to weight.

## Workflow

### 1. Detect languages, money types & data stores
Identify which of Node.js/TypeScript, Python, Go, Elixir are present (manifests: `package.json`,
`requirements.txt`/`pyproject.toml`, `go.mod`, `mix.exs`). Note the **money representation already
in use** — integer minor units, a decimal library (`decimal.js`, `dinero.js`, `bignumber.js`,
Python `Decimal`/`py-moneyed`, Go `shopspring/decimal`, Elixir `Decimal`/`ex_money`), or raw
floats — and the data store (Postgres/MySQL `NUMERIC`, Mongo, an event store). Load only the
relevant `references/*.md`.

### 2. Run the heuristic pre-filter
Run the bundled scanner to get candidate `file:line` locations fast. It is **high-recall,
low-precision** — a triage list, not a verdict.

```sh
scripts/scan.sh [PATH]        # default scope = path arg or "."
scripts/scan.sh --diff        # changed files only
scripts/scan.sh PATH --lang node|typescript|python|go|elixir   # restrict language
```

Output is `CATEGORY \t file:line \t matched text`. It prefers `ripgrep` and falls back to `grep`.
The scanner cannot see the highest-value bugs — missing idempotency, missing transaction
boundaries, ledger imbalance — so reason about those in step 4.

### 3. Map the money flows
Before triaging, list the **value-moving operations**: every endpoint or job that credits/debits a
balance, posts a ledger entry, captures/refunds a payment, or computes a fee/interest/settlement
amount. These are the spots where the design-level categories (idempotency, atomicity, double
entry) apply. The scanner will not hand you this list — derive it from routes and service methods.

### 4. Triage every candidate in context
For each scanner hit, open the file, read the matching `references/*.md` entry, and decide if it is
real. Discard false positives (e.g. a `* 100` that is a percentage, not a cents conversion). Then
add the findings grep cannot reach by reasoning about each money flow from step 3:

- **Float-for-money** — is any amount stored or computed as `float`/`double`/JS `number` where
  precision matters? (Use integer minor units or a decimal type.)
- **Rounding** — is the rounding mode explicit and consistent (banker's vs half-up), applied once
  at the right boundary, and does the sum of rounded splits equal the rounded total?
- **Currency** — do amounts carry a currency, and is cross-currency arithmetic blocked?
- **Idempotency** — can a retried/duplicated payment/transfer/refund request execute twice? Is
  there an idempotency key enforced by a unique constraint? (See `references/patterns.md`.)
- **Atomicity / races** — is balance read-modify-write done inside one transaction with a lock or
  optimistic version, or can two concurrent requests double-spend? (Cat. overlaps `owasp` Cat 19.)
- **Double-entry** — for ledgers, does every posting balance (debits == credits) inside one
  transaction, and are entries append-only?
- **Overflow / units** — minor-unit math in a type that can overflow; mixing major and minor units.
- **Time** — settlement/interest using wall-clock or wrong timezone instead of a business date.

Trace the data flow before reporting — do not flag a `Number(amount)` that is only ever a row count.

### 5. Report findings
Group by severity (Critical → High → Medium → Low/Info; see `references/catalog.md`). For each:

- **Severity** and **confidence** (heuristic hit needing confirmation vs. confirmed).
- **Category** (e.g. `Float-for-money`, `Missing idempotency`, `Ledger imbalance`).
- **Location** — `file:line` as a clickable link.
- **What & why** — one or two sentences on the financial impact in *this* code (e.g. "two
  concurrent withdrawals can both pass the balance check → overdraft").
- **Fix** — concrete remediation (snippet from the language reference or `patterns.md`, adapted).

Lead with a one-line summary (counts by severity). If scope was narrowed (e.g. `--diff`) say so —
never imply full coverage that was not performed.

### 6. Fix (only when `--fix` or explicitly requested)
Apply the smallest correct fix, preferring the money type already in the codebase. Then:

- Make low-risk, mechanical fixes directly — set an explicit rounding mode, add a `NUMERIC`/decimal
  cast, add a `UNIQUE` constraint on `(account_id, idempotency_key)`, wrap a read-modify-write in
  the framework's transaction helper.
- For changes that alter behavior or stored data — converting a `float` column to integer minor
  units (a **data migration**: existing rows must be re-encoded), changing a rounding mode (changes
  amounts), introducing optimistic-lock version columns — explain the change and the migration, and
  confirm with the user before applying.
- Never make a balance assertion looser to pass a test. After fixing, re-run the scan and note any
  fix that still needs human review (especially anything touching stored money or live ledgers).

## Boundaries

- This skill finds **common, pattern-detectable** correctness bugs and reasons about high-value
  design gaps (idempotency, atomicity, double entry). It is not a formal verification of your
  ledger and not a substitute for reconciliation testing — say so for core ledger/settlement code.
- Heuristics produce false positives (percentages, non-money floats) and miss logic-only bugs.
  Always confirm in context; always disclose what was and was not covered.
- It does not assess regulatory/compliance posture (data residency, reporting) — that is `regtech`.

## Resources

- `references/catalog.md` — the financial-correctness categories, descriptions, severity rubric.
- `references/nodejs.md` · `references/typescript.md` · `references/python.md` ·
  `references/golang.md` · `references/elixir.md` — per-language money-type signatures and fixes.
- `references/patterns.md` — idempotency keys, double-entry invariant, atomic balance updates.
- `scripts/scan.sh` — heuristic candidate finder (ripgrep/grep).
