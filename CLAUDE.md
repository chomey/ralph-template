# CLAUDE.md - Project Instructions

## Project Overview
{{PROJECT_NAME}}: {{PROJECT_DESCRIPTION}}.

See `PRD.md` for full product requirements.

## Tech Stack
- {{LANGUAGE}}, {{FRAMEWORK}}, {{PACKAGE_MANAGER}}

## Key Commands
- Build: `{{BUILD_COMMAND}}`
- Test: `{{TEST_COMMAND}}`
- Lint: `{{LINT_COMMAND}}`
- Run: `{{RUN_COMMAND}}`

## Coding Conventions
- {{CONVENTION_1}}
- {{CONVENTION_2}}
- {{CONVENTION_3}}

## Workflow: Plan Then Build
Strict separation: **planning agents** generate tasks, **Ralph Loop** implements them.

### Planning Agents (no code)
- **Product Designer** (`agents/PRODUCT-DESIGNER.md`) — Product vision, UX, feature design. Writes PRD.md and tasks.
- **Software Architect** (`agents/SOFTWARE-ARCHITECT.md`) — Infrastructure, security, tech architecture. Configures CLAUDE.md.
- **Code Reviewer** (`agents/CODE-REVIEWER.md`) — Post-implementation audit.

### Implementation (Ralph Loop)
`ralph.zsh` or `"Read PROMPT.md and follow its instructions"`. Each task tagged with an agent: `[@frontend]`, `[@backend]`, `[@database]`, `[@devops]`, `[@qa]`, `[@security]`, `[@fullstack]` (default). Ralph loads the corresponding file from `agents/`.

### Task Format
```
- [ ] Task N: Short title — Description [@agent-tag]
```
Ralph picks first unchecked task, completes it, stops. One at a time.

### Model Tags
Sonnet by default. These tags force Opus via `ralph.zsh`:
- `[OPUS]` — Deep cross-file reasoning, architectural audits
- `[MATH]` — Complex calculations where Sonnet gets formulas wrong
- `[MILESTONE]` / `[E2E]` — Informational only, does NOT force Opus

### The Rule
**Prefer tasks for all meaningful work.** Small bug fixes and config tweaks can be done inline in interactive sessions.

## Ralph Loop Instructions
1. Read TASKS.md → first unchecked task
2. Read PROGRESS.md for recent context
3. Complete exactly ONE task
4. **Write tests** — T1 (unit) always required. T2 (Playwright) for `[@frontend]`, `[@fullstack]`, `[@qa]`. T3 (full E2E) for `[@qa]`, `[E2E]`/`[MILESTONE]` tags, and every 5th task.
5. **Run tests/build in one pass** — `{{TEST_COMMAND}}` + `{{BUILD_COMMAND}}`. T2: `CAPTURE_SCREENSHOTS=1 CAPTURE_TASK=<N> npx playwright test tests/e2e/<your-test>.spec.ts`. T3: `CAPTURE_SCREENSHOTS=1 CAPTURE_TASK=<N> npx playwright test`. Do NOT run Playwright twice. Pre-existing test failures: `git stash`, fix, commit `ralph: fix pre-existing test failure during task [N]`, `git stash pop`.
6. Mark task done (`- [x]`) in TASKS.md
7. Log in PROGRESS.md (one entry: task number, date, files, test results, screenshots)
8. Commit with descriptive message
9. Never modify completed tasks. Never skip ahead.

## External Dependencies
Ralph MUST NOT run forbidden commands (e.g., `docker`, `docker-compose`). If a dependency is missing, print an `ACTION REQUIRED` block with the exact command the user must run, log the blocker in PROGRESS.md, and stop.

<!-- Define dependencies that must be running before Ralph can proceed.
     Format: name, check command, start command, required_by task numbers.
     Example:
- name: PostgreSQL
  check: pg_isready -h localhost -p 5432
  start: docker compose up -d db
  required_by: [6, 7, 8]
-->

## Screenshots & Git LFS
- `.gitattributes` must track `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.webp`, `*.svg` via Git LFS
- Screenshots committed with each task. `CAPTURE_TASK=<N>` scopes writes to current task only.
- T3/regression tasks: report "all tests pass", don't duplicate screenshots.

## Important Notes
- {{NOTE_1}}
- {{NOTE_2}}
