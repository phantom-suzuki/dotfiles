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

# --- Open PR for current branch (cached per branch, 60s TTL) ---
# Replicates the open-PR indicator Claude Code's default statusline used to show.
# gh is a network call, so cache aggressively and guard every read (set -euo pipefail safe).
pr_number=""; pr_url=""
if [[ -n "$branch" && -n "$project_dir" ]] && command -v gh >/dev/null 2>&1; then
  pr_cache="${cache_file}.pr"
  use_pr_cache=""
  if [[ -f "$pr_cache" ]]; then
    pr_ctime=$(sed -n '1p' "$pr_cache" 2>/dev/null || echo 0); pr_ctime=${pr_ctime:-0}
    pr_cbranch=$(sed -n '2p' "$pr_cache" 2>/dev/null || echo "")
    if [[ "$pr_cbranch" == "$branch" ]] && (( now - pr_ctime < 60 )); then
      pr_number=$(sed -n '3p' "$pr_cache" 2>/dev/null || echo "")
      pr_url=$(sed -n '4p' "$pr_cache" 2>/dev/null || echo "")
      use_pr_cache=1
    fi
  fi
  if [[ -z "$use_pr_cache" ]]; then
    pr_line=$( (cd "$project_dir" && gh pr view --json number,url,state 2>/dev/null) \
      | jq -r 'select(.state=="OPEN") | "\(.number)\t\(.url)"' 2>/dev/null || true )
    if [[ "$pr_line" == *$'\t'* ]]; then
      pr_number="${pr_line%%$'\t'*}"
      pr_url="${pr_line#*$'\t'}"
    else
      pr_number=""; pr_url=""
    fi
    printf '%s\n%s\n%s\n%s\n' "$now" "$branch" "$pr_number" "$pr_url" > "$pr_cache"
  fi
fi

# --- PR segment (clickable OSC 8 hyperlink when URL is known) ---
pr_seg=""
if [[ -n "$pr_number" ]]; then
  if [[ -n "$pr_url" ]]; then
    pr_seg="\033[34m\033]8;;${pr_url}\033\134PR #${pr_number}\033]8;;\033\134\033[0m"
  else
    pr_seg="\033[34mPR #${pr_number}\033[0m"
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

# --- Rate limit segment (Claude.ai Pro/Max only; appears after 1st API response) ---
# Nudges an account switch as you approach the usage cap before a rate-limit stop.
# Thresholds overridable via env. All reads are guarded for absence (set -euo pipefail safe).
RL_WARN=${CLAUDE_RL_WARN:-80}   # yellow gauge
RL_CRIT=${CLAUDE_RL_CRIT:-90}   # red + macOS notification ("switch account")
rl_full=""; rl_short=""
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_max=0; rl_label=""; rl_reset=""
if [[ -n "$five_h" ]]; then
  v=${five_h%%.*}; v=${v:-0}; rl_max=$v; rl_label="5h"
  rl_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
fi
if [[ -n "$seven_d" ]]; then
  v=${seven_d%%.*}; v=${v:-0}
  if (( v > rl_max )); then
    rl_max=$v; rl_label="7d"
    rl_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  fi
fi
if [[ -n "$rl_label" ]]; then
  if (( rl_max >= RL_CRIT )); then
    rl_full="\033[31;1m⚠ ${rl_label}:${rl_max}% 切替検討\033[0m"
    rl_short="\033[31;1m⚠${rl_max}%\033[0m"
    # Desktop notification — macOS only, debounced once per reset window, backgrounded
    if [[ "$(uname)" == "Darwin" && -n "$rl_reset" ]]; then
      flag="$cache_dir/rl-notified-${rl_reset%%.*}"
      if [[ ! -f "$flag" ]]; then
        hm=$(date -r "${rl_reset%%.*}" +%H:%M 2>/dev/null || echo "?")
        ( osascript -e "display notification \"${rl_label} 使用率 ${rl_max}%。${hm} にリセット。別アカウントへの切替を検討してください\" with title \"Claude Code rate limit\" sound name \"Sosumi\"" >/dev/null 2>&1 & )
        : > "$flag"
      fi
    fi
  elif (( rl_max >= RL_WARN )); then
    rl_full="\033[33m${rl_label}:${rl_max}%\033[0m"; rl_short="\033[33m${rl_max}%\033[0m"
  else
    # Normal: show gauge on wide/medium only; keep narrow uncluttered
    rl_full="\033[32m${rl_label}:${rl_max}%\033[0m"; rl_short=""
  fi
fi

# --- Compose lines (responsive; wide/medium render two rows) ---
# Row 1 = identity (project | branch | PR), Row 2 = metrics (context | model | cost | rate-limit).
# Narrow stays a single row. Using printf '%b' for reliable escape handling across shells.
line1=""; line2=""
if (( cols >= 90 )); then
  # Wide
  bar_width=10
  filled=$(( used * bar_width / 100 ))
  (( filled > bar_width )) && filled=$bar_width
  empty=$(( bar_width - filled ))
  bar=""
  for (( i=0; i<filled; i++ )); do bar+="▓"; done
  for (( i=0; i<empty; i++ ));  do bar+="░"; done

  # Row 1: project | branch | PR
  line1="\033[36;1m${project}\033[0m"
  [[ -n "$branch" ]] && line1+=" \033[2m|\033[0m \033[35m${branch}\033[0m"
  [[ -n "$pr_seg" ]] && line1+=" \033[2m|\033[0m ${pr_seg}"
  # Row 2: ▓▓▓░░ XX% | model $X.XX | rate-limit
  line2="\033[${bar_color}m${bar}\033[0m \033[${bar_color}m${used}%\033[0m"
  line2+=" \033[2m|\033[0m ${model} \033[2m${cost_fmt}\033[0m"
  [[ -n "$rl_full" ]] && line2+=" \033[2m|\033[0m ${rl_full}"

elif (( cols >= 60 )); then
  # Medium
  # Row 1: project | branch | PR
  line1="\033[36;1m${project}\033[0m"
  [[ -n "$branch" ]] && line1+=" \033[2m|\033[0m \033[35m${branch}\033[0m"
  [[ -n "$pr_seg" ]] && line1+=" \033[2m|\033[0m ${pr_seg}"
  # Row 2: XX% | $X.XX | rate-limit
  line2="\033[${bar_color}m${used}%\033[0m"
  line2+=" \033[2m|\033[0m \033[2m${cost_fmt}\033[0m"
  [[ -n "$rl_full" ]] && line2+=" \033[2m|\033[0m ${rl_full}"

else
  # Narrow: single row — project XX% $X.XX (rate-limit shown only when critical)
  line1="\033[36m${project}\033[0m \033[${bar_color}m${used}%\033[0m \033[2m${cost_fmt}\033[0m"
  [[ -n "$rl_short" ]] && line1+=" ${rl_short}"
fi

printf '%b\n' "$line1"
[[ -n "$line2" ]] && printf '%b\n' "$line2"
