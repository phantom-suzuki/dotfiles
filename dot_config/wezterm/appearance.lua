local wezterm = require("wezterm")
local M = {}

function M.apply(config)
  -- Font with Nerd Font fallback
  config.font = wezterm.font_with_fallback({
    { family = "Source Han Code JP", weight = "Regular" },
    { family = "Symbols Nerd Font Mono", weight = "Regular" },
  })
  config.font_size = 14.0

  -- Window
  config.window_decorations = "RESIZE"
  config.max_fps = 60
  config.animation_fps = 60

  -- Background image with dark overlay for readability
  config.background = {
    {
      source = {
        File = wezterm.home_dir .. "/.config/wezterm/backgrounds/nixie-tube.png",
      },
      hsb = { brightness = 0.15 },
      attachment = "Fixed",
      horizontal_align = "Center",
      vertical_align = "Middle",
    },
    {
      source = { Color = "#161821" },
      width = "100%",
      height = "100%",
      opacity = 0.75,
    },
  }

  -- Dim inactive panes for visual distinction
  config.inactive_pane_hsb = {
    saturation = 0.6,
    brightness = 0.4,
  }

  -- Iceberg phantom colors
  config.colors = {
    foreground = "#c5c8d0",
    background = "#161821",
    cursor_bg = "#c5c8d0",
    cursor_fg = "#161821",
    cursor_border = "#c5c8d0",
    selection_bg = "#272b41",
    selection_fg = "#c5c8d0",
    ansi = {
      "#151820", "#e17878", "#b3bd82", "#e1a378",
      "#83a0c5", "#a092c7", "#89b8c1", "#c5c8d0",
    },
    brights = {
      "#6a7089", "#e98989", "#c0c98e", "#e9b189",
      "#91abd0", "#aca0d3", "#95c4ce", "#d2d3de",
    },
    tab_bar = {
      inactive_tab_edge = "none",
    },
  }

  -- Tab bar transparency
  config.window_frame = {
    inactive_titlebar_bg = "none",
    active_titlebar_bg = "none",
  }
end

return M
