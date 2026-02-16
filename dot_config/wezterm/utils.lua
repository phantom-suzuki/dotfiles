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

-- Get current working directory from pane
function M.get_cwd(pane)
  local cwd_uri = pane:get_current_working_dir()
  if cwd_uri then
    local cwd = cwd_uri.file_path
    -- Replace home directory with ~
    local home = os.getenv("HOME")
    if home and cwd then
      cwd = cwd:gsub("^" .. home, "~")
    end
    return cwd
  end
  return ""
end

-- Get basename of a path
function M.basename(path)
  if not path then return "" end
  return path:gsub("(.*[/\\])(.*)", "%2")
end

return M
