local wezterm = require("wezterm")
local act = wezterm.action
local utils = require("utils")

local M = {}

-- smart-splits: navigate/resize panes, forwarding to Neovim when active
local function split_nav(resize_or_move, key)
  local direction_keys = { h = "Left", j = "Down", k = "Up", l = "Right" }
  return {
    key = key,
    mods = resize_or_move == "resize" and "ALT" or "CTRL",
    action = wezterm.action_callback(function(win, pane)
      if utils.is_vim(pane) then
        -- Forward to Neovim
        win:perform_action(
          act.SendKey({ key = key, mods = resize_or_move == "resize" and "ALT" or "CTRL" }),
          pane
        )
      else
        if resize_or_move == "resize" then
          win:perform_action(act.AdjustPaneSize({ direction_keys[key], 3 }), pane)
        else
          win:perform_action(act.ActivatePaneDirection(direction_keys[key]), pane)
        end
      end
    end),
  }
end

M.keys = {
  -- smart-splits: Ctrl+hjkl move, Alt+hjkl resize
  split_nav("move", "h"),
  split_nav("move", "j"),
  split_nav("move", "k"),
  split_nav("move", "l"),
  split_nav("resize", "h"),
  split_nav("resize", "j"),
  split_nav("resize", "k"),
  split_nav("resize", "l"),

  -- Cmd+P routing: Neovim -> Telescope, terminal -> command palette
  {
    key = "p",
    mods = "SUPER",
    action = wezterm.action_callback(function(win, pane)
      if utils.is_vim(pane) then
        -- Send Space+ff to Neovim for Telescope find_files
        win:perform_action(act.SendKey({ key = " " }), pane)
        win:perform_action(act.SendKey({ key = "f" }), pane)
        win:perform_action(act.SendKey({ key = "f" }), pane)
      else
        win:perform_action(act.ActivateCommandPalette, pane)
      end
    end),
  },

  -- Quick Select: Leader+q general, Leader+u URL select
  { key = "q", mods = "LEADER", action = act.QuickSelect },
  {
    key = "u",
    mods = "LEADER",
    action = act.QuickSelectArgs({
      label = "open url",
      patterns = { "https?://\\S+" },
      action = wezterm.action_callback(function(window, pane)
        local url = window:get_selection_text_for_pane(pane)
        wezterm.log_info("opening: " .. url)
        wezterm.open_with(url)
      end),
    }),
  },

  -- Resurrect: save/restore state
  {
    key = "S",
    mods = "LEADER|SHIFT",
    action = wezterm.action_callback(function(win, pane)
      local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")
      resurrect.save_state(resurrect.workspace_state.get_workspace_state())
      win:toast_notification("WezTerm", "State saved", nil, 4000)
    end),
  },
  {
    key = "R",
    mods = "LEADER|SHIFT",
    action = wezterm.action_callback(function(win, pane)
      local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")
      resurrect.fuzzy_load(win, pane, function(id, label)
        local state = resurrect.load_state(id, "workspace")
        resurrect.workspace_state.restore_workspace(state, {
          window = win,
          relative = true,
          restore_text = true,
          on_pane_restore = resurrect.tab_state.default_on_pane_restore,
        })
      end)
    end),
  },

  -- Scrollback search (fullscreen moved to Ctrl+Shift+Enter)
  { key = "f", mods = "SHIFT|CTRL", action = act.Search({ CaseInSensitiveString = "" }) },
  { key = "Enter", mods = "SHIFT|CTRL", action = act.ToggleFullScreen },

  -- Workspace
  {
    key = "w",
    mods = "LEADER",
    action = act.ShowLauncherArgs({ flags = "WORKSPACES", title = "Select workspace" }),
  },
  {
    key = "$",
    mods = "LEADER",
    action = act.PromptInputLine({
      description = "(wezterm) Set workspace title:",
      action = wezterm.action_callback(function(win, pane, line)
        if line then
          wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
        end
      end),
    }),
  },
  {
    key = "W",
    mods = "LEADER|SHIFT",
    action = act.PromptInputLine({
      description = "(wezterm) Create new workspace:",
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
        end
      end),
    }),
  },

  -- Tab navigation
  { key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
  { key = "Tab", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(-1) },
  { key = "{", mods = "LEADER", action = act.MoveTabRelative(-1) },
  { key = "}", mods = "LEADER", action = act.MoveTabRelative(1) },
  { key = "t", mods = "SUPER", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "SUPER", action = act.CloseCurrentTab({ confirm = true }) },

  -- Copy mode
  { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
  { key = "c", mods = "SUPER", action = act.CopyTo("Clipboard") },
  { key = "v", mods = "SUPER", action = act.PasteFrom("Clipboard") },

  -- Pane operations
  { key = "d", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "r", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
  { key = "[", mods = "CTRL|SHIFT", action = act.PaneSelect },
  { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

  -- Font size
  { key = "+", mods = "CTRL", action = act.IncreaseFontSize },
  { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
  { key = "0", mods = "CTRL", action = act.ResetFontSize },

  -- Tab switch: Cmd + number
  { key = "1", mods = "SUPER", action = act.ActivateTab(0) },
  { key = "2", mods = "SUPER", action = act.ActivateTab(1) },
  { key = "3", mods = "SUPER", action = act.ActivateTab(2) },
  { key = "4", mods = "SUPER", action = act.ActivateTab(3) },
  { key = "5", mods = "SUPER", action = act.ActivateTab(4) },
  { key = "6", mods = "SUPER", action = act.ActivateTab(5) },
  { key = "7", mods = "SUPER", action = act.ActivateTab(6) },
  { key = "8", mods = "SUPER", action = act.ActivateTab(7) },
  { key = "9", mods = "SUPER", action = act.ActivateTab(-1) },

  -- Command palette & config reload
  { key = "p", mods = "SHIFT|CTRL", action = act.ActivateCommandPalette },
  { key = "r", mods = "SHIFT|CTRL", action = act.ReloadConfiguration },

  -- Key tables
  { key = "s", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
  { key = "a", mods = "LEADER", action = act.ActivateKeyTable({ name = "activate_pane", timeout_milliseconds = 1000 }) },
}

M.key_tables = {
  -- Pane resize: Leader+s
  resize_pane = {
    { key = "h", action = act.AdjustPaneSize({ "Left", 1 }) },
    { key = "l", action = act.AdjustPaneSize({ "Right", 1 }) },
    { key = "k", action = act.AdjustPaneSize({ "Up", 1 }) },
    { key = "j", action = act.AdjustPaneSize({ "Down", 1 }) },
    { key = "Enter", action = "PopKeyTable" },
  },
  activate_pane = {
    { key = "h", action = act.ActivatePaneDirection("Left") },
    { key = "l", action = act.ActivatePaneDirection("Right") },
    { key = "k", action = act.ActivatePaneDirection("Up") },
    { key = "j", action = act.ActivatePaneDirection("Down") },
  },
  -- Copy mode: Leader+[
  copy_mode = {
    -- Movement
    { key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
    { key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
    { key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
    { key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
    -- Start/end of line
    { key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
    { key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
    { key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
    { key = "o", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEnd") },
    { key = "O", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
    { key = ";", mods = "NONE", action = act.CopyMode("JumpAgain") },
    -- Word movement
    { key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
    { key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
    { key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
    -- Jump
    { key = "t", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
    { key = "f", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
    { key = "T", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
    { key = "F", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
    -- Scrollback top/bottom
    { key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },
    { key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
    -- Viewport
    { key = "H", mods = "NONE", action = act.CopyMode("MoveToViewportTop") },
    { key = "L", mods = "NONE", action = act.CopyMode("MoveToViewportBottom") },
    { key = "M", mods = "NONE", action = act.CopyMode("MoveToViewportMiddle") },
    -- Scroll
    { key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
    { key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
    { key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },
    { key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
    -- Selection modes
    { key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
    { key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
    { key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
    -- Copy
    { key = "y", mods = "NONE", action = act.CopyTo("Clipboard") },
    -- Exit copy mode
    {
      key = "Enter",
      mods = "NONE",
      action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
    },
    { key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
    { key = "c", mods = "CTRL", action = act.CopyMode("Close") },
    { key = "q", mods = "NONE", action = act.CopyMode("Close") },
  },
}

return M
