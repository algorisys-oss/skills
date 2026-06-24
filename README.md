# Claude Skills

A monorepo of [Claude Code](https://claude.com/claude-code) skills authored in-house.

Each top-level directory containing a `SKILL.md` is one skill. Skills are loaded by Claude Code
via [progressive disclosure](https://docs.claude.com): only the `name` + `description` are always
in context; the body loads when the skill triggers; `references/` and `scripts/` load on demand.

## Contents

### Skills (`SKILL.md`-based, symlinked into `~/.claude/skills`)

| Skill | What it does |
|-------|--------------|
| [`owasp/`](owasp/) | Identify, explain, and (on request) fix OWASP-class vulnerabilities in Node.js, TypeScript, React, SolidJS, Elixir, Python, and Go. Top 10 (2021) + 10 extended categories, with onboarding/KYC/backoffice/AI-ML domain checks. |
| [`money-safety/`](money-safety/) | Find financial-correctness bugs in Node.js, TypeScript, Python, Go, and Elixir — float-for-money, rounding/currency errors, missing idempotency on payment endpoints, non-atomic balance updates, double-spend races, double-entry ledger imbalance. For banking/NBFC/fintech/ecommerce ledger & payment code. `/money-safety`. |
| [`audit-trail/`](audit-trail/) | Find audit-logging gaps — sensitive operations (money movement, KYC/AML decisions, role/limit changes, auth, data export) with no audit record, records missing required fields, mutable/tamper-evident-less audit stores, and PII written into logs. Maps to PCI Req. 10 / RBI / DPDP / SOC2. `/audit-trail`. |
| [`resilience/`](resilience/) | Find reliability gaps in external integrations — calls with no timeout, retries without backoff/jitter, non-idempotent retries, missing circuit breakers/bulkheads, unbounded pools, fragile webhooks. For gateway/UPI-NPCI/bureau/KYC-vendor integrations. `/resilience`. |
| [`regtech/`](regtech/) | Map code & data flows against PCI-DSS/GDPR/SOC2 (global) and RBI/DPDP/NPCI/SEBI/Account Aggregator (India): data residency, consent, retention/erasure, encryption, PII inventory, access accountability. Orchestrates `owasp`/`audit-trail`/`money-safety` for security & logging controls. `/regtech`. |
| [`pii-guard/`](pii-guard/) | Find PII/PCI data (card PAN, CVV, income-tax PAN, Aadhaar, account number, IFSC, UPI VPA, passport, DOB, name, email, phone, biometrics) leaking into logs, error trackers, analytics, API responses, URLs, caches, and non-prod — plus plaintext-at-rest and missing masking/tokenisation. Owns the masking/redaction patterns; India-aware value formats. `/pii-guard`. |
| [`threat-model/`](threat-model/) | Produce a STRIDE threat model for a feature/endpoint/journey — enumerate the data-flow diagram and trust boundaries, derive threats per element, rate them, and map each to a concrete mitigation and the skill that owns the fix. Saves to `docs/threat-models/<feature>.md`. The preventive, design-level counterpart to the detective skills. `/threat-model <feature>`. |
| [`teachme/`](teachme/) | Teach a concept or skill through Socratic questioning + worked examples (not lectures). Runs a diagnose → worked-example → faded-example → independent-practice → spaced-retrieval loop, calibrated to the learner's level and continued across sessions via a small workspace. `/teachme <topic>`. |

#### Using `owasp` — scan vs. fix

`owasp` **reports by default and never modifies your code unless you ask.** Fixing is opt-in:

```
/owasp                 Scan the whole repo and report findings (no changes)
/owasp <path>          Scan a directory or file
/owasp --diff          Scan only changed files (pre-commit / PR use)
/owasp --staged        Scan only git-staged files
/owasp --fix [scope]   Scan, then apply fixes
```

When fixing, it splits changes by risk:

- **Mechanical / low-risk fixes are applied directly** — e.g. parameterize a SQL query, add
  `httpOnly`/`secure`/`sameSite` cookie flags, pin a JWT algorithm, add `rel="noopener"`.
- **Behavior-changing fixes are explained and confirmed first** — auth/authz logic, removing
  deserialization, tightening CORS, redirect allowlists, or anything needing a migration (e.g.
  `md5` → `bcrypt`/`argon2` changes the stored-hash format).

It never weakens a control to make a test pass, and **re-runs the scan after fixing** to confirm
the signature is gone — flagging anything that still needs a human security review.

#### The fintech skills follow the same scan-vs-fix model

[`money-safety`](money-safety/), [`audit-trail`](audit-trail/), [`resilience`](resilience/),
[`regtech`](regtech/), and [`pii-guard`](pii-guard/) are built on the same contract as `owasp`:
**report by default, never modify code unless you pass `--fix`**, the same `<path>` / `--diff` /
`--staged` scoping, mechanical fixes applied directly while behavior-changing ones (data migrations,
consent gates, breaker thresholds, retrying a non-idempotent call) are explained and confirmed
first, and a re-scan after fixing. They cross-reference rather than duplicate each other — `regtech`
orchestrates `owasp`/`audit-trail`/`money-safety` for the security and logging controls, `resilience`
defers operation idempotency to `money-safety`, and `pii-guard` owns the masking/redaction depth that
`regtech` and `audit-trail` point at. `regtech` additionally states it is **not legal advice**.

[`threat-model`](threat-model/) is the odd one out: it is **preventive, not detective** — instead of
scanning for and fixing instances, it produces a STRIDE threat-model *document* for one flow and maps
each threat to the detective skill that owns the fix. Use it at design time; use the others to find
and fix.

### Command-based projects

| Project | What it does |
|---------|--------------|
| [`code-to-docs/`](code-to-docs/) | Transform a codebase into a structured, multi-page interactive course. Distributed as Claude Code slash commands under `code-to-docs/.claude/commands/` (`/code-to-docs`), not as a `SKILL.md` skill — `install.sh` skips it. Originally [algorisys-oss/code-to-docs](https://github.com/algorisys-oss/code-to-docs). |

## Install

There are two ways to install a skill, depending on whether you want it for **yourself everywhere**
or **shared with everyone working in one project**.

### Option A — Personal, all your repos (symlink)

Symlink the skills into your personal skills directory so Claude Code discovers them in every repo
you open on this machine:

```bash
git clone https://github.com/algorisys-oss/skills
cd skills
./install.sh            # symlink every skill in this repo into ~/.claude/skills
./install.sh owasp      # symlink just one skill
```

To remove, delete the symlink: `rm ~/.claude/skills/<name>`. Because it is a symlink, editing the
skill here updates it everywhere. (Override the target with `CLAUDE_SKILLS_DIR=... ./install.sh`.)

### Option B — Add a skill to an existing project (committed, shared with your team)

Vendor the skill into the target project's `.claude/skills/` and commit it. Then anyone who clones
that project gets the skill automatically — no install step, no dependency on this repo.

```bash
# 1. Get this repo (anywhere outside your project)
git clone https://github.com/algorisys-oss/skills /tmp/skills

# 2. Copy the skill you want into your project
cd /path/to/your-project
mkdir -p .claude/skills
cp -R /tmp/skills/owasp .claude/skills/owasp

# 3. Commit it so your team gets it too
git add .claude/skills/owasp
git commit -m "Add owasp security-scan skill"
```

That's it — open the project in Claude Code and the skill is available (e.g. `/owasp`, or just ask
for a "security scan"). **Copy, don't symlink**, for this mode: a symlink would point at a path that
doesn't exist on a teammate's machine. To update later, re-copy the folder and commit the diff.

> Project skills under `.claude/skills/` take precedence and are great for repo-specific tooling;
> the personal symlink (Option A) is better when you want the same skill across many repos.

Skills marked `user-invocable: true` in their frontmatter are also available as slash commands
(e.g. `/owasp`) in both modes.

## Using these skills in other agents (Cursor, Google Antigravity, Windsurf, Copilot…)

Every skill here is just **portable Markdown + a plain shell script** — there is nothing
Claude-specific about the analysis. Claude Code is the only tool that *natively* discovers a
`SKILL.md` and exposes it as a `/slash-command`; other agentic editors have no `SKILL.md` loader
(they use their own rules/instructions formats). But you can still use these skills in them two ways:

**1. Run the scanners directly — works in any tool, no skill support needed.**
`scripts/scan.sh` is ordinary `bash` + `ripgrep`/`grep`. Run it from the integrated terminal of
Cursor / Antigravity / Windsurf / VS Code (or a CI step) and feed the output to that tool's agent:

```bash
# clone once, anywhere
git clone https://github.com/algorisys-oss/skills ~/.agent-skills

# then, in your project, run a scanner and let the IDE's agent triage the hits
~/.agent-skills/owasp/scripts/scan.sh src/ > /tmp/owasp.txt
~/.agent-skills/pii-guard/scripts/scan.sh src/ --diff
```

Then ask the agent: *"Triage these `file:line` hits using the guidance in `~/.agent-skills/owasp/`."*

**2. Point the agent at the `SKILL.md` as an instruction file.** The body is a self-contained
playbook; any agent that can read repo files can follow it. Two common wirings:

- **Cursor** — add a rule that references the skill, or `@`-mention the file in chat:
  ```md
  <!-- .cursor/rules/owasp.mdc -->
  When asked to run a security scan, follow ~/.agent-skills/owasp/SKILL.md:
  run scripts/scan.sh, then triage each hit against references/<language>.md.
  ```
  or just type in Cursor chat: `@owasp/SKILL.md follow this to scan src/`.
- **Google Antigravity / Windsurf / Copilot / any AGENTS.md-aware agent** — these read agent
  instruction files and support MCP/terminal tools. Vendor a skill into the project (Option B above)
  and add a pointer in your `AGENTS.md` so the agent knows it exists:
  ```md
  ## Skills
  - Security scan: follow `.claude/skills/owasp/SKILL.md` (run its `scripts/scan.sh`, triage hits).
  - PII / data-protection: `.claude/skills/pii-guard/SKILL.md`.
  - Threat model a feature: `.claude/skills/threat-model/SKILL.md`.
  ```
  Then prompt the agent: *"Threat-model the payments flow using the threat-model skill."*

The skills are deliberately built so the **deterministic part** (the `scan.sh` heuristics) is separable
from the **reasoning part** (the `SKILL.md` + `references/`). That split is what makes them portable:
the scanner runs anywhere, and the playbook is plain English any capable agent can execute.

## Authoring conventions

Skills in this repo follow the Claude Code skill-development guidance:

- **Frontmatter `description`** uses third person with concrete trigger phrases
  (`"run owasp"`, `"security scan"`, …) — this is what decides when the skill loads.
- **`SKILL.md` body** is lean (target ~1,500–2,000 words), written in imperative form, and points
  to bundled resources rather than inlining everything.
- **`references/`** holds detailed material loaded on demand (catalogs, per-language tables).
- **`scripts/`** holds deterministic, executable helpers (e.g. `owasp/scripts/scan.sh`).

### Add a new skill

```bash
mkdir -p my-skill/{references,scripts}
$EDITOR my-skill/SKILL.md     # frontmatter: name, description, optional user-invocable: true
./install.sh my-skill
```
