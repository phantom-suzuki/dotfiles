#!/usr/bin/env bash
# Claude Code statusline — Iceberg phantom palette
# Responsive: adapts to pane width (wide / medium / narrow)
# Uses printf '%b' instead of echo -e for reliable escape handling

set -euo pipefail

input=$(cat)

# --- Terminal width guard ---
# WezTerm pane split may report incorrect width before initialization.
# Also skip during session startup (before first API response) since
# Claude Code's TUI renderer may not have the correct dimensions yet.
cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 0)}
(( cols < 30 )) && exit 0

duration=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' | cut -d. -f1)
(( duration == 0 )) && exit 0

# --- Extract fields via jq ---
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
project=$(basename "${project_dir:-unknown}")
model=$(echo "$input" | jq -r '.model.display_name // "?"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# --- Git branch (cached per project, 5s TTL) ---
cache_dir="/tmp/claude-statusline"
mkdir -p "$cache_dir"
cache_file="$cache_dir/$(echo "$project_dir" | tr '/' '_')"
now=$(date +%s)

branch=""
if [[ -n "$project_dir" && ( -d "$project_dir/.git" || -f "$project_dir/.git" ) ]]; then
  if [[ -f "$cache_file" ]]; then
    cached_time=$(head -1 "$cache_file")
    if (( now - cached_time < 5 )); then
      branch=$(tail -1 "$cache_file")
    fi
  fi
  if [[ -z "$branch" ]]; then
    branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    printf '%s\n%s\n' "$now" "$branch" > "$cache_file"
  fi
fi

# --- Context bar color ---
if (( used >= 80 )); then
  bar_color="31"   # red
elif (( used >= 50 )); then
  bar_color="33"   # yellow
else
  bar_color="32"   # green
fi

# --- Cost formatting ---
cost_fmt=$(printf '$%.2f' "$cost")

# --- Compose line (responsive) ---
# Using printf '%b' for reliable escape handling across shells
if (( cols >= 90 )); then
  # Wide: project | branch | ▓▓▓░░░░░░░ XX% | model $X.XX
  bar_width=10
  filled=$(( used * bar_width / 100 ))
  (( filled > bar_width )) && filled=$bar_width
  empty=$(( bar_width - filled ))
  bar=""
  for (( i=0; i<filled; i++ )); do bar+="▓"; done
  for (( i=0; i<empty; i++ ));  do bar+="░"; done

  line="\033[36;1m${project}\033[0m"
  [[ -n "$branch" ]] && line+=" \033[2m|\033[0m \033[35m${branch}\033[0m"
  line+=" \033[2m|\033[0m \033[${bar_color}m${bar}\033[0m \033[${bar_color}m${used}%\033[0m"
  line+=" \033[2m|\033[0m ${model} \033[2m${cost_fmt}\033[0m"

elif (( cols >= 60 )); then
  # Medium: project | branch | XX% | $X.XX
  line="\033[36;1m${project}\033[0m"
  [[ -n "$branch" ]] && line+=" \033[2m|\033[0m \033[35m${branch}\033[0m"
  line+=" \033[2m|\033[0m \033[${bar_color}m${used}%\033[0m"
  line+=" \033[2m|\033[0m \033[2m${cost_fmt}\033[0m"

else
  # Narrow: project XX% $X.XX
  line="\033[36m${project}\033[0m \033[${bar_color}m${used}%\033[0m \033[2m${cost_fmt}\033[0m"
fi

printf '%b\n' "$line"
