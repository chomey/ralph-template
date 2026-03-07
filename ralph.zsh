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
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

TASKS_ARCHIVE="$SCRIPT_DIR/TASKS-ARCHIVE.md"
PROGRESS_ARCHIVE="$SCRIPT_DIR/PROGRESS-ARCHIVE.md"

# Rolling archive thresholds
PROGRESS_MAX_ENTRIES=10   # Keep last N task entries in PROGRESS.md
TASKS_MAX_COMPLETED=3     # Keep last N completed tasks in TASKS.md

# Tracking arrays for the final summary
typeset -a ITER_TIMES=()
typeset -a ITER_MODELS=()
typeset -a ITER_TAGS=()
typeset -a ITER_TITLES=()
TASKS_COMPLETED_THIS_RUN=0
TASKS_FAILED_THIS_RUN=0

# format_duration — converts seconds to a human-readable string
format_duration() {
  local secs=$1
  local mins=$((secs / 60))
  local s=$((secs % 60))
  if [[ $mins -gt 0 ]]; then
    printf '%dm %ds' "$mins" "$s"
  else
    printf '%ds' "$s"
  fi
}

# progress_bar — renders a visual bar like [████████░░░░] 75%
progress_bar() {
  local current=$1 total=$2 width=${3:-20}
  if [[ $total -eq 0 ]]; then
    printf '[%*s] 0%%' "$width" ''
    return
  fi
  local pct=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))
  local bar=""
  for ((b = 0; b < filled; b++)); do bar+="█"; done
  for ((b = 0; b < empty; b++)); do bar+="░"; done
  printf '[%s] %d%%' "$bar" "$pct"
}

# extract_task_title — pulls the short title from a task line
extract_task_title() {
  local line="$1"
  # "- [ ] Task 42: [OPUS] Short title — Description" -> "Task 42: [OPUS] Short title"
  echo "$line" | sed -E 's/^- \[.\] //' | sed -E 's/ — .*//'
}

# extract_agent_tag — pulls [@tag] from a task line
extract_agent_tag() {
  local line="$1"
  echo "$line" | grep -oE '\[@[a-z]+\]' | tail -1 || echo "[@fullstack]"
}

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
  print "${DIM}  Archiving ${to_archive} old progress entries...${NC}"

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
  print "${DIM}  Archiving ${to_archive} old completed tasks...${NC}"

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
  done <<< "$lines_to_remove" 2>/dev/null

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

# print_summary — shows final stats (also used by the SIGINT trap)
print_summary() {
  local end_time=$(date +%s)
  local total_elapsed=$((end_time - START_TIME))

  print ""
  print "${GREEN}╔══════════════════════════════════════════╗${NC}"
  print "${GREEN}║  Ralph Loop complete!                    ║${NC}"
  print "${GREEN}║ \"Me fail English? That's unpossible!\"    ║${NC}"
  print "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  print ""

  # Final task count (include archived)
  local completed_final
  completed_final=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
  completed_final=${completed_final:-0}
  local archived_final=0
  if [[ -f "$TASKS_ARCHIVE" ]]; then
    archived_final=$(grep -c '^\- \[x\]' "$TASKS_ARCHIVE" 2>/dev/null || true)
    archived_final=${archived_final:-0}
  fi
  local total_done=$((completed_final + archived_final))

  # Progress bar
  print "  ${BOLD}Progress:${NC}  $(progress_bar $total_done $total_tasks 25)  ${total_done}/${total_tasks}"
  print ""

  # This run stats
  if [[ $TASKS_COMPLETED_THIS_RUN -gt 0 ]]; then
    print "  ${BOLD}This run:${NC}  ${GREEN}${TASKS_COMPLETED_THIS_RUN} completed${NC}${TASKS_FAILED_THIS_RUN:+, ${RED}${TASKS_FAILED_THIS_RUN} failed${NC}}"
  fi

  # Timing
  print "  ${BOLD}Total time:${NC} $(format_duration $total_elapsed)"
  if [[ ${#ITER_TIMES[@]} -gt 0 ]]; then
    local sum=0
    for t in "${ITER_TIMES[@]}"; do sum=$((sum + t)); done
    local avg=$((sum / ${#ITER_TIMES[@]}))
    local fastest=${ITER_TIMES[1]} slowest=${ITER_TIMES[1]}
    for t in "${ITER_TIMES[@]}"; do
      [[ $t -lt $fastest ]] && fastest=$t
      [[ $t -gt $slowest ]] && slowest=$t
    done
    print "  ${BOLD}Avg/task:${NC}  $(format_duration $avg)  ${DIM}(fastest: $(format_duration $fastest), slowest: $(format_duration $slowest))${NC}"
  fi

  # Model breakdown
  if [[ ${#ITER_MODELS[@]} -gt 0 ]]; then
    local sonnet_count=0 opus_count=0
    for m in "${ITER_MODELS[@]}"; do
      [[ "$m" == "sonnet" ]] && sonnet_count=$((sonnet_count + 1))
      [[ "$m" == "opus" ]] && opus_count=$((opus_count + 1))
    done
    local model_summary=""
    [[ $sonnet_count -gt 0 ]] && model_summary+="${sonnet_count} Sonnet"
    [[ $opus_count -gt 0 ]] && { [[ -n "$model_summary" ]] && model_summary+=" + "; model_summary+="${opus_count} Opus"; }
    print "  ${BOLD}Models:${NC}    ${model_summary}"
  fi

  # Agent tag breakdown
  if [[ ${#ITER_TAGS[@]} -gt 0 ]]; then
    # Count tags using an associative array
    typeset -A tag_counts
    for tag in "${ITER_TAGS[@]}"; do
      tag_counts[$tag]=$(( ${tag_counts[$tag]:-0} + 1 ))
    done
    local tag_parts=()
    for tag count in "${(@kv)tag_counts}"; do
      tag_parts+=("${count} ${tag}")
    done
    # Join with comma
    local tag_str="${(j:, :)tag_parts}"
    print "  ${BOLD}Agents:${NC}    ${tag_str}"
  fi

  # Per-task breakdown
  if [[ ${#ITER_TITLES[@]} -gt 0 ]]; then
    print ""
    print "  ${BOLD}Task breakdown:${NC}"
    for ((t = 1; t <= ${#ITER_TITLES[@]}; t++)); do
      local dur=$(format_duration ${ITER_TIMES[$t]})
      local mdl="${ITER_MODELS[$t]}"
      local mdl_color="${CYAN}"
      [[ "$mdl" == "opus" ]] && mdl_color="${MAGENTA}"
      print "    ${DIM}${dur}${NC}  ${mdl_color}${mdl}${NC}  ${ITER_TITLES[$t]}"
    done
  fi

  print ""
  print "  ${CYAN}Finished: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
  print ""
}

# ─── Trap: Ctrl+C graceful exit ─────────────────────────────────────────────
INTERRUPTED=0
trap_handler() {
  INTERRUPTED=1
  print ""
  print ""
  print "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print "${YELLOW}  Interrupted! Showing summary so far...${NC}"
  print "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print_summary
  # macOS notification
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "Loop interrupted after '"${TASKS_COMPLETED_THIS_RUN}"' tasks" with title "Ralph Loop" sound name "Basso"' 2>/dev/null &
  fi
  exit 130
}
trap trap_handler INT TERM

# ─── Main ───────────────────────────────────────────────────────────────────

START_TIME=$(date +%s)
START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

print "${BLUE}╔══════════════════════════════════════╗${NC}"
print "${BLUE}║       🚌 Ralph Loop v2.0 🚌          ║${NC}"
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

print "  $(progress_bar $((completed_tasks + archived_tasks)) $total_tasks 25)  ${BOLD}$((completed_tasks + archived_tasks))${NC}/${total_tasks} tasks"
print ""

if [[ "$remaining_tasks" -eq 0 ]]; then
  print "${GREEN}All tasks are complete! Ralph did it! 🎉${NC}"
  exit 0
fi

# Cap task count to remaining
if [[ "$TASK_COUNT" -gt "$remaining_tasks" ]]; then
  TASK_COUNT="$remaining_tasks"
fi

print "${YELLOW}Tasks to run: ${TASK_COUNT}  ${DIM}(${remaining_tasks} remaining)${NC}"
print ""

# Show the next N uncompleted tasks for confirmation
print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print "${YELLOW}  Next ${TASK_COUNT} task(s) to execute:${NC}"
print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print ""

# Extract next N uncompleted tasks
grep '^\- \[ \]' "$TASKS_FILE" | head -n "$TASK_COUNT" | while IFS= read -r task; do
  local title=$(extract_task_title "$task")
  local tag=$(extract_agent_tag "$task")
  local model_hint=""
  if echo "$task" | grep -qiE '\[MILESTONE\]|\[E2E\]|\[OPUS\]'; then
    model_hint=" ${MAGENTA}opus${NC}"
  else
    model_hint=" ${CYAN}sonnet${NC}"
  fi
  print "  ${YELLOW}${title}${NC}  ${DIM}${tag}${NC}${model_hint}"
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

# Run Claude for each task
for ((i = 1; i <= TASK_COUNT; i++)); do
  ITER_START=$(date +%s)

  # Snapshot which tasks are checked before Claude runs
  local before_completed
  before_completed=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
  before_completed=${before_completed:-0}

  # Get current task info
  next_task=$(grep '^\- \[ \]' "$TASKS_FILE" | head -n 1)
  task_title=$(extract_task_title "$next_task")
  task_tag=$(extract_agent_tag "$next_task")

  print ""
  print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print "${YELLOW}  [${i}/${TASK_COUNT}]  ${task_title}${NC}"
  print "${DIM}  $(date '+%H:%M:%S')  ${task_tag}${NC}"
  print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print ""

  # Build the prompt from PROMPT.md
  prompt=$(cat "$PROMPT_FILE")

  # Pick model: Opus for MILESTONE/E2E/complex tasks, Sonnet for everything else
  if echo "$next_task" | grep -qiE '\[MILESTONE\]|\[E2E\]|\[OPUS\]'; then
    model="opus"
    print "  ${MAGENTA}▸ Model: opus${NC} ${DIM}(milestone/complex task)${NC}"
  else
    model="sonnet"
    print "  ${CYAN}▸ Model: sonnet${NC}"
  fi
  print ""

  # Run Claude with the prompt, passing project context via CLAUDE.md
  local claude_exit=0
  claude --print --dangerously-skip-permissions --model "$model" "$prompt" || claude_exit=$?

  # Check if Claude failed
  if [[ $claude_exit -ne 0 ]]; then
    print ""
    print "${RED}  ✗ Claude exited with code ${claude_exit} on iteration ${i}.${NC}"

    # Retry once for transient failures
    print "${YELLOW}  Retrying in 5 seconds...${NC}"
    sleep 5
    claude --print --dangerously-skip-permissions --model "$model" "$prompt" || {
      print "${RED}  ✗ Retry also failed. Stopping loop.${NC}"
      TASKS_FAILED_THIS_RUN=$((TASKS_FAILED_THIS_RUN + 1))
      ITER_TIMES+=($(($(date +%s) - ITER_START)))
      ITER_MODELS+=("$model")
      ITER_TAGS+=("$task_tag")
      ITER_TITLES+=("${task_title} ${RED}(FAILED)${NC}")
      print_summary
      exit 1
    }
  fi

  # Detect stuck task: if the same task is still unchecked, warn
  local after_completed
  after_completed=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
  after_completed=${after_completed:-0}

  if [[ "$after_completed" -le "$before_completed" ]]; then
    print ""
    print "${RED}  ⚠ Warning: Task may not have been marked complete!${NC}"
    print "${RED}    '${task_title}' is still unchecked in TASKS.md${NC}"
    print "${YELLOW}    Continuing to next iteration anyway...${NC}"
    TASKS_FAILED_THIS_RUN=$((TASKS_FAILED_THIS_RUN + 1))
  else
    TASKS_COMPLETED_THIS_RUN=$((TASKS_COMPLETED_THIS_RUN + 1))
  fi

  # Auto-archive if files have grown too large
  archive_progress
  archive_tasks

  # Iteration timing
  ITER_END=$(date +%s)
  ITER_ELAPSED=$((ITER_END - ITER_START))
  ITER_TIMES+=($ITER_ELAPSED)
  ITER_MODELS+=("$model")
  ITER_TAGS+=("$task_tag")
  ITER_TITLES+=("$task_title")

  # Cumulative timing
  local cumulative=$((ITER_END - START_TIME))

  # Re-check progress after each iteration (include archived)
  local completed_now archived_now
  completed_now=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
  completed_now=${completed_now:-0}
  archived_now=0
  if [[ -f "$TASKS_ARCHIVE" ]]; then
    archived_now=$(grep -c '^\- \[x\]' "$TASKS_ARCHIVE" 2>/dev/null || true)
    archived_now=${archived_now:-0}
  fi
  local total_done=$((completed_now + archived_now))

  print ""
  print "  $(progress_bar $total_done $total_tasks 20)  ${BOLD}${total_done}/${total_tasks}${NC}  ${DIM}$(format_duration $ITER_ELAPSED) this task | $(format_duration $cumulative) total${NC}"

  # Brief pause between iterations to avoid rate limiting
  if [[ "$i" -lt "$TASK_COUNT" ]]; then
    sleep 2
  fi
done

# ─── Final summary ──────────────────────────────────────────────────────────
print_summary

# macOS notification on completion
if command -v osascript &>/dev/null; then
  osascript -e 'display notification "'"${TASKS_COMPLETED_THIS_RUN}"' tasks completed in '"$(format_duration $(($(date +%s) - START_TIME)))"'" with title "Ralph Loop ✅" sound name "Glass"' 2>/dev/null &
fi
