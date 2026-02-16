local wezterm = require("wezterm")
local utils = require("utils")
local M = {}

function M.setup()
  wezterm.on("update-status", function(window, pane)
    -- Left status: workspace name (gold) + key mode
    local workspace = window:active_workspace()
    local key_table = window:active_key_table()
    local mode = key_table and (" [" .. key_table .. "]") or ""

    window:set_left_status(wezterm.format({
      { Background = { Color = "#ae8b2d" } },
      { Foreground = { Color = "#FFFFFF" } },
      { Text = "  " .. workspace .. mode .. "  " },
      { Background = { Color = "none" } },
      { Foreground = { Color = "#ae8b2d" } },
      { Text = wezterm.nerdfonts.ple_upper_left_triangle },
    }))

    -- Right status: CWD + time
    local cwd = utils.get_cwd(pane) or ""
    local time = wezterm.strftime("%H:%M")

    local cells = {}
    if cwd ~= "" then
      table.insert(cells, { Foreground = { Color = "#89b8c1" }, Text = "  " .. wezterm.nerdfonts.md_folder .. " " .. cwd })
    end
    table.insert(cells, { Foreground = { Color = "#6a7089" }, Text = "  |  " })
    table.insert(cells, { Foreground = { Color = "#c5c8d0" }, Text = wezterm.nerdfonts.md_clock_outline .. " " .. time .. "  " })

    window:set_right_status(wezterm.format(cells))
  end)
end

return M
