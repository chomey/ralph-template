---
name: ralph-dependencies
description: "Protocol for checking external service dependencies before Ralph task execution. Handles missing dependency detection and ACTION REQUIRED prompts."
user-invocable: false
---

# How Ralph Handles Missing Dependencies

Before starting implementation on a task, Ralph MUST:

1. **Determine which dependencies apply to the current task.** Each dependency has an optional `required_by` field listing task numbers that need it. If `required_by` is omitted, the dependency applies to ALL tasks. If the current task number is not in any dependency's `required_by` list, skip the check for that dependency.
2. **Check only the applicable dependencies** by running their `check` commands
3. If all applicable checks pass (or none apply), proceed with the task normally
4. If ANY applicable check fails, **do NOT attempt the task**. Instead:
   a. Print a clear `ACTION REQUIRED` block listing every failing dependency and the exact command to start it:
      ```
      ══════════════════════════════════════════════════
      ACTION REQUIRED — External dependencies not running
      ══════════════════════════════════════════════════

      The following dependencies are needed for this task but are not available:

      ✗ PostgreSQL (via Docker)
        → Run: docker compose up -d db

      After starting them, re-run Ralph to continue.
      ══════════════════════════════════════════════════
      ```
   b. Log the blocker in PROGRESS.md under the current task
   c. **Stop the current iteration immediately** — do NOT proceed, do NOT skip to another task
