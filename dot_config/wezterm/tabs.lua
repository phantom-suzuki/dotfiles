local wezterm = require("wezterm")
local utils = require("utils")
local M = {}

function M.apply(config)
  config.show_tabs_in_tab_bar = true
  config.hide_tab_bar_if_only_one_tab = true
  config.show_new_tab_button_in_tab_bar = false
  config.show_close_tab_button_in_tabs = false
end

function M.setup()
  local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_lower_right_triangle
  local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_upper_left_triangle

  wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
    local background = "#5c6d74"
    local foreground = "#FFFFFF"
    local edge_background = "none"
    if tab.is_active then
      background = "#ae8b2d"
      foreground = "#FFFFFF"
    end
    local edge_foreground = background

    -- Get process name or directory name for the tab title
    local pane = tab.active_pane
    local process_name = utils.basename(pane.foreground_process_name)
    local title = process_name
    if process_name == "zsh" or process_name == "bash" or process_name == "fish" then
      -- Show directory name for shell processes
      local cwd = utils.get_cwd(pane)
      title = utils.basename(cwd)
    elseif process_name == "claude" then
      -- Show project name for Claude Code
      local cwd = utils.get_cwd(pane)
      local dir_name = utils.basename(cwd)
      title = "claude:" .. dir_name
    elseif process_name == "node" then
      -- Node.js fallback (Claude Code may run via node)
      local cwd = utils.get_cwd(pane)
      title = utils.basename(cwd)
    end

    -- Format: "1: nvim" or "2: projects"
    local tab_index = tab.tab_index + 1
    local tab_title = "   " .. tab_index .. ": " .. title .. "   "

    return {
      { Background = { Color = edge_background } },
      { Foreground = { Color = edge_foreground } },
      { Text = SOLID_LEFT_ARROW },
      { Background = { Color = background } },
      { Foreground = { Color = foreground } },
      { Text = tab_title },
      { Background = { Color = edge_background } },
      { Foreground = { Color = edge_foreground } },
      { Text = SOLID_RIGHT_ARROW },
    }
  end)
end

return M
