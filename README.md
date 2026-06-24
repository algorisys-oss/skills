# Claude Skills

A monorepo of [Claude Code](https://claude.com/claude-code) skills authored in-house.

Each top-level directory containing a `SKILL.md` is one skill. Skills are loaded by Claude Code
via [progressive disclosure](https://docs.claude.com): only the `name` + `description` are always
in context; the body loads when the skill triggers; `references/` and `scripts/` load on demand.

## Contents

### Skills (`SKILL.md`-based, symlinked into `~/.claude/skills`)

| Skill | What it does |
|-------|--------------|
| [`owasp/`](owasp/) | Identify, explain, and (on request) fix OWASP-class vulnerabilities in Node.js, React, Elixir, Python, and Go. Top 10 (2021) + 10 extended categories, with onboarding/KYC/backoffice/AI-ML domain checks. |

### Command-based projects

| Project | What it does |
|---------|--------------|
| [`code-to-docs/`](code-to-docs/) | Transform a codebase into a structured, multi-page interactive course. Distributed as Claude Code slash commands under `code-to-docs/.claude/commands/` (`/code-to-docs`), not as a `SKILL.md` skill — `install.sh` skips it. Originally [algorisys-oss/code-to-docs](https://github.com/algorisys-oss/code-to-docs). |

## Install

Symlink the skills into your personal skills directory so Claude Code discovers them:

```bash
./install.sh            # symlink every skill in this repo into ~/.claude/skills
./install.sh owasp      # symlink just one skill
```

To remove, delete the symlink: `rm ~/.claude/skills/<name>`.

Skills marked `user-invocable: true` in their frontmatter are also available as slash commands
(e.g. `/owasp`).

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
