local wezterm = require("wezterm")
local M = {}

-- Check if current pane is running Neovim (for smart-splits)
function M.is_vim(pane)
  local process_info = pane:get_foreground_process_info()
  if process_info then
    local process_name = process_info.name
    return process_name == "nvim" or process_name == "vim"
  end
  -- Fallback: check user var set by smart-splits.nvim
  local is_vim_env = pane:get_user_vars().IS_NVIM
  return is_vim_env == "true"
end

-- Normalize a CWD value (URL object or string) into a ~-prefixed path string.
local function normalize_cwd(cwd_uri)
  if not cwd_uri then return "" end
  local cwd = type(cwd_uri) == "string" and cwd_uri or cwd_uri.file_path
  if not cwd then return "" end
  local home = os.getenv("HOME")
  if home then
    cwd = cwd:gsub("^" .. home, "~")
  end
  return cwd
end

-- For Pane objects (event args like update-status second arg).
function M.get_cwd(pane)
  if not pane then return "" end
  return normalize_cwd(pane:get_current_working_dir())
end

-- For PaneInformation tables (e.g. tab.active_pane in format-tab-title).
-- PaneInformation is a userdata that rejects unknown field access, so we
-- cannot reuse get_cwd here via type-dispatch.
function M.get_cwd_from_info(info)
  if not info then return "" end
  return normalize_cwd(info.current_working_dir)
end

-- Get basename of a path
function M.basename(path)
  if not path then return "" end
  return path:gsub("(.*[/\\])(.*)", "%2")
end

return M
