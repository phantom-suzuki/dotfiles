# Git worktree + tmux + Claude workflow

# --- Create worktree + tmux window + Claude ---
function wta() {
  [[ -z "$1" ]] && { echo "Usage: wta <branch> [-p <prompt>]"; return 1; }
  local branch="$1"; shift
  local prompt=""
  [[ "$1" == "-p" ]] && { prompt="$2"; shift 2; }

  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  [[ -z "$repo_root" ]] && { echo "Error: not in a git repo"; return 1; }
  local wt_base="${repo_root}__worktrees"
  local wt_dir="${wt_base}/${branch}"

  mkdir -p "$wt_base"
  git worktree add -b "$branch" "$wt_dir" 2>/dev/null || git worktree add "$wt_dir" "$branch" || return 1

  # Run project-local init hook if present
  [[ -x "${repo_root}/.worktree-init" ]] && (cd "$wt_dir" && "${repo_root}/.worktree-init")

  if [[ -n "$TMUX" ]]; then
    tmux new-window -n "$branch" -c "$wt_dir"
    if [[ -n "$prompt" ]]; then
      printf '%s' "$prompt" > "${wt_dir}/.claude-prompt"
      tmux send-keys -t ":${branch}" "claude 'Read .claude-prompt and work on the described task.'" Enter
    else
      tmux send-keys -t ":${branch}" "claude" Enter
    fi
  else
    echo "Worktree created: $wt_dir"
    [[ -n "$prompt" ]] && printf '%s' "$prompt" > "${wt_dir}/.claude-prompt"
    echo "Run: cd $wt_dir && claude"
  fi
}

# --- Remove worktree + branch + tmux window ---
function wtr() {
  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  local wt_path=$(pwd)
  [[ "$(git rev-parse --git-dir 2>/dev/null)" == *"worktrees"* ]] || { echo "Error: not in a worktree"; return 1; }

  local main_root=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
  cd "$main_root" || return 1
  git worktree remove "$wt_path" && {
    git branch -D "$branch" 2>/dev/null
    [[ -n "$TMUX" ]] && tmux kill-window -t ":${branch}" 2>/dev/null
    echo "Removed: $branch"
  }
}

# --- Merge worktree branch + cleanup ---
function wtm() {
  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  local wt_path=$(pwd)
  [[ "$(git rev-parse --git-dir 2>/dev/null)" == *"worktrees"* ]] || { echo "Error: not in a worktree"; return 1; }

  local main_root=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
  local target=$(git -C "$main_root" rev-parse --abbrev-ref HEAD 2>/dev/null)

  echo -n "Merge $branch → $target? [y/N] "
  read -q || { echo "\nCancelled."; return 1; }
  echo

  cd "$main_root" || return 1
  git merge "$branch" && {
    git worktree remove "$wt_path"
    git branch -d "$branch"
    [[ -n "$TMUX" ]] && tmux kill-window -t ":${branch}" 2>/dev/null
    echo "Merged: $branch → $target"
  }
}

# --- Create worktree from GitHub Issue ---
function wti() {
  [[ -z "$1" ]] && { echo "Usage: wti <issue-number>"; return 1; }
  local num="$1"
  local json=$(gh issue view "$num" --json title,body 2>/dev/null)
  [[ -z "$json" ]] && { echo "Error: issue #$num not found"; return 1; }
  local title=$(echo "$json" | jq -r '.title')
  local body=$(echo "$json" | jq -r '"# \(.title)\n\n\(.body)"')
  local slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 50)
  wta "issue-${num}-${slug}" -p "$body"
}

# --- List / prune ---
function wtl() { git worktree list; }
function wtprune() { git worktree prune -v; }
