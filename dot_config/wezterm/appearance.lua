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
  config.window_background_opacity = 0.80
  config.macos_window_background_blur = 20
  config.window_decorations = "RESIZE"
  config.max_fps = 120
  config.animation_fps = 120

  -- Dim inactive panes for visual distinction
  config.inactive_pane_hsb = {
    saturation = 0.85,
    brightness = 0.65,
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
  config.window_background_gradient = {
    colors = { "#161821" },
  }
end

return M
