# CLAUDE.md - Project Instructions

## Project Overview
<!-- Fill this in with your project details -->
This project is {{PROJECT_NAME}}: {{PROJECT_DESCRIPTION}}.

See `PRD.md` for full product requirements.

## Tech Stack
- Language: {{LANGUAGE}}
- Framework: {{FRAMEWORK}}
- Package Manager: {{PACKAGE_MANAGER}}

## Project Structure
```
├── CLAUDE.md              # Project instructions for Claude
├── PRD.md                 # Product requirements document
├── PROMPT.md              # Ralph Loop iteration prompt
├── TASKS.md               # Discrete tasks to complete
├── PROGRESS.md            # Per-task progress log
├── ralph.zsh              # Ralph Loop driver script
├── agents/
│   ├── PRODUCT-DESIGNER.md    # Planning: product vision, UX, feature design
│   ├── SOFTWARE-ARCHITECT.md  # Planning: infrastructure, security, tech architecture
│   ├── FRONTEND-ENGINEER.md   # Implementation: UI, styling, accessibility
│   ├── BACKEND-ENGINEER.md    # Implementation: APIs, business logic, middleware
│   ├── DATABASE-ENGINEER.md   # Implementation: schema, migrations, queries
│   ├── DEVOPS-ENGINEER.md     # Implementation: CI/CD, Docker, deployment
│   ├── QA-ENGINEER.md         # Implementation: test infrastructure, E2E, screenshots
│   ├── SECURITY-ENGINEER.md   # Implementation: auth, validation, OWASP
│   ├── FULLSTACK-ENGINEER.md  # Implementation: cross-cutting frontend + backend
│   └── CODE-REVIEWER.md      # Review: post-implementation audit
└── src/                   # Source code (adjust to your project)
```

## Workflow: Plan Then Build
This project enforces a strict separation between **planning** and **implementation**.

### Phase 1: Planning (no code written)
Two planning agents generate tasks. They NEVER write code:

- **Product Designer** (`agents/PRODUCT-DESIGNER.md`) — Owns product vision, UX, and feature design. Writes PRD.md and generates user-facing tasks. Makes design decisions autonomously, asks the user only for genuinely ambiguous tradeoffs. Tags infrastructure tasks with `[ARCH]` for the Software Architect.

- **Software Architect** (`agents/SOFTWARE-ARCHITECT.md`) — Owns infrastructure, security, and technical architecture. Configures CLAUDE.md (tech stack, commands, dependencies). Generates `[ARCH]` technical tasks and reviews `[ARCH]`-tagged tasks from the Product Designer.

Invoke them in a Claude session:
```
"Read agents/PRODUCT-DESIGNER.md and follow its instructions"
"Read agents/SOFTWARE-ARCHITECT.md and follow its instructions"
```

### Post-Implementation Review
After completing tasks, invoke the Code Reviewer to audit changes:
```
"Read agents/CODE-REVIEWER.md and review the recent changes"
```

### Phase 2: Implementation (Ralph Loop with specialized agents)
Once tasks exist in TASKS.md, **only the Ralph Loop executes them** — via `ralph.zsh` or an interactive Claude session with `"Read PROMPT.md and follow its instructions"`. No agent should implement features inline during a planning conversation.

Each task MUST be tagged with a specialized implementation agent (e.g., `[@frontend]`, `[@backend]`). Ralph loads the corresponding agent file from `agents/` for domain-specific guidance. Tasks without an agent tag are invalid and must not be executed.

### Agent Reference

| Tag | Agent File | Scope |
|-----|-----------|-------|
| `[@frontend]` | `agents/FRONTEND-ENGINEER.md` | UI components, styling, responsive design, accessibility |
| `[@backend]` | `agents/BACKEND-ENGINEER.md` | API endpoints, business logic, middleware |
| `[@database]` | `agents/DATABASE-ENGINEER.md` | Schema design, migrations, ORM models, queries |
| `[@devops]` | `agents/DEVOPS-ENGINEER.md` | CI/CD pipelines, Docker, deployment, env setup |
| `[@qa]` | `agents/QA-ENGINEER.md` | Test infrastructure, E2E tests, screenshots |
| `[@security]` | `agents/SECURITY-ENGINEER.md` | Auth, validation, CORS/CSRF, encryption |
| `[@fullstack]` | `agents/FULLSTACK-ENGINEER.md` | Cross-cutting frontend + backend (default) |
| `[@reviewer]` | `agents/CODE-REVIEWER.md` | Post-implementation review and audit |

### Task Format
```
- [ ] Task N: Short title — Description [@agent-tag]
- [ ] Task N: [ARCH] Short title — Description [@devops]
- [ ] Task N: [OPUS] Complex title — Description [@fullstack]
```

### Model Tags
Tasks are run with Sonnet by default for speed. Add these tags to force Opus for complex tasks:
- `[MILESTONE]` — Major integration milestones (auto-detected by ralph.zsh)
- `[E2E]` — End-to-end test tasks (auto-detected)
- `[OPUS]` — Manually tagged complex tasks requiring deeper reasoning (cross-file audits, multi-system changes, architectural work)

### The Rule
**Prefer tasks for all meaningful work.** New features, multi-file changes, and anything that needs integration tests should be a task in TASKS.md and implemented by Ralph. Small bug fixes, config tweaks, and quick adjustments can be done inline when the user drives an interactive session.

## Key Commands
<!-- Fill in your project's commands -->
- Build: `{{BUILD_COMMAND}}`
- Test: `{{TEST_COMMAND}}`
- Lint: `{{LINT_COMMAND}}`
- Run: `{{RUN_COMMAND}}`

## Coding Conventions
<!-- Add your project's conventions -->
- {{CONVENTION_1}}
- {{CONVENTION_2}}
- {{CONVENTION_3}}

## Ralph Loop Instructions
When operating in Ralph Loop mode (invoked via `ralph.zsh`), follow these rules:

1. **Find your task** — Search TASKS.md for the first unchecked task (`- [ ]`). Read only that task, not the full file.
2. **Skim PROGRESS.md** — Read the last ~5 entries for recent context. Older entries are in PROGRESS-ARCHIVE.md.
3. **Complete exactly ONE task** per iteration
4. **Write tests (tiered by domain)** — See PROMPT.md step 7 for tier definitions.
   T1 always required. T2 for `[@frontend]`/`[@fullstack]`/`[@qa]`.
   T3 for `[@qa]`, `[E2E]`/`[MILESTONE]`, or every 5 completed tasks. Do not mark a task complete without passing all required-tier tests.
5. **Capture screenshots** — If the project has a visual UI, capture screenshots during the test run (not separately). Use `CAPTURE_SCREENSHOTS=1 CAPTURE_TASK=<N>` env vars to scope captures to the current task. Save to `screenshots/` and embed in PROGRESS.md.
6. **Mark the task as done** in TASKS.md (`- [x]`)
7. **Log your work** in PROGRESS.md — keep entries brief (see PROMPT.md step 10 for format)
8. **Run tests/build** after each change to verify nothing is broken. Run all T1 tests plus any new tests you wrote. Run T2 tests only if the agent tag requires it (`[@frontend]`, `[@fullstack]`, `[@qa]`). Run T3 tests only when triggered (every 5 completed tasks, `[E2E]`/`[MILESTONE]` tags, or `[@qa]` tasks). All required-tier tests MUST pass. **If tests you did NOT write are now failing**, `git stash` your changes, fix the pre-existing failure, commit the fix with `ralph: fix pre-existing test failure during task [N]`, then `git stash pop` and continue.
9. **Commit your changes** with a descriptive message referencing the task
10. **Print a structured summary** to stdout after committing (see PROMPT.md step 12)
11. Do NOT skip ahead or do multiple tasks at once
12. **NEVER modify completed (`- [x]`) or in-progress tasks in TASKS.md.** Only unchecked/unstarted tasks (`- [ ]`) may be edited, reordered, or removed. Completed and in-progress tasks are immutable records.
13. If a task is blocked, note it in PROGRESS.md and move to the next unblocked task

## Task Ordering: Dependencies First, Then UI-First
When generating or ordering tasks in TASKS.md, **set up external dependencies early** and then **prioritize getting a visible, working UI as soon as possible** so that progress is verifiable by human eyes. Follow this order:

1. **External dependency setup** — `[@devops]` tasks that create `docker-compose.yml`, `Dockerfile`, `.env.example`, and any other config files needed to run external services. These tasks create the files but do NOT run docker — the task description tells the user what commands to run (e.g., `docker compose up -d`). This lets the user have services running before backend tasks begin.
2. **Project scaffolding & dev server** — The app should be runnable immediately
3. **Basic UI shell & layout** — Navigation, page structure, visible skeleton
4. **Core UI screens/pages** — Render with hardcoded/mock data if backend isn't ready
5. **Screenshot & test infrastructure** — Playwright or equivalent set up early
6. **Data models & backend logic** — Wire real data into already-visible UI
7. **Feature refinement & edge cases** — Polish once the UI is demonstrably working

The goal: a human reviewing PROGRESS.md should be able to see screenshots proving real UI progress within the first few tasks, not just backend plumbing. External services should be ready before any task that needs them.

## External Dependencies & Forbidden Commands
Ralph MUST NOT directly run certain commands. These require the user to execute them manually outside of Claude.

### Forbidden commands
- `docker`, `docker-compose`, `docker compose` (and all subcommands)
- Any other commands listed in `## External Dependencies` below

### External Dependencies
<!-- Define services/dependencies that must be running before Ralph can proceed.
     Each entry has:
       - name: human-readable label
       - check: command Ralph CAN run to verify the dependency is available
       - start: command the USER must run manually (Ralph prints this)
       - required_by: list of task numbers/patterns that need this dependency
                      (omit to make it required by ALL tasks)

     Example entries (uncomment/edit for your project):
-->
<!--
- name: PostgreSQL (via Docker)
  check: pg_isready -h localhost -p 5432
  start: docker compose up -d db
  required_by: [6, 7, 8]  # Only tasks that touch the database

- name: Redis (via Docker)
  check: redis-cli -h localhost ping
  start: docker compose up -d redis
  required_by: [7, 8]  # Only tasks that need caching

- name: API server
  check: curl -sf http://localhost:3000/health
  start: cd api && npm start
-->

### How Ralph handles missing dependencies
Ralph checks applicable dependencies before each task. See dependency protocol in `.claude/skills/ralph-dependencies/`.

## Screenshots & Git LFS
- **Git LFS is required for all image files.** Ensure `.gitattributes` tracks `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.webp`, and `*.svg` via Git LFS. If `.gitattributes` doesn't exist or doesn't track images, create/update it before committing any screenshots.
- **Screenshots MUST be committed with each task** — include them in the task's commit so progress is visible in the git history.
- **Screenshot capture is opt-in via env vars.** Set `CAPTURE_SCREENSHOTS=1` to enable capture. Set `CAPTURE_TASK=<N>` to scope captures to a specific task number — this prevents running the full test suite from overwriting screenshots from other tasks. Without these env vars, `captureScreenshot()` is a no-op.
- **T3/regression QA tasks do NOT commit screenshots.** When running full T3 regression tests or QA summary tasks, just report "all tests pass" — do not duplicate screenshots that were already captured in the original task commits.

## Important Notes
- {{NOTE_1}}
- {{NOTE_2}}
