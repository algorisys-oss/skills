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
| [`teachme/`](teachme/) | Teach a concept or skill through Socratic questioning + worked examples (not lectures). Runs a diagnose → worked-example → faded-example → independent-practice → spaced-retrieval loop, calibrated to the learner's level and continued across sessions via a small workspace. `/teachme <topic>`. |

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
