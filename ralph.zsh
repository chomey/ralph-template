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
    print "$stack_lines" | while IFS= read -r line; do
      print "  ${line}"
    done
  fi
fi
print ""

# Count total tasks and completed tasks
total_tasks=$(grep -c '^\- \[' "$TASKS_FILE" 2>/dev/null || true)
total_tasks=${total_tasks:-0}
completed_tasks=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
completed_tasks=${completed_tasks:-0}
remaining_tasks=$((total_tasks - completed_tasks))

print "${YELLOW}Total tasks:     ${total_tasks}${NC}"
print "${GREEN}Completed:       ${completed_tasks}${NC}"
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

  # Run Claude with the prompt, passing project context via CLAUDE.md
  claude --print --dangerously-skip-permissions "$prompt"

  # Check exit code
  if [[ $? -ne 0 ]]; then
    print "${RED}Claude exited with error on iteration ${i}. Stopping.${NC}"
    exit 1
  fi

  # Iteration timing
  ITER_END=$(date +%s)
  ITER_ELAPSED=$((ITER_END - ITER_START))
  ITER_MINS=$((ITER_ELAPSED / 60))
  ITER_SECS=$((ITER_ELAPSED % 60))

  # Re-check progress after each iteration
  completed_now=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
  completed_now=${completed_now:-0}
  print "${GREEN}Progress: ${completed_now}/${total_tasks} tasks complete (iteration took ${ITER_MINS}m ${ITER_SECS}s)${NC}"

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
print "${GREEN}║  \"Me fail English? That's unpossible!\"║${NC}"
print "${GREEN}╚══════════════════════════════════════╝${NC}"

# Final summary
completed_final=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
completed_final=${completed_final:-0}
print "${YELLOW}Final progress: ${completed_final}/${total_tasks} tasks complete${NC}"
print "${CYAN}Total time: ${TOTAL_MINS}m ${TOTAL_SECS}s${NC}"
print "${CYAN}Finished: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
