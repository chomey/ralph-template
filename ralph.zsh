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
print "${BLUE}║     🚌 Ralph Loop v3.0 (worktree) 🚌  ║${NC}"
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
grep '^\- \[ \]' "$TASKS_FILE" | sort -t' ' -k4 -n | head -n "$TASK_COUNT" | while IFS= read -r task; do
  local title=$(extract_task_title "$task")
  local tag=$(extract_agent_tag "$task")
  local model_hint=""
  if echo "$task" | grep -qiE '\[OPUS\]|\[MATH\]'; then
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

# Worktree base directory (sibling to the repo)
WORKTREE_BASE="${SCRIPT_DIR}/.worktrees"
MAIN_BRANCH=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)

# Pull latest from remote before starting
print "${DIM}Pulling latest from origin/${MAIN_BRANCH}...${NC}"
git -C "$SCRIPT_DIR" pull --rebase origin "$MAIN_BRANCH" 2>/dev/null || true

# cleanup_worktree — removes a worktree and its branch
cleanup_worktree() {
  local wt_path="$1" branch_name="$2"
  if [[ -d "$wt_path" ]]; then
    git -C "$SCRIPT_DIR" worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"
  fi
  git -C "$SCRIPT_DIR" branch -D "$branch_name" 2>/dev/null || true
}

# ─── Cleanup leftover worktrees/branches from previous failed runs ──────────
git -C "$SCRIPT_DIR" worktree prune 2>/dev/null || true
if [[ -d "$WORKTREE_BASE" ]]; then
  for wt_dir in "$WORKTREE_BASE"/task-*(N); do
    [[ -d "$wt_dir" ]] || continue
    local leftover_num
    leftover_num=$(basename "$wt_dir" | sed 's/task-//')
    local leftover_branch="ralph/task-${leftover_num}"
    print "${DIM}  Cleaning up leftover worktree: ${wt_dir}${NC}"
    cleanup_worktree "$wt_dir" "$leftover_branch"
  done
fi
# Also clean any orphaned ralph/* branches with no matching worktree
for orphan_branch in $(git -C "$SCRIPT_DIR" branch --list 'ralph/task-*' 2>/dev/null | sed 's/^[* ]*//' ); do
  local orphan_num
  orphan_num=$(echo "$orphan_branch" | sed 's|ralph/task-||')
  local orphan_wt="${WORKTREE_BASE}/task-${orphan_num}"
  if [[ ! -d "$orphan_wt" ]]; then
    print "${DIM}  Cleaning up orphaned branch: ${orphan_branch}${NC}"
    git -C "$SCRIPT_DIR" branch -D "$orphan_branch" 2>/dev/null || true
  fi
done

# Run Claude for each task (in isolated worktrees)
for ((i = 1; i <= TASK_COUNT; i++)); do
  # Bail out if interrupted between iterations
  [[ $INTERRUPTED -eq 1 ]] && { print_summary; exit 130; }

  ITER_START=$(date +%s)

  # Snapshot which tasks are checked before Claude runs
  local before_completed
  before_completed=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
  before_completed=${before_completed:-0}

  # Get current task info
  next_task=$(grep '^\- \[ \]' "$TASKS_FILE" | sort -t' ' -k4 -n | head -n 1)
  task_title=$(extract_task_title "$next_task")
  task_tag=$(extract_agent_tag "$next_task")

  # Extract task number for branch naming (head -1: only the FIRST "Task NNN", not references to other tasks)
  local task_num
  task_num=$(echo "$next_task" | grep -oE 'Task [0-9]+' | head -1 | grep -oE '[0-9]+')
  task_num=${task_num:-$i}

  print ""
  print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print "${YELLOW}  [${i}/${TASK_COUNT}]  ${task_title}${NC}"
  print "${DIM}  $(date '+%H:%M:%S')  ${task_tag}${NC}"
  print "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  print ""

  # ─── Worktree setup ──────────────────────────────────────────────────────
  local branch_name="ralph/task-${task_num}"
  local wt_path="${WORKTREE_BASE}/task-${task_num}"

  # Clean up any leftover worktree from a previous failed run
  cleanup_worktree "$wt_path" "$branch_name"

  mkdir -p "$WORKTREE_BASE"
  print "  ${DIM}▸ Creating worktree: ${wt_path}${NC}"
  local wt_create_exit=0
  git -C "$SCRIPT_DIR" worktree add -b "$branch_name" "$wt_path" "$MAIN_BRANCH" 2>&1 || wt_create_exit=$?
  if [[ $wt_create_exit -ne 0 ]]; then
    print "${RED}  ✗ Failed to create worktree for ${branch_name}. Attempting cleanup and retry...${NC}"
    cleanup_worktree "$wt_path" "$branch_name"
    git -C "$SCRIPT_DIR" worktree prune 2>/dev/null || true
    git -C "$SCRIPT_DIR" worktree add -b "$branch_name" "$wt_path" "$MAIN_BRANCH" 2>&1 || {
      print "${RED}  ✗ Retry failed. Stopping loop.${NC}"
      TASKS_FAILED_THIS_RUN=$((TASKS_FAILED_THIS_RUN + 1))
      ITER_TIMES+=($(($(date +%s) - ITER_START)))
      ITER_MODELS+=("unknown")
      ITER_TAGS+=("$task_tag")
      ITER_TITLES+=("${task_title} ${RED}(worktree failed)${NC}")
      break
    }
  fi

  # Build the prompt from PROMPT.md (read from worktree copy)
  local wt_prompt_file="${wt_path}/PROMPT.md"
  prompt=$(cat "$wt_prompt_file")

  # Pick model: Opus for tasks needing deep reasoning, Sonnet for everything else
  if echo "$next_task" | grep -qiE '\[OPUS\]|\[MATH\]'; then
    model="opus"
    local tag_reason="complex"
    echo "$next_task" | grep -qiE '\[MATH\]' && tag_reason="math-heavy"
    print "  ${MAGENTA}▸ Model: opus${NC} ${DIM}(${tag_reason} task)${NC}"
  else
    model="sonnet"
    print "  ${CYAN}▸ Model: sonnet${NC}"
  fi
  print ""

  # Run Claude inside the worktree (45-minute timeout per task)
  local claude_exit=0
  local TASK_TIMEOUT=2700  # 45 minutes
  local claude_pid
  (cd "$wt_path" && claude --print --dangerously-skip-permissions --model "$model" "$prompt") &
  claude_pid=$!

  # Monitor with timeout — check every 10 seconds
  local elapsed=0
  while kill -0 "$claude_pid" 2>/dev/null; do
    if [[ $elapsed -ge $TASK_TIMEOUT ]]; then
      print ""
      print "${RED}  ✗ Task timed out after $((TASK_TIMEOUT / 60)) minutes. Killing...${NC}"
      kill -TERM "$claude_pid" 2>/dev/null
      sleep 2
      kill -9 "$claude_pid" 2>/dev/null || true
      wait "$claude_pid" 2>/dev/null || true
      TASKS_FAILED_THIS_RUN=$((TASKS_FAILED_THIS_RUN + 1))
      ITER_TIMES+=($(($(date +%s) - ITER_START)))
      ITER_MODELS+=("$model")
      ITER_TAGS+=("$task_tag")
      ITER_TITLES+=("${task_title} ${RED}(timed out)${NC}")
      cleanup_worktree "$wt_path" "$branch_name"
      continue 2  # continue outer for loop
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  wait "$claude_pid" 2>/dev/null || claude_exit=$?

  # If interrupted (Ctrl+C), clean up worktree and exit
  if [[ $INTERRUPTED -eq 1 || $claude_exit -eq 130 ]]; then
    INTERRUPTED=1
    cleanup_worktree "$wt_path" "$branch_name"
    ITER_TIMES+=($(($(date +%s) - ITER_START)))
    ITER_MODELS+=("$model")
    ITER_TAGS+=("$task_tag")
    ITER_TITLES+=("${task_title} ${YELLOW}(interrupted)${NC}")
    print_summary
    exit 130
  fi

  # Check if Claude failed
  if [[ $claude_exit -ne 0 ]]; then
    print ""
    print "${RED}  ✗ Claude exited with code ${claude_exit} on iteration ${i}.${NC}"

    # Retry once for transient failures
    print "${YELLOW}  Retrying in 5 seconds...${NC}"
    sleep 5
    (cd "$wt_path" && claude --print --dangerously-skip-permissions --model "$model" "$prompt") || {
      # Check again for interrupt during retry
      if [[ $INTERRUPTED -eq 1 ]]; then
        cleanup_worktree "$wt_path" "$branch_name"
        print_summary
        exit 130
      fi
      print "${RED}  ✗ Retry also failed. Stopping loop.${NC}"
      TASKS_FAILED_THIS_RUN=$((TASKS_FAILED_THIS_RUN + 1))
      ITER_TIMES+=($(($(date +%s) - ITER_START)))
      ITER_MODELS+=("$model")
      ITER_TAGS+=("$task_tag")
      ITER_TITLES+=("${task_title} ${RED}(FAILED)${NC}")
      cleanup_worktree "$wt_path" "$branch_name"
      print_summary
      exit 1
    }
  fi

  # ─── Merge worktree back to main branch ────────────────────────────────
  # Check if the worktree branch has any commits beyond main
  local wt_tasks_file="${wt_path}/TASKS.md"
  local wt_after_completed
  wt_after_completed=$(grep -c '^\- \[x\]' "$wt_tasks_file" 2>/dev/null || true)
  wt_after_completed=${wt_after_completed:-0}

  if [[ "$wt_after_completed" -le "$before_completed" ]]; then
    print ""
    print "${RED}  ⚠ Warning: Task may not have been marked complete!${NC}"
    print "${RED}    '${task_title}' is still unchecked in TASKS.md${NC}"
    print "${YELLOW}    Continuing to next iteration anyway...${NC}"
    TASKS_FAILED_THIS_RUN=$((TASKS_FAILED_THIS_RUN + 1))
  else
    TASKS_COMPLETED_THIS_RUN=$((TASKS_COMPLETED_THIS_RUN + 1))
  fi

  # Merge the worktree branch into main
  local has_new_commits
  has_new_commits=$(git -C "$SCRIPT_DIR" log "${MAIN_BRANCH}..${branch_name}" --oneline 2>/dev/null | head -1)

  if [[ -n "$has_new_commits" ]]; then
    print ""
    print "  ${DIM}▸ Merging ${branch_name} → ${MAIN_BRANCH}${NC}"

    # Stash any uncommitted local changes on main before merging
    local did_stash=0
    local stash_output
    stash_output=$(git -C "$SCRIPT_DIR" stash push -u -m "ralph: auto-stash before merging ${branch_name}" 2>&1)
    if [[ "$stash_output" != *"No local changes"* ]]; then
      did_stash=1
      print "  ${DIM}▸ Stashed local changes${NC}"
    fi

    local merge_exit=0
    git -C "$SCRIPT_DIR" merge "$branch_name" --no-edit || merge_exit=$?

    if [[ $merge_exit -ne 0 ]]; then
      print "${RED}  ✗ Merge conflict! Aborting merge.${NC}"
      git -C "$SCRIPT_DIR" merge --abort 2>/dev/null || true
      # Restore stash before bailing
      if [[ $did_stash -eq 1 ]]; then
        git -C "$SCRIPT_DIR" stash pop 2>/dev/null || true
        print "  ${DIM}▸ Restored stashed changes${NC}"
      fi
      print "${RED}  Worktree preserved at: ${wt_path}${NC}"
      print "${YELLOW}    Resolve manually: cd ${SCRIPT_DIR} && git merge ${branch_name}${NC}"
      TASKS_FAILED_THIS_RUN=$((TASKS_FAILED_THIS_RUN + 1))
      ITER_TIMES+=($(($(date +%s) - ITER_START)))
      ITER_MODELS+=("$model")
      ITER_TAGS+=("$task_tag")
      ITER_TITLES+=("${task_title} ${RED}(merge conflict)${NC}")
      print_summary
      exit 1
    fi
    print "  ${GREEN}▸ Merged successfully${NC}"

    # Restore stashed changes on top of the merge
    if [[ $did_stash -eq 1 ]]; then
      if git -C "$SCRIPT_DIR" stash pop 2>&1; then
        print "  ${DIM}▸ Restored stashed changes${NC}"
      else
        # Stash pop conflict — keep the merge result (--ours), discard stash
        print "${YELLOW}  ⚠ Stash pop had conflicts — keeping merge result${NC}"
        git -C "$SCRIPT_DIR" checkout --ours . 2>/dev/null || true
        git -C "$SCRIPT_DIR" add -A 2>/dev/null || true
        git -C "$SCRIPT_DIR" reset HEAD 2>/dev/null || true
        git -C "$SCRIPT_DIR" stash drop 2>/dev/null || true
      fi
    fi
  else
    print "  ${DIM}▸ No new commits on ${branch_name}, skipping merge${NC}"
  fi

  # Clean up worktree
  cleanup_worktree "$wt_path" "$branch_name"

  # Auto-archive if files have grown too large (non-fatal)
  archive_progress || print "${YELLOW}  ⚠ archive_progress failed (non-fatal)${NC}"
  archive_tasks || print "${YELLOW}  ⚠ archive_tasks failed (non-fatal)${NC}"

  # Commit archive changes so they don't cause stash conflicts on next iteration
  if ! git -C "$SCRIPT_DIR" diff --quiet PROGRESS.md PROGRESS-ARCHIVE.md TASKS.md TASKS-ARCHIVE.md 2>/dev/null; then
    git -C "$SCRIPT_DIR" add PROGRESS.md PROGRESS-ARCHIVE.md TASKS.md TASKS-ARCHIVE.md 2>/dev/null
    git -C "$SCRIPT_DIR" commit -m "ralph: archive old progress/task entries" --no-verify 2>/dev/null || true
  fi

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

# ─── Clean up worktree directory if empty ──────────────────────────────────
if [[ -d "$WORKTREE_BASE" ]] && [[ -z "$(ls -A "$WORKTREE_BASE" 2>/dev/null)" ]]; then
  rmdir "$WORKTREE_BASE" 2>/dev/null || true
fi

# ─── Final summary ──────────────────────────────────────────────────────────
print_summary

# macOS notification on completion
if command -v osascript &>/dev/null; then
  osascript -e 'display notification "'"${TASKS_COMPLETED_THIS_RUN}"' tasks completed in '"$(format_duration $(($(date +%s) - START_TIME)))"'" with title "Ralph Loop ✅" sound name "Glass"' 2>/dev/null &
fi
