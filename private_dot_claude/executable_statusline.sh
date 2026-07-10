#!/usr/bin/env bash
# Claude Code statusline — Iceberg phantom palette
# Responsive: adapts to pane width (wide / medium / narrow)
# Uses printf '%b' instead of echo -e for reliable escape handling

set -euo pipefail

input=$(cat)

# --- Terminal width ---
# COLUMNS is set by Claude Code v2.1.153+. In environments where it's absent
# (older Claude Code, or the shell has no TERM), `tput cols` doesn't work since
# this script isn't attached to a terminal — so fall back to 80 instead of
# calling tput. Never exit early on a small/unknown width: narrow layout
# renders a short single row, so there's no reason to blank the whole bar.
cols="${COLUMNS:-}"
if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ || "$cols" -eq 0 ]]; then
  cols=80
fi

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

# --- Open PR for current branch (read cache only; never blocks the render path) ---
# Replicates the open-PR indicator Claude Code's default statusline used to show.
# gh is a blocking network call, so it never runs inline here. A detached background
# job refreshes the cache; this script only reads whatever is already on disk, even
# if stale — a stale PR badge beats no statusline at all.

# Read line N from a PR cache file (empty string if the file or line is missing).
pr_cache_line() {
  sed -n "${1}p" "$2" 2>/dev/null || true
}

refresh_pr_cache() {
  local proj_dir="$1" br="$2" cfile="$3"
  local pcache="${cfile}.pr"
  # Not `local`: this function only ever runs inside its own backgrounded
  # process, so leaving it in the process-global scope is safe, and it lets
  # the EXIT trap below reference it by name (single-quoted, expanded at fire
  # time) instead of splicing the path into the trap string — untrusted path
  # bytes (quotes, shell metacharacters) in a double-quoted trap would be
  # re-parsed as shell syntax at signal time (CWE-78).
  lock_dir="${pcache}.lock"
  local now_ts
  now_ts=$(date +%s)

  if ! mkdir "$lock_dir" 2>/dev/null; then
    local lock_age
    lock_age=$(( now_ts - $(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo "$now_ts") ))
    if (( lock_age > 120 )); then
      rmdir "$lock_dir" 2>/dev/null || true
      mkdir "$lock_dir" 2>/dev/null || return 0
    else
      return 0
    fi
  fi
  # ${lock_dir:-} keeps this safe under `set -u` even if the trap somehow
  # fires before lock_dir is assigned; rmdir on an empty/missing path just
  # fails and `|| true` swallows it.
  trap 'rmdir "${lock_dir:-}" 2>/dev/null || true' EXIT

  # `env` is a no-op prefix used when no timeout binary is found. Kept as a
  # non-empty array element on purpose: macOS ships bash 3.2, where `set -u`
  # treats expanding an empty array as an unbound-variable error.
  local -a timeout_prefix=(env)
  if command -v timeout >/dev/null 2>&1; then
    timeout_prefix=(timeout 10)
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_prefix=(gtimeout 10)
  fi

  # `gh pr list` (unlike `gh pr view`) exits 0 with `[]` when there's no open
  # PR for the branch, so a missing PR and a failed call are cleanly distinguished
  # by exit code alone — no stderr text matching needed. `--head` only matches
  # on branch name, so a same-named fork branch's cross-repository PR would
  # otherwise be shown as our own; fetch a few candidates (limit 1 would already
  # cut the list before we can filter) and exclude isCrossRepository ones. If we
  # only ever open PRs from a fork ourselves, our badge simply won't show — an
  # accepted trade-off for not misattributing someone else's PR.
  local pr_json="" gh_exit=0
  pr_json=$(cd "$proj_dir" && "${timeout_prefix[@]}" gh pr list --head "$br" --state open --json number,url,isCrossRepository --limit 10 2>/dev/null) || gh_exit=$?

  local new_number="" new_url=""
  if (( gh_exit == 0 )); then
    local line
    line=$(echo "$pr_json" | jq -r '[.[] | select(.isCrossRepository | not)] | if length > 0 then "\(.[0].number)\t\(.[0].url)" else "" end' 2>/dev/null || echo "")
    if [[ "$line" == *$'\t'* ]]; then
      new_number="${line%%$'\t'*}"
      new_url="${line#*$'\t'}"
    fi
  elif [[ -f "$pcache" ]] && [[ "$(pr_cache_line 2 "$pcache")" == "$br" ]]; then
    # Transient failure (network, auth, etc.) — keep the cached PR value, but
    # only when it belongs to this same branch, so we retry in 60s without
    # blanking the badge and never carry a stale branch's PR into this one.
    new_number=$(pr_cache_line 3 "$pcache")
    new_url=$(pr_cache_line 4 "$pcache")
  fi

  local tmp_file="${pcache}.tmp.$$"
  printf '%s\n%s\n%s\n%s\n' "$now_ts" "$br" "$new_number" "$new_url" > "$tmp_file"
  mv -f "$tmp_file" "$pcache"
}

pr_number=""; pr_url=""
if [[ -n "$branch" && -n "$project_dir" ]] && command -v gh >/dev/null 2>&1; then
  pr_cache="${cache_file}.pr"
  need_refresh=1
  if [[ -f "$pr_cache" ]]; then
    pr_ctime=$(pr_cache_line 1 "$pr_cache"); pr_ctime=${pr_ctime//[^0-9]/}; pr_ctime=${pr_ctime:-0}
    pr_cbranch=$(pr_cache_line 2 "$pr_cache")
    if [[ "$pr_cbranch" == "$branch" ]]; then
      pr_number=$(pr_cache_line 3 "$pr_cache")
      pr_url=$(pr_cache_line 4 "$pr_cache")
      (( now - pr_ctime < 60 )) && need_refresh=0
    fi
  fi
  if (( need_refresh )); then
    refresh_pr_cache "$project_dir" "$branch" "$cache_file" >/dev/null 2>&1 &
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
  (( rl_max >= RL_CRIT )) && [[ -n "$rl_short" ]] && line1+=" ${rl_short}"
fi

printf '%b\n' "$line1"
[[ -n "$line2" ]] && printf '%b\n' "$line2"
exit 0
