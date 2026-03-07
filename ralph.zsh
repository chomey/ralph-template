#!/usr/bin/env zsh
set -euo pipefail

# Ralph Loop - Automated Claude iteration driver
# Usage: ./ralph.zsh [number_of_tasks]
#
# Examples:
#   ./ralph.zsh 20    # Run next 20 uncompleted tasks
#   ./ralph.zsh 5     # Run next 5 uncompleted tasks
#   ./ralph.zsh       # Run next 10 uncompleted tasks (default)

TASK_COUNT="${1:-10}"

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
TASKS_FILE="$SCRIPT_DIR/TASKS.md"
PROGRESS_FILE="$SCRIPT_DIR/PROGRESS.md"
PROMPT_FILE="$SCRIPT_DIR/PROMPT.md"
CLAUDE_FILE="$SCRIPT_DIR/CLAUDE.md"
PRD_FILE="$SCRIPT_DIR/PRD.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TASKS_ARCHIVE="$SCRIPT_DIR/TASKS-ARCHIVE.md"
PROGRESS_ARCHIVE="$SCRIPT_DIR/PROGRESS-ARCHIVE.md"

# Rolling archive thresholds
PROGRESS_MAX_ENTRIES=10   # Keep last N task entries in PROGRESS.md
TASKS_MAX_COMPLETED=3     # Keep last N completed tasks in TASKS.md

# archive_progress — moves older entries from PROGRESS.md to PROGRESS-ARCHIVE.md
# Keeps header (everything before first ## Task) + last N task entries.
archive_progress() {
  local file="$PROGRESS_FILE"
  local archive="$PROGRESS_ARCHIVE"

  # Count task entries
  local entry_count
  entry_count=$(grep -c '^## Task ' "$file" 2>/dev/null || true)
  entry_count=${entry_count:-0}

  if [[ "$entry_count" -le "$PROGRESS_MAX_ENTRIES" ]]; then
    return 0
  fi

  local to_archive=$((entry_count - PROGRESS_MAX_ENTRIES))
  print "${CYAN}  Archiving ${to_archive} old progress entries...${NC}"

  # Find the line number of the first ## Task header
  local first_task_line
  first_task_line=$(grep -n '^## Task ' "$file" | head -1 | cut -d: -f1)

  # Find the line number of the (to_archive+1)th ## Task header (where we keep from)
  local keep_from_line
  keep_from_line=$(grep -n '^## Task ' "$file" | sed -n "$((to_archive + 1))p" | cut -d: -f1)

  # Extract header (before first task)
  local header
  header=$(head -n $((first_task_line - 1)) "$file")

  # Extract entries to archive
  local archive_content
  archive_content=$(sed -n "${first_task_line},$((keep_from_line - 1))p" "$file")

  # Extract entries to keep
  local keep_content
  keep_content=$(tail -n +"${keep_from_line}" "$file")

  # Append to archive file
  if [[ -f "$archive" ]]; then
    printf '\n%s' "$archive_content" >> "$archive"
  else
    printf '# Progress Archive\n\n%s' "$archive_content" > "$archive"
  fi

  # Rewrite PROGRESS.md with header + archive marker + kept entries
  printf '%s\n\n<!-- Older entries archived to PROGRESS-ARCHIVE.md -->\n\n%s\n' "$header" "$keep_content" > "$file"
}

# archive_tasks — moves older completed tasks from TASKS.md to TASKS-ARCHIVE.md
# Keeps the file header, last N completed tasks, and all unchecked tasks.
archive_tasks() {
  local file="$TASKS_FILE"
  local archive="$TASKS_ARCHIVE"

  # Count completed tasks
  local completed_count
  completed_count=$(grep -c '^\- \[x\]' "$file" 2>/dev/null || true)
  completed_count=${completed_count:-0}

  if [[ "$completed_count" -le "$TASKS_MAX_COMPLETED" ]]; then
    return 0
  fi

  local to_archive=$((completed_count - TASKS_MAX_COMPLETED))
  print "${CYAN}  Archiving ${to_archive} old completed tasks...${NC}"

  # Build archive content: the first N completed task lines
  local archive_lines
  archive_lines=$(grep '^\- \[x\]' "$file" | head -n "$to_archive")

  # Append to archive
  if [[ -f "$archive" ]]; then
    printf '\n%s\n' "$archive_lines" >> "$archive"
  else
    printf '# Tasks Archive\n\n%s\n' "$archive_lines" > "$archive"
  fi

  # Remove those lines from the original file.
  # Strategy: collect line numbers of completed tasks to remove, then delete them.
  local lines_to_remove
  lines_to_remove=$(grep -n '^\- \[x\]' "$file" | head -n "$to_archive" | cut -d: -f1)

  # Build sed delete command (e.g., "3d;5d;7d")
  local sed_cmd=""
  while IFS= read -r linenum; do
    # Also remove the blank line after each task (tasks are separated by blank lines)
    sed_cmd="${sed_cmd}${linenum}d;"
    # Check if next line is blank and delete it too
    local next=$((linenum + 1))
    local next_content
    next_content=$(sed -n "${next}p" "$file")
    if [[ -z "$next_content" ]]; then
      sed_cmd="${sed_cmd}${next}d;"
    fi
  done <<< "$lines_to_remove"

  if [[ -n "$sed_cmd" ]]; then
    sed -i '' "$sed_cmd" "$file"
  fi

  # Add archive marker if not already present
  if ! grep -q 'Older tasks archived' "$file"; then
    # Insert after the header line
    sed -i '' '1 a\
\
<!-- Older tasks archived to TASKS-ARCHIVE.md -->' "$file"
  fi
}

START_TIME=$(date +%s)
START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

print "${BLUE}╔══════════════════════════════════════╗${NC}"
print "${BLUE}║       🚌 Ralph Loop v1.0 🚌          ║${NC}"
print "${BLUE}║  \"I'm helping!\" - Ralph Wiggum       ║${NC}"
print "${BLUE}╚══════════════════════════════════════╝${NC}"
print ""
print "${CYAN}Started: ${START_TIMESTAMP}${NC}"
print ""

# Validate required files exist
for f in "$TASKS_FILE" "$PROMPT_FILE" "$PROGRESS_FILE"; do
  if [[ ! -f "$f" ]]; then
    print "${RED}Error: Missing required file: $f${NC}"
    exit 1
  fi
done

# Show project summary from CLAUDE.md (first non-comment, non-empty line after "## Project Overview")
if [[ -f "$CLAUDE_FILE" ]]; then
  project_line=$(sed -n '/^## Project Overview/,/^## /{/^## Project Overview/d;/^## /d;/^<!--/,/-->/d;/^$/d;p;}' "$CLAUDE_FILE" | head -n 2)
  if [[ -n "$project_line" ]]; then
    print "${BOLD}Project:${NC} ${project_line}"
  fi
fi

# Show tech stack summary
if [[ -f "$CLAUDE_FILE" ]]; then
  stack_lines=$(sed -n '/^## Tech Stack/,/^## /{/^## /d;/^$/d;p;}' "$CLAUDE_FILE" | head -n 3)
  if [[ -n "$stack_lines" ]]; then
    print "${BOLD}Stack:${NC}"
    print -r -- "$stack_lines" | while IFS= read -r line; do
      print -r -- "  ${line}"
    done
  fi
fi
print ""

# Count total tasks and completed tasks (including archived)
completed_tasks=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
completed_tasks=${completed_tasks:-0}
archived_tasks=0
if [[ -f "$TASKS_ARCHIVE" ]]; then
  archived_tasks=$(grep -c '^\- \[x\]' "$TASKS_ARCHIVE" 2>/dev/null || true)
  archived_tasks=${archived_tasks:-0}
fi
remaining_tasks=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null || true)
remaining_tasks=${remaining_tasks:-0}
total_tasks=$((completed_tasks + archived_tasks + remaining_tasks))

print "${YELLOW}Total tasks:     ${total_tasks}${NC}"
print "${GREEN}Completed:       $((completed_tasks + archived_tasks))${NC}"
print "${BLUE}Remaining:       ${remaining_tasks}${NC}"
print ""

if [[ "$remaining_tasks" -eq 0 ]]; then
  print "${GREEN}All tasks are complete! Ralph did it!${NC}"
  exit 0
fi

# Cap task count to remaining
if [[ "$TASK_COUNT" -gt "$remaining_tasks" ]]; then
  TASK_COUNT="$remaining_tasks"
fi

print "${YELLOW}Tasks to run:    ${TASK_COUNT}${NC}"
print ""

# Show the next N uncompleted tasks for confirmation
print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print "${YELLOW}  Next ${TASK_COUNT} task(s) to execute:${NC}"
print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print ""

# Extract next N uncompleted tasks
grep '^\- \[ \]' "$TASKS_FILE" | head -n "$TASK_COUNT" | while IFS= read -r task; do
  print "  ${YELLOW}${task}${NC}"
done

print ""
print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print ""

# Prompt user for confirmation
print -n "Proceed with these ${TASK_COUNT} task(s)? [y/N] "
read -r confirm
case "$confirm" in
  [yY]|[yY][eE][sS])
    print ""
    print "${GREEN}Starting Ralph Loop...${NC}"
    ;;
  *)
    print "${YELLOW}Aborted by user.${NC}"
    exit 0
    ;;
esac

# Show the next task's suggested approach
next_task=$(grep '^\- \[ \]' "$TASKS_FILE" | head -n 1)
if [[ -n "$next_task" ]]; then
  print "${BOLD}Next up:${NC} ${next_task}"
  print ""
fi

# Run Claude for each task
for ((i = 1; i <= TASK_COUNT; i++)); do
  ITER_START=$(date +%s)

  print ""
  print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print "${YELLOW}  Ralph Loop iteration ${i}/${TASK_COUNT}  $(date '+%H:%M:%S')${NC}"
  print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print ""

  # Build the prompt from PROMPT.md
  prompt=$(cat "$PROMPT_FILE")

  # Pick model: Opus for MILESTONE/E2E/OPUS tasks, Sonnet for everything else
  next_task=$(grep '^\- \[ \]' "$TASKS_FILE" | head -n 1)
  if echo "$next_task" | grep -qiE '\[MILESTONE\]|\[E2E\]|\[OPUS\]'; then
    model="opus"
    print "${CYAN}  Model: opus (milestone/E2E/complex task)${NC}"
  else
    model="sonnet"
    print "${CYAN}  Model: sonnet${NC}"
  fi

  # Run Claude with the prompt, passing project context via CLAUDE.md
  claude --print --dangerously-skip-permissions --model "$model" "$prompt"

  # Check exit code
  if [[ $? -ne 0 ]]; then
    print "${RED}Claude exited with error on iteration ${i}. Stopping.${NC}"
    exit 1
  fi

  # Auto-archive if files have grown too large
  archive_progress
  archive_tasks

  # Iteration timing
  ITER_END=$(date +%s)
  ITER_ELAPSED=$((ITER_END - ITER_START))
  ITER_MINS=$((ITER_ELAPSED / 60))
  ITER_SECS=$((ITER_ELAPSED % 60))

  # Re-check progress after each iteration (include archived)
  completed_now=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
  completed_now=${completed_now:-0}
  archived_now=0
  if [[ -f "$TASKS_ARCHIVE" ]]; then
    archived_now=$(grep -c '^\- \[x\]' "$TASKS_ARCHIVE" 2>/dev/null || true)
    archived_now=${archived_now:-0}
  fi
  print "${GREEN}Progress: $((completed_now + archived_now))/${total_tasks} tasks complete (iteration took ${ITER_MINS}m ${ITER_SECS}s)${NC}"

  # Brief pause between iterations to avoid rate limiting
  if [[ "$i" -lt "$TASK_COUNT" ]]; then
    sleep 2
  fi
done

END_TIME=$(date +%s)
TOTAL_ELAPSED=$((END_TIME - START_TIME))
TOTAL_MINS=$((TOTAL_ELAPSED / 60))
TOTAL_SECS=$((TOTAL_ELAPSED % 60))

print ""
print "${GREEN}╔══════════════════════════════════════╗${NC}"
print "${GREEN}║  Ralph Loop complete!                ║${NC}"
print "${GREEN}║ \"Me fail English? That's unpossible!\"║${NC}"
print "${GREEN}╚══════════════════════════════════════╝${NC}"

# Final summary (include archived)
completed_final=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
completed_final=${completed_final:-0}
archived_final=0
if [[ -f "$TASKS_ARCHIVE" ]]; then
  archived_final=$(grep -c '^\- \[x\]' "$TASKS_ARCHIVE" 2>/dev/null || true)
  archived_final=${archived_final:-0}
fi
print "${YELLOW}Final progress: $((completed_final + archived_final))/${total_tasks} tasks complete${NC}"
print "${CYAN}Total time: ${TOTAL_MINS}m ${TOTAL_SECS}s${NC}"
print "${CYAN}Finished: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
