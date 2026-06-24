# Code-to-Docs

Transform any codebase into a structured, multi-page interactive course — with real code references, multi-audience explanations, and hands-on exercises.

## What It Does

Given a code repository, this tool generates:

- **Executive Overview** — what the system does and why
- **Architecture Guide** — ASCII diagrams, component explanations, data/control flow
- **Module Deep Dives** — one page per module with multi-level explanations
- **End-to-End Flow Traces** — real function-by-function walkthroughs with file:line references
- **Interactive Practice** — quizzes, code exploration exercises, debugging challenges, mini-projects

All code references point to real files and line numbers in the repo. Nothing is fabricated.

## Setup by Agent

### Claude Code (CLI or VS Code extension)

```bash
# Copy commands into your target repo
cp -r .claude/ /path/to/your/repo/.claude/
```

Then from your repo:
```
/code-to-docs                    # Phase 1: index + plan
/code-to-docs-generate all       # Phase 2: generate content
```

Commands are auto-discovered from `.claude/commands/`. Start a new session if you just added the files.

### Cursor

Copy the skill files into Cursor's rules directory:

```bash
mkdir -p /path/to/your/repo/.cursor/rules
cp .claude/commands/code-to-docs.md /path/to/your/repo/.cursor/rules/
cp .claude/commands/code-to-docs-generate.md /path/to/your/repo/.cursor/rules/
cp .claude/commands/code-to-docs-reference.md /path/to/your/repo/.cursor/rules/
```

Then in Cursor chat:
```
@code-to-docs index this codebase
@code-to-docs-generate generate all modules
```

Or reference the files directly:
```
Follow the instructions in .cursor/rules/code-to-docs.md to index this codebase
```

### Antigravity

Copy the commands directory into your repo:

```bash
cp -r .claude/ /path/to/your/repo/.claude/
```

Then in Antigravity:
```
Follow the instructions in .claude/commands/code-to-docs.md to index this codebase
```

After Phase 1 completes:
```
Follow the instructions in .claude/commands/code-to-docs-generate.md with argument: all
```

### Codex (OpenAI)

Copy the prompt files into your repo and reference them:

```bash
cp -r .claude/commands/ /path/to/your/repo/.codex/prompts/
```

Then in Codex:
```
Read and follow the instructions in .codex/prompts/code-to-docs.md to index this codebase
```

After Phase 1:
```
Read and follow .codex/prompts/code-to-docs-generate.md with argument: all
```

### Windsurf / Cline / Aider / Any Other Agent

The skill files are agent-agnostic markdown prompts. For any agent:

1. Copy the `.claude/commands/` directory into your repo
2. Tell the agent to read and follow the prompt file:

```
Phase 1: Read .claude/commands/code-to-docs.md and follow all instructions to index this codebase
Phase 2: Read .claude/commands/code-to-docs-generate.md and follow all instructions with argument: all
```

The prompts use generic instructions (read files, search for patterns, write output) that any capable coding agent can execute.

---

## Usage

### Phase 1: Index & Plan

```
/code-to-docs
```

Or specify a subdirectory for monorepos:

```
/code-to-docs backend/
```

This produces:
- `course/00-index.json` — machine-readable metadata
- `course/01-overview.md` — executive overview
- `course/02-architecture.md` — architecture deep dive
- A **generation plan** listing all modules and flows to document

### Phase 2: Generate Content

Generate everything:
```
/code-to-docs-generate all
```

Generate a single module:
```
/code-to-docs-generate auth
```

Generate only flow traces:
```
/code-to-docs-generate --flows
```

Regenerate only modules with changed code:
```
/code-to-docs-generate --diff
```

### Keeping the Course Updated

The `--diff` flag uses a saved git SHA (`course/.last-generation-sha`) to detect which files changed since the last generation, maps them to affected modules, and regenerates only those. Updated modules get a "What Changed" banner.

**Manual (recommended to start):**
```
# After making code changes
/code-to-docs-generate --diff
```

**Automate with a git hook (post-commit):**
```bash
# .git/hooks/post-commit
#!/bin/bash
if [ -f course/.last-generation-sha ]; then
  echo "Course may be outdated. Run: /code-to-docs-generate --diff"
fi
```

**Automate with a CI step (GitHub Actions):**
```yaml
# .github/workflows/update-course.yml
name: Update Course
on:
  push:
    branches: [main]
    paths-ignore:
      - 'course/**'

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check for course changes
        run: |
          if [ -f course/.last-generation-sha ]; then
            LAST_SHA=$(cat course/.last-generation-sha)
            CHANGED=$(git diff --name-only $LAST_SHA HEAD -- lib/ src/ | head -5)
            if [ -n "$CHANGED" ]; then
              echo "::warning::Course is outdated. Changed files: $CHANGED"
              echo "Run: /code-to-docs-generate --diff"
            fi
          fi
```

**Automate with Claude Code hooks (settings.json):**
```json
{
  "hooks": {
    "PostCommit": [
      {
        "command": "echo 'Tip: run /code-to-docs-generate --diff to update the course'"
      }
    ]
  }
}
```

**Automate with a scheduled Claude Code trigger:**
```
/schedule create --name "update-course" --cron "0 9 * * 1" --prompt "/code-to-docs-generate --diff"
```

Pick whichever fits your workflow. The diff-aware approach is fast — it only touches modules whose source files actually changed.

## Output Structure

```
course/
  00-index.json              # Module list, dependencies, complexity tags
  01-overview.md             # What this system does (5-min read)
  02-architecture.md         # Interactive diagrams, component map, heatmap
  modules/
    01-auth.md               # One file per module
    02-users.md
    03-billing.md
    ...
  flows/
    login-flow.md            # Animated end-to-end traces across modules
    create-order-flow.md
  assets/
    theme.css                # Dark/light theme (warm light + Catppuccin dark)
    viewer.html              # Interactive HTML viewer with all renderers
  .last-generation-sha       # For diff-aware regeneration
```

Open `course/assets/viewer.html` in a browser to view the full interactive course.

## Course Features

### Interactive Visualizations (10 Types)

The HTML viewer renders special markdown blocks as rich, interactive JS components:

| Element | What it does |
|---------|-------------|
| **Architecture Diagram** | Clickable Mermaid.js diagrams — hover for details, click to navigate to modules |
| **Sequence Diagram** | Mermaid-based request flow diagrams |
| **Dependency Graph** | D3.js force-directed graph — zoom, pan, hover to highlight connections |
| **Animated Flow Trace** | Step-by-step walkthrough with Prev/Next controls and highlighted component lanes |
| **Group Chat** | iMessage-style conversation between system components with technical detail toggles |
| **Code Walkthrough** | Split-panel: syntax-highlighted code + step-by-step annotations |
| **Drag-and-Drop Matching** | Interactive exercise matching concepts to descriptions (touch-friendly) |
| **Spot-the-Bug** | Click suspicious code lines — wrong guesses give hints, correct guess reveals explanation |
| **Complexity Heatmap** | D3.js treemap colored by complexity, sized by LOC |
| **Architecture Minimap** | Small navigable SVG map highlighting your current position |

All elements support dark/light theme. Libraries (Mermaid, D3, Prism) load on-demand from CDN — no build step.

The markdown files also work standalone (GitHub, any markdown reader) — interactive blocks degrade to code blocks, and markdown-native quizzes/exercises use `<details>` for answers.

### Dark/Light Theme

Professional warm-palette design with full dark mode:
- **Light:** Paper-like background, charcoal text, vermillion accent
- **Dark:** Catppuccin Mocha palette, soft pink accent
- Toggle persisted in localStorage
- All interactive elements, diagrams, and syntax highlighting adapt to theme

### Multi-Audience Explanations

Every topic includes three depth levels:

- **Big Picture** — analogy-based, accessible to anyone
- **Intermediate** — implementation details with code references
- **Advanced** — performance, concurrency, edge cases, tradeoffs

### Real Code References

Every reference points to an actual file and line number:

```
1. `src/routes/auth.rs:15` — login_handler() receives POST /login
2. `src/services/auth.rs:42` — validate_credentials() checks bcrypt hash
3. `src/db/users.rs:28` — find_by_email() queries PostgreSQL
```

### Interactive Practice

Each module includes:
- Drag-and-drop matching exercises
- Spot-the-bug debugging challenges with progressive hints
- Markdown quizzes with hidden answers (works without HTML viewer)

### Complexity Tags

Modules are tagged: **Simple** | **Moderate** | **Complex** | **Critical**

### Diff-Aware Updates

After code changes, run `/code-to-docs-generate --diff` to update only affected modules. Changed modules get a "What Changed" banner.

## Using Without Slash Commands

If your agent doesn't support slash commands, you can use the prompt files directly:

```
# Phase 1: paste or reference the prompt
"Follow the instructions in .claude/commands/code-to-docs.md to index this codebase"

# Phase 2: same approach
"Follow the instructions in .claude/commands/code-to-docs-generate.md with argument: all"
```

## Files

| File | Purpose |
|------|---------|
| `.claude/commands/code-to-docs.md` | Phase 1 skill: index, architecture, plan |
| `.claude/commands/code-to-docs-generate.md` | Phase 2 skill: module & flow content generation |
| `.claude/commands/code-to-docs-reference.md` | Shared templates, conventions, 10 interactive element data formats |
| `templates/viewer.html` | Interactive HTML viewer with rendering pipeline for all 10 element types |
| `templates/theme.css` | Dark/light theme stylesheet with styles for all interactive elements |
| `CLAUDE.md` | Full specification and design philosophy |

## Design Philosophy

- **Not documentation** — a developer's mental model of the system
- **Architecture-first** — understand the forest before the trees
- **Layered knowledge** — progressive disclosure from overview to internals
- **Learning by doing** — every module includes hands-on practice
- **Incremental** — generate, review, regenerate. Never a single monolithic dump

## Inspired By

[codebase-to-course](https://github.com/zarazhangrui/codebase-to-course) — improved with modular output, real code references, multi-audience depth, interactive exercises, and agent-agnostic design.
