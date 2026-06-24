# Handoff — Claude Skills monorepo

Pick-up notes for continuing this project in a new session. Open the folder
`/home/rajesh/lab/skills` and read this first.

## What this repo is

A monorepo of in-house Claude Code skills and command-based projects. Set up as a single git
repo (the user chose one repo over per-skill repos). Two things live here today:

- **`owasp/`** — a `SKILL.md` skill (the main work product of this project).
- **`code-to-docs/`** — a pre-existing Claude Code course-generator distributed as slash commands
  (`.claude/commands/`), folded in after its own `.git` was removed by the user.

## Current state (as of handoff)

- `owasp/` skill: **complete and tested.** Covers Node.js, React, Python, Elixir, Go.
- `code-to-docs/`: present, tracked, unchanged in content. Not a skill (no `SKILL.md`); `install.sh`
  intentionally skips it.
- Repo scaffolding done: `README.md`, `.gitignore`, `install.sh`, this `HANDOFF.md`.
- **Git: initialized with one local commit, no remote** (user will add a remote/push later).
  If you arrive and `git log` is empty, the init/commit step did not run — do it (see Next steps).

## Key decisions already made (do not re-litigate)

1. **One monorepo**, not per-skill repos.
2. **`owasp` default behavior: report findings, do not auto-modify.** Fixes apply only on `--fix`
   or explicit request.
3. **`owasp` default scope: whole repository** (path / `--diff` / `--staged` narrow it).
4. **`code-to-docs` is folded in** (user deleted its `.git`); it was originally the public repo
   `algorisys-oss/code-to-docs`.
5. Git: **local commit only, no remote yet.** Repo is private-intent (contains KYC domain
   knowledge in `owasp/references/domain-kyc-aiml.md`).

## Layout

```
skills/
├── README.md            # what's here + install instructions
├── HANDOFF.md           # this file
├── .gitignore           # ignores OS cruft, node_modules, __pycache__, scratchpad/, etc.
├── install.sh           # symlinks SKILL.md skills into ~/.claude/skills (skips code-to-docs)
├── owasp/
│   ├── SKILL.md         # orchestrator: triggers, workflow, report/fix policy, scopes
│   ├── references/
│   │   ├── catalog.md          # the "Top 20" categories + severity rubric
│   │   ├── nodejs.md           # per-language signature -> fix tables
│   │   ├── react.md
│   │   ├── python.md
│   │   ├── elixir.md
│   │   ├── golang.md
│   │   └── domain-kyc-aiml.md  # KYC/upload, workflow races, multi-tenant IDOR, LLM/prompt-injection
│   └── scripts/
│       └── scan.sh      # heuristic ripgrep/grep candidate finder (high recall, low precision)
└── code-to-docs/        # command-based project; .claude/commands/, CLAUDE.md, templates/
```

## How the `owasp` skill works (mental model)

`SKILL.md` drives a pipeline: detect languages → run `scripts/scan.sh` for candidate `file:line`
hits → run ecosystem auditors for dependencies (`npm audit`, `pip-audit`, `mix deps.audit`,
`govulncheck`/`gosec`, `mix sobelow`) → triage each hit in context against the matching
`references/<lang>.md` → reason about non-greppable classes (access control/IDOR, insecure design,
race conditions, AI/ML) → report grouped by severity + confidence → fix only when asked.

The "Top 20" = OWASP Top 10 (2021) + 10 extended (CSRF, XSS, mass assignment, path traversal,
insecure upload, open redirect, deserialization, secrets, race conditions, AI/ML). Defined in
`owasp/references/catalog.md`.

## scan.sh — important implementation notes

- High-recall / low-precision pre-filter. Output: `CATEGORY \t file:line \t matched text`.
- Prefers `ripgrep`, falls back to `grep`. Case-insensitive (`-i`) so camelCase identifiers match.
- **Glob filtering is done in the shell (`matches_glob`), not via rg `--glob`**, because rg
  searches explicitly-named files regardless of `--glob`. Without this, single-file and
  `--diff`/`--staged` scans would apply every language's patterns to every file (e.g. Go
  `os.ReadFile` matching the Node `readFile` pattern). Keep this if editing `search()`.
- Two known regex constraints that bit us: ripgrep's regex engine has **no lookarounds** (a
  `(?!...)` made the Python deserialization pattern silently match nothing), and Python `%s` is
  both a DB-API placeholder and a format char (the SQL pattern was tightened to flag only
  f-strings / `.format(` / `+` / `%`-operator, so parameterized queries pass clean).

### Test scan.sh quickly

```sh
cd owasp
# vulnerable fixtures live nowhere in-repo by design; create throwaway files to test, e.g.:
printf 'cursor.execute(f"SELECT %%s" %% x)\n' > /tmp/t.py && scripts/scan.sh /tmp/t.py
bash -n scripts/scan.sh          # syntax check
scripts/scan.sh . --lang go      # whole repo, Go patterns only
scripts/scan.sh --diff           # changed files only (needs a git repo)
```

## Next steps / open ideas (none are blocking)

- **If git not yet initialized:** `cd /home/rajesh/lab/skills && git init -b main && git add -A &&
  git commit` (commit message footer convention: end with the Co-Authored-By line). No remote
  unless the user asks; if pushing, make it **private** (KYC domain content).
- Run `./install.sh` to symlink `owasp` into `~/.claude/skills`, then try `/owasp` in a repo.
- Possible future work (only if user asks):
  - Add more languages (Java/Kotlin, Ruby, PHP, C#) following the `references/<lang>.md` +
    `scan.sh` block pattern.
  - Package as a proper Claude Code plugin (`.claude-plugin/plugin.json` + `skills/` subdir) and/or
    a marketplace manifest, so skills install via the plugin mechanism instead of symlinks.
  - Decide how `code-to-docs` should be exposed in this repo (its slash commands are under
    `code-to-docs/.claude/commands/`, scoped to that subfolder).
  - Add a tiny `owasp/examples/` set of intentionally-vulnerable fixtures + an expected-output
    test so `scan.sh` regressions are caught.

## Conventions to keep

- Skill `description` frontmatter: third person, concrete trigger phrases.
- `SKILL.md` body: lean (~1.5–2k words), imperative voice, point to `references/`/`scripts/`.
- Defensive security posture only: identify and remediate; no working exploits beyond minimal
  proof needed to confirm a finding.
